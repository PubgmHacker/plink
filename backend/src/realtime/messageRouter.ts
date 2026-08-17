// src/realtime/messageRouter.ts — Type-based WS message router (runbook §5)
//
// FIXES the §19 bug: 'stateRequest должен обрабатываться до generic command
// routing'. The old ws-handler.ts checked `msg.command && msg.roomID` BEFORE
// `msg.command === 'stateRequest' && msg.roomID` — so stateRequest was
// shadowed and never reached.
//
// v2 design (runbook §5):
//   1. Single JSON parse, single schema validation, single switch on `type`.
//   2. membership check BEFORE any room-scoped action.
//   3. host check with 1-2s cache + invalidation.
//   4. bufferedAmount > 512KB → close slow consumer.
//   5. heartbeat isAlive via WS ping frames every 20s.
//   6. per-type rate limits: sync 20/sec burst 30, chat 5/10s, reactions 2/s.
//   7. graceful shutdown: stop accepting, notify draining, close after 10s.

import type { WebSocket } from 'ws';
import type { PrismaClient } from '@prisma/client';
import {
  ClientMessageSchema,
  StateRequestSchema,
  SyncCommandSchema,
  ChatSendSchema,
  ReactionSendSchema,
  ClockProbeSchema,
  PauseRequestSchema,
  PauseResolveSchema,
  type RoomState,
  type SyncStateMessage,
  type SyncStateSnapshotMessage,
  type ChatBroadcast,
  type ParticipantEvent,
  type ErrorMessage,
  type SessionReady,
} from '../contracts/realtime-v2.js';
import type { RoomStateStore } from './roomStateStore.js';
import type { RoomPubSub } from './roomPubSub.js';
import type { ConnectionRegistry, PlinkSocket } from './connectionRegistry.js';
import { filterChatMessage } from '../utils/chatFilter.js';
// M16: ИИ-модератор — муты за маты, системные сообщения в чат
import {
  containsProfanity,
  muteUser,
  muteRemainingSec,
  auditModeration,
  buildModWirePayload,
} from '../moderation/autoMod.js';

// ─────────────────────────────────────────────────────────────────────────────
// Rate limits (per-type, per-socket)
// ─────────────────────────────────────────────────────────────────────────────
const RATE_LIMITS = {
  'sync.command': { max: 20, windowMs: 1000, burst: 30 },
  'sync.state.request': { max: 5, windowMs: 1000, burst: 10 },
  'chat.send': { max: 5, windowMs: 10_000, burst: 8 },
  'reaction.send': { max: 2, windowMs: 1000, burst: 4 },
  'clock.probe': { max: 10, windowMs: 1000, burst: 20 },
  // M26: просьба о паузе прилетает хосту как заметное уведомление, поэтому
  // лимит жёстче чата — одна просьба в 10 с. Иначе гость получил бы способ
  // забить хосту весь экран, не написав ни слова в чат.
  'pause.request': { max: 1, windowMs: 10_000, burst: 2 },
  // M27: ответ хоста. Просьб больше одной в 10 с не бывает (лимит выше),
  // но burst даёт хосту исправить случайный тап «отклонить → принять».
  'pause.resolve': { max: 2, windowMs: 10_000, burst: 3 },
} as const;

type RateBucket = { count: number; resetAt: number };

// ─────────────────────────────────────────────────────────────────────────────
// Host check cache: roomId → { hostId, expiresAt }
// Invalidated on host migration / participant role change.
// ─────────────────────────────────────────────────────────────────────────────
const HOST_CACHE_TTL_MS = 2000;
const hostCache = new Map<string, { hostId: string; expiresAt: number }>();

async function isHost(prisma: PrismaClient, roomId: string, userId: string): Promise<boolean> {
  const cached = hostCache.get(roomId);
  const now = Date.now();
  if (cached && cached.expiresAt > now) {
    return cached.hostId === userId;
  }
  const room = await prisma.room.findUnique({
    where: { id: roomId },
    select: { hostID: true },
  });
  if (!room) return false;
  hostCache.set(roomId, { hostId: room.hostID, expiresAt: now + HOST_CACHE_TTL_MS });
  return room.hostID === userId;
}

/** Invalidate host cache — called on host migration, room teardown, etc. */
export function invalidateHostCache(roomId: string): void {
  hostCache.delete(roomId);
}

// ─────────────────────────────────────────────────────────────────────────────
// Membership check: confirms user is in RoomParticipant for this room.
// DB-checked — never trust the socket's claim alone.
// ─────────────────────────────────────────────────────────────────────────────
async function isRoomMember(prisma: PrismaClient, roomId: string, userId: string): Promise<boolean> {
  // RoomParticipant rows are deleted when a user leaves (no leftAt field).
  // Existence == current membership.
  try {
    const participant = await prisma.roomParticipant.findUnique({
      where: { roomID_userID: { roomID: roomId, userID: userId } },
      select: { id: true },
    });
    return participant !== null;
  } catch {
    // Composite key name may differ — fall back to findFirst
    const participant = await prisma.roomParticipant.findFirst({
      where: { roomID: roomId, userID: userId },
      select: { id: true },
    });
    return participant !== null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error helper — type-safe ErrorMessage
// ─────────────────────────────────────────────────────────────────────────────
function sendError(socket: PlinkSocket, code: string, message: string): void {
  const payload: ErrorMessage = {
    type: 'error',
    protocolVersion: 2,
    code,
    message,
  };
  if (socket.readyState === socket.OPEN) socket.send(JSON.stringify(payload));
}

// ─────────────────────────────────────────────────────────────────────────────
// Rate limit check
// ─────────────────────────────────────────────────────────────────────────────
function checkRateLimit(socket: PlinkSocket, type: keyof typeof RATE_LIMITS): boolean {
  const limit = RATE_LIMITS[type];
  const now = Date.now();
  if (!socket._rateBuckets) socket._rateBuckets = new Map();
  let bucket: RateBucket | undefined = socket._rateBuckets.get(type);
  if (!bucket || now > bucket.resetAt) {
    bucket = { count: 0, resetAt: now + limit.windowMs };
    socket._rateBuckets.set(type, bucket);
  }
  bucket.count++;
  return bucket.count <= limit.max + limit.burst;
}

// ─────────────────────────────────────────────────────────────────────────────
// Slow consumer guard (runbook §5)
// ─────────────────────────────────────────────────────────────────────────────
function checkSlowConsumer(socket: PlinkSocket): boolean {
  const buffered = (socket.bufferedAmount ?? 0) as number;
  if (buffered > 512 * 1024) {
    sendError(socket, 'SLOW_CONSUMER', 'Buffered amount exceeded 512KB — closing');
    socket.close(1011, 'Slow consumer');
    return false;
  }
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main router
// ─────────────────────────────────────────────────────────────────────────────
export interface RouterDeps {
  prisma: PrismaClient;
  store: RoomStateStore;
  pubsub: RoomPubSub;
  registry: ConnectionRegistry;
  /**
   * P0-3: typed event bus for chat/reaction/participant distribution
   * across replicas. Router PUBLISHES to this bus; gateway subscribes
   * per-room and fans out to local sockets.
   */
  eventBus: import('./roomEventBus.js').RoomEventBus;
  /**
   * Returns the current epoch for a room. Typically reads from the last
   * known state in Redis (via store.get), defaulting to 1.
   */
  currentEpoch: (roomId: string) => Promise<number>;
}

export function createMessageRouter(deps: RouterDeps) {
  const { prisma, store, registry, eventBus, currentEpoch } = deps;

  /**
   * Handle a single inbound WebSocket message.
   * All control flow is type-based — no `msg.command && msg.roomID` shadowing.
   */
  async function handleMessage(socket: PlinkSocket, raw: Buffer): Promise<void> {
    // §5: payload size guard
    if (raw.byteLength > 64 * 1024) {
      socket.close(1009, 'Payload too large');
      return;
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(raw.toString('utf8'));
    } catch {
      sendError(socket, 'INVALID_JSON', 'Message is not valid JSON');
      return;
    }

    // Single schema parse — discriminatedUnion('type', ...) rejects unknown
    // types AND validates per-type shape with .strict().
    let msg;
    try {
      msg = ClientMessageSchema.parse(parsed);
    } catch (err) {
      sendError(socket, 'SCHEMA_INVALID', (err as Error).message.substring(0, 400));
      return;
    }

    // Slow consumer check before any work
    if (!checkSlowConsumer(socket)) return;

    switch (msg.type) {
      // ── sync.state.request ─────────────────────────────────────────────
      // CRITICAL: handled FIRST in v2 (the §19 bug fix). The old code's
      // `msg.command && msg.roomID` shadowed this case.
      case 'sync.state.request': {
        if (!checkRateLimit(socket, 'sync.state.request')) {
          sendError(socket, 'RATE_LIMITED', 'state.request rate limit exceeded');
          return;
        }
        const m = StateRequestSchema.parse(parsed);
        // Membership check (§5)
        if (!(await isRoomMember(prisma, m.roomId, socket.userId!))) {
          sendError(socket, 'NOT_MEMBER', 'User is not a member of this room');
          return;
        }
        const state = await store.get(m.roomId);
        const reply: SyncStateSnapshotMessage = {
          type: 'sync.state.snapshot',
          protocolVersion: 2,
          roomId: m.roomId,
          state,
          serverTimeMs: Date.now(),
        };
        socket.send(JSON.stringify(reply));
        return;
      }

      // ── sync.command (host-only) ───────────────────────────────────────
      case 'sync.command': {
        if (!checkRateLimit(socket, 'sync.command')) {
          sendError(socket, 'RATE_LIMITED', 'sync.command rate limit exceeded');
          return;
        }
        const m = SyncCommandSchema.parse(parsed);
        if (!(await isRoomMember(prisma, m.roomId, socket.userId!))) {
          sendError(socket, 'NOT_MEMBER', 'User is not a member of this room');
          return;
        }
        if (!(await isHost(prisma, m.roomId, socket.userId!))) {
          sendError(socket, 'NOT_HOST', 'Only the host can control playback');
          return;
        }
        const epoch = await currentEpoch(m.roomId);
        const result = await store.apply({
          roomId: m.roomId,
          actionId: m.actionId,
          epoch,
          mediaId: m.mediaId,
          positionMs: m.positionMs,
          playing: m.playing,
          rate: m.rate,
          issuedBy: socket.userId!,
        });
        if (result.kind === 'stale_epoch') {
          sendError(socket, 'STALE_EPOCH', 'Server epoch is ahead — refetch snapshot');
          return;
        }
        // result.kind === 'applied' | 'replay'
        // Lua PUBLISH already fired for 'applied'; this replica's local
        // subscribers (RoomPubSub) will fan it out to local connections.
        // For 'replay', we don't republish (idempotent no-op).
        if (result.kind === 'replay' && result.state) {
          // Send the current state back to the caller so they can reconcile
          const reply: SyncStateMessage = {
            type: 'sync.state',
            protocolVersion: 2,
            roomId: m.roomId,
            state: result.state,
            serverTimeMs: Date.now(),
          };
          socket.send(JSON.stringify(reply));
        }
        return;
      }

      // ── chat.send ──────────────────────────────────────────────────────
      case 'chat.send': {
        if (!checkRateLimit(socket, 'chat.send')) {
          sendError(socket, 'RATE_LIMITED', 'chat rate limit exceeded');
          return;
        }
        const m = ChatSendSchema.parse(parsed);
        if (!(await isRoomMember(prisma, m.roomId, socket.userId!))) {
          sendError(socket, 'NOT_MEMBER', 'User is not a member of this room');
          return;
        }
        // M16: активный мут от ИИ-модератора — сообщения не принимаются
        const mutedSec = muteRemainingSec(m.roomId, socket.userId!);
        if (mutedSec > 0) {
          sendError(socket, 'MUTED', `Вы замучены модератором ещё на ${mutedSec} сек`);
          return;
        }
        const filtered = filterChatMessage(m.text);
        if (!filtered.ok) {
          sendError(socket, 'MESSAGE_BLOCKED', filtered.reason);
          return;
        }
        // M16: маты → временный мут; сообщение НЕ сохраняется и НЕ рассылается,
        // в чат уходит системное уведомление ИИ-модератора
        if (containsProfanity(m.text)) {
          const seconds = muteUser(m.roomId, socket.userId!, 'profanity');
          const sysId = crypto.randomUUID();
          await auditModeration({
            roomId: m.roomId,
            messageId: sysId,
            subjectUserId: socket.userId!,
            action: 'mute_profanity',
            reasonCode: 'profanity',
          });
          await eventBus.publish(m.roomId, {
            kind: 'chat.broadcast',
            roomId: m.roomId,
            messageId: sysId,
            clientMessageId: sysId,
            senderId: 'plink-ai-moderator',
            senderName: 'ИИ-модератор',
            text: buildModWirePayload({
              action: 'mute',
              userId: socket.userId!,
              username: socket.username ?? 'user',
              seconds,
              reason: 'profanity',
            }),
            createdAtMs: Date.now(),
          });
          sendError(socket, 'MUTED', `Мут на ${seconds} сек за нецензурную лексику`);
          return;
        }
        // Persist
        const created = await prisma.chatMessage.create({
          data: {
            roomID: m.roomId,
            senderID: socket.userId!,
            text: filtered.text,
          },
        });
        // P0-3: publish to event bus — ALL replicas (including this one)
        // receive via subscriber and fan out to local sockets. We do NOT
        // also call registry.broadcastLocal — that would double-deliver
        // to local sockets on this replica.
        await eventBus.publish(m.roomId, {
          kind: 'chat.broadcast',
          roomId: m.roomId,
          messageId: created.id,
          clientMessageId: m.clientMessageId,
          senderId: socket.userId!,
          senderName: socket.username ?? 'unknown',
          text: filtered.text,
          createdAtMs: created.createdAt?.getTime?.() ?? Date.now(),
        });
        return;
      }

      // ── reaction.send ──────────────────────────────────────────────────
      // GPT-5 BE-P0-05: server-side validation — grapheme count, allowlisted
      // emoji, entitlement check for premium reactions.
      case 'reaction.send': {
        if (!checkRateLimit(socket, 'reaction.send')) {
          sendError(socket, 'RATE_LIMITED', 'reaction rate limit exceeded');
          return;
        }
        const m = ReactionSendSchema.parse(parsed);
        if (!(await isRoomMember(prisma, m.roomId, socket.userId!))) {
          sendError(socket, 'NOT_MEMBER', 'User is not a member of this room');
          return;
        }

        // GPT-5 BE-P0-05: validate emoji is in allowlist (prevent arbitrary
        // text/bidi abuse). Allow common emoji + a premium set.
        const ALLOWED_FREE_EMOJIS = new Set([
          '❤️', '😂', '😍', '👍', '🔥', '😮', '😢', '👏', '🎉', '💯',
          '🤣', '🥰', '😱', '🤩', '🤔', '😴', '🤯', '🥳', '😭', '🤗',
        ]);
        const ALLOWED_PREMIUM_EMOJIS = new Set([
          '💎', '👑', '🚀', '⚡', '🌟', '🎨', '🎭', '🏆', '🌈', '✨',
        ]);
        const allAllowed = new Set([...ALLOWED_FREE_EMOJIS, ...ALLOWED_PREMIUM_EMOJIS]);

        // GPT-5.6 SOL fix: Array.from() counts UTF-16 code units, not grapheme clusters.
        // ❤️ = U+2764 U+FE0F → Array.from gives 2 elements, but it's 1 grapheme cluster.
        // Use Intl.Segmenter (Node 16+) for correct grapheme cluster counting.
        const segmenter = new Intl.Segmenter('en', { granularity: 'grapheme' });
        const graphemeCount = [...segmenter.segment(m.emoji)].length;
        if (graphemeCount > 4) {
          sendError(socket, 'INVALID_REACTION', 'Emoji too long (max 4 graphemes)');
          return;
        }

        // GPT-5 BE-P0-05: must be in allowlist.
        if (!allAllowed.has(m.emoji)) {
          sendError(socket, 'INVALID_REACTION', 'Emoji not in allowlist');
          return;
        }

        // GPT-5 BE-P0-05: premium emoji requires entitlement.
        if (ALLOWED_PREMIUM_EMOJIS.has(m.emoji)) {
          const user = await prisma.user.findUnique({
            where: { id: socket.userId! },
            select: { isPremium: true, premiumUntil: true },
          });
          const isPremium = user?.isPremium === true &&
            (!user.premiumUntil || user.premiumUntil > new Date());
          if (!isPremium) {
            sendError(socket, 'PREMIUM_REQUIRED', 'This reaction requires Plink+');
            return;
          }
        }

        // P0-3: publish via event bus — same fanout rule as chat.
        await eventBus.publish(m.roomId, {
          kind: 'reaction.broadcast',
          roomId: m.roomId,
          userId: socket.userId!,
          username: socket.username ?? 'unknown',
          emoji: m.emoji,
          serverTimeMs: Date.now(),
        });
        return;
      }

      // ── pause.request ──────────────────────────────────────────────────
      // M26: гость просит паузу. Плеер НЕ трогаем: управление принадлежит
      // хосту (sync.command проверяет роль), здесь только доставка просьбы.
      case 'pause.request': {
        if (!checkRateLimit(socket, 'pause.request')) {
          sendError(socket, 'RATE_LIMITED', 'pause request rate limit exceeded');
          return;
        }
        const m = PauseRequestSchema.parse(parsed);
        if (!(await isRoomMember(prisma, m.roomId, socket.userId!))) {
          sendError(socket, 'NOT_MEMBER', 'User is not a member of this room');
          return;
        }

        // Причина — свободный текст, поэтому проходит тот же фильтр, что и чат.
        // Без него «просьба о паузе» стала бы каналом в обход модерации.
        const rawReason = m.reason?.trim();
        let reason: string | null = rawReason && rawReason.length > 0 ? rawReason : null;
        if (reason && containsProfanity(reason)) {
          sendError(socket, 'PROFANITY', 'Reason contains prohibited language');
          return;
        }

        await eventBus.publish(m.roomId, {
          kind: 'pause.requested',
          roomId: m.roomId,
          userId: socket.userId!,
          username: socket.username ?? 'unknown',
          reason,
          serverTimeMs: Date.now(),
        });
        return;
      }

      // ── pause.resolve ──────────────────────────────────────────────────
      // M27: хост отвечает на просьбу. Только хост — иначе любой гость мог бы
      // «отклонять» чужие просьбы. Плеер по-прежнему не трогаем: принятая
      // пауза едет отдельным sync.command, который сам проверяет роль.
      case 'pause.resolve': {
        if (!checkRateLimit(socket, 'pause.resolve')) {
          sendError(socket, 'RATE_LIMITED', 'pause resolve rate limit exceeded');
          return;
        }
        const m = PauseResolveSchema.parse(parsed);
        if (!(await isHost(prisma, m.roomId, socket.userId!))) {
          sendError(socket, 'NOT_HOST', 'Only the host can resolve a pause request');
          return;
        }

        await eventBus.publish(m.roomId, {
          kind: 'pause.resolved',
          roomId: m.roomId,
          hostId: socket.userId!,
          hostName: socket.username ?? 'unknown',
          accepted: m.accepted,
          requestUserId: m.requestUserId ?? null,
          serverTimeMs: Date.now(),
        });
        return;
      }

      // ── clock.probe ────────────────────────────────────────────────────
      case 'clock.probe': {
        if (!checkRateLimit(socket, 'clock.probe')) {
          return; // silent — clock probes should not produce error spam
        }
        const m = ClockProbeSchema.parse(parsed);
        socket.send(
          JSON.stringify({
            type: 'clock.probe.reply',
            protocolVersion: 2,
            clientSentMs: m.clientSentMs,
            serverMs: Date.now(),
          }),
        );
        return;
      }

      default: {
        // Exhaustiveness check — TypeScript guarantees we handled every case.
        // Reaching here means a new message type was added to the schema but
        // not to this switch. Cast to never for the compile-time check, but
        // fall back to a runtime error using the parsed type field.
        const _exhaustive: never = msg as never;
        void _exhaustive;
        const fallbackType = (msg as { type?: string } | null)?.type ?? 'unknown';
        sendError(socket, 'UNKNOWN_MESSAGE_TYPE', `Unhandled type: ${fallbackType}`);
        return;
      }
    }
  }

  return { handleMessage };
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers for the gateway to broadcast state to local connections
// (called when RoomPubSub listener fires)
// ─────────────────────────────────────────────────────────────────────────────
export function makeSyncStateMessage(roomId: string, state: RoomState): SyncStateMessage {
  return {
    type: 'sync.state',
    protocolVersion: 2,
    roomId,
    state,
    serverTimeMs: Date.now(),
  };
}

// P1-26: timestampMs parameter — preserve original event timestamp
// instead of regenerating Date.now() at conversion time.
export function makeParticipantEvent(
  kind: 'participant.joined' | 'participant.left',
  roomId: string,
  userId: string,
  username: string,
  timestampMs?: number,
): ParticipantEvent {
  const ts = timestampMs ?? Date.now();
  return {
    type: kind,
    protocolVersion: 2,
    roomId,
    userId,
    username,
    joinedAtMs: kind === 'participant.joined' ? ts : undefined,
    leftAtMs: kind === 'participant.left' ? ts : undefined,
  };
}

export function makeSessionReady(roomId: string, role: 'host' | 'viewer'): SessionReady {
  return {
    type: 'session.ready',
    protocolVersion: 2,
    roomId,
    role,
    serverTimeMs: Date.now(),
  };
}
