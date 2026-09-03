// src/tests/contract/roomAppearance.contract.test.ts
// Live delivery of the room theme.
//
// PATCH /rooms/:id/appearance used to "broadcast" through a non-existent
// fastify.io, so delivery was dead. The route now publishes an event to the
// RoomEventBus and the gateway expands it into a v2 wire message.
// The tests cover three seams:
//   1) the event passes the REAL bus schema (it is not silently dropped by a subscriber);
//   2) the REAL gateway.eventToServerMessage yields a message that passes
//      ServerMessageSchema (this used to be a hand-written copy of the mapping, so the
//      test would stay green even with the production mapping broken);
//   3) the call site in rooms.ts is in place; otherwise delivery goes dead again while
//      the schemas stay valid and the whole suite stays green.
//
// Schemas and functions come from the sources rather than a rewritten copy:
// roomEventBus.contract showed exactly how a hand-kept mirror ends (its copy had
// drifted from the original on clientMessageId/senderId/text).

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  RoomAppearanceUpdatedSchema,
  ServerMessageSchema,
  SERVER_MESSAGE_TYPES,
} from '../../contracts/realtime-v2.js';
import { RoomEventSchema, type RoomEvent } from '../../realtime/roomEventBus.js';

// gateway.ts pulls in config, which requires DATABASE_URL at import time. Nothing
// connects on import (the Redis clients are created in the class constructor), so a
// placeholder in env BEFORE the dynamic import is enough.
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
    // updatedAt/updatedBy stay in the database and never go out
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
      RoomEventSchema.parse(v); // the event is legal for the bus…
      const msg = ServerMessageSchema.parse(eventToServerMessage(v)); // …and for the wire
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

// ── Tripwire on the call site ──────────────────────────────────────────────────
// Schemas and the mapping are checked in isolation, but "does the route call the
// publish at all" is not: bringing up rooms.ts with prisma/auth/redis is too expensive
// here. So we read the source, the way the protocol-parity test already does for
// Swift. Remove the call from rooms.ts and delivery goes dead again, and it is this
// test that fails rather than "nothing".
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
    // Pairs with the test above: the line in rooms.ts plus the method on the class.
    // Rename the method and this check fails, instead of silence in production.
    expect(typeof (RealtimeGateway.prototype as any).publishRoomAppearance).toBe('function');
  });

  it('вызов НЕ спрятан за optional chaining (иначе это тихий no-op)', () => {
    // It was `?.()` on the method itself that once turned delivery into a fiction:
    // no exception, catch never fires, nothing in the log.
    expect(ROOMS_SRC).not.toContain('publishRoomAppearance?.(');
  });

  it('у роута есть рейт-лимит (PATCH усиливает фан-аут на всю комнату)', () => {
    // Layout-independent: Prettier may put the path on its own line, so match the
    // call with a regex and look for the limiter anywhere in the route options,
    // i.e. between `fastify.patch(` and the handler's `async (`.
    const route = /fastify\.patch\(\s*'\/rooms\/:id\/appearance'/.exec(ROOMS_SRC);
    expect(route).not.toBeNull();
    const rest = ROOMS_SRC.slice(route!.index);
    const handlerAt = rest.search(/async\s*\(/);
    expect(handlerAt).toBeGreaterThan(0);
    expect(rest.slice(0, handlerAt)).toContain('rateLimit');
  });
});
