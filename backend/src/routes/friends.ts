import { prisma } from '../config/db.js';
import { pushToUser } from '../services/pushService.js';
import { resolvePresence } from '../services/presence.js';
import {
  STORY_WINDOW_MS,
  groupStorySlides,
  orderStoryOwners,
} from '../utils/friendStories.js';

/** Минимальная длина поискового запроса (защита от перечисления профилей). */
const MIN_SEARCH_LEN = 2;

export default async function friendRoutes(fastify: any) {
  // GET /api/friends — accepted friendships (both directions, de-duplicated)
  // Some historical rows may exist only as A→B; always surface the other user.
  fastify.get(
    '/friends',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const me = request.user.id;
      // lastSeenAt optional until migrate — select dynamically
      const selectUser: any = {
        id: true,
        username: true,
        avatarURL: true,
        avatarUpdatedAt: true,
        isOnline: true,
        displayName: true,
        updatedAt: true,
        lastSeenAt: true,
        deletedAt: true,
      };
      const publicBase = process.env.PUBLIC_BASE_URL || 'https://plink-production.up.railway.app';

      // Always expose a loadable avatar endpoint with a version query so clients
      // refetch immediately when a friend changes their photo (stable path, new ?v=).
      const withAvatar = (u: any) => {
        const id = u?.id;
        if (!id) return u;
        let versionMs = 0;
        if (u.avatarUpdatedAt) {
          const t = new Date(u.avatarUpdatedAt).getTime();
          if (Number.isFinite(t)) versionMs = t;
        } else if (u.avatarURL && String(u.avatarURL).includes('v=')) {
          try {
            const q = new URL(String(u.avatarURL), 'https://local').searchParams.get('v');
            if (q && /^\d+$/.test(q)) versionMs = Number(q);
          } catch {
            /* ignore */
          }
        }
        const url =
          versionMs > 0
            ? `${publicBase}/api/users/${id}/avatar?v=${versionMs}`
            : `${publicBase}/api/users/${id}/avatar`;
        return { ...u, avatarURL: url, avatarVersion: versionMs || null };
      };

      const mapFriend = (
        u: any,
        friendsSince: any,
        pin?: { isPinned?: boolean; pinOrder?: number },
      ) => {
        // Telegram: deleted peers stay in the graph as «Удалённый аккаунт»
        const deleted = !!u?.deletedAt || String(u?.username || '').startsWith('deleted_');
        if (deleted) {
          return {
            id: u.id,
            username: u.username || `deleted_${String(u.id).slice(0, 8)}`,
            avatarURL: null,
            avatarVersion: null,
            isOnline: false,
            lastSeenAt: null,
            displayName: 'Удалённый аккаунт',
            friendsSince,
            isPinned: !!pin?.isPinned,
            pinOrder: typeof pin?.pinOrder === 'number' ? pin.pinOrder : 0,
            isDeleted: true,
          };
        }
        const base = withAvatar(u);
        const pres = resolvePresence(base);
        return {
          id: base.id,
          username: base.username,
          avatarURL: base.avatarURL,
          avatarVersion: base.avatarVersion,
          isOnline: pres.isOnline,
          lastSeenAt: pres.lastSeenAt,
          displayName: base.displayName,
          friendsSince,
          isPinned: !!pin?.isPinned,
          pinOrder: typeof pin?.pinOrder === 'number' ? pin.pinOrder : 0,
          isDeleted: false,
        };
      };

      let asInitiator: any[] = [];
      let asTarget: any[] = [];
      try {
        [asInitiator, asTarget] = await Promise.all([
          prisma.friendship.findMany({
            where: { userID: me },
            include: { friend: { select: selectUser } },
          }),
          prisma.friendship.findMany({
            where: { friendID: me },
            include: { user: { select: selectUser } },
          }),
        ]);
      } catch {
        // Fallback if optional columns not migrated yet — keep deletedAt when present
        const selectLegacy: any = {
          id: true,
          username: true,
          avatarURL: true,
          isOnline: true,
          displayName: true,
          updatedAt: true,
          deletedAt: true,
        };
        [asInitiator, asTarget] = await Promise.all([
          prisma.friendship.findMany({
            where: { userID: me },
            include: { friend: { select: selectLegacy } },
          }),
          prisma.friendship.findMany({
            where: { friendID: me },
            include: { user: { select: selectLegacy } },
          }),
        ]);
      }

      const byId = new Map<string, any>();
      for (const f of asInitiator) {
        if (!f.friend?.id) continue;
        // Pin is only valid on MY row (userID = me)
        byId.set(
          f.friend.id,
          mapFriend(f.friend, f.friendsSince, {
            isPinned: f.isPinned,
            pinOrder: f.pinOrder,
          }),
        );
      }
      for (const f of asTarget) {
        if (!f.user?.id || byId.has(f.user.id)) continue;
        // Reverse-only row: no pin on my side yet
        byId.set(f.user.id, mapFriend(f.user, f.friendsSince, { isPinned: false, pinOrder: 0 }));
      }

      // Self-heal: if only one direction exists, create the reverse row.
      // O(n) по Set вместо .some (было O(n^2)) и один
      // createMany вместо последовательных create — эндпоинт клиент поллит
      // каждую секунду. Записи происходят только пока в графе есть перекос.
      const forwardIds = new Set<string>(
        asInitiator.map((f: any) => f.friendID).filter((id: any): id is string => !!id),
      );
      const reverseIds = new Set<string>(
        asTarget.map((f: any) => f.userID).filter((id: any): id is string => !!id),
      );
      const missing: { userID: string; friendID: string }[] = [];
      for (const friendId of forwardIds) {
        if (!reverseIds.has(friendId)) missing.push({ userID: friendId, friendID: me });
      }
      for (const userId of reverseIds) {
        if (!forwardIds.has(userId)) missing.push({ userID: me, friendID: userId });
      }
      // Ревью: по одной строке за раз — легаси-строка с friendID, которого нет в
      // User, даёт FK violation и одним createMany откатила бы весь батч (перекос
      // не лечился бы никогда). Строк тут единицы, и только пока перекос есть.
      for (const row of missing) {
        try {
          await prisma.friendship.createMany({ data: [row], skipDuplicates: true });
        } catch {
          /* unique race / битая легаси-строка — остальные всё равно лечим */
        }
      }

      reply.send([...byId.values()]);
    },
  );

  // GET /api/friends/requests/incoming
  fastify.get(
    '/friends/requests/incoming',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const requests = await prisma.friendRequest.findMany({
        where: { toUserID: request.user.id, status: 'pending' },
        include: {
          fromUser: {
            select: {
              id: true,
              username: true,
              avatarURL: true,
              isOnline: true,
              displayName: true,
            },
          },
        },
        orderBy: { createdAt: 'desc' },
      });
      reply.send(
        requests.map((r: any) => ({
          id: r.id,
          fromUser: {
            id: r.fromUser.id,
            username: r.fromUser.username,
            avatarURL: r.fromUser.avatarURL,
            isOnline: r.fromUser.isOnline,
            displayName: r.fromUser.displayName,
          },
          status: r.status,
          createdAt: r.createdAt,
        })),
      );
    },
  );

  // GET /api/friends/requests/outgoing
  fastify.get(
    '/friends/requests/outgoing',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const requests = await prisma.friendRequest.findMany({
        where: { fromUserID: request.user.id, status: 'pending' },
        include: {
          toUser: {
            select: {
              id: true,
              username: true,
              avatarURL: true,
              isOnline: true,
              displayName: true,
            },
          },
        },
        orderBy: { createdAt: 'desc' },
      });
      reply.send(
        requests.map((r: any) => ({
          id: r.id,
          toUser: {
            id: r.toUser.id,
            username: r.toUser.username,
            avatarURL: r.toUser.avatarURL,
            isOnline: r.toUser.isOnline,
            displayName: r.toUser.displayName,
          },
          status: r.status,
          createdAt: r.createdAt,
        })),
      );
    },
  );

  // POST /api/friends/request — body: { friendId } or { username }
  fastify.post(
    '/friends/request',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request: any, reply: any) => {
      const body = (request.body ?? {}) as { friendId?: string; username?: string };
      let targetId = body.friendId?.trim();

      if (!targetId && body.username) {
        const uname = body.username.trim().replace(/^@/, '');
        const byName = await prisma.user.findFirst({
          where: { username: { equals: uname, mode: 'insensitive' } },
          select: { id: true },
        });
        if (!byName) return reply.status(404).send({ error: 'User not found' });
        targetId = byName.id;
      }

      if (!targetId) return reply.status(400).send({ error: 'friendId or username required' });
      if (targetId === request.user.id) {
        return reply.status(400).send({ error: 'Cannot friend yourself' });
      }

      const target = await prisma.user.findUnique({
        where: { id: targetId },
        select: { id: true },
      });
      if (!target) return reply.status(404).send({ error: 'User not found' });

      // При блокировке (в любую сторону) заявки запрещены —
      // иначе заблокированный получал прямой канал пуш-уведомлений жертве.
      // Отвечаем 404, не раскрывая факт блокировки.
      const blockedPair = await prisma.userBlock
        .findFirst({
          where: {
            OR: [
              { blockerID: request.user.id, blockedID: targetId },
              { blockerID: targetId, blockedID: request.user.id },
            ],
          },
          select: { id: true },
        })
        .catch(() => null);
      if (blockedPair) return reply.status(404).send({ error: 'User not found' });

      // Already friends?
      const already = await prisma.friendship.findFirst({
        where: { userID: request.user.id, friendID: targetId },
      });
      if (already) return reply.status(409).send({ error: 'Already friends' });

      // Reverse pending request → auto-accept (they already invited you)
      const reverse = await prisma.friendRequest.findFirst({
        where: {
          fromUserID: targetId,
          toUserID: request.user.id,
          status: 'pending',
        },
      });
      if (reverse) {
        await prisma.friendRequest.update({
          where: { id: reverse.id },
          data: { status: 'accepted' },
        });
        await prisma.friendship.createMany({
          data: [
            { userID: request.user.id, friendID: targetId },
            { userID: targetId, friendID: request.user.id },
          ],
          skipDuplicates: true,
        });
        return reply.send({
          success: true,
          autoAccepted: true,
          id: reverse.id,
          status: 'accepted',
          friendId: targetId,
        });
      }

      const existing = await prisma.friendRequest.findFirst({
        where: {
          OR: [
            { fromUserID: request.user.id, toUserID: targetId },
            { fromUserID: targetId, toUserID: request.user.id },
          ],
        },
      });

      if (existing) {
        if (existing.status === 'pending') {
          return reply.status(409).send({ error: 'Request already exists' });
        }
        // Re-open declined / rejected
        if (existing.fromUserID === request.user.id) {
          const updated = await prisma.friendRequest.update({
            where: { id: existing.id },
            data: { status: 'pending' },
          });
          return reply.send({
            success: true,
            id: updated.id,
            status: 'pending',
            friendId: targetId,
          });
        }
        // Other direction was declined — create new direction by updating
        const updated = await prisma.friendRequest.update({
          where: { id: existing.id },
          data: {
            fromUserID: request.user.id,
            toUserID: targetId,
            status: 'pending',
          },
        });
        return reply.send({
          success: true,
          id: updated.id,
          status: 'pending',
          friendId: targetId,
        });
      }

      const req = await prisma.friendRequest.create({
        data: { fromUserID: request.user.id, toUserID: targetId, status: 'pending' },
      });

      // APNs push to the recipient (no-op when not configured)
      void pushToUser(targetId, {
        title: 'Plink',
        body: `@${request.user.username} хочет добавить вас в друзья`,
        data: { kind: 'friend_request', fromUserId: request.user.id },
      });

      reply.send({
        success: true,
        id: req.id,
        status: req.status,
        friendId: targetId,
        fromUserID: req.fromUserID,
        toUserID: req.toUserID,
        createdAt: req.createdAt,
      });
    },
  );

  // PUT /api/friends/requests/:id — accept | rejected | declined
  fastify.put(
    '/friends/requests/:id',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const { id } = request.params as { id: string };
      const { status } = (request.body ?? {}) as { status?: string };
      const normalized = (status ?? '').toLowerCase();
      if (!['accepted', 'rejected', 'declined'].includes(normalized)) {
        return reply.status(400).send({ error: 'status must be accepted|rejected|declined' });
      }

      const req = await prisma.friendRequest.findUnique({ where: { id } });
      if (!req || req.toUserID !== request.user.id) {
        return reply.status(404).send({ error: 'Request not found' });
      }
      if (req.status !== 'pending') {
        return reply.status(409).send({ error: 'Request already handled' });
      }

      const finalStatus = normalized === 'accepted' ? 'accepted' : 'rejected';
      await prisma.friendRequest.update({ where: { id }, data: { status: finalStatus } });

      if (finalStatus === 'accepted') {
        // Always create BOTH directions (sender ↔ accepter)
        for (const row of [
          { userID: req.fromUserID, friendID: req.toUserID },
          { userID: req.toUserID, friendID: req.fromUserID },
        ]) {
          try {
            await prisma.friendship.upsert({
              where: {
                userID_friendID: { userID: row.userID, friendID: row.friendID },
              },
              create: row,
              update: {},
            });
          } catch (e: any) {
            // Fallback if compound unique name differs
            console.warn('[friends] upsert friendship failed, try create:', e?.message);
            try {
              await prisma.friendship.create({ data: row });
            } catch {
              /* already exists */
            }
          }
        }
      }

      reply.send({
        success: true,
        status: finalStatus,
        // Help both clients refresh without guessing
        friendship:
          finalStatus === 'accepted' ? { userA: req.fromUserID, userB: req.toUserID } : null,
      });
    },
  );

  // DELETE /api/friends/:friendId
  fastify.delete(
    '/friends/:friendId',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const { friendId } = request.params as { friendId: string };
      await prisma.friendship.deleteMany({
        where: {
          OR: [
            { userID: request.user.id, friendID: friendId },
            { userID: friendId, friendID: request.user.id },
          ],
        },
      });
      reply.send({ success: true });
    },
  );

  // POST /api/friends/:friendId/pin — pin friend to top of chat list (Telegram-style)
  // Body optional: { pin: true|false }. Default true.
  fastify.post(
    '/friends/:friendId/pin',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
    },
    async (request: any, reply: any) => {
      const me = request.user.id;
      const { friendId } = request.params as { friendId: string };
      if (!friendId || friendId === me) {
        return reply.status(400).send({ error: 'Invalid friendId' });
      }
      const body = (request.body ?? {}) as { pin?: boolean };
      const wantPin = body.pin !== false;

      // Ensure my directional friendship row exists
      let row = await prisma.friendship
        .findUnique({
          where: { userID_friendID: { userID: me, friendID: friendId } },
        })
        .catch(() => null);

      if (!row) {
        // Friendship might only exist reverse — create my side
        const reverse = await prisma.friendship.findFirst({
          where: { userID: friendId, friendID: me },
        });
        if (!reverse) {
          return reply.status(404).send({ error: 'Not friends' });
        }
        try {
          row = await prisma.friendship.create({
            data: { userID: me, friendID: friendId, isPinned: false, pinOrder: 0 },
          });
        } catch (e: any) {
          // Column may not exist yet — create without pin fields
          try {
            row = await prisma.friendship.create({
              data: { userID: me, friendID: friendId },
            });
          } catch {
            return reply.status(404).send({ error: 'Not friends' });
          }
        }
      }

      try {
        if (wantPin) {
          // Cap pins (Telegram-like soft limit)
          const pinnedCount = await prisma.friendship.count({
            where: { userID: me, isPinned: true },
          });
          if (!row.isPinned && pinnedCount >= 10) {
            return reply.status(400).send({ error: 'Максимум 10 закреплений', code: 'PIN_LIMIT' });
          }
          // New pin → top of pin section (pinOrder = min-1)
          const top = await prisma.friendship.findFirst({
            where: { userID: me, isPinned: true },
            orderBy: { pinOrder: 'asc' },
            select: { pinOrder: true },
          });
          const nextOrder = (top?.pinOrder ?? 1) - 1;
          await prisma.friendship.update({
            where: { id: row.id },
            data: { isPinned: true, pinOrder: nextOrder },
          });
          return reply.send({ success: true, isPinned: true, pinOrder: nextOrder });
        } else {
          await prisma.friendship.update({
            where: { id: row.id },
            data: { isPinned: false, pinOrder: 0 },
          });
          return reply.send({ success: true, isPinned: false, pinOrder: 0 });
        }
      } catch (e: any) {
        // Columns not migrated — client keeps local pin only
        console.warn('[friends] pin columns missing?', e?.message);
        return reply.send({ success: true, isPinned: wantPin, pinOrder: 0, localOnly: true });
      }
    },
  );

  // GET /api/friends/search?q=
  fastify.get(
    '/friends/search',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      let { q } = request.query as { q?: string };
      if (!q) return reply.send([]);
      q = q.trim().replace(/^@/, '');
      // Минимум 2 символа — запрос из одной буквы отдавал
      // 20 произвольных аккаунтов (перечисление чужих профилей) и всегда бил
      // full scan по users на каждый кейстрок.
      // Ревью: длина считается в code points, а для не-ASCII (китайская локаль —
      // один иероглиф = полноценное имя) порог 1 символ.
      const qLen = [...q].length;
      if (qLen < (/^[\x00-\x7F]*$/.test(q) ? MIN_SEARCH_LEN : 1)) return reply.send([]);

      // Ревью: поиск по хвосту id вернули — клиент показывает тег #<последние 8
      // символов id> в результатах поиска и в профиле (FriendsView/User.shortId),
      // полный UUID в UI не виден нигде. 8+ hex-символов = не перечисление.
      const idTail = qLen >= 8 && /^[0-9a-fA-F-]+$/.test(q) ? [{ id: { endsWith: q } }] : [];

      // Hide soft-deleted tombstones from discovery (Telegram: cannot find deleted users)
      let users: any[] = [];
      try {
        users = await prisma.user.findMany({
          where: {
            AND: [
              { id: { not: request.user.id } },
              { deletedAt: null } as any,
              { NOT: { username: { startsWith: 'deleted_' } } },
              {
                OR: [
                  { username: { contains: q, mode: 'insensitive' } },
                  { displayName: { contains: q, mode: 'insensitive' } },
                  { id: { equals: q } },
                  ...idTail,
                ],
              },
            ],
          },
          select: { id: true, username: true, avatarURL: true, isOnline: true, displayName: true },
          take: 20,
        });
      } catch {
        users = await prisma.user.findMany({
          where: {
            AND: [
              { id: { not: request.user.id } },
              { NOT: { username: { startsWith: 'deleted_' } } },
              {
                OR: [
                  { username: { contains: q, mode: 'insensitive' } },
                  { displayName: { contains: q, mode: 'insensitive' } },
                  { id: { equals: q } },
                  ...idTail,
                ],
              },
            ],
          },
          select: { id: true, username: true, avatarURL: true, isOnline: true, displayName: true },
          take: 20,
        });
      }
      reply.send(users);
    },
  );

  // GET /api/friends/stories — the "stories" rail of the Friends tab.
  // A story is what a friend watched over the last week (newest first, one
  // slide per title) with their custom status as the opening slide. `me` is
  // always returned so the client can draw the "my status" tile even when
  // nobody else has a story. Closed profiles are friends-only by definition,
  // so friends see them here; blocked pairs never do. Deleted accounts are
  // skipped — a tombstone has nothing to tell.
  fastify.get(
    '/friends/stories',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const me: string = request.user.id;
      const publicBase = process.env.PUBLIC_BASE_URL || 'https://plink-production.up.railway.app';

      const [asInitiator, asTarget, blocks] = await Promise.all([
        prisma.friendship.findMany({ where: { userID: me }, select: { friendID: true } }),
        prisma.friendship.findMany({ where: { friendID: me }, select: { userID: true } }),
        prisma.userBlock.findMany({
          where: { OR: [{ blockerID: me }, { blockedID: me }] },
          select: { blockerID: true, blockedID: true },
        }),
      ]);
      const blocked = new Set<string>();
      for (const b of blocks) {
        blocked.add(b.blockerID === me ? b.blockedID : b.blockerID);
      }
      const friendIds = Array.from(
        new Set<string>([
          ...asInitiator.map((f: { friendID: string }) => f.friendID),
          ...asTarget.map((f: { userID: string }) => f.userID),
        ]),
      ).filter((id) => id !== me && !blocked.has(id));
      const ids = [...friendIds, me];
      const since = new Date(Date.now() - STORY_WINDOW_MS);

      const [users, rows] = await Promise.all([
        prisma.user.findMany({
          where: { id: { in: ids } },
          select: {
            id: true,
            username: true,
            displayName: true,
            avatarURL: true,
            avatarUpdatedAt: true,
            isOnline: true,
            lastSeenAt: true,
            statusText: true,
            deletedAt: true,
          } as any,
        }),
        prisma.watchHistory.findMany({
          where: { userID: { in: ids }, watchedAt: { gte: since } },
          orderBy: { watchedAt: 'desc' },
          // A week of a whole friend list — bounded, the grouping caps per person.
          take: 600,
          select: {
            id: true,
            userID: true,
            mediaTitle: true,
            mediaThumb: true,
            mediaKind: true,
            watchedAt: true,
            roomID: true,
          },
        }),
      ]);

      const slidesByUser = groupStorySlides(rows);
      const avatarFor = (u: any): string | null => {
        let versionMs = 0;
        if (u.avatarUpdatedAt) {
          const t = new Date(u.avatarUpdatedAt).getTime();
          if (Number.isFinite(t)) versionMs = t;
        }
        if (!u.avatarURL && versionMs === 0) return null;
        return versionMs > 0
          ? `${publicBase}/api/users/${u.id}/avatar?v=${versionMs}`
          : `${publicBase}/api/users/${u.id}/avatar`;
      };

      const owners = users
        .filter((u: any) => !u.deletedAt && !String(u.username || '').startsWith('deleted_'))
        .map((u: any) => {
          const pres = resolvePresence(u);
          const statusText = typeof u.statusText === 'string' && u.statusText.trim() ? u.statusText.trim() : null;
          return {
            id: u.id,
            username: u.username,
            displayName: u.displayName ?? null,
            avatarURL: avatarFor(u),
            isOnline: pres.isOnline,
            lastSeenAt: pres.lastSeenAt,
            statusText,
            slides: slidesByUser.get(u.id) ?? [],
          };
        });

      const mine = owners.find((o: { id: string }) => o.id === me) ?? null;
      const friends = orderStoryOwners(owners.filter((o: { id: string }) => o.id !== me));
      reply.header('Cache-Control', 'no-store');
      reply.send({ me: mine, friends, windowDays: Math.round(STORY_WINDOW_MS / 86_400_000) });
    },
  );
}
