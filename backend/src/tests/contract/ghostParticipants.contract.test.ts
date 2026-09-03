// Ghost participants inside live rooms.
//
// A force-quit app never sends POST /rooms/:id/leave, so its RoomParticipant
// row outlives the WebSocket. While other people keep watching, the room is
// legitimately alive — but for the ghost's owner /rooms/mine?status=active
// still lists it, and the "return to room" capsule above the tab bar keeps
// advertising a session they left. `sweepOrphanRooms` therefore removes rows
// whose owner has no presence lease past the grace period and, when the
// ghost was the host, hands the role to the longest-present live viewer and
// tells the room through the hook.
import { describe, it, expect } from 'vitest';
import {
  sweepOrphanRooms,
  GHOST_PARTICIPANT_GRACE_MS,
  type PrismaLike,
} from '../../services/roomLifecycle.js';

const ROOM_ID = '11111111-1111-4111-8111-111111111111';
const HOST_ID = '22222222-2222-4222-8222-222222222222';
const GUEST_ID = '33333333-3333-4333-8333-333333333333';
const LATE_ID = '44444444-4444-4444-8444-444444444444';

type Row = { userID: string; username: string; joinedAt: number };

/** Prisma fake that keeps state so tests assert outcomes, not call lists. */
function makePrisma(opts: { hostID: string; participants: Row[]; createdAtMs?: number }) {
  const state = {
    isActive: true,
    hostID: opts.hostID,
    participants: [...opts.participants],
    history: [] as string[],
  };
  const inList = (where: any): ((r: Row) => boolean) => {
    const list: string[] | undefined = where?.userID?.in;
    const exact: string | undefined = typeof where?.userID === 'string' ? where.userID : undefined;
    return (r) => (list ? list.includes(r.userID) : exact ? r.userID === exact : true);
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
      findMany: async () =>
        state.isActive
          ? [
              {
                id: ROOM_ID,
                hostID: state.hostID,
                name: 'Комната',
                mediaItem: null,
                createdAt: new Date(opts.createdAtMs ?? Date.now() - 60 * 60 * 1000),
              },
            ]
          : [],
      update: async (args: any) => {
        if (args?.data?.hostID) state.hostID = args.data.hostID;
        if (args?.data?.isActive === false) state.isActive = false;
        return {};
      },
      updateMany: async (args: any) => {
        if (args?.data?.isActive === false) state.isActive = false;
        return {};
      },
    },
    roomParticipant: {
      findMany: async (args: any) =>
        state.participants
          .filter(inList(args?.where))
          .map((p) => ({ userID: p.userID, joinedAt: new Date(p.joinedAt) })),
      findFirst: async (args: any) => {
        const pool = state.participants
          .filter(inList(args?.where))
          .filter((p) => p.userID !== args?.where?.userID?.not)
          .sort((a, b) => a.joinedAt - b.joinedAt);
        const first = pool[0];
        return first ? { userID: first.userID, user: { username: first.username } } : null;
      },
      count: async () => state.participants.length,
      groupBy: async () =>
        state.participants.length > 0
          ? [{ roomID: ROOM_ID, _count: { roomID: state.participants.length } }]
          : [],
      deleteMany: async (args: any) => {
        const drop = inList(args?.where);
        state.participants = state.participants.filter((p) => !drop(p));
        return {};
      },
    },
    watchHistory: {
      createMany: async () => ({}),
      findFirst: async () => null,
      create: async (args: any) => {
        state.history.push(args?.data?.userID);
        return {};
      },
    },
  };
  return { prisma, state };
}

/** Redis fake: the room index ZSET answers with the given live user ids. */
function makeRedis(liveUserIds: string[]) {
  return {
    set: async () => 'OK',
    zremrangebyscore: async () => 0,
    zcount: async () => liveUserIds.length,
    zrangebyscore: async () => liveUserIds,
  };
}

const now = Date.now();
const OLD = now - GHOST_PARTICIPANT_GRACE_MS - 60_000; // joined long ago
const FRESH = now - 20_000; // joined 20 s ago — still connecting

describe('призрачные участники живой комнаты (капсула «вернуться в комнату»)', () => {
  it('хост убил приложение — его строка снята, хост передан живому зрителю, комната жива', async () => {
    const { prisma, state } = makePrisma({
      hostID: HOST_ID,
      participants: [
        { userID: HOST_ID, username: 'host', joinedAt: OLD - 10 },
        { userID: GUEST_ID, username: 'guest', joinedAt: OLD },
      ],
    });
    const migrated: string[] = [];

    const ended = await sweepOrphanRooms(prisma, makeRedis([GUEST_ID]), {
      onHostMigrated: async (roomId, newHostId, newHostName) => {
        migrated.push(`${roomId}:${newHostId}:${newHostName}`);
      },
    });

    expect(ended).toBe(0);
    expect(state.isActive).toBe(true);
    expect(state.participants.map((p) => p.userID)).toEqual([GUEST_ID]);
    expect(state.hostID).toBe(GUEST_ID);
    expect(migrated).toEqual([`${ROOM_ID}:${GUEST_ID}:guest`]);
    expect(state.history).toContain(HOST_ID);
  });

  it('обычный зритель-призрак снимается без смены хоста', async () => {
    const { prisma, state } = makePrisma({
      hostID: HOST_ID,
      participants: [
        { userID: HOST_ID, username: 'host', joinedAt: OLD - 10 },
        { userID: GUEST_ID, username: 'guest', joinedAt: OLD },
      ],
    });
    let hookCalls = 0;

    await sweepOrphanRooms(prisma, makeRedis([HOST_ID]), {
      onHostMigrated: async () => {
        hookCalls += 1;
      },
    });

    expect(state.participants.map((p) => p.userID)).toEqual([HOST_ID]);
    expect(state.hostID).toBe(HOST_ID);
    expect(hookCalls).toBe(0);
  });

  it('только что вошедший без lease не трогается — он ещё подключает сокет', async () => {
    const { prisma, state } = makePrisma({
      hostID: HOST_ID,
      participants: [
        { userID: HOST_ID, username: 'host', joinedAt: OLD },
        { userID: LATE_ID, username: 'late', joinedAt: FRESH },
      ],
    });

    await sweepOrphanRooms(prisma, makeRedis([HOST_ID]));

    expect(state.participants.map((p) => p.userID).sort()).toEqual([HOST_ID, LATE_ID].sort());
  });

  it('никого живого не осталось — комната закрывается (прежнее правило)', async () => {
    const { prisma, state } = makePrisma({
      hostID: HOST_ID,
      participants: [{ userID: HOST_ID, username: 'host', joinedAt: OLD }],
    });

    const ended = await sweepOrphanRooms(prisma, makeRedis([]));

    expect(ended).toBe(1);
    expect(state.isActive).toBe(false);
    expect(state.participants).toEqual([]);
  });

  it('без Redis присутствие неизвестно — строки не трогаем', async () => {
    const { prisma, state } = makePrisma({
      hostID: HOST_ID,
      participants: [
        { userID: HOST_ID, username: 'host', joinedAt: OLD },
        { userID: GUEST_ID, username: 'guest', joinedAt: OLD },
      ],
    });

    await sweepOrphanRooms(prisma, null);

    expect(state.participants.length).toBe(2);
    expect(state.hostID).toBe(HOST_ID);
  });
});
