// src/realtime/roomEventBus.ts — Typed room event bus (Brain Review P0-3 + P1-10)
//
// Distributes ALL room-scoped events across replicas, not just sync.state.
// Used for: chat.broadcast, reaction.broadcast, participant.joined,
// participant.left, participant.kicked, room.appearance.updated.
//
// P1-10 fix: incoming events are validated with Zod before dispatch. A
// malformed event from a compromised publisher is dropped with a warning,
// not cast blindly to RoomEvent.
//
// Each replica runs ONE subscriber per room it has local sockets in.
// When a router on replica A wants to broadcast a chat message:
//   1. It publishes to roomEvents:<roomId> via this bus.
//   2. ALL replicas (including A) receive the event via their subscriber.
//   3. Each replica fans out to its local sockets via registry.broadcastLocal.
//
// This ensures exactly-once delivery to each socket regardless of which
// replica published — NO split-brain, NO double-delivery (because the
// publisher does NOT also broadcastLocal directly; only the subscriber does).
//
// CRITICAL: the publishing router MUST NOT also call registry.broadcastLocal
// for the same event — that would double-deliver to local sockets on the
// publishing replica.

import Redis from 'ioredis';
import type { Redis as RedisType } from 'ioredis';
import { z } from 'zod';

export type RoomEvent =
  | {
      kind: 'chat.broadcast';
      roomId: string;
      messageId: string;
      clientMessageId: string | null;
      senderId: string;
      senderName: string;
      text: string;
      createdAtMs: number;
      mediaType?: 'photo' | null;
      hasMedia?: boolean;
    }
  | {
      kind: 'reaction.broadcast';
      roomId: string;
      userId: string;
      username: string;
      emoji: string;
      serverTimeMs: number;
    }
  | {
      kind: 'participant.joined';
      roomId: string;
      userId: string;
      username: string;
      timestampMs: number;
    }
  | {
      kind: 'participant.left';
      roomId: string;
      userId: string;
      username: string;
      timestampMs: number;
    }
  | {
      // Аудит 26.07.2026 P1: отзыв WS-доступа при кике — реплики закрывают
      // локальные сокеты кикнутого пользователя (см. gateway.kickUser).
      kind: 'participant.kicked';
      roomId: string;
      userId: string;
      byUserId: string;
      timestampMs: number;
    }
  | {
      // Аудит 26.07.2026 P2: живая доставка темы комнаты. Поля плоские (как у
      // остальных событий шины); в вложенный wire-формат room.appearance.updated
      // их сворачивает gateway.eventToServerMessage.
      kind: 'room.appearance.updated';
      roomId: string;
      themeId: string;
      themeRevision: number;
      intensity: number;
      motionEnabled: boolean;
      serverTimeMs: number;
    }
  | {
      // M26: гость попросил хоста поставить паузу. Сервер не трогает плеер —
      // только доставляет просьбу (см. PauseRequestSchema).
      kind: 'pause.requested';
      roomId: string;
      userId: string;
      username: string;
      reason: string | null;
      serverTimeMs: number;
    }
  | {
      // M27: хост ответил на просьбу о паузе. Социальный сигнал, не команда
      // плееру — принятая пауза едет отдельным sync.command (см. PauseResolveSchema).
      kind: 'pause.resolved';
      roomId: string;
      hostId: string;
      hostName: string;
      accepted: boolean;
      requestUserId: string | null;
      serverTimeMs: number;
    }
  | {
      // Аудит 12.08.2026 (P0): передача хоста. Раньше уход хоста ЗАКРЫВАЛ комнату
      // всем (roomLifecycle.maybeEndAfterLeave), даже если досматривали ещё десять
      // человек. Схема role.changed и bumpEpoch() существовали с P1-64, но никто
      // это событие не публиковал — миграция хоста была собрана и не подключена.
      // epoch обязателен: он аннулирует команды прежнего хоста, если тот вернётся.
      kind: 'role.changed';
      roomId: string;
      newHostId: string;
      newHostName: string;
      epoch: number;
      serverTimeMs: number;
    };

export type RoomEventListener = (event: RoomEvent) => void;

// ── P1-10: Zod validation for incoming events ──────────────────────────
// Any publisher with Redis access can send malformed events. Validate
// before dispatch — don't trust JSON.parse(raw) as RoomEvent.
// Аудит 26.07.2026 P2: схема экспортируется — контрактные тесты раньше
// держали её РУЧНУЮ копию и успели разойтись с оригиналом (uuid у
// clientMessageId/senderId, лимит text). Проверяем настоящую схему.
export const RoomEventSchema = z.discriminatedUnion('kind', [
  z.object({
    kind: z.literal('chat.broadcast'),
    roomId: z.string().uuid(),
    messageId: z.string().min(1),
    // Аудит 26.07.2026 P1: clientMessageId клиента — произвольная строка
    // (rooms.ts photo-роут), не обязательно UUID; uuid() молча дропал событие.
    clientMessageId: z.string().min(1).max(128).nullable(),
    // Аудит 26.07.2026 P1: senderId бывает сервисным ('plink-ai',
    // 'plink-ai-moderator') — строгий uuid() молча дропал все системные
    // броадкасты (очередь видео, ИИ-ассистент, уведомления о мутах).
    senderId: z.string().min(1).max(64),
    senderName: z.string().min(1).max(64),
    // Аудит 26.07.2026 P1: системные wire-пейлоады (очередь до 50 элементов)
    // превышают 2000 символов; лимит юзерского чата обеспечивает ChatSendSchema.
    text: z.string().max(100_000),
    createdAtMs: z.number().int(),
    mediaType: z.enum(['photo']).nullable().optional(),
    hasMedia: z.boolean().optional(),
  }),
  z.object({
    kind: z.literal('reaction.broadcast'),
    roomId: z.string().uuid(),
    userId: z.string().uuid(),
    username: z.string().min(1).max(64),
    emoji: z.string().min(1).max(32),
    serverTimeMs: z.number().int(),
  }),
  z.object({
    kind: z.literal('participant.joined'),
    roomId: z.string().uuid(),
    userId: z.string().uuid(),
    username: z.string().min(1).max(64),
    timestampMs: z.number().int(),
  }),
  z.object({
    kind: z.literal('participant.left'),
    roomId: z.string().uuid(),
    userId: z.string().uuid(),
    username: z.string().min(1).max(64),
    timestampMs: z.number().int(),
  }),
  // Аудит 26.07.2026 P1: событие кика для отзыва WS-доступа
  z.object({
    kind: z.literal('participant.kicked'),
    roomId: z.string().uuid(),
    userId: z.string().uuid(),
    byUserId: z.string().uuid(),
    timestampMs: z.number().int(),
  }),
  // Аудит 26.07.2026 P2: тема комнаты. Границы полей совпадают с
  // RoomAppearanceUpdatedSchema (contracts/realtime-v2.ts) — если роут
  // однажды перестанет резать intensity до 0.44, publish() упадёт у
  // отправителя, а не отдаст клиенту значение вне контракта.
  z.object({
    kind: z.literal('room.appearance.updated'),
    roomId: z.string().uuid(),
    themeId: z.string().min(1).max(64),
    themeRevision: z.number().int().nonnegative(),
    intensity: z.number().min(0).max(0.44),
    motionEnabled: z.boolean(),
    serverTimeMs: z.number().int(),
  }),
  // M26: просьба о паузе. Границы совпадают с PauseRequestedSchema
  // (contracts/realtime-v2.ts) — событие, которое не пройдёт wire-контракт,
  // должно падать у отправителя, а не долетать до клиента.
  z.object({
    kind: z.literal('pause.requested'),
    roomId: z.string().uuid(),
    userId: z.string().uuid(),
    username: z.string().min(1).max(64),
    reason: z.string().min(1).max(120).nullable(),
    serverTimeMs: z.number().int(),
  }),
  // M27: ответ хоста на просьбу о паузе. Границы совпадают с PauseResolvedSchema.
  z.object({
    kind: z.literal('pause.resolved'),
    roomId: z.string().uuid(),
    hostId: z.string().uuid(),
    hostName: z.string().min(1).max(64),
    accepted: z.boolean(),
    requestUserId: z.string().uuid().nullable(),
    serverTimeMs: z.number().int(),
  }),
  // Аудит 12.08.2026 P0: передача хоста. Границы совпадают с RoleChangedSchema
  // (contracts/realtime-v2.ts): epoch там positive(), поэтому и здесь — нулевой
  // epoch означал бы, что состояние комнаты не переинициализировано, и команды
  // прежнего хоста остались бы валидными.
  z.object({
    kind: z.literal('role.changed'),
    roomId: z.string().uuid(),
    newHostId: z.string().uuid(),
    newHostName: z.string().min(1).max(64),
    epoch: z.number().int().positive(),
    serverTimeMs: z.number().int(),
  }),
]);

export class RoomEventBus {
  private readonly subscriber: RedisType;
  private readonly publisher: RedisType;
  private readonly listeners = new Map<string, Set<RoomEventListener>>();
  private readonly subscribedChannels = new Set<string>();

  constructor(redisUrl: string) {
    // Dedicated subscriber connection (P0-2 rule: separate from publisher)
    this.subscriber = new Redis(redisUrl, {
      maxRetriesPerRequest: null,
      lazyConnect: false,
    });
    // Reuse a separate publisher connection (could be the main command client
    // in a future refactor, but kept separate here to keep this module
    // self-contained and avoid ordering issues during shutdown).
    this.publisher = new Redis(redisUrl, {
      maxRetriesPerRequest: 3,
      lazyConnect: false,
    });

    this.subscriber.on('message', (channel, raw) => {
      if (!channel.startsWith('roomEvents:')) return;
      const roomId = channel.substring('roomEvents:'.length);
      const set = this.listeners.get(roomId);
      if (!set || set.size === 0) return;
      // P1-10: validate with Zod before dispatch
      let event: RoomEvent;
      try {
        const parsed = JSON.parse(raw);
        event = RoomEventSchema.parse(parsed) as RoomEvent;
      } catch (err) {
        // Аудит 26.07.2026 P2: печатаем kind. При rolling deploy старая реплика
        // видит kind, добавленный новой версией схемы, и без этого поля warn не
        // отличить от реального мусора от скомпрометированного публикатора.
        let kind = 'unparsable';
        try {
          const k = (JSON.parse(raw) as { kind?: unknown }).kind;
          if (typeof k === 'string') kind = k;
          else kind = 'missing-kind';
        } catch {
          /* raw не JSON — так и оставляем 'unparsable' */
        }
        console.warn(
          `[RoomEventBus] dropped malformed event (kind=${kind}):`,
          (err as Error).message,
        );
        return;
      }
      for (const fn of set) {
        try {
          fn(event);
        } catch (err) {
          console.error('[RoomEventBus] listener threw:', err);
        }
      }
    });

    this.subscriber.on('error', (err) => {
      console.warn('[RoomEventBus] subscriber error:', err.message);
    });
    this.publisher.on('error', (err) => {
      console.warn('[RoomEventBus] publisher error:', err.message);
    });
  }

  async publish(roomId: string, event: RoomEvent): Promise<void> {
    // Аудит 26.07.2026 P1: валидируем при публикации — расхождение со схемой
    // падает у отправителя, а не молча дропается у подписчика.
    const check = RoomEventSchema.safeParse(event);
    if (!check.success) {
      throw new Error(`[RoomEventBus] invalid ${event.kind} event: ${check.error.message}`);
    }
    await this.publisher.publish(`roomEvents:${roomId}`, JSON.stringify(event));
  }

  async subscribe(roomId: string, listener: RoomEventListener): Promise<void> {
    let set = this.listeners.get(roomId);
    if (!set) {
      set = new Set();
      this.listeners.set(roomId, set);
    }
    set.add(listener);

    if (!this.subscribedChannels.has(roomId)) {
      await this.subscriber.subscribe(`roomEvents:${roomId}`);
      this.subscribedChannels.add(roomId);
    }
  }

  async unsubscribe(roomId: string, listener: RoomEventListener): Promise<void> {
    const set = this.listeners.get(roomId);
    if (!set) return;
    set.delete(listener);
    if (set.size === 0) {
      this.listeners.delete(roomId);
      if (this.subscribedChannels.has(roomId)) {
        // Аудит 26.07.2026 P1: снимаем флаг ДО await — иначе конкурентный
        // subscribe() в окне await считал канал подписанным, пропускал
        // реальный SUBSCRIBE, и после реконнекта комната теряла события.
        this.subscribedChannels.delete(roomId);
        try {
          await this.subscriber.unsubscribe(`roomEvents:${roomId}`);
        } catch (err) {
          this.subscribedChannels.add(roomId);
          throw err;
        }
      }
    }
  }

  async close(): Promise<void> {
    await Promise.allSettled([this.subscriber.quit(), this.publisher.quit()]);
  }
}
