// src/tests/contract/roomAppearance.contract.test.ts
// Живая доставка темы комнаты.
//
// PATCH /rooms/:id/appearance раньше «броадкастил» через несуществующий
// fastify.io — доставка была мёртвой. Теперь роут публикует событие в
// RoomEventBus, а gateway разворачивает его в wire-сообщение v2.
// Тесты закрывают три стыка:
//   1) событие проходит РЕАЛЬНУЮ схему шины (не молча дропается подписчиком);
//   2) РЕАЛЬНЫЙ gateway.eventToServerMessage даёт сообщение, проходящее
//      ServerMessageSchema (раньше здесь была ручная копия маппинга — тест
//      зеленел бы, даже если продакшн-маппинг сломан);
//   3) call-site в rooms.ts на месте — иначе доставка снова станет мёртвой,
//      а схемы останутся валидными и вся сюита зелёной.
//
// Схемы и функции берём из исходников, а не переписываем копией: roomEventBus.contract
// как раз показал, чем кончается ручное зеркало (его копия успела разойтись
// с оригиналом по clientMessageId/senderId/text).

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  RoomAppearanceUpdatedSchema,
  ServerMessageSchema,
  SERVER_MESSAGE_TYPES,
} from '../../contracts/realtime-v2.js';
import { RoomEventSchema, type RoomEvent } from '../../realtime/roomEventBus.js';

// gateway.ts тянет config, который требует DATABASE_URL на импорте. Реальных
// подключений при импорте нет (Redis-клиенты создаются в конструкторе класса),
// поэтому достаточно заглушки в env ДО динамического импорта.
process.env.DATABASE_URL ||= 'postgresql://test:test@localhost:5432/plink_test';
const { eventToServerMessage, RealtimeGateway } = await import('../../realtime/gateway.js');

const VALID_UUID = '00000000-0000-4000-8000-000000000000';

const busEvent: Extract<RoomEvent, { kind: 'room.appearance.updated' }> = {
  kind: 'room.appearance.updated',
  roomId: VALID_UUID,
  themeId: 'room-aurora-live',
  themeRevision: 3,
  intensity: 0.44,
  motionEnabled: true,
  serverTimeMs: 1_700_000_000_000,
};

describe('room.appearance.updated — шина (RoomEventBus)', () => {
  it('валидное событие проходит схему шины', () => {
    const parsed = RoomEventSchema.parse(busEvent);
    expect(parsed.kind).toBe('room.appearance.updated');
  });

  it('переживает JSON-раунд-трип (publish → Redis → subscriber)', () => {
    const roundTripped = JSON.parse(JSON.stringify(busEvent));
    expect(RoomEventSchema.parse(roundTripped)).toEqual(busEvent);
  });

  it('дискриминатор не задевает соседние события', () => {
    const reaction = {
      kind: 'reaction.broadcast',
      roomId: VALID_UUID,
      userId: VALID_UUID,
      username: 'alice',
      emoji: '👍',
      serverTimeMs: 1_700_000_000_000,
    };
    expect(RoomEventSchema.parse(reaction).kind).toBe('reaction.broadcast');
  });

  it('режет intensity выше V4-капа 0.44 (не даёт уехать за контракт)', () => {
    expect(() => RoomEventSchema.parse({ ...busEvent, intensity: 0.9 })).toThrow();
  });

  it('отклоняет не-uuid roomId', () => {
    expect(() => RoomEventSchema.parse({ ...busEvent, roomId: 'not-a-uuid' })).toThrow();
  });

  it('отклоняет пустой themeId и дробный themeRevision', () => {
    expect(() => RoomEventSchema.parse({ ...busEvent, themeId: '' })).toThrow();
    expect(() => RoomEventSchema.parse({ ...busEvent, themeRevision: 1.5 })).toThrow();
  });

  it('отклоняет событие без motionEnabled', () => {
    const { motionEnabled, ...withoutMotion } = busEvent;
    expect(() => RoomEventSchema.parse(withoutMotion)).toThrow();
  });
});

describe('room.appearance.updated — провод (реальный gateway.eventToServerMessage)', () => {
  it('входит в объединение ServerMessage и в SERVER_MESSAGE_TYPES', () => {
    expect(SERVER_MESSAGE_TYPES).toContain('room.appearance.updated');
    const msg = ServerMessageSchema.parse(eventToServerMessage(busEvent));
    expect(msg.type).toBe('room.appearance.updated');
  });

  it('сериализуется в ожидаемый JSON без аудит-метаданных', () => {
    const wire = JSON.parse(JSON.stringify(eventToServerMessage(busEvent)));
    expect(wire).toEqual({
      type: 'room.appearance.updated',
      protocolVersion: 2,
      roomId: VALID_UUID,
      appearance: {
        themeId: 'room-aurora-live',
        themeRevision: 3,
        intensity: 0.44,
        motionEnabled: true,
      },
      serverTimeMs: 1_700_000_000_000,
    });
    // updatedAt/updatedBy остаются в БД и наружу не выходят
    expect(wire.appearance.updatedBy).toBeUndefined();
    expect(wire.appearance.updatedAt).toBeUndefined();
  });

  it('десериализуется обратно в валидное сообщение', () => {
    const original = eventToServerMessage(busEvent);
    const decoded = ServerMessageSchema.parse(JSON.parse(JSON.stringify(original)));
    expect(decoded).toEqual(original);
  });

  it('маппинг не теряет поля: любое валидное событие шины → валидный ServerMessage', () => {
    const variants: Array<Extract<RoomEvent, { kind: 'room.appearance.updated' }>> = [
      { ...busEvent, themeId: 'a', themeRevision: 0, intensity: 0, motionEnabled: false },
      { ...busEvent, themeId: 'x'.repeat(64), themeRevision: 9999, intensity: 0.44 },
    ];
    for (const v of variants) {
      RoomEventSchema.parse(v); // событие легально для шины…
      const msg = ServerMessageSchema.parse(eventToServerMessage(v)); // …и для провода
      expect(msg).toMatchObject({
        type: 'room.appearance.updated',
        appearance: {
          themeId: v.themeId,
          themeRevision: v.themeRevision,
          intensity: v.intensity,
          motionEnabled: v.motionEnabled,
        },
      });
    }
  });

  it('неизвестный kind не превращается в сообщение (никакого мусора на провод)', () => {
    expect(eventToServerMessage({ kind: 'totally.unknown' } as unknown as RoomEvent)).toBeNull();
  });

  it('strict: лишнее поле в appearance отклоняется', () => {
    const bad = eventToServerMessage(busEvent) as Record<string, any>;
    bad.appearance = { ...bad.appearance, updatedBy: VALID_UUID };
    expect(() => ServerMessageSchema.parse(bad)).toThrow();
  });

  it('отклоняет protocolVersion != 2', () => {
    const bad = { ...(eventToServerMessage(busEvent) as Record<string, any>), protocolVersion: 1 };
    expect(() => RoomAppearanceUpdatedSchema.parse(bad)).toThrow();
  });

  it('отклоняет плоский appearance (поля не должны утечь в корень)', () => {
    const bad = {
      type: 'room.appearance.updated',
      protocolVersion: 2,
      roomId: VALID_UUID,
      themeId: 'room-aurora-live',
      themeRevision: 3,
      intensity: 0.44,
      motionEnabled: true,
      serverTimeMs: 1_700_000_000_000,
    };
    expect(() => RoomAppearanceUpdatedSchema.parse(bad)).toThrow();
  });
});

// ── Тривайр на call-site ──────────────────────────────────────────────────
// Схемы и маппинг проверяются в изоляции, а «роут вообще зовёт публикацию» —
// нет: поднимать rooms.ts с prisma/auth/redis здесь слишком дорого. Поэтому
// читаем исходник, как это уже делает protocol-parity-тест для Swift. Если из
// rooms.ts убрать вызов, доставка снова станет мёртвой — и упадёт именно этот
// тест, а не «ничего».
const ROOMS_SRC = readFileSync(
  fileURLToPath(new URL('../../routes/rooms.ts', import.meta.url)),
  'utf8',
);

describe('room.appearance.updated — call-site в routes/rooms.ts', () => {
  it('PATCH /rooms/:id/appearance публикует событие через gateway', () => {
    expect(ROOMS_SRC).toContain('gateway.publishRoomAppearance(');
    expect(ROOMS_SRC).toContain("kind: 'room.appearance.updated'");
  });

  it('метод, который зовёт роут, реально есть у gateway', () => {
    // Пара с тестом выше: строка в rooms.ts + метод в классе. Переименуют
    // метод — упадёт эта проверка, а не тишина в проде.
    expect(typeof (RealtimeGateway.prototype as any).publishRoomAppearance).toBe('function');
  });

  it('вызов НЕ спрятан за optional chaining (иначе это тихий no-op)', () => {
    // Именно `?.()` на самом методе однажды превратило доставку в фикцию:
    // исключения нет, catch не срабатывает, в логе пусто.
    expect(ROOMS_SRC).not.toContain('publishRoomAppearance?.(');
  });

  it('у роута есть рейт-лимит (PATCH усиливает фан-аут на всю комнату)', () => {
    const routeIdx = ROOMS_SRC.indexOf("fastify.patch('/rooms/:id/appearance'");
    expect(routeIdx).toBeGreaterThan(-1);
    const head = ROOMS_SRC.slice(routeIdx, routeIdx + 400);
    expect(head).toContain('rateLimit');
  });
});
