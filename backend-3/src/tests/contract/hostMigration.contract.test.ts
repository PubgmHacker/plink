// Аудит 12.08.2026 P0 — передача хоста при его уходе.
//
// До этого `maybeEndAfterLeave` содержала `if (isHost || remaining === 0)`:
// уход хоста закрывал комнату ВСЕМ, кто ещё смотрел. Схема `role.changed`
// (contracts/realtime-v2.ts, P1-64) и `bumpEpoch()` (roomStateStore) были
// написаны под миграцию хоста, но её никто не вызывал — фича была собрана
// и не подключена.
//
// Тест закрепляет ровно то поведение, из-за которого сеанс раньше умирал:
// хост уходит, а комната живёт и получает нового хоста.
import { describe, it, expect } from 'vitest';
import { maybeEndAfterLeave, type PrismaLike } from '../../services/roomLifecycle.js';
import { RoomEventSchema } from '../../realtime/roomEventBus.js';
import { ServerMessageSchema } from '../../contracts/realtime-v2.js';

// gateway.ts тянет config, который требует DATABASE_URL на импорте. Реальных
// подключений при импорте нет (Redis-клиенты создаются в конструкторе класса),
// поэтому достаточно заглушки в env ДО динамического импорта — тот же приём,
// что в roomAppearance.contract.test.ts.
process.env.DATABASE_URL ||= 'postgresql://test:test@localhost:5432/plink_test';
const { eventToServerMessage } = await import('../../realtime/gateway.js');

const ROOM_ID = '11111111-1111-4111-8111-111111111111';
const HOST_ID = '22222222-2222-4222-8222-222222222222';
const GUEST_ID = '33333333-3333-4333-8333-333333333333';

/**
 * Минимальная подделка Prisma под контракт PrismaLike. Держим состояние в
 * переменных, чтобы проверять НЕ вызовы, а результат: активна ли комната и
 * кто в ней хост после ухода.
 */
function makePrisma(opts: {
  hostID: string;
  participants: Array<{ userID: string; username: string; joinedAt: number }>;
}) {
  const state = {
    isActive: true,
    hostID: opts.hostID,
    participants: [...opts.participants],
    endRoomCalled: false,
  };

  const prisma: PrismaLike = {
    room: {
      findUnique: async () => ({
        id: ROOM_ID,
        hostID: state.hostID,
        name: 'Комната',
        mediaItem: null,
        isActive: state.isActive,
      }),
      findMany: async () => [],
      update: async (args: any) => {
        if (args?.data?.hostID) state.hostID = args.data.hostID;
        if (args?.data?.isActive === false) {
          state.isActive = false;
          state.endRoomCalled = true;
        }
        return {};
      },
      updateMany: async (args: any) => {
        if (args?.data?.isActive === false) {
          state.isActive = false;
          state.endRoomCalled = true;
        }
        return {};
      },
    },
    roomParticipant: {
      findMany: async () => state.participants.map((p) => ({ userID: p.userID })),
      findFirst: async (args: any) => {
        const excluded = args?.where?.userID?.not;
        const pool = state.participants
          .filter((p) => p.userID !== excluded)
          .sort((a, b) => a.joinedAt - b.joinedAt);
        const first = pool[0];
        if (!first) return null;
        return { userID: first.userID, user: { username: first.username } };
      },
      count: async () => state.participants.length,
      deleteMany: async () => {
        state.participants = [];
        return {};
      },
    },
    watchHistory: {
      createMany: async () => ({}),
      findFirst: async () => null,
      create: async () => ({}),
    },
  };

  return { prisma, state };
}

describe('передача хоста при уходе (P0 12.08.2026)', () => {
  it('хост ушёл, но остальные смотрят — комната ЖИВА и хост передан', async () => {
    // Уходящий хост уже удалён из participants роутом (deleteMany до вызова).
    const { prisma, state } = makePrisma({
      hostID: HOST_ID,
      participants: [{ userID: GUEST_ID, username: 'guest', joinedAt: 100 }],
    });

    const res = await maybeEndAfterLeave(prisma, ROOM_ID, HOST_ID);

    expect(res.roomEnded).toBe(false);
    expect(res.newHostId).toBe(GUEST_ID);
    expect(res.newHostName).toBe('guest');
    expect(state.isActive).toBe(true);
    expect(state.hostID).toBe(GUEST_ID);
    expect(state.endRoomCalled).toBe(false);
  });

  it('хостом становится самый давний из оставшихся, а не случайный', async () => {
    const OLDEST = '44444444-4444-4444-8444-444444444444';
    const { prisma } = makePrisma({
      hostID: HOST_ID,
      participants: [
        { userID: GUEST_ID, username: 'newcomer', joinedAt: 900 },
        { userID: OLDEST, username: 'veteran', joinedAt: 100 },
      ],
    });

    const res = await maybeEndAfterLeave(prisma, ROOM_ID, HOST_ID);

    expect(res.newHostId).toBe(OLDEST);
    expect(res.newHostName).toBe('veteran');
  });

  it('ушёл последний участник — комната закрывается (прежнее поведение)', async () => {
    const { prisma, state } = makePrisma({ hostID: HOST_ID, participants: [] });

    const res = await maybeEndAfterLeave(prisma, ROOM_ID, HOST_ID);

    expect(res.roomEnded).toBe(true);
    expect(res.newHostId).toBeUndefined();
    expect(state.endRoomCalled).toBe(true);
  });

  it('ушёл обычный зритель — хост не меняется, комната жива', async () => {
    const { prisma, state } = makePrisma({
      hostID: HOST_ID,
      participants: [{ userID: HOST_ID, username: 'host', joinedAt: 10 }],
    });

    const res = await maybeEndAfterLeave(prisma, ROOM_ID, GUEST_ID);

    expect(res.roomEnded).toBe(false);
    expect(res.newHostId).toBeUndefined();
    expect(state.hostID).toBe(HOST_ID);
    expect(state.isActive).toBe(true);
  });

  it('событие шины role.changed проходит свою схему', () => {
    const event = {
      kind: 'role.changed' as const,
      roomId: ROOM_ID,
      newHostId: GUEST_ID,
      newHostName: 'guest',
      epoch: 2,
      serverTimeMs: Date.now(),
    };
    expect(() => RoomEventSchema.parse(event)).not.toThrow();
  });

  it('нулевой epoch отклоняется: состояние комнаты не переинициализировано', () => {
    const bad = {
      kind: 'role.changed' as const,
      roomId: ROOM_ID,
      newHostId: GUEST_ID,
      newHostName: 'guest',
      epoch: 0,
      serverTimeMs: Date.now(),
    };
    expect(() => RoomEventSchema.parse(bad)).toThrow();
  });

  it('НАСТОЯЩИЙ маппинг шины → wire проходит контракт ServerMessage', () => {
    // Гоняем реальный eventToServerMessage, а не его копию в тесте: именно
    // ручная копия однажды позволила маппингу разойтись с контрактом.
    const msg = eventToServerMessage({
      kind: 'role.changed',
      roomId: ROOM_ID,
      newHostId: GUEST_ID,
      newHostName: 'guest',
      epoch: 3,
      serverTimeMs: Date.now(),
    });

    expect(msg).not.toBeNull();
    expect(() => ServerMessageSchema.parse(msg)).not.toThrow();
    expect((msg as any).type).toBe('role.changed');
    // newHostId — единственный источник истины о том, кто теперь хост:
    // событие одно на всю комнату, и клиент сверяет его со своим id.
    expect((msg as any).newHostId).toBe(GUEST_ID);
    expect((msg as any).newRole).toBe('host');
    expect((msg as any).epoch).toBe(3);
  });
});
