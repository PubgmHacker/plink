// src/tests/contract/pauseRequest.contract.test.ts
// M26: просьба гостя о паузе — контракт целиком, от входящего сообщения до
// провода наружу.
//
// Продуктовое правило, которое эти тесты и охраняют: СЕРВЕР НЕ СТАВИТ ПАУЗУ.
// Он доставляет просьбу, решение остаётся за хостом. Как только в обработчик
// заедет sync.command или прямая запись состояния комнаты, любой гость получит
// кнопку «остановить чужой сеанс» — и об этом узнают не из ревью, а из отзывов.
//
// Закрываем четыре стыка:
//   1) входящая схема strict (лишние поля и null в reason не проходят);
//   2) событие проходит РЕАЛЬНУЮ схему шины (иначе подписчик молча дропнет);
//   3) РЕАЛЬНЫЙ gateway.eventToServerMessage даёт валидный ServerMessage;
//   4) call-site в messageRouter.ts на месте — с проверкой членства,
//      фильтром мата и рейт-лимитом, и БЕЗ управления плеером.
//
// Схемы и функции берём из исходников, а не переписываем копией:
// roomEventBus.contract показал, чем кончается ручное зеркало.

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  PauseRequestSchema,
  PauseRequestedSchema,
  ClientMessageSchema,
  ServerMessageSchema,
  CLIENT_MESSAGE_TYPES,
  SERVER_MESSAGE_TYPES,
} from '../../contracts/realtime-v2.js';
import { RoomEventSchema, type RoomEvent } from '../../realtime/roomEventBus.js';

// gateway.ts тянет config, который требует DATABASE_URL на импорте. Реальных
// подключений при импорте нет (Redis-клиенты создаются в конструкторе класса),
// поэтому достаточно заглушки в env ДО динамического импорта.
process.env.DATABASE_URL ||= 'postgresql://test:test@localhost:5432/plink_test';
const { eventToServerMessage } = await import('../../realtime/gateway.js');

const VALID_UUID = '00000000-0000-4000-8000-000000000000';
const OTHER_UUID = '00000000-0000-4000-8000-000000000001';

const inbound = {
  type: 'pause.request' as const,
  protocolVersion: 2 as const,
  roomId: VALID_UUID,
  reason: 'отойду на минуту',
};

const busEvent: Extract<RoomEvent, { kind: 'pause.requested' }> = {
  kind: 'pause.requested',
  roomId: VALID_UUID,
  userId: OTHER_UUID,
  username: 'alice',
  reason: 'отойду на минуту',
  serverTimeMs: 1_700_000_000_000,
};

// ── 1. Входящая схема ─────────────────────────────────────────────────────

describe('pause.request — входящая схема', () => {
  it('принимает просьбу с причиной', () => {
    const parsed = PauseRequestSchema.parse(inbound);
    expect(parsed.reason).toBe('отойду на минуту');
  });

  it('принимает просьбу БЕЗ причины (поле отсутствует)', () => {
    const { reason, ...withoutReason } = inbound;
    const parsed = PauseRequestSchema.parse(withoutReason);
    expect(parsed.reason).toBeUndefined();
  });

  it('отклоняет reason: null — .optional() это не .nullable()', () => {
    // Ровно тот стык, из-за которого в Swift написан ручной encode(to:):
    // дефолтный кодировщик положил бы "reason": null и сервер отверг бы
    // совершенно нормальную просьбу без пометки.
    expect(() => PauseRequestSchema.parse({ ...inbound, reason: null })).toThrow();
  });

  it('отклоняет пустой reason (min 1)', () => {
    expect(() => PauseRequestSchema.parse({ ...inbound, reason: '' })).toThrow();
  });

  it('отклоняет reason длиннее 120 символов', () => {
    expect(() => PauseRequestSchema.parse({ ...inbound, reason: 'я'.repeat(121) })).toThrow();
  });

  it('принимает reason ровно 120 символов (граница включительно)', () => {
    const parsed = PauseRequestSchema.parse({ ...inbound, reason: 'я'.repeat(120) });
    expect(parsed.reason).toHaveLength(120);
  });

  it('отклоняет protocolVersion != 2', () => {
    expect(() => PauseRequestSchema.parse({ ...inbound, protocolVersion: 1 })).toThrow();
  });

  it('отклоняет roomId, который не UUID', () => {
    expect(() => PauseRequestSchema.parse({ ...inbound, roomId: 'room-1' })).toThrow();
  });

  it('strict: лишнее поле не проходит', () => {
    // Гость не должен уметь дописать в просьбу ничего своего — например
    // positionMs, из которого однажды сделают «просьбу с перемоткой».
    expect(() => PauseRequestSchema.parse({ ...inbound, positionMs: 0 })).toThrow();
  });

  it('входит в ClientMessage и в CLIENT_MESSAGE_TYPES', () => {
    expect(CLIENT_MESSAGE_TYPES).toContain('pause.request');
    expect(ClientMessageSchema.parse(inbound).type).toBe('pause.request');
  });
});

// ── 2. Шина ───────────────────────────────────────────────────────────────

describe('pause.requested — шина (RoomEventBus)', () => {
  it('валидное событие проходит схему шины', () => {
    expect(RoomEventSchema.parse(busEvent).kind).toBe('pause.requested');
  });

  it('переживает JSON-раунд-трип (publish → Redis → subscriber)', () => {
    expect(RoomEventSchema.parse(JSON.parse(JSON.stringify(busEvent)))).toEqual(busEvent);
  });

  it('reason: null проходит (на шине причина именно nullable)', () => {
    // Границы шины и провода совпадают намеренно: на входе поле опциональное,
    // а дальше отсутствие причины превращается в явный null.
    expect(RoomEventSchema.parse({ ...busEvent, reason: null }).kind).toBe('pause.requested');
  });

  it('отклоняет событие без serverTimeMs', () => {
    const { serverTimeMs, ...withoutTime } = busEvent;
    expect(() => RoomEventSchema.parse(withoutTime)).toThrow();
  });

  it('дискриминатор не задевает соседние события', () => {
    const reaction = {
      kind: 'reaction.broadcast',
      roomId: VALID_UUID,
      userId: OTHER_UUID,
      username: 'alice',
      emoji: '🔥',
      serverTimeMs: 1_700_000_000_000,
    };
    expect(RoomEventSchema.parse(reaction).kind).toBe('reaction.broadcast');
  });
});

// ── 3. Провод (реальный маппинг gateway) ──────────────────────────────────

describe('pause.requested — провод (реальный gateway.eventToServerMessage)', () => {
  it('входит в объединение ServerMessage и в SERVER_MESSAGE_TYPES', () => {
    expect(SERVER_MESSAGE_TYPES).toContain('pause.requested');
    expect(ServerMessageSchema.parse(eventToServerMessage(busEvent)).type).toBe('pause.requested');
  });

  it('сериализуется в ожидаемый JSON', () => {
    expect(JSON.parse(JSON.stringify(eventToServerMessage(busEvent)))).toEqual({
      type: 'pause.requested',
      protocolVersion: 2,
      roomId: VALID_UUID,
      userId: OTHER_UUID,
      username: 'alice',
      reason: 'отойду на минуту',
      serverTimeMs: 1_700_000_000_000,
    });
  });

  it('просьба без причины уходит с явным null, а не с пропавшим полем', () => {
    // Swift-декодер ждёт String? — отсутствие ключа он тоже переживёт, но
    // явный null не даёт полю однажды тихо исчезнуть из контракта.
    const wire = JSON.parse(JSON.stringify(eventToServerMessage({ ...busEvent, reason: null })));
    expect(wire.reason).toBeNull();
    expect('reason' in wire).toBe(true);
    ServerMessageSchema.parse(wire);
  });

  it('десериализуется обратно в валидное сообщение', () => {
    const original = eventToServerMessage(busEvent);
    expect(ServerMessageSchema.parse(JSON.parse(JSON.stringify(original)))).toEqual(original);
  });

  it('маппинг не теряет поля ни на одной легальной границе', () => {
    const variants: Array<Extract<RoomEvent, { kind: 'pause.requested' }>> = [
      { ...busEvent, reason: null, username: 'a' },
      { ...busEvent, reason: 'я'.repeat(120), username: 'x'.repeat(64) },
    ];
    for (const v of variants) {
      RoomEventSchema.parse(v); // легально для шины…
      const msg = ServerMessageSchema.parse(eventToServerMessage(v)); // …и для провода
      expect(msg).toMatchObject({
        type: 'pause.requested',
        userId: v.userId,
        username: v.username,
        reason: v.reason,
      });
    }
  });

  it('не отдаёт наружу sync.state — просьба не является командой плееру', () => {
    const wire = eventToServerMessage(busEvent) as Record<string, unknown>;
    expect(wire.type).toBe('pause.requested');
    expect(wire.state).toBeUndefined();
    expect(wire.playing).toBeUndefined();
    expect(wire.positionMs).toBeUndefined();
  });

  it('отклоняет protocolVersion != 2 на проводе', () => {
    const bad = { ...(eventToServerMessage(busEvent) as Record<string, unknown>), protocolVersion: 1 };
    expect(() => PauseRequestedSchema.parse(bad)).toThrow();
  });
});

// ── 4. Тривайр на call-site ───────────────────────────────────────────────
// Схемы и маппинг проверяются в изоляции, а «роутер вообще обрабатывает
// сообщение» — нет: поднимать messageRouter с prisma/redis здесь слишком
// дорого. Читаем исходник, как это уже делает roomAppearance.contract.

const ROUTER_SRC = readFileSync(
  fileURLToPath(new URL('../../realtime/messageRouter.ts', import.meta.url)),
  'utf8',
);

/// Тело обработчика — от `case 'pause.request'` до следующего case.
const HANDLER_SRC = (() => {
  const start = ROUTER_SRC.indexOf("case 'pause.request'");
  expect(start).toBeGreaterThan(-1);
  const next = ROUTER_SRC.indexOf('    case ', start + 10);
  return ROUTER_SRC.slice(start, next > start ? next : start + 2000);
})();

/// Тот же обработчик без строчных комментариев. Негативные проверки ниже
/// смотрят только на КОД: иначе комментарий «плеером управляет sync.command»
/// ронял бы тест, который этот комментарий как раз и описывает — а закомменти-
/// рованный вызов, наоборот, сошёл бы за живой.
const HANDLER_CODE = HANDLER_SRC.replace(/\/\/[^\n]*/g, '');

describe('pause.request — call-site в realtime/messageRouter.ts', () => {
  it('обработчик есть и валидирует настоящей схемой', () => {
    expect(HANDLER_SRC).toContain('PauseRequestSchema.parse(');
  });

  it('публикует событие в шину', () => {
    expect(HANDLER_SRC).toContain('eventBus.publish(');
    expect(HANDLER_SRC).toContain("kind: 'pause.requested'");
  });

  it('проверяет членство в комнате', () => {
    // Без этого просить паузу в чужой комнате мог бы любой владелец токена.
    expect(HANDLER_SRC).toContain('isRoomMember(');
    expect(HANDLER_SRC).toContain('NOT_MEMBER');
  });

  it('прогоняет свободный текст через тот же фильтр, что и чат', () => {
    // Иначе reason становится обходом модерации: 120 символов кому угодно.
    expect(HANDLER_SRC).toContain('containsProfanity(');
  });

  it('стоит под рейт-лимитом', () => {
    expect(HANDLER_SRC).toContain("checkRateLimit(socket, 'pause.request')");
    expect(HANDLER_SRC).toContain('RATE_LIMITED');
  });

  it('лимит строже чата: не больше одной просьбы в 10 секунд', () => {
    const limitsIdx = ROUTER_SRC.indexOf("'pause.request': {");
    expect(limitsIdx).toBeGreaterThan(-1);
    const decl = ROUTER_SRC.slice(limitsIdx, limitsIdx + 120);
    expect(decl).toMatch(/max:\s*1\b/);
    expect(decl).toMatch(/windowMs:\s*10_000\b/);
  });

  it('НЕ управляет плеером: ни sync.command, ни записи состояния комнаты', () => {
    // Главный инвариант фичи. Появится здесь применение состояния — и просьба
    // превратится в право любого гостя остановить чужой сеанс.
    expect(HANDLER_CODE).not.toContain('sync.command');
    expect(HANDLER_CODE).not.toContain('applyCommand');
    expect(HANDLER_CODE).not.toContain('setRoomState');
    expect(HANDLER_CODE).not.toContain('playing:');
  });

  it('не рассылает мимо шины (иначе двойная доставка на реплике-издателе)', () => {
    // Правило roomEventBus: издатель НЕ зовёт broadcastLocal сам.
    expect(HANDLER_CODE).not.toContain('broadcastLocal');
  });
});
