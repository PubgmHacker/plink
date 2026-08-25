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
    // Нужен для выбора преемника хоста (самый давний
    // участник комнаты) в maybeEndAfterLeave.
    findFirst: (args: any) => Promise<any>;
    count: (args: any) => Promise<number>;
    deleteMany: (args: any) => Promise<any>;
    // Свип считает участников всех активных комнат одним запросом.
    groupBy: (args: any) => Promise<any[]>;
  };
  watchHistory: {
    createMany: (args: any) => Promise<any>;
    findFirst: (args: any) => Promise<any>;
    create: (args: any) => Promise<any>;
  };
};

function mediaMetaFromRoom(room: { name?: string; mediaItem?: string | null }): {
  title: string;
  thumb: string | null;
  kind: string | null;
} {
  let title: string | null = null;
  let thumb: string | null = null;
  let kind: string | null = null;
  if (room.mediaItem) {
    try {
      const parsed = typeof room.mediaItem === 'string' ? JSON.parse(room.mediaItem) : room.mediaItem;
      if (parsed?.title && typeof parsed.title === 'string') title = parsed.title.slice(0, 200);
      // Постер — только http(s): data-URL в строку истории не пускаем.
      if (parsed?.thumbnailURL && typeof parsed.thumbnailURL === 'string' && /^https?:\/\//i.test(parsed.thumbnailURL)) {
        thumb = parsed.thumbnailURL.slice(0, 2000);
      }
      if (parsed?.mediaType && typeof parsed.mediaType === 'string') kind = parsed.mediaType.slice(0, 32);
    } catch {
      /* ignore */
    }
  }
  return { title: title ?? (room.name || 'Комната').slice(0, 200), thumb, kind };
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

    const meta = mediaMetaFromRoom(room);
    await prisma.watchHistory.create({
      data: {
        userID: userId,
        roomID: room.id,
        mediaTitle: meta.title,
        mediaThumb: meta.thumb,
        mediaKind: meta.kind,
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
): Promise<{ roomEnded: boolean; newHostId?: string; newHostName?: string }> {
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

  // Комната закрывается только если в ней НИКОГО не осталось.
  if (remaining === 0) {
    await endRoom(prisma, roomId, { extraUserIds: [leavingUserId] });
    return { roomEnded: true };
  }

  // Раньше здесь стояло `if (isHost || remaining === 0)` —
  // уход хоста убивал сеанс всем, кто ещё смотрел. Для co-watching это худший
  // из возможных отказов: у Hearo вся ценность в вечернем ритуале, а у нас
  // сорванный звонок хоста заканчивал фильм десяти людям. Теперь хост-роль
  // передаётся самому давнему из оставшихся участников, а комната живёт.
  if (isHost) {
    const successor = await prisma.roomParticipant.findFirst({
      where: { roomID: roomId, userID: { not: leavingUserId } },
      orderBy: { joinedAt: 'asc' },
      select: { userID: true, user: { select: { username: true } } },
    });

    // Участники есть по счётчику, но подходящего преемника нет (например, в
    // таблице осталась только строка самого уходящего) — тогда закрываем, как раньше.
    if (!successor) {
      await endRoom(prisma, roomId, { extraUserIds: [leavingUserId] });
      return { roomEnded: true };
    }

    await prisma.room.update({
      where: { id: roomId },
      data: { hostID: successor.userID },
    });

    return {
      roomEnded: false,
      newHostId: successor.userID,
      newHostName: successor.user?.username ?? 'Хост',
    };
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
  // Лидер-лок на цикл: без него каждая реплика гоняет свип каждые 60с —
  // одинаковые запросы × N и гонки двух endRoom по одной комнате. TTL 55с
  // (< интервала), владельца не помним: следующий цикл возьмёт замок заново.
  // Redis нет/мигнул — свипим без замка: дубль безопасен (endRoom проверяет
  // isActive, deleteMany идемпотентен), а потерять свип целиком хуже.
  if (redis) {
    try {
      const got = await redis.set('plink:sweep:rooms:lock', '1', 'PX', 55_000, 'NX');
      if (got !== 'OK') return 0;
    } catch {
      /* замок не взялся из-за сбоя Redis — продолжаем без него */
    }
  }

  const activeRooms = await prisma.room.findMany({
    where: { isActive: true },
    select: { id: true, hostID: true, name: true, mediaItem: true, createdAt: true },
  });
  if (activeRooms.length === 0) return 0;

  // Один groupBy вместо COUNT-запроса на каждую комнату (N+1: при сотнях
  // активных комнат свип сам становился нагрузкой, ради снятия которой писался).
  const counts = await prisma.roomParticipant.groupBy({
    by: ['roomID'],
    where: { roomID: { in: activeRooms.map((r) => r.id) } },
    _count: { roomID: true },
  });
  const participantsByRoom = new Map<string, number>(
    counts.map((c: any) => [c.roomID, Number(c._count?.roomID ?? 0)])
  );

  const now = Date.now();
  // Ghost rows after force-quit: no WS leases for a while, but DB participants remain.
  // Generous grace so we never kill a room mid-join / brief network blip.
  const minAgeMs = 10 * 60 * 1000;
  const orphanIds: string[] = [];

  for (const room of activeRooms) {
    const pCount = participantsByRoom.get(room.id) ?? 0;
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
