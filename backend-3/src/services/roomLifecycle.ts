// Room lifecycle: end empty/abandoned rooms, record WatchHistory, keep rows for history only.

export type PrismaLike = {
  room: {
    findUnique: (args: any) => Promise<any>;
    findMany: (args: any) => Promise<any[]>;
    update: (args: any) => Promise<any>;
    updateMany: (args: any) => Promise<any>;
  };
  roomParticipant: {
    findMany: (args: any) => Promise<any[]>;
    count: (args: any) => Promise<number>;
    deleteMany: (args: any) => Promise<any>;
  };
  watchHistory: {
    createMany: (args: any) => Promise<any>;
    findFirst: (args: any) => Promise<any>;
    create: (args: any) => Promise<any>;
  };
};

function mediaTitleFromRoom(room: { name?: string; mediaItem?: string | null }): string {
  if (room.mediaItem) {
    try {
      const parsed = typeof room.mediaItem === 'string' ? JSON.parse(room.mediaItem) : room.mediaItem;
      if (parsed?.title && typeof parsed.title === 'string') return parsed.title.slice(0, 200);
    } catch {
      /* ignore */
    }
  }
  return (room.name || 'Комната').slice(0, 200);
}

/** Record one watch-history row (dedupe: same user+room within last hour). */
export async function recordWatchHistory(
  prisma: PrismaLike,
  userId: string,
  room: { id: string; name?: string; mediaItem?: string | null }
): Promise<void> {
  try {
    const recent = await prisma.watchHistory.findFirst({
      where: {
        userID: userId,
        roomID: room.id,
        watchedAt: { gte: new Date(Date.now() - 60 * 60 * 1000) },
      },
      select: { id: true },
    });
    if (recent) return;

    await prisma.watchHistory.create({
      data: {
        userID: userId,
        roomID: room.id,
        mediaTitle: mediaTitleFromRoom(room),
      },
    });
  } catch (e: any) {
    console.warn('[roomLifecycle] watchHistory failed:', e?.message || e);
  }
}

/**
 * Soft-end a room: isActive=false, clear participants, write history for
 * host + all current participants. Room row stays for /rooms/mine history.
 */
export async function endRoom(
  prisma: PrismaLike,
  roomId: string,
  opts?: { extraUserIds?: string[] }
): Promise<{ ended: boolean; participantCount: number }> {
  const room = await prisma.room.findUnique({
    where: { id: roomId },
    select: { id: true, hostID: true, name: true, mediaItem: true, isActive: true },
  });
  if (!room) return { ended: false, participantCount: 0 };

  const participants = await prisma.roomParticipant.findMany({
    where: { roomID: roomId },
    select: { userID: true },
  });
  const userIds = new Set<string>([
    room.hostID,
    ...participants.map((p) => p.userID),
    ...(opts?.extraUserIds ?? []),
  ]);

  for (const uid of userIds) {
    await recordWatchHistory(prisma, uid, room);
  }

  if (room.isActive) {
    await prisma.room.update({
      where: { id: roomId },
      data: { isActive: false },
    });
  }

  await prisma.roomParticipant.deleteMany({ where: { roomID: roomId } });

  return { ended: true, participantCount: participants.length };
}

/**
 * After leave/kick: if nobody left in the room, soft-end it.
 * Host leave always ends the room (session is over).
 */
export async function maybeEndAfterLeave(
  prisma: PrismaLike,
  roomId: string,
  leavingUserId: string
): Promise<{ roomEnded: boolean }> {
  const room = await prisma.room.findUnique({
    where: { id: roomId },
    select: { id: true, hostID: true, name: true, mediaItem: true, isActive: true },
  });
  if (!room) return { roomEnded: false };

  // Always record history for the leaver
  await recordWatchHistory(prisma, leavingUserId, room);

  const remaining = await prisma.roomParticipant.count({ where: { roomID: roomId } });
  const isHost = room.hostID === leavingUserId;

  if (!room.isActive) {
    // Already ended — still clear leftover participant rows
    if (remaining > 0) {
      await prisma.roomParticipant.deleteMany({ where: { roomID: roomId } });
    }
    return { roomEnded: true };
  }

  if (isHost || remaining === 0) {
    await endRoom(prisma, roomId, { extraUserIds: [leavingUserId] });
    return { roomEnded: true };
  }

  return { roomEnded: false };
}

/**
 * Sweep active rooms:
 * 1) 0 DB participants → end immediately
 * 2) optional Redis: 0 presence leases for long-idle rooms → end (ghost after app kill)
 */
export async function sweepOrphanRooms(
  prisma: PrismaLike,
  redis: any | null | undefined
): Promise<number> {
  const activeRooms = await prisma.room.findMany({
    where: { isActive: true },
    select: { id: true, hostID: true, name: true, mediaItem: true, createdAt: true },
  });

  const now = Date.now();
  // Ghost rows after force-quit: no WS leases for a while, but DB participants remain.
  // Generous grace so we never kill a room mid-join / brief network blip.
  const minAgeMs = 10 * 60 * 1000;
  const orphanIds: string[] = [];

  for (const room of activeRooms) {
    const pCount = await prisma.roomParticipant.count({ where: { roomID: room.id } });
    if (pCount === 0) {
      orphanIds.push(room.id);
      continue;
    }

    if (!redis) continue;
    const age = now - new Date(room.createdAt).getTime();
    if (age < minAgeMs) continue;

    try {
      const roomIndexKey = `plink:room:${room.id}:activeUsers`;
      await redis.zremrangebyscore(roomIndexKey, '-inf', now);
      const activeCount = await redis.zcount(roomIndexKey, now, '+inf');
      if (activeCount === 0) {
        // No live WS presence — abandoned with stale RoomParticipant rows
        orphanIds.push(room.id);
      }
    } catch {
      /* redis blip — skip this room this cycle */
    }
  }

  if (orphanIds.length === 0) return 0;

  for (const id of orphanIds) {
    await endRoom(prisma, id);
  }
  return orphanIds.length;
}
