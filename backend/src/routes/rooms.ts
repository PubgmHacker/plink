// src/routes/rooms.ts — с Redis кэшем
import crypto from 'node:crypto';
import { hashRoomPassword, verifyRoomPassword, requireHost } from '../middleware/security.js';
import { validateBody } from '../middleware/validate.js';
import { roomCreateBody, roomJoinBody, roomQueueReorderBody } from '../schemas/requests.js';
import { cacheGet, cacheSet, cacheDel, redis } from '../config/redis.js';
import { logAudit, AuditActions } from '../utils/audit.js';
import {
  endRoom,
  maybeEndAfterLeave,
  recordWatchHistory,
  sweepOrphanRooms,
} from '../services/roomLifecycle.js';
// ИИ-модератор — запрещённый контент комнат, NSFW-фото, муты
import {
  violatesContentPolicy,
  containsProfanity,
  moderateImage,
  muteUser,
  muteRemainingSec,
  auditModeration,
  buildModWirePayload,
} from '../moderation/autoMod.js';
// Реальная очередь видео комнаты (REST + broadcast)
import {
  getRoomQueue,
  enqueueRoomMedia,
  dequeueRoomMedia,
  promoteRoomMedia,
  reorderRoomQueue,
  buildQueueWirePayload,
} from '../realtime/roomQueueStore.js';

const ROOMS_CACHE_KEY = 'rooms:public:50';
const ROOMS_CACHE_TTL = 30; // 30 sec

function parseImageDataURL(
  input: string,
): { mime: string; buffer: Buffer; dataUrl: string } | null {
  const match = input.match(/^data:(image\/(jpeg|jpg|png|webp));base64,(.+)$/i);
  if (!match) return null;
  const mime = match[1].toLowerCase() === 'image/jpg' ? 'image/jpeg' : match[1].toLowerCase();
  let buffer: Buffer;
  try {
    buffer = Buffer.from(match[3], 'base64');
  } catch {
    return null;
  }
  const isJPEG = buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
  const isPNG =
    buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47;
  const isWebP =
    buffer[0] === 0x52 && buffer[1] === 0x49 && buffer[2] === 0x46 && buffer[3] === 0x46;
  if (!isJPEG && !isPNG && !isWebP) return null;
  return { mime, buffer, dataUrl: `data:${mime};base64,${match[3]}` };
}

// Единая проверка ссылки на поток.
// Раньше валидация была только в POST /rooms (инлайном), а POST /rooms/:id/queue
// принимал streamURL как есть — любой `javascript:`, `file:` или внутренний
// хост (169.254.169.254) попадал в очередь и рассылался клиентам на проигрывание.
// Возвращает текст ошибки или null, если ссылка допустима.
//
// Границы проверки (ревью P2, честно): это денилист по СТРОКЕ hostname, а не
// полноценная защита от SSRF. Не покрывает hex/decimal-формы IP
// (http://0x7f000001, http://2130706433), IPv4-mapped IPv6 и любые DNS-имена,
// резолвящиеся в приватную сеть (dns.lookup не делается). Сервер сам streamURL
// не тянет, поэтому цель здесь — не пустить в клиенты явную дичь; полноценный
// фильтр требует нормализации адреса + резолва и выносится отдельной задачей.
function validateStreamURL(raw: string): string | null {
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    return 'Invalid streamURL format.';
  }
  // Only allow http/https schemes
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    return `Invalid URL scheme: ${parsed.protocol}. Only http/https allowed.`;
  }
  // Block localhost, private IPs, and metadata endpoints
  const hostname = parsed.hostname.toLowerCase();
  const blockedHosts = ['localhost', '127.0.0.1', '0.0.0.0', '::1', 'metadata.google.internal'];
  const privateIpPattern =
    /^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|169\.254\.|::1$|fc00:|fe80:)/;
  if (blockedHosts.includes(hostname) || privateIpPattern.test(hostname)) {
    return 'URLs pointing to local or private networks are not allowed.';
  }
  return null;
}

// mediaItem хранится в БД как JSON-строка (Prisma `String?` колонка).
// iOS ожидает structured object, не строку — иначе decoding падает с typeMismatch
// и весь Room decode ломается. Эта функция парсит строку обратно в объект.
// Применяется во всех endpoints которые возвращают room: create, join, list, get.
//
// ROBUSTNESS: try/catch вокруг JSON.parse. Если в БД лежит битая строка
// (исторические данные, partial write и т.п.) — возвращаем null вместо того
// чтобы ронять весь endpoint 500-й. Иначе iOS видит ошибку → myRooms = [] →
// юзер думает что у него нет комнат, хотя они есть.
function serializeRoom(room) {
  if (!room) return null;
  const { password, ...rest } = room;
  let parsedMediaItem = null;
  if (rest.mediaItem) {
    try {
      parsedMediaItem = JSON.parse(rest.mediaItem);
    } catch (e: any) {
      // Битая JSON-строка — логируем, возвращаем null, не роняем endpoint
      console.warn(`[rooms] Failed to parse mediaItem for room ${rest.id}:`, e?.message || e);
      parsedMediaItem = null;
    }
  }
  return {
    ...rest,
    mediaItem: parsedMediaItem,
  };
}

export default async function roomRoutes(fastify, _options) {
  const { prisma } = fastify;

  // GET /api/rooms/:id/queue — текущая очередь видео комнаты
  fastify.get(
    '/rooms/:id/queue',
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const roomId = request.params.id;
      const isMember = await prisma.roomParticipant.findFirst({
        where: { roomID: roomId, userID: request.user.id },
      });
      if (!isMember) return reply.status(403).send({ error: 'Вы не участник комнаты' });
      return reply.send({ queue: await getRoomQueue(roomId) });
    },
  );

  // POST /api/rooms/:id/queue — поставить видео в очередь (+ broadcast всем)
  fastify.post(
    '/rooms/:id/queue',
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const roomId = request.params.id;
      const isMember = await prisma.roomParticipant.findFirst({
        where: { roomID: roomId, userID: request.user.id },
      });
      if (!isMember) return reply.status(403).send({ error: 'Вы не участник комнаты' });
      const body = request.body ?? {};
      const title = typeof body.title === 'string' ? body.title.trim().slice(0, 200) : '';
      if (!title) return reply.status(400).send({ error: 'title обязателен' });
      // Модерация контента очереди
      const queueCheck = [title, body.streamURL, body.artist]
        .filter((v: unknown) => typeof v === 'string')
        .join(' ');
      if (violatesContentPolicy(queueCheck)) {
        return reply
          .status(422)
          .send({ error: 'Контент нарушает правила Plink', code: 'CONTENT_BLOCKED' });
      }
      // streamURL очереди проходит ту же SSRF-проверку,
      // что и mediaItem.streamURL в POST /rooms — иначе `javascript:`/`file:`
      // и внутренние адреса броадкастятся клиентам на проигрывание.
      const queueStreamURL = typeof body.streamURL === 'string' ? body.streamURL.trim() : '';
      if (queueStreamURL) {
        const urlError = validateStreamURL(queueStreamURL);
        if (urlError) return reply.status(400).send({ error: urlError });
      }
      const qUser = await prisma.user.findUnique({
        where: { id: request.user.id },
        select: { username: true },
      });
      const queue = await enqueueRoomMedia(roomId, {
        id: typeof body.id === 'string' ? body.id : crypto.randomUUID(),
        title,
        streamURL: queueStreamURL,
        source: typeof body.source === 'string' ? body.source : 'youtube',
        addedBy: qUser?.username ?? 'user',
      });
      try {
        await (fastify as any).gateway?.publishChatMessage?.({
          kind: 'chat.broadcast' as const,
          roomId,
          messageId: crypto.randomUUID(),
          clientMessageId: crypto.randomUUID(),
          senderId: 'plink-ai',
          senderName: 'Plink AI',
          text: buildQueueWirePayload(queue),
          createdAtMs: Date.now(),
        });
      } catch {
        /* noop */
      }
      return reply.status(201).send({ queue });
    },
  );

  // DELETE /api/rooms/:id/queue/:itemId — убрать элемент из очереди (+ broadcast)
  fastify.delete(
    '/rooms/:id/queue/:itemId',
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const roomId = request.params.id;
      const itemId = request.params.itemId;
      const isMember = await prisma.roomParticipant.findFirst({
        where: { roomID: roomId, userID: request.user.id },
      });
      if (!isMember) return reply.status(403).send({ error: 'Вы не участник комнаты' });
      // Раньше любой участник мог вычистить чужую очередь.
      // Убрать элемент может хост комнаты или тот, кто его поставил.
      const [dRoom, dUser, currentQueue] = await Promise.all([
        prisma.room.findUnique({ where: { id: roomId }, select: { hostID: true } }),
        prisma.user.findUnique({ where: { id: request.user.id }, select: { username: true } }),
        getRoomQueue(roomId),
      ]);
      const target = currentQueue.find((q) => q.id === itemId);
      const isRoomHost = dRoom?.hostID === request.user.id;
      // Fails closed. When the queue read comes back empty because Redis is
      // degraded, `target` is undefined — and skipping the ownership check in
      // that case let the dequeue below remove another user's item. A
      // non-host with no matching item now gets a 404 instead.
      if (!isRoomHost) {
        if (!target) {
          return reply.status(404).send({ error: 'Элемент очереди не найден' });
        }
        if (target.addedBy !== dUser?.username) {
          return reply
            .status(403)
            .send({ error: 'Убрать элемент может хост или тот, кто его добавил' });
        }
      }
      const queue = await dequeueRoomMedia(roomId, itemId);
      try {
        await (fastify as any).gateway?.publishChatMessage?.({
          kind: 'chat.broadcast' as const,
          roomId,
          messageId: crypto.randomUUID(),
          clientMessageId: crypto.randomUUID(),
          senderId: 'plink-ai',
          senderName: 'Plink AI',
          text: buildQueueWirePayload(queue),
          createdAtMs: Date.now(),
        });
      } catch {
        /* noop */
      }
      return reply.send({ queue });
    },
  );

  // POST /api/rooms/:id/queue/:itemId/play — включить элемент (промоут в начало + broadcast).
  // Клиент показывает кнопку только хосту; сервер проверяет членство.
  fastify.post(
    '/rooms/:id/queue/:itemId/play',
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const roomId = request.params.id;
      const itemId = request.params.itemId;
      const isMember = await prisma.roomParticipant.findFirst({
        where: { roomID: roomId, userID: request.user.id },
      });
      if (!isMember) return reply.status(403).send({ error: 'Вы не участник комнаты' });
      // «включить сейчас» — управление воспроизведением,
      // поэтому только хост (клиент и так показывает кнопку лишь ему).
      const pRoom = await prisma.room.findUnique({
        where: { id: roomId },
        select: { hostID: true },
      });
      if (pRoom?.hostID !== request.user.id) {
        return reply.status(403).send({ error: 'Только хост может включить видео из очереди' });
      }
      const queue = await promoteRoomMedia(roomId, itemId);
      const nowPlaying = queue.find((q) => q.id === itemId) ?? null;
      try {
        await (fastify as any).gateway?.publishChatMessage?.({
          kind: 'chat.broadcast' as const,
          roomId,
          messageId: crypto.randomUUID(),
          clientMessageId: crypto.randomUUID(),
          senderId: 'plink-ai',
          senderName: 'Plink AI',
          text: buildQueueWirePayload(queue, nowPlaying),
          createdAtMs: Date.now(),
        });
      } catch {
        /* noop */
      }
      return reply.send({ queue, nowPlaying });
    },
  );

  // PATCH /api/rooms/:id/queue — хост меняет порядок очереди (+ broadcast).
  //
  // Присланный список — перестановка, а не замена: элементы, добавленные
  // пока хост тянул строку, дописываются в конец, неизвестные id
  // игнорируются. Иначе гонка стирала бы чужое добавление.
  fastify.patch(
    '/rooms/:id/queue',
    {
      preHandler: [fastify.authenticate, validateBody(roomQueueReorderBody)],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const roomId = request.params.id;
      const { order } = request.body as { order: string[] };

      const isMember = await prisma.roomParticipant.findFirst({
        where: { roomID: roomId, userID: request.user.id },
      });
      if (!isMember) return reply.status(403).send({ error: 'Вы не участник комнаты' });

      // Порядок воспроизведения — управление плеером, поэтому только хост
      // (та же логика, что у .../queue/:itemId/play).
      const room = await prisma.room.findUnique({
        where: { id: roomId },
        select: { hostID: true, isActive: true },
      });
      if (!room || !room.isActive) {
        return reply.status(404).send({ error: 'Комната не найдена' });
      }
      if (room.hostID !== request.user.id) {
        return reply.status(403).send({ error: 'Только хост может менять порядок очереди' });
      }

      const queue = await reorderRoomQueue(roomId, order);
      try {
        await (fastify as any).gateway?.publishChatMessage?.({
          kind: 'chat.broadcast' as const,
          roomId,
          messageId: crypto.randomUUID(),
          clientMessageId: crypto.randomUUID(),
          senderId: 'plink-ai',
          senderName: 'Plink AI',
          text: buildQueueWirePayload(queue),
          createdAtMs: Date.now(),
        });
      } catch {
        /* noop */
      }
      return reply.send({ queue });
    },
  );

  // POST /api/rooms — Создание комнаты
  fastify.post(
    '/rooms',
    {
      preHandler: [fastify.authenticate, validateBody(roomCreateBody)],
    },
    async (request, reply) => {
      const { name, maxParticipants, mediaItem, privacy, password, hostName } = request.body;

      // ИИ-модерация контента — нельзя создать комнату с порнографией/запрещёнкой
      const contentToCheck = [name, mediaItem?.title, mediaItem?.streamURL, mediaItem?.artist]
        .filter((v: unknown) => typeof v === 'string' && (v as string).length > 0)
        .join(' ');
      if (violatesContentPolicy(contentToCheck)) {
        return reply.status(422).send({
          error: 'Название или контент комнаты нарушает правила Plink',
          code: 'CONTENT_BLOCKED',
        });
      }

      // Pack v3 FIX: JWT содержит только {id}, без username.
      // Берём username из БД, fallback на body.hostName, потом 'Unknown'.
      let resolvedHostName = hostName || 'Unknown';
      let isPremiumHost = false;
      try {
        const user = await prisma.user.findUnique({
          where: { id: request.user.id },
          select: { username: true, isPremium: true },
        });
        if (user?.username) resolvedHostName = user.username;
        isPremiumHost = user?.isPremium ?? false;
      } catch {}

      // P1 free-tier: free users = 1 active room. Auto-close previous rooms
      // so create never hard-fails with 403 when stale rooms were left open.
      if (!isPremiumHost) {
        const previous = await prisma.room.findMany({
          where: { hostID: request.user.id, isActive: true },
          select: { id: true },
        });
        if (previous.length > 0) {
          const ids = previous.map((r: { id: string }) => r.id);
          await prisma.room.updateMany({
            where: { id: { in: ids } },
            data: { isActive: false },
          });
          await prisma.roomParticipant.deleteMany({
            where: { roomID: { in: ids } },
          });
          console.log(
            `[rooms] free-tier: auto-ended ${ids.length} previous room(s) for ${request.user.id}`,
          );
        }
      }

      const requestedMax = Number(maxParticipants) || 10;
      const effectiveMax = isPremiumHost
        ? Math.min(Math.max(requestedMax, 2), 50)
        : Math.min(Math.max(requestedMax, 2), 10);

      const hashedPassword = password ? await hashRoomPassword(password) : null;

      // The stream URL is caller-supplied and later fetched server-side, so
      // validate it here or it becomes an SSRF into the private network.
      if (mediaItem?.streamURL) {
        const urlError = validateStreamURL(String(mediaItem.streamURL));
        if (urlError) return reply.status(400).send({ error: urlError });
      }

      // SAFETY: simple create — no endedAt column (uses isActive: false
      // to mark ended rooms instead, history preserved in /rooms/mine query).
      const room = await prisma.room.create({
        data: {
          name: name || 'Комната',
          hostID: request.user.id,
          hostName: resolvedHostName,
          code: generateRoomCode(),
          maxParticipants: effectiveMax,
          mediaItem: mediaItem ? JSON.stringify(mediaItem) : null,
          privacy: privacy || 'public',
          password: hashedPassword,
          hostIsPremium: isPremiumHost,
          isActive: true,
        },
      });

      // Host is always a participant — otherwise UI shows "0 человек"
      try {
        await prisma.roomParticipant.create({
          data: { roomID: room.id, userID: request.user.id },
        });
      } catch {
        /* unique race ok */
      }

      // Invalidate cache
      await cacheDel(ROOMS_CACHE_KEY);

      await logAudit({
        userId: request.user.id,
        action: AuditActions.ROOM_CREATE,
        ip: request.ip,
        metadata: { roomId: room.id, roomCode: room.code },
      });

      const { password: _, ...roomWithoutPassword } = room;
      // Include host as participant count for iOS
      const payload = serializeRoom(roomWithoutPassword) as any;
      payload._count = { participants: 1 };
      payload.participantCount = 1;
      reply.send(payload);
    },
  );

  // POST /api/rooms/join — Вход в комнату
  fastify.post(
    '/rooms/join',
    {
      preHandler: [fastify.authenticate, validateBody(roomJoinBody)],
      // Вход по коду не был ограничен по частоте.
      // Пространство кодов — 32^6, и без лимита его можно перебирать,
      // попадая в чужие приватные комнаты. Лимит считаем по пользователю,
      // а не по IP: за одним адресом провайдера сидят тысячи людей.
      config: {
        rateLimit: {
          max: 20,
          timeWindow: '1 minute',
          keyGenerator: (req: any) => req.user?.id ?? req.ip,
        },
      },
    },
    async (request, reply) => {
      const { code, password } = request.body ?? {};
      // Раньше отсутствие code давало 500 на code.toUpperCase().
      if (!code || typeof code !== 'string') {
        return reply.status(400).send({ error: 'Код комнаты обязателен' });
      }

      const room = await prisma.room.findFirst({
        where: { code: code.toUpperCase(), isActive: true },
      });

      if (!room) return reply.status(404).send({ error: 'Комната не найдена' });

      if (room.password) {
        // Здесь был 401 — клиент трактует 401 как смерть
        // сессии (plinkSessionExpired), и опечатка в пароле комнаты выкидывала
        // пользователя из аккаунта. 401 зарезервирован за аутентификацией,
        // доменные отказы — 403.
        if (!password)
          return reply
            .status(403)
            .send({ error: 'Требуется пароль', code: 'ROOM_PASSWORD_REQUIRED' });
        const isValid = await verifyRoomPassword(password, room.password);
        if (!isValid)
          return reply
            .status(403)
            .send({ error: 'Неверный пароль', code: 'ROOM_PASSWORD_INVALID' });
      }

      // Privacy 'friends' — впускаем только друзей хоста (в любом направлении дружбы)
      if (room.privacy === 'friends' && room.hostID !== request.user.id) {
        const friendship = await prisma.friendship.findFirst({
          where: {
            OR: [
              { userID: room.hostID, friendID: request.user.id },
              { userID: request.user.id, friendID: room.hostID },
            ],
          },
          select: { id: true },
        });
        if (!friendship) {
          return reply.status(403).send({
            error: 'Комната только для друзей хоста',
            code: 'FRIENDS_ONLY',
          });
        }
      }

      const participantCount = await prisma.roomParticipant.count({
        where: { roomID: room.id },
      });
      // Free-tier hosts: hard cap 10 even if room was created with higher max historically
      const cap = room.hostIsPremium ? room.maxParticipants : Math.min(room.maxParticipants, 10);
      if (participantCount >= cap) {
        return reply.status(409).send({
          error: room.hostIsPremium
            ? 'Комната заполнена'
            : 'Free tier limit: 10 participants max. Host can upgrade to Plink+.',
          code: 'ROOM_FULL',
          upgradeUrl: '/plink-plus',
        });
      }

      // Idempotent join if already a member
      const existing = await prisma.roomParticipant
        .findUnique({
          where: { roomID_userID: { roomID: room.id, userID: request.user.id } },
        })
        .catch(() => null);
      if (!existing) {
        await prisma.roomParticipant.create({
          data: { roomID: room.id, userID: request.user.id },
        });
      }

      await logAudit({
        userId: request.user.id,
        action: AuditActions.ROOM_JOIN,
        ip: request.ip,
        metadata: { roomId: room.id, roomCode: room.code },
      });

      const { password: _, ...roomWithoutPassword } = room;
      // Parse mediaItem JSON string back to object for iOS
      reply.send(serializeRoom(roomWithoutPassword));
    },
  );

  // DELETE /api/rooms/:id — soft-close (host/ADMIN). Room stays in history only.
  // Hard delete would wipe WatchHistory cascade — we never do that here.
  fastify.delete(
    '/rooms/:id',
    {
      preHandler: [fastify.authenticate],
    },
    async (request, reply) => {
      const { id } = request.params;

      const room = await prisma.room.findUnique({ where: { id } });
      if (!room) {
        return reply.status(404).send({ error: 'Комната не найдена' });
      }

      const isHost = room.hostID === request.user.id;
      const isAdmin = request.user.role === 'ADMIN' || request.user.role === 'FOUNDER';
      if (!isHost && !isAdmin) {
        return reply.status(403).send({ error: 'Нет прав на удаление комнаты' });
      }

      await endRoom(prisma, id, { extraUserIds: [request.user.id] });
      await cacheDel(ROOMS_CACHE_KEY);

      await logAudit({
        userId: request.user.id,
        action: AuditActions.ROOM_DELETE,
        ip: request.ip,
        metadata: { roomId: id, roomCode: room.code, roomName: room.name, soft: true },
      });

      reply.send({ success: true, roomEnded: true });
    },
  );

  // POST /api/rooms/:id/playback
  fastify.post(
    '/rooms/:id/playback',
    {
      preHandler: [fastify.authenticate, requireHost(prisma)],
    },
    async (request, reply) => {
      const { id } = request.params;
      const { time, isPlaying } = request.body;

      await prisma.playbackState.upsert({
        where: { roomID: id },
        update: { currentTime: time, isPlaying },
        create: { roomID: id, currentTime: time, isPlaying },
      });

      await logAudit({
        userId: request.user.id,
        action: AuditActions.PLAYBACK_CONTROL,
        ip: request.ip,
        metadata: { roomId: id, isPlaying, time },
      });

      reply.send({ success: true });
    },
  );

  // ─────────────────────────────────────────────────────────────────────
  // V5 (Phase 4): PATCH /api/rooms/:id/appearance
  // ─────────────────────────────────────────────────────────────────────
  // Host-only. Validates Plink+ for premium theme IDs, persists the
  // RoomAppearance JSON, broadcasts `room.appearance.updated` to all
  // participants via WebSocket. Non-hosts receive 403.
  // рейт-лимит обязателен. rate-limit зарегистрирован с
  // global: false (app.ts), поэтому без config роут был безлимитным — а теперь
  // один PATCH порождает фан-аут на ВСЕ сокеты комнаты на ВСЕХ репликах.
  // Хост в цикле мог бы забить буферы зрителей и словить их эвикцию по
  // backpressure (connectionRegistry.ts). Лимит как у соседних PATCH-роутов.
  fastify.patch(
    '/rooms/:id/appearance',
    {
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
      preHandler: [fastify.authenticate, requireHost(prisma)],
    },
    async (request, reply) => {
      const { id } = request.params;
      const { themeId, themeRevision, intensity, motionEnabled } = request.body;

      if (typeof themeId !== 'string' || typeof intensity !== 'number') {
        return reply.status(400).send({ error: 'themeId and intensity required' });
      }
      // Границы themeId/intensity совпадают с
      // RoomAppearanceUpdatedSchema. Без этого в БД лёг бы вид, который
      // потом не проходит валидацию шины — тема сохранена, но не доставлена.
      if (themeId.length < 1 || themeId.length > 64 || !Number.isFinite(intensity)) {
        return reply.status(400).send({ error: 'Invalid themeId or intensity' });
      }

      // P1 5.11: живые темы комнаты — фича Plink+. Бесплатная только
      // дефолтная статика; клиентский каталог (PlinkAppearanceRegistry)
      // помечает все roomLive-темы premium, сервер обязан это подтверждать.
      const FREE_ROOM_THEME_IDS = new Set(['room-default-static']);
      if (!FREE_ROOM_THEME_IDS.has(themeId)) {
        const host = await prisma.user.findUnique({
          where: { id: request.user.id },
          select: { isPremium: true, premiumUntil: true },
        });
        const now = new Date();
        const premiumActive = !!host?.isPremium && (!host.premiumUntil || host.premiumUntil > now);
        if (!premiumActive) {
          return reply.status(403).send({
            error: 'Живые темы комнаты доступны в Plink+',
            code: 'PREMIUM_REQUIRED',
          });
        }
      }

      // 44% intensity cap (V4 rule)
      const cappedIntensity = Math.min(Math.max(intensity, 0), 0.44);
      const cappedRevision =
        typeof themeRevision === 'number' && Number.isInteger(themeRevision) && themeRevision >= 0
          ? themeRevision
          : 1;
      const cappedMotion = typeof motionEnabled === 'boolean' ? motionEnabled : true;
      const appearance = JSON.stringify({
        themeId,
        themeRevision: cappedRevision,
        intensity: cappedIntensity,
        motionEnabled: cappedMotion,
        updatedAt: new Date().toISOString(),
        updatedBy: request.user.id,
      });

      await prisma.room.update({
        where: { id },
        data: { appearance },
      });

      // Здесь был «броадкаст» через fastify.io?.to(...).emit(...),
      // но Socket.IO в проекте нет вообще (реалтайм — ws + RealtimeGateway), поэтому
      // optional chaining превращало весь цикл по участникам в no-op: код делал вид,
      // что доставляет тему, и грузил БД лишним findMany на каждый PATCH.
      // Теперь доставка живая: после успешного сохранения публикуем типизированное
      // событие в RoomEventBus, и КАЖДАЯ реплика с сокетами комнаты рассылает своим
      // клиентам room.appearance.updated (contracts/realtime-v2.ts). Публикуем строго
      // после update — иначе клиенты увидят тему, которой нет в БД.
      // Клиент: iOS-декодер (Plink/Realtime/RealtimeEnvelope.swift) на неизвестный type
      // бросает DecodingError, но RealtimeClient.handleIncoming ловит его и лишь пишет
      // lastError — соединение живо, старые сборки просто игнорируют событие. Применение
      // темы у зрителей включится, когда iOS добавит case и вызовет
      // RoomAppearanceStore.applyServerUpdate.
      // Доставка best-effort: упавший push не должен откатывать сохранённую тему.
      // Call the method WITHOUT `?.`: optional chaining on the call swallows a
      // missing or renamed method and silently degrades delivery to a no-op.
      // Called directly, that becomes a TypeError → warn in the log instead of
      // an event lost without trace. A missing gateway itself (WS disabled) is
      // logged explicitly too.
      const gateway = (fastify as any).gateway;
      if (!gateway) {
        request.log?.warn?.({ roomId: id }, 'gateway missing — appearance push skipped');
      } else {
        // Бюджет на публикацию, как у presence-cleanup в gateway.ts: ioredis
        // с offline-очередью может держать команду весь reconnect-backoff,
        // а 200 на PATCH не должен зависеть от живости Redis.
        let published = false;
        let timer: NodeJS.Timeout | undefined;
        try {
          const publish = (async () => {
            await gateway.publishRoomAppearance({
              kind: 'room.appearance.updated',
              roomId: id,
              themeId,
              themeRevision: cappedRevision,
              intensity: cappedIntensity,
              motionEnabled: cappedMotion,
              serverTimeMs: Date.now(),
            });
            published = true;
          })();
          // Таймаут РЕЗОЛВИТСЯ (не реджектится): реджект проигравшей ветки
          // гонки стал бы unhandled rejection после того, как race уже осел.
          await Promise.race([
            publish.catch((err) => {
              request.log?.warn?.({ err, roomId: id }, 'room.appearance.updated publish failed');
              published = true; // ошибка уже залогирована, второй warn не нужен
            }),
            new Promise<void>((resolve) => {
              timer = setTimeout(resolve, 2000);
            }),
          ]);
          if (!published) {
            request.log?.warn?.(
              { roomId: id },
              'room.appearance.updated publish timed out after 2000ms',
            );
          }
        } catch (err) {
          // Сюда попадает только синхронный бросок (например, метод исчез).
          request.log?.warn?.({ err, roomId: id }, 'room.appearance.updated publish failed');
        } finally {
          if (timer) clearTimeout(timer);
        }
      }

      await logAudit({
        userId: request.user.id,
        action: 'ROOM_APPEARANCE_UPDATE',
        ip: request.ip,
        metadata: { roomId: id, themeId, intensity: cappedIntensity },
      });

      reply.send({
        success: true,
        appearance: JSON.parse(appearance),
      });
    },
  );

  // GET /api/rooms — активные публичные комнаты (только с участниками)
  // PATCH /api/rooms/:id/privacy — хост меняет режим модерации живой комнаты
  // (публичная / закрытая с паролем / по ссылке / только друзья)
  fastify.patch(
    '/rooms/:id/privacy',
    {
      preHandler: [fastify.authenticate],
    },
    async (request, reply) => {
      const { privacy, password } = request.body || {};
      const allowed = ['public', 'private', 'link', 'friends'];
      if (!allowed.includes(privacy)) {
        return reply.status(400).send({ error: 'Invalid privacy value' });
      }

      const room = await prisma.room.findUnique({ where: { id: request.params.id } });
      if (!room || !room.isActive) return reply.status(404).send({ error: 'Комната не найдена' });
      if (room.hostID !== request.user.id) {
        return reply.status(403).send({ error: 'Только хост может менять приватность' });
      }

      // Пароль имеет смысл только для 'private': новый — хешируем,
      // не передан — сохраняем старый; для остальных режимов — сбрасываем.
      const hashedPassword =
        privacy === 'private'
          ? password
            ? await hashRoomPassword(password)
            : room.password
          : null;

      const updated = await prisma.room.update({
        where: { id: room.id },
        data: { privacy, password: hashedPassword },
      });

      const { password: _, ...roomWithoutPassword } = updated;
      reply.send(serializeRoom(roomWithoutPassword));
    },
  );

  fastify.get(
    '/rooms',
    {
      preHandler: [fastify.authenticate],
    },
    async (request, reply) => {
      // Try cache first
      const cached = await cacheGet<any[]>(ROOMS_CACHE_KEY);
      if (cached) {
        return reply.send(cached);
      }

      const rooms = await prisma.room.findMany({
        where: {
          isActive: true,
          privacy: 'public',
          // Hide empty shells — nothing to join
          participants: { some: {} },
        },
        include: { _count: { select: { participants: true } } },
        orderBy: { createdAt: 'desc' },
        take: 50,
      });

      const safeRooms = rooms
        .map((r) => serializeRoom(r))
        .filter((r: any) => (r?._count?.participants ?? r?.participantCount ?? 0) > 0);

      // Save to cache
      await cacheSet(ROOMS_CACHE_KEY, safeRooms, ROOMS_CACHE_TTL);

      reply.send(safeRooms);
    },
  );

  // POST /api/rooms/:id/leave — leave; host leave or 0 people → soft-end → history only
  fastify.post(
    '/rooms/:id/leave',
    {
      preHandler: [fastify.authenticate],
      schema: {
        body: {
          type: 'object',
          additionalProperties: true,
        },
      },
    },
    async (request, reply) => {
      if (request.body == null) (request as any).body = {};
      const { id } = request.params as { id: string };

      const room = await prisma.room.findUnique({ where: { id } });
      if (!room) {
        return reply.status(404).send({ error: 'Комната не найдена' });
      }

      // Remove this user's participation first
      await prisma.roomParticipant.deleteMany({
        where: { roomID: id, userID: request.user.id },
      });

      // Detach any live sockets this user still has in the room — cross-replica,
      // via the same participant.kicked event kicks use (the gateway closes the
      // sockets and does NOT broadcast it to the room). Without this, a client
      // that leaves via REST but keeps its WS open would still pass the
      // socket-local membership check in messageRouter. Best-effort: a Redis
      // blip must not fail the leave that already happened in the DB.
      {
        const gw = (fastify as any).gateway;
        if (gw) {
          try {
            await gw.kickUser(id, request.user.id, request.user.id);
          } catch (err) {
            request.log?.warn?.({ err, roomId: id }, 'leave: socket detach publish failed');
          }
        }
      }

      const { roomEnded, newHostId, newHostName } = await maybeEndAfterLeave(
        prisma,
        id,
        request.user.id,
      );

      // Хост ушёл, но комната жива — надо сказать об этом
      // тем, кто остался, иначе новый хост узнает о своей роли только при
      // перезаходе (session.ready читает hostID из БД), а до тех пор плеером
      // не управляет НИКТО. Публикация best-effort: упавший Redis не должен
      // отменять уже произошедшую в БД передачу роли — комната в худшем случае
      // доживёт до реконнекта, а не закроется.
      let hostEpoch: number | undefined;
      if (!roomEnded && newHostId) {
        const gateway = (fastify as any).gateway;
        if (!gateway) {
          request.log?.warn?.(
            { roomId: id, newHostId },
            'gateway missing — role.changed push skipped',
          );
        } else {
          try {
            hostEpoch = await gateway.publishHostMigration(id, newHostId, newHostName ?? 'Хост');
          } catch (err) {
            request.log?.warn?.({ err, roomId: id, newHostId }, 'role.changed publish failed');
          }
        }
      }

      await logAudit({
        userId: request.user.id,
        action: AuditActions.ROOM_LEAVE,
        ip: request.ip,
        metadata: { roomId: id, roomEnded, newHostId: newHostId ?? null },
      });

      if (roomEnded) {
        await cacheDel(ROOMS_CACHE_KEY);
      }

      return reply.send({
        success: true,
        roomEnded,
        newHostId: newHostId ?? null,
        epoch: hostEpoch ?? null,
      });
    },
  );

  // POST /api/rooms/:id/end — host explicitly ends room (soft, keeps history)
  fastify.post(
    '/rooms/:id/end',
    {
      preHandler: [fastify.authenticate],
    },
    async (request, reply) => {
      const { id } = request.params as { id: string };
      const room = await prisma.room.findUnique({ where: { id } });
      if (!room) return reply.status(404).send({ error: 'Комната не найдена' });
      const isHost = room.hostID === request.user.id;
      const isAdmin = request.user.role === 'ADMIN' || request.user.role === 'FOUNDER';
      if (!isHost && !isAdmin) {
        return reply.status(403).send({ error: 'Только хост может закрыть комнату' });
      }
      await endRoom(prisma, id, { extraUserIds: [request.user.id] });
      await cacheDel(ROOMS_CACHE_KEY);
      await logAudit({
        userId: request.user.id,
        action: AuditActions.ROOM_LEAVE,
        ip: request.ip,
        metadata: { roomId: id, roomEnded: true, explicit: true },
      });
      reply.send({ success: true, roomEnded: true });
    },
  );

  // POST /api/rooms/:id/kick — host removes a participant (UGC / room control)
  fastify.post(
    '/rooms/:id/kick',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request: any, reply: any) => {
      const { id } = request.params as { id: string };
      const { userId } = (request.body ?? {}) as { userId?: string };
      if (!userId) return reply.status(400).send({ error: 'userId required' });

      const room = await prisma.room.findUnique({ where: { id } });
      if (!room) return reply.status(404).send({ error: 'Room not found' });
      if (room.hostID !== request.user.id) {
        return reply.status(403).send({ error: 'Only the host can kick participants' });
      }
      if (userId === room.hostID) {
        return reply.status(400).send({ error: 'Cannot kick the host' });
      }

      const removed = await prisma.roomParticipant.deleteMany({
        where: { roomID: id, userID: userId },
      });
      if (removed.count === 0) {
        return reply.status(404).send({ error: 'Participant not in room' });
      }

      // History for kicked user
      await recordWatchHistory(prisma, userId, room);

      // broadcastToRoom не существовал (no-op за
      // optional chaining) — сокет кикнутого оставался в комнате и читал
      // броадкасты. kickUser закрывает его WS на всех репликах через RoomEventBus.
      try {
        const gateway = (fastify as any).gateway;
        await gateway?.kickUser?.(id, userId, request.user.id);
      } catch {
        /* ignore — best-effort, gateway может быть null */
      }

      // If nobody left after kick — soft-end
      const remaining = await prisma.roomParticipant.count({ where: { roomID: id } });
      let roomEnded = false;
      if (remaining === 0 && room.isActive) {
        await endRoom(prisma, id);
        roomEnded = true;
        await cacheDel(ROOMS_CACHE_KEY);
      }

      reply.send({ success: true, kickedUserId: userId, roomEnded });
    },
  );

  // GET /api/rooms/mine — мои комнаты
  // ?status=active  — только живые (isActive + есть люди)
  // ?status=history — закрытые (для истории; активные не показываем)
  // default / ?status=all — active first, then history (legacy)
  // NOTE: must be registered BEFORE /rooms/:id so "mine" is not captured as an id.
  fastify.get(
    '/rooms/mine',
    {
      preHandler: [fastify.authenticate],
    },
    async (request, reply) => {
      const status = String((request.query as any)?.status || 'all').toLowerCase();
      const userId = request.user.id;

      if (status === 'active') {
        const rooms = await prisma.room.findMany({
          where: {
            isActive: true,
            participants: { some: {} },
            OR: [{ hostID: userId }, { participants: { some: { userID: userId } } }],
          },
          include: { _count: { select: { participants: true } } },
          orderBy: { createdAt: 'desc' },
          take: 50,
        });
        return reply.send(rooms.map((r) => serializeRoom(r)));
      }

      if (status === 'history') {
        // Closed rooms I hosted, or appeared in watch history
        const [hostedEnded, historyRows] = await Promise.all([
          prisma.room.findMany({
            where: { hostID: userId, isActive: false },
            include: { _count: { select: { participants: true } } },
            orderBy: { createdAt: 'desc' },
            take: 40,
          }),
          prisma.watchHistory.findMany({
            where: { userID: userId, roomID: { not: null } },
            orderBy: { watchedAt: 'desc' },
            take: 40,
            select: { roomID: true },
          }),
        ]);
        const extraIds = [
          ...new Set(
            historyRows
              .map((h: { roomID: string | null }) => h.roomID)
              .filter((id: string | null): id is string => !!id),
          ),
        ].filter((id) => !hostedEnded.some((r) => r.id === id));

        const extraRooms = extraIds.length
          ? await prisma.room.findMany({
              where: { id: { in: extraIds }, isActive: false },
              include: { _count: { select: { participants: true } } },
            })
          : [];

        const merged = [...hostedEnded, ...extraRooms]
          .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
          .slice(0, 50)
          .map((r) => serializeRoom(r));
        return reply.send(merged);
      }

      // all — active (with people) + recent inactive history; never show empty "active" shells
      const rooms = await prisma.room.findMany({
        where: {
          OR: [
            { hostID: userId },
            { participants: { some: { userID: userId } } },
            { watchHistory: { some: { userID: userId } } },
          ],
        },
        include: { _count: { select: { participants: true } } },
        orderBy: { createdAt: 'desc' },
        take: 80,
      });

      // Soft-fix any active rows that have 0 participants (stale)
      const staleActive = rooms.filter(
        (r: any) => r.isActive && (r._count?.participants ?? 0) === 0,
      );
      if (staleActive.length > 0) {
        for (const r of staleActive) {
          await endRoom(prisma, r.id, { extraUserIds: [userId] });
          r.isActive = false;
          if (r._count) r._count.participants = 0;
        }
        await cacheDel(ROOMS_CACHE_KEY);
      }

      const safeRooms = rooms.map((r) => serializeRoom(r));
      reply.send(safeRooms);
    },
  );

  // GET /api/rooms/:id — single room (media recovery after create/join)
  // Registered after /rooms/mine so "mine" is never treated as an id.
  fastify.get(
    '/rooms/:id',
    {
      preHandler: [fastify.authenticate],
    },
    async (request: any, reply: any) => {
      const { id } = request.params as { id: string };
      if (!id || id === 'mine' || id === 'public') {
        return reply.status(404).send({ error: 'Room not found' });
      }
      const room = await prisma.room.findUnique({ where: { id } });
      if (!room) return reply.status(404).send({ error: 'Room not found' });
      const me = request.user.id;
      const isHost = room.hostID === me;
      const isMember = await prisma.roomParticipant.findFirst({
        where: { roomID: id, userID: me },
        select: { id: true },
      });
      if (!isHost && !isMember) {
        if (!(room.isActive && room.privacy === 'public')) {
          return reply.status(403).send({ error: 'Forbidden' });
        }
      }
      const count = await prisma.roomParticipant.count({ where: { roomID: id } });
      const payload = serializeRoom(room) as any;
      payload._count = { participants: count };
      payload.participantCount = count;
      return reply.send(payload);
    },
  );

  // GET /api/rooms/:id/participants — active participant snapshot
  // NO Redis KEYS — uses room-indexed ZSET + Lua to prune expired and return active userIds.
  // Host returned separately with online status, not forced into participants.
  // Single Lua call, no N+1 zcount.
  fastify.get(
    '/rooms/:id/participants',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request: any, reply: any) => {
      const { id: roomId } = request.params;

      // Verify membership
      const [participant, room] = await Promise.all([
        prisma.roomParticipant
          .findUnique({
            where: { roomID_userID: { roomID: roomId, userID: request.user.id } },
            select: { id: true },
          })
          .catch(() => null),
        prisma.room.findUnique({
          where: { id: roomId },
          select: { hostID: true, isActive: true },
        }),
      ]);
      if (!room) return reply.status(404).send({ error: 'Room not found' });
      if (room.hostID !== request.user.id && !participant) {
        return reply.status(403).send({ error: 'Not a room member' });
      }

      // Use room-indexed ZSET instead of KEYS.
      // Each presence key is plink:presence:{roomId}:{userId} with ZSET of
      // connectionId → leaseExpiresAtMs. We also maintain a room-level index
      // ZSET: plink:room:{roomId}:activeUsers with userId → latestLeaseExpiresAtMs.
      // This Lua script prunes expired entries from both the index and
      // individual user keys, then returns active userIds.
      let activeUserIds: string[] = [];
      if (redis) {
        const now = Date.now();
        const roomIndexKey = `plink:room:${roomId}:activeUsers`;
        // Prune expired from room index
        await redis.zremrangebyscore(roomIndexKey, '-inf', now);
        // Get active userIds from room index
        const activeEntries = await redis.zrangebyscore(roomIndexKey, now, '+inf');
        activeUserIds = activeEntries;
      }

      // Fetch host separately with online status
      const host = await prisma.user.findUnique({
        where: { id: room.hostID },
        select: { id: true, username: true },
      });

      // Fetch usernames for active participants
      const users =
        activeUserIds.length > 0
          ? await prisma.user.findMany({
              where: { id: { in: activeUserIds } },
              select: { id: true, username: true },
            })
          : [];

      return reply.send({
        // Host metadata separate from active participants
        host: host
          ? {
              userId: host.id,
              username: host.username,
              online: activeUserIds.includes(host.id),
            }
          : null,
        // Only actually active connections
        participants: users.map((u) => ({ userId: u.id, username: u.username })),
      });
    },
  );

  // POST /api/rooms/:id/messages/photo — room photo message via REST upload.
  // Realtime only broadcasts metadata; base64 image bytes never go over WebSocket.
  fastify.post(
    '/rooms/:id/messages/photo',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 15, timeWindow: '1 minute' } },
      bodyLimit: 3 * 1024 * 1024,
    },
    async (request: any, reply: any) => {
      const { id: roomId } = request.params as { id: string };
      const body = (request.body ?? {}) as {
        imageData?: string;
        content?: string;
        clientMessageId?: string;
      };

      const [participant, room, sender] = await Promise.all([
        prisma.roomParticipant
          .findUnique({
            where: { roomID_userID: { roomID: roomId, userID: request.user.id } },
            select: { id: true },
          })
          .catch(() => null),
        prisma.room.findUnique({
          where: { id: roomId },
          select: { hostID: true, isActive: true },
        }),
        prisma.user.findUnique({
          where: { id: request.user.id },
          select: { username: true },
        }),
      ]);
      if (!room) return reply.status(404).send({ error: 'Room not found' });
      if (!room.isActive) return reply.status(410).send({ error: 'Room is closed' });
      if (room.hostID !== request.user.id && !participant) {
        return reply.status(403).send({ error: 'Not a room member' });
      }

      const parsed = parseImageDataURL(typeof body.imageData === 'string' ? body.imageData : '');
      if (!parsed) {
        return reply.status(400).send({ error: 'Invalid image. Expected JPEG/PNG/WebP data URL.' });
      }
      if (parsed.buffer.length < 200) {
        return reply.status(400).send({ error: 'Image too small' });
      }
      if (parsed.buffer.length > 2.25 * 1024 * 1024) {
        return reply.status(413).send({ error: 'Image too large (max 2.25MB)' });
      }

      // ИИ-модератор — активный мут и NSFW-проверка фото перед публикацией
      const modMutedSec = await muteRemainingSec(roomId, request.user.id);
      if (modMutedSec > 0) {
        return reply.status(403).send({
          error: `Вы замучены модератором ещё на ${modMutedSec} сек`,
          code: 'MODERATION_MUTED',
          mutedForSec: modMutedSec,
        });
      }
      const imageCheck = await moderateImage(parsed.dataUrl);
      if (imageCheck.nsfw) {
        const seconds = await muteUser(roomId, request.user.id, 'nsfw_image', 600);
        const sysId = crypto.randomUUID();
        void auditModeration({
          roomId,
          messageId: sysId,
          subjectUserId: request.user.id,
          action: 'mute_nsfw_photo',
          reasonCode: 'nsfw_image',
        });
        try {
          await (fastify as any).gateway?.publishChatMessage?.({
            kind: 'chat.broadcast' as const,
            roomId,
            messageId: sysId,
            clientMessageId: sysId,
            senderId: 'plink-ai-moderator',
            senderName: 'ИИ-модератор',
            text: buildModWirePayload({
              action: 'mute',
              userId: request.user.id,
              username: sender?.username ?? 'user',
              seconds,
              reason: 'nsfw_image',
            }),
            createdAtMs: Date.now(),
          });
        } catch {
          /* noop */
        }
        return reply.status(422).send({
          error: `Фото отклонено ИИ-модератором. Мут на ${seconds} сек`,
          code: 'NSFW_BLOCKED',
          mutedForSec: seconds,
        });
      }
      if (typeof body.content === 'string' && containsProfanity(body.content)) {
        const seconds = await muteUser(roomId, request.user.id, 'profanity');
        return reply.status(403).send({
          error: `Мут на ${seconds} сек за нецензурную лексику`,
          code: 'MODERATION_MUTED',
          mutedForSec: seconds,
        });
      }

      const caption = typeof body.content === 'string' ? body.content.trim().slice(0, 2000) : '';
      const created = await prisma.chatMessage.create({
        data: {
          roomID: roomId,
          senderID: request.user.id,
          text: caption,
          mediaType: 'photo',
          mediaData: parsed.dataUrl,
        },
      });
      const clientMessageId =
        typeof body.clientMessageId === 'string' && body.clientMessageId.length > 0
          ? body.clientMessageId
          : null;
      const senderName = sender?.username ?? request.user.username ?? 'unknown';
      const event = {
        kind: 'chat.broadcast' as const,
        roomId,
        messageId: created.id,
        clientMessageId,
        senderId: request.user.id,
        senderName,
        text: caption,
        createdAtMs: created.createdAt.getTime(),
        mediaType: 'photo' as const,
        hasMedia: true,
      };
      try {
        await (fastify as any).gateway?.publishChatMessage?.(event);
      } catch (e: any) {
        console.warn('[room-photo] realtime publish failed:', e?.message || e);
      }
      return reply.send({
        messageId: created.id,
        clientMessageId,
        senderId: request.user.id,
        senderName,
        text: caption,
        createdAtMs: created.createdAt.getTime(),
        mediaType: 'photo',
        hasMedia: true,
      });
    },
  );

  // GET /api/rooms/:id/messages/:messageId/photo — stream room photo attachment.
  fastify.get(
    '/rooms/:id/messages/:messageId/photo',
    {
      preHandler: [fastify.authenticate],
    },
    async (request: any, reply: any) => {
      const { id: roomId, messageId } = request.params as { id: string; messageId: string };
      const [participant, room, message] = await Promise.all([
        prisma.roomParticipant
          .findUnique({
            where: { roomID_userID: { roomID: roomId, userID: request.user.id } },
            select: { id: true },
          })
          .catch(() => null),
        prisma.room.findUnique({
          where: { id: roomId },
          select: { hostID: true },
        }),
        prisma.chatMessage.findUnique({
          where: { id: messageId },
          select: { roomID: true, mediaType: true, mediaData: true },
        }),
      ]);
      if (!room || !message || message.roomID !== roomId)
        return reply.status(404).send({ error: 'Not found' });
      if (room.hostID !== request.user.id && !participant) {
        return reply.status(403).send({ error: 'Not a room member' });
      }
      if (message.mediaType !== 'photo' || !message.mediaData) {
        return reply.status(404).send({ error: 'No photo attachment' });
      }
      const parsed = parseImageDataURL(String(message.mediaData));
      if (!parsed) return reply.status(500).send({ error: 'Corrupt photo data' });
      reply
        .header('Cache-Control', 'private, max-age=3600')
        .header('Content-Length', String(parsed.buffer.length))
        .type(parsed.mime)
        .send(parsed.buffer);
    },
  );

  // GET /api/rooms/:id/messages — chat catch-up with opaque cursor
  // Cursor is opaque base64 of (createdAtMs,id), not raw messageId.
  // Fetches limit+1 to determine hasMore deterministically.
  // Tie-breaker: createdAt > ts OR (createdAt = ts AND id > id).
  fastify.get(
    '/rooms/:id/messages',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request: any, reply: any) => {
      const { id: roomId } = request.params;
      const cursor = (request.query as any)?.cursor as string | undefined;
      const limit = Math.min(parseInt((request.query as any)?.limit as string) || 50, 200);

      // Verify membership
      const [participant, room] = await Promise.all([
        prisma.roomParticipant
          .findUnique({
            where: { roomID_userID: { roomID: roomId, userID: request.user.id } },
            select: { id: true },
          })
          .catch(() => null),
        prisma.room.findUnique({
          where: { id: roomId },
          select: { hostID: true, isActive: true },
        }),
      ]);
      if (!room) return reply.status(404).send({ error: 'Room not found' });
      if (room.hostID !== request.user.id && !participant) {
        return reply.status(403).send({ error: 'Not a room member' });
      }

      // Decode opaque cursor — base64 of "createdAtMs:id"
      let afterCreatedAt: Date | undefined;
      let afterId: string | undefined;
      if (cursor) {
        try {
          const decoded = Buffer.from(cursor, 'base64').toString('utf-8');
          const parts = decoded.split(':');
          if (parts.length === 2) {
            afterCreatedAt = new Date(parseInt(parts[0]));
            afterId = parts[1];
          }
        } catch {
          // Invalid cursor — return from beginning
        }
      }

      // Fetch limit+1 to determine hasMore
      const fetchLimit = limit + 1;
      const messages = await prisma.chatMessage.findMany({
        where: {
          roomID: roomId,
          ...(afterCreatedAt && afterId
            ? {
                OR: [
                  { createdAt: { gt: afterCreatedAt } },
                  { createdAt: { equals: afterCreatedAt }, id: { gt: afterId } },
                ],
              }
            : afterCreatedAt
              ? { createdAt: { gt: afterCreatedAt } }
              : {}),
        },
        orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
        take: fetchLimit,
        select: {
          id: true,
          senderID: true,
          text: true,
          createdAt: true,
          mediaType: true,
          // mediaData (base64 до ~3MB на сообщение)
          // НЕ тянем — ради Boolean hasMedia; 200 фото давали ~600MB RSS.
        },
      });

      // hasMore is true only if we got limit+1 messages
      const hasMore = messages.length > limit;
      const returnMessages = hasMore ? messages.slice(0, limit) : messages;

      // Build nextCursor from last returned message
      let nextCursor: string | null = null;
      if (hasMore && returnMessages.length > 0) {
        const last = returnMessages[returnMessages.length - 1];
        nextCursor = Buffer.from(`${last.createdAt.getTime()}:${last.id}`).toString('base64');
      }

      // Fetch sender usernames in bulk
      const senderIds = [...new Set(returnMessages.map((m) => m.senderID))];
      const senders =
        senderIds.length > 0
          ? await prisma.user.findMany({
              where: { id: { in: senderIds } },
              select: { id: true, username: true },
            })
          : [];
      const senderMap = new Map(senders.map((s) => [s.id, s.username]));

      // hasMedia без загрузки base64-тела — лёгкий
      // запрос только id по кандидатам с mediaType.
      const mediaCandidateIds = returnMessages.filter((m) => m.mediaType).map((m) => m.id);
      const withMedia =
        mediaCandidateIds.length > 0
          ? await prisma.chatMessage.findMany({
              where: { id: { in: mediaCandidateIds }, mediaData: { not: null } },
              select: { id: true },
            })
          : [];
      const hasMediaSet = new Set(withMedia.map((m) => m.id));

      reply.send({
        messages: returnMessages.map((m) => ({
          messageId: m.id,
          clientMessageId: null,
          senderId: m.senderID,
          senderName: senderMap.get(m.senderID) ?? 'unknown',
          text: m.text,
          createdAtMs: m.createdAt.getTime(),
          mediaType: m.mediaType ?? null,
          hasMedia: Boolean(m.mediaType && hasMediaSet.has(m.id)),
        })),
        hasMore,
        nextCursor, // Opaque cursor, not messageId
      });
    },
  );

  // AUTO-CLEANUP: empty rooms (0 participants) + abandoned (no WS presence).
  // Soft-end only — room row + WatchHistory remain for UI history.
  // Every 60s so ghost rooms don't linger on Home/Friends.
  setInterval(async () => {
    try {
      const n = await sweepOrphanRooms(prisma, redis);
      if (n > 0) {
        await cacheDel(ROOMS_CACHE_KEY);
        console.log(`[cleanup] Soft-ended ${n} empty/abandoned room(s)`);
      }
    } catch (e: any) {
      console.error('[cleanup] Error:', e?.message || e);
    }
  }, 60 * 1000).unref();

  // One-shot sweep shortly after boot (clear stale from previous deploys)
  setTimeout(async () => {
    try {
      const n = await sweepOrphanRooms(prisma, redis);
      if (n > 0) {
        await cacheDel(ROOMS_CACHE_KEY);
        console.log(`[cleanup] Boot sweep: soft-ended ${n} room(s)`);
      }
    } catch (e: any) {
      console.error('[cleanup] Boot sweep error:', e?.message || e);
    }
  }, 15_000).unref();
}

/// Код комнаты генерировался через Math.random() —
/// предсказуемый PRNG, не предназначенный для секретов. Для комнат
/// с приватностью «по ссылке» этот код и есть единственный секрет,
/// поэтому берём криптостойкий источник.
///
/// Дополнительно исключены символы, которые путают при чтении вслух
/// и при вводе: 0/O и 1/I. Это заодно снижает число ошибочных попыток входа.
function generateRoomCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = crypto.randomBytes(6);
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars[bytes[i] % chars.length];
  }
  return code;
}

async function getUserPremiumStatus(prisma, userId: string): Promise<boolean> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { isPremium: true },
  });
  return user?.isPremium ?? false;
}
