// src/tests/contract/pauseResolve.contract.test.ts
// Ответ хоста на просьбу о паузе — контракт целиком, от входящего
// сообщения до провода наружу. Зеркало pauseRequest.contract.test.ts.
//
// Продуктовое правило: это СОЦИАЛЬНЫЙ сигнал, не команда плееру. Принятая
// пауза едет отдельным sync.command (который сам проверяет роль); здесь
// сервер лишь доставляет вердикт. Второе правило — отвечает ТОЛЬКО хост:
// иначе любой гость мог бы «отклонять» чужие просьбы от имени комнаты.
//
// Закрываем четыре стыка:
//   1) входящая схема strict (null в requestUserId и лишние поля не проходят);
//   2) событие проходит РЕАЛЬНУЮ схему шины;
//   3) РЕАЛЬНЫЙ gateway.eventToServerMessage даёт валидный ServerMessage;
//   4) call-site в messageRouter.ts — с проверкой ХОСТА, рейт-лимитом
//      и БЕЗ управления плеером.

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  PauseResolveSchema,
  PauseResolvedSchema,
  ClientMessageSchema,
  ServerMessageSchema,
  CLIENT_MESSAGE_TYPES,
  SERVER_MESSAGE_TYPES,
} from '../../contracts/realtime-v2.js';
import { RoomEventSchema, type RoomEvent } from '../../realtime/roomEventBus.js';

// gateway.ts тянет config, требующий DATABASE_URL на импорте (см. pauseRequest).
process.env.DATABASE_URL ||= 'postgresql://test:test@localhost:5432/plink_test';
const { eventToServerMessage } = await import('../../realtime/gateway.js');

const HOST_UUID = '00000000-0000-4000-8000-000000000000';
const GUEST_UUID = '00000000-0000-4000-8000-000000000001';
const ROOM_UUID = '00000000-0000-4000-8000-00000000000a';

const inbound = {
  type: 'pause.resolve' as const,
  protocolVersion: 2 as const,
  roomId: ROOM_UUID,
  accepted: false,
  requestUserId: GUEST_UUID,
};

const busEvent: Extract<RoomEvent, { kind: 'pause.resolved' }> = {
  kind: 'pause.resolved',
  roomId: ROOM_UUID,
  hostId: HOST_UUID,
  hostName: 'alice',
  accepted: false,
  requestUserId: GUEST_UUID,
  serverTimeMs: 1_700_000_000_000,
};

// ── 1. Входящая схема ─────────────────────────────────────────────────────

describe('pause.resolve — входящая схема', () => {
  it('принимает вердикт с атрибуцией просьбы', () => {
    const parsed = PauseResolveSchema.parse(inbound);
    expect(parsed.accepted).toBe(false);
    expect(parsed.requestUserId).toBe(GUEST_UUID);
  });

  it('принимает вердикт БЕЗ requestUserId (поле отсутствует)', () => {
    const { requestUserId, ...withoutId } = inbound;
    const parsed = PauseResolveSchema.parse(withoutId);
    expect(parsed.requestUserId).toBeUndefined();
  });

  it('отклоняет requestUserId: null — .optional() это не .nullable()', () => {
    // Тот же стык, из-за которого в Swift написан ручной encode(to:):
    // дефолтный кодировщик положил бы null, и сервер отверг бы вердикт.
    expect(() => PauseResolveSchema.parse({ ...inbound, requestUserId: null })).toThrow();
  });

  it('отклоняет requestUserId, который не UUID', () => {
    expect(() => PauseResolveSchema.parse({ ...inbound, requestUserId: 'guest-1' })).toThrow();
  });

  it('отклоняет accepted не-boolean (строку "true" не приводим)', () => {
    expect(() => PauseResolveSchema.parse({ ...inbound, accepted: 'true' })).toThrow();
  });

  it('отклоняет вердикт без accepted', () => {
    const { accepted, ...withoutAccepted } = inbound;
    expect(() => PauseResolveSchema.parse(withoutAccepted)).toThrow();
  });

  it('отклоняет protocolVersion != 2', () => {
    expect(() => PauseResolveSchema.parse({ ...inbound, protocolVersion: 1 })).toThrow();
  });

  it('strict: лишнее поле не проходит', () => {
    // Хост не должен уметь дописать в вердикт ничего своего — например
    // positionMs, из которого однажды сделают «отклонить с перемоткой».
    expect(() => PauseResolveSchema.parse({ ...inbound, positionMs: 0 })).toThrow();
  });

  it('входит в ClientMessage и в CLIENT_MESSAGE_TYPES', () => {
    expect(CLIENT_MESSAGE_TYPES).toContain('pause.resolve');
    expect(ClientMessageSchema.parse(inbound).type).toBe('pause.resolve');
  });
});

// ── 2. Шина ───────────────────────────────────────────────────────────────

describe('pause.resolved — шина (RoomEventBus)', () => {
  it('валидное событие проходит схему шины', () => {
    expect(RoomEventSchema.parse(busEvent).kind).toBe('pause.resolved');
  });

  it('переживает JSON-раунд-трип (publish → Redis → subscriber)', () => {
    expect(RoomEventSchema.parse(JSON.parse(JSON.stringify(busEvent)))).toEqual(busEvent);
  });

  it('requestUserId: null проходит (на шине атрибуция именно nullable)', () => {
    // Как и у pause.requested: на входе поле опциональное, дальше отсутствие
    // атрибуции превращается в явный null.
    expect(RoomEventSchema.parse({ ...busEvent, requestUserId: null }).kind).toBe('pause.resolved');
  });

  it('отклоняет событие без serverTimeMs', () => {
    const { serverTimeMs, ...withoutTime } = busEvent;
    expect(() => RoomEventSchema.parse(withoutTime)).toThrow();
  });

  it('дискриминатор не задевает соседнее pause.requested', () => {
    const request = {
      kind: 'pause.requested',
      roomId: ROOM_UUID,
      userId: GUEST_UUID,
      username: 'bob',
      reason: null,
      serverTimeMs: 1_700_000_000_000,
    };
    expect(RoomEventSchema.parse(request).kind).toBe('pause.requested');
  });
});

// ── 3. Провод (реальный маппинг gateway) ──────────────────────────────────

describe('pause.resolved — провод (реальный gateway.eventToServerMessage)', () => {
  it('входит в объединение ServerMessage и в SERVER_MESSAGE_TYPES', () => {
    expect(SERVER_MESSAGE_TYPES).toContain('pause.resolved');
    expect(ServerMessageSchema.parse(eventToServerMessage(busEvent)).type).toBe('pause.resolved');
  });

  it('сериализуется в ожидаемый JSON', () => {
    expect(JSON.parse(JSON.stringify(eventToServerMessage(busEvent)))).toEqual({
      type: 'pause.resolved',
      protocolVersion: 2,
      roomId: ROOM_UUID,
      hostId: HOST_UUID,
      hostName: 'alice',
      accepted: false,
      requestUserId: GUEST_UUID,
      serverTimeMs: 1_700_000_000_000,
    });
  });

  it('вердикт без атрибуции уходит с явным null, а не с пропавшим полем', () => {
    const wire = JSON.parse(JSON.stringify(eventToServerMessage({ ...busEvent, requestUserId: null })));
    expect(wire.requestUserId).toBeNull();
    expect('requestUserId' in wire).toBe(true);
    ServerMessageSchema.parse(wire);
  });

  it('десериализуется обратно в валидное сообщение', () => {
    const original = eventToServerMessage(busEvent);
    expect(ServerMessageSchema.parse(JSON.parse(JSON.stringify(original)))).toEqual(original);
  });

  it('оба вердикта легальны на всех границах', () => {
    const variants: Array<Extract<RoomEvent, { kind: 'pause.resolved' }>> = [
      { ...busEvent, accepted: true, requestUserId: null, hostName: 'a' },
      { ...busEvent, accepted: false, hostName: 'x'.repeat(64) },
    ];
    for (const v of variants) {
      RoomEventSchema.parse(v); // легально для шины…
      const msg = ServerMessageSchema.parse(eventToServerMessage(v)); // …и для провода
      expect(msg).toMatchObject({
        type: 'pause.resolved',
        hostId: v.hostId,
        hostName: v.hostName,
        accepted: v.accepted,
        requestUserId: v.requestUserId,
      });
    }
  });

  it('не отдаёт наружу sync.state — вердикт не является командой плееру', () => {
    const wire = eventToServerMessage(busEvent) as Record<string, unknown>;
    expect(wire.type).toBe('pause.resolved');
    expect(wire.state).toBeUndefined();
    expect(wire.playing).toBeUndefined();
    expect(wire.positionMs).toBeUndefined();
  });

  it('отклоняет protocolVersion != 2 на проводе', () => {
    const bad = { ...(eventToServerMessage(busEvent) as Record<string, unknown>), protocolVersion: 1 };
    expect(() => PauseResolvedSchema.parse(bad)).toThrow();
  });
});

// ── 4. Тривайр на call-site ───────────────────────────────────────────────
// Поднимать messageRouter с prisma/redis здесь так же дорого, как в
// pauseRequest.contract — читаем исходник тем же способом.

const ROUTER_SRC = readFileSync(
  fileURLToPath(new URL('../../realtime/messageRouter.ts', import.meta.url)),
  'utf8',
);

/// Тело обработчика — от `case 'pause.resolve'` до следующего case.
const HANDLER_SRC = (() => {
  const start = ROUTER_SRC.indexOf("case 'pause.resolve'");
  expect(start).toBeGreaterThan(-1);
  const next = ROUTER_SRC.indexOf('      case ', start + 10);
  return ROUTER_SRC.slice(start, next > start ? next : start + 2000);
})();

/// Без строчных комментариев: негативные проверки смотрят только на КОД.
const HANDLER_CODE = HANDLER_SRC.replace(/\/\/[^\n]*/g, '');

describe('pause.resolve — call-site в realtime/messageRouter.ts', () => {
  it('обработчик есть и валидирует настоящей схемой', () => {
    expect(HANDLER_SRC).toContain('PauseResolveSchema.parse(');
  });

  it('публикует событие в шину', () => {
    expect(HANDLER_SRC).toContain('eventBus.publish(');
    expect(HANDLER_SRC).toContain("kind: 'pause.resolved'");
  });

  it('проверяет РОЛЬ ХОСТА, а не просто членство', () => {
    // Главное отличие от pause.request: вердикт от гостя — это способ
    // «отклонять» чужие просьбы от имени комнаты.
    expect(HANDLER_SRC).toContain('isHost(');
    expect(HANDLER_SRC).toContain('NOT_HOST');
  });

  it('стоит под рейт-лимитом', () => {
    expect(HANDLER_SRC).toContain("checkRateLimit(socket, 'pause.resolve')");
    expect(HANDLER_SRC).toContain('RATE_LIMITED');
  });

  it('лимит объявлен: 2 вердикта в 10 секунд', () => {
    const limitsIdx = ROUTER_SRC.indexOf("'pause.resolve': {");
    expect(limitsIdx).toBeGreaterThan(-1);
    const decl = ROUTER_SRC.slice(limitsIdx, limitsIdx + 120);
    expect(decl).toMatch(/max:\s*2\b/);
    expect(decl).toMatch(/windowMs:\s*10_000\b/);
  });

  it('НЕ управляет плеером: ни sync.command, ни записи состояния комнаты', () => {
    // Принятая пауза едет отдельным sync.command от клиента хоста. Появится
    // здесь применение состояния — и «социальный сигнал» начнёт дёргать плеер
    // в обход epoch/seq-машинерии синхронизации.
    expect(HANDLER_CODE).not.toContain('sync.command');
    expect(HANDLER_CODE).not.toContain('applyCommand');
    expect(HANDLER_CODE).not.toContain('setRoomState');
    expect(HANDLER_CODE).not.toContain('playing:');
  });

  it('не рассылает мимо шины (иначе двойная доставка на реплике-издателе)', () => {
    expect(HANDLER_CODE).not.toContain('broadcastLocal');
  });
});
