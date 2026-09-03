// Групповые чаты (беседы), как в Telegram.
// Полноценный мессенджер внутри приложения синхронного просмотра.
// Встроенный ИИ-модератор: муты за маты, NSFW-фото, запрещённые названия.
import { prisma } from '../config/db.js';
import { redis } from '../config/redis.js';
import { config } from '../config/index.js';
import { randomUUID } from 'node:crypto';
import {
  containsProfanity,
  violatesContentPolicy,
  moderateImage,
  muteUser,
  muteRemainingSec,
  auditModeration,
} from '../moderation/autoMod.js';
import { resolvePresence } from '../services/presence.js';

const MAX_MEMBERS = 64;
const MAX_TITLE = 60;
const MAX_MESSAGE = 2000;
const MAX_DESCRIPTION = 240;
const MAX_AVATAR_BYTES = 2 * 1024 * 1024;
const GROUP_CREATE_IDEMPOTENCY_TTL_SEC = 900;
const GROUP_CREATE_PENDING_TTL_SEC = 60;
const GROUP_CREATE_WAIT_ATTEMPTS = 30;
const GROUP_CREATE_WAIT_MS = 100;

// A GET followed by SET is not idempotency: two replicas can both observe a
// missing key and create two rows. Reserve the key with SET NX, then replace
// the reservation only if we still own it. The compare-and-set scripts also
// prevent a slow/failed request from deleting or overwriting a newer retry.
const COMPLETE_GROUP_CREATE_LUA = `
if redis.call('get', KEYS[1]) == ARGV[1] then
  return redis.call('set', KEYS[1], ARGV[2], 'EX', ARGV[3])
end
return nil
`;
const RELEASE_GROUP_CREATE_LUA = `
if redis.call('get', KEYS[1]) == ARGV[1] then
  return redis.call('del', KEYS[1])
end
return 0
`;

const pause = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

function groupCreatePayload(group: {
  id: string;
  title: string;
  ownerID: string;
  createdAt: Date;
  members: unknown[];
}) {
  return {
    id: group.id,
    title: group.title,
    ownerID: group.ownerID,
    createdAt: group.createdAt,
    memberCount: group.members.length,
  };
}

/** Версия аватара беседы — миллисекунды avatarUpdatedAt, для ?v= и ETag. */
function avatarVersionOf(group: {
  avatarData?: string | null;
  avatarUpdatedAt?: Date | string | null;
}): number | null {
  if (!group?.avatarData) return null;
  if (!group.avatarUpdatedAt) return null;
  const ms = new Date(group.avatarUpdatedAt).getTime();
  return Number.isFinite(ms) ? ms : null;
}

/** Магические байты — data URL с картинкой, а не переименованный файл. */
function isRealImage(base64: string): boolean {
  const b = Buffer.from(base64, 'base64');
  if (b.length < 12) return false;
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return true; // JPEG
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return true; // PNG
  if (b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46) return true; // WebP (RIFF)
  return false;
}

/** Парсинг data:image/...;base64 — как в rooms.ts photo. */
function parseImage(dataUrl: unknown): { dataUrl: string; bytes: number } | null {
  if (typeof dataUrl !== 'string') return null;
  const m = dataUrl.match(/^data:image\/(png|jpe?g|webp|heic);base64,([A-Za-z0-9+/=]+)$/);
  if (!m) return null;
  const bytes = Math.floor((m[2].length * 3) / 4);
  return { dataUrl, bytes };
}

async function requireMember(groupId: string, userId: string) {
  return prisma.groupMember.findUnique({
    where: { groupID_userID: { groupID: groupId, userID: userId } },
  });
}

// В группу нельзя добавлять несуществующих/удалённых
// пользователей и пары с активной блокировкой (в любую сторону) относительно
// добавляющего — иначе блокировка обходилась созданием группы с жертвой.
async function filterAddableMemberIds(adderId: string, rawIds: string[]): Promise<string[]> {
  const unique = [...new Set(rawIds.filter((id) => id && id !== adderId))];
  if (unique.length === 0) return [];

  let existing: Set<string>;
  try {
    const users = await prisma.user.findMany({
      where: { id: { in: unique }, deletedAt: null } as any,
      select: { id: true },
    });
    existing = new Set(users.map((u: { id: string }) => u.id));
  } catch {
    // deletedAt может отсутствовать до миграции — проверяем только существование
    const users = await prisma.user.findMany({
      where: { id: { in: unique } },
      select: { id: true },
    });
    existing = new Set(users.map((u: { id: string }) => u.id));
  }

  const blockedPeers = new Set<string>();
  try {
    const blocks = await prisma.userBlock.findMany({
      where: {
        OR: [
          { blockerID: adderId, blockedID: { in: unique } },
          { blockedID: adderId, blockerID: { in: unique } },
        ],
      },
      select: { blockerID: true, blockedID: true },
    });
    for (const b of blocks as { blockerID: string; blockedID: string }[]) {
      blockedPeers.add(b.blockerID === adderId ? b.blockedID : b.blockerID);
    }
  } catch {
    /* таблица блокировок может отсутствовать mid-migrate */
  }

  return unique.filter((id) => existing.has(id) && !blockedPeers.has(id));
}

export default async function groupRoutes(fastify) {
  // POST /api/groups — создать беседу
  // Rate limit (создание групп не троттлилось вовсе)
  fastify.post(
    '/groups',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 5, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const { title, memberIds, clientRequestId } = request.body ?? {};
      const cleanTitle = typeof title === 'string' ? title.trim().slice(0, MAX_TITLE) : '';
      if (!cleanTitle) {
        return reply.status(400).send({ error: 'Название беседы обязательно' });
      }
      // ИИ-модерация названия
      if (violatesContentPolicy(cleanTitle) || containsProfanity(cleanTitle)) {
        return reply.status(422).send({
          error: 'Название беседы нарушает правила Plink',
          code: 'CONTENT_BLOCKED',
        });
      }
      const rawIds: string[] = Array.isArray(memberIds)
        ? memberIds.filter((x: unknown) => typeof x === 'string').slice(0, MAX_MEMBERS - 1)
        : [];
      const me = request.user.id;
      // Идемпотентность: на флаки-сети POST успевает создать беседу, а ответ
      // теряется таймаутом — повторный тап приносил второй POST и дубль беседы.
      const idemKey =
        typeof clientRequestId === 'string' && /^[A-Za-z0-9-]{8,64}$/.test(clientRequestId)
          ? `group:create:${me}:${clientRequestId}`
          : null;
      let reservationToken: string | null = null;
      if (idemKey && redis) {
        try {
          const token = `pending:${randomUUID()}`;
          for (let attempt = 0; attempt < GROUP_CREATE_WAIT_ATTEMPTS; attempt += 1) {
            const current = await redis.get(idemKey);
            if (!current) {
              const acquired = await redis.set(
                idemKey,
                token,
                'EX',
                GROUP_CREATE_PENDING_TTL_SEC,
                'NX',
              );
              if (acquired === 'OK') {
                reservationToken = token;
                break;
              }
              // Another replica won the race between GET and SET NX. Read it on
              // the next iteration instead of creating a second conversation.
              continue;
            }

            if (!current.startsWith('pending:')) {
              const existing = await prisma.groupChat.findUnique({
                where: { id: current },
                include: { members: true },
              });
              if (existing) {
                return reply.status(200).send(groupCreatePayload(existing));
              }
              // A crashed/rolled-back create can leave a result tombstone whose
              // row was removed by an administrator. Remove only that exact value
              // and retry the reservation; never DEL a key owned by a newer call.
              await redis.eval(RELEASE_GROUP_CREATE_LUA, 1, idemKey, current);
              continue;
            }

            // A peer is currently creating the row. Give it a short window to
            // commit, then return a retryable conflict instead of duplicating it.
            await pause(GROUP_CREATE_WAIT_MS);
          }

          if (!reservationToken) {
            return reply.status(409).send({
              error: 'Создание беседы ещё выполняется. Повторите через секунду.',
              code: 'GROUP_CREATE_IN_PROGRESS',
            });
          }
        } catch (error) {
          // Redis is an availability aid, not a reason to take the chat API down.
          // If it fails before a reservation is acquired we keep the old
          // fail-soft behavior; once a token is owned, creation below remains
          // responsible for releasing it on a database error.
          request.log?.warn?.({ err: error }, 'group idempotency reservation unavailable');
          reservationToken = null;
        }
      }
      // Фильтруем несуществующих/удалённых и блокировки
      const ids = await filterAddableMemberIds(me, rawIds);
      let group;
      try {
        group = await prisma.groupChat.create({
          data: {
            title: cleanTitle,
            ownerID: me,
            members: {
              create: [
                { userID: me, role: 'owner' },
                ...ids.filter((id) => id !== me).map((id) => ({ userID: id, role: 'member' })),
              ],
            },
          },
          include: { members: true },
        });
      } catch (error) {
        if (idemKey && redis && reservationToken) {
          await redis.eval(RELEASE_GROUP_CREATE_LUA, 1, idemKey, reservationToken).catch(() => {});
        }
        throw error;
      }
      if (idemKey && redis && reservationToken) {
        try {
          const completed = await redis.eval(
            COMPLETE_GROUP_CREATE_LUA,
            1,
            idemKey,
            reservationToken,
            group.id,
            String(GROUP_CREATE_IDEMPOTENCY_TTL_SEC),
          );
          if (completed !== 'OK') {
            request.log?.warn?.(
              { groupId: group.id },
              'group idempotency result was not committed',
            );
          }
        } catch (error) {
          // The group is already committed. Do not turn a successful create into
          // a 500; the client can still reconcile through GET /groups.
          request.log?.warn?.(
            { err: error, groupId: group.id },
            'group idempotency result write failed',
          );
        }
      }
      // Живое уведомление добавленным: беседа появляется в их списке сразу,
      // а не после ручного обновления (создатель перечитывает список сам).
      for (const uid of ids) {
        if (uid === me) continue;
        (fastify as any).gateway?.notifyUser(uid, {
          type: 'group:created',
          groupId: group.id,
          title: group.title,
        });
      }
      return reply.status(201).send(groupCreatePayload(group));
    },
  );

  // GET /api/groups — мои беседы (с последним сообщением)
  fastify.get('/groups', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const memberships = await prisma.groupMember.findMany({
      where: { userID: request.user.id },
      select: { groupID: true, role: true, lastReadAt: true },
    });
    const groupIds = memberships.map((m) => m.groupID);
    if (groupIds.length === 0) return reply.send({ groups: [] });

    const groups = await prisma.groupChat.findMany({
      where: { id: { in: groupIds } },
      include: {
        members: { select: { userID: true } },
        // description/avatar — чтобы строка чата рисовала фото беседы
        messages: {
          orderBy: { createdAt: 'desc' },
          take: 1,
          select: { content: true, senderName: true, mediaType: true, createdAt: true },
        },
      },
    });
    const roleById = new Map(memberships.map((m) => [m.groupID, m.role]));
    // unread-счётчики — сообщения после lastReadAt, не мои, не удалённые
    // Один groupBy вместо count на каждую беседу —
    // список чатов поллится клиентом, 50 групп давали 50 запросов.
    const unreadById = new Map<string, number>();
    const unreadGrouped = await prisma.groupMessage.groupBy({
      by: ['groupID'],
      where: {
        deletedAt: null,
        senderID: { not: request.user.id },
        OR: memberships.map((m) => ({
          groupID: m.groupID,
          ...(m.lastReadAt ? { createdAt: { gt: m.lastReadAt } } : {}),
        })),
      },
      _count: { _all: true },
    });
    for (const row of unreadGrouped) {
      unreadById.set(row.groupID, row._count._all);
    }
    const result = groups
      .map((g) => {
        const last = g.messages[0] ?? null;
        return {
          id: g.id,
          title: g.title,
          ownerID: g.ownerID,
          myRole: roleById.get(g.id) ?? 'member',
          unreadCount: unreadById.get(g.id) ?? 0,
          memberCount: g.members.length,
          memberIds: g.members.map((m) => m.userID),
          description: g.description ?? null,
          avatarVersion: avatarVersionOf(g),
          lastMessageText: last
            ? last.mediaType === 'photo'
              ? '\u{1F4F7} Фото'
              : last.content
            : null,
          lastMessageSender: last?.senderName ?? null,
          lastMessageAt: last?.createdAt ?? g.createdAt,
        };
      })
      .sort((a, b) => new Date(b.lastMessageAt).getTime() - new Date(a.lastMessageAt).getTime());
    return reply.send({ groups: result });
  });

  // GET /api/groups/:id/messages — история (последние 100, опционально after=ISO)
  fastify.get(
    '/groups/:id/messages',
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const groupId = request.params.id;
      const member = await requireMember(groupId, request.user.id);
      if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });

      const parsed =
        typeof request.query?.after === 'string' ? new Date(request.query.after) : null;
      const after = parsed && !Number.isNaN(parsed.getTime()) ? parsed : null;
      const select = {
        id: true,
        senderID: true,
        senderName: true,
        content: true,
        mediaType: true,
        createdAt: true,
        reactions: true,
      };
      if (after) {
        const messages = await prisma.groupMessage.findMany({
          where: { groupID: groupId, deletedAt: null, createdAt: { gt: after } },
          orderBy: { createdAt: 'asc' },
          take: 100,
          select,
        });
        return reply.send({ messages });
      }
      // Последние 100 берём desc+reverse — без отдельного
      // count и без OFFSET-скана всей истории беседы.
      const recent = await prisma.groupMessage.findMany({
        where: { groupID: groupId, deletedAt: null },
        orderBy: { createdAt: 'desc' },
        take: 100,
        select,
      });
      return reply.send({ messages: recent.reverse() });
    },
  );

  // POST /api/groups/:id/read — отметить беседу прочитанной
  // Rate limit на все write-роуты групп
  fastify.post(
    '/groups/:id/read',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const groupId = request.params.id;
      const member = await requireMember(groupId, request.user.id);
      if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });
      await prisma.groupMember.update({
        where: { groupID_userID: { groupID: groupId, userID: request.user.id } },
        data: { lastReadAt: new Date() },
      });
      return reply.send({ ok: true });
    },
  );

  // DELETE /api/groups/:id/messages/:messageId — удалить сообщение (soft delete).
  // Своё — любой участник; чужое — owner/admin беседы.
  fastify.delete(
    '/groups/:id/messages/:messageId',
    {
      preHandler: [fastify.authenticate],
      // Rate limit на все write-роуты групп
      config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const groupId = request.params.id;
      const messageId = request.params.messageId;
      const member = await requireMember(groupId, request.user.id);
      if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });
      const msg = await prisma.groupMessage.findUnique({
        where: { id: messageId },
        select: { senderID: true, groupID: true },
      });
      if (!msg || msg.groupID !== groupId)
        return reply.status(404).send({ error: 'Сообщение не найдено' });
      const isOwnerOrAdmin = member.role === 'owner' || member.role === 'admin';
      if (msg.senderID !== request.user.id && !isOwnerOrAdmin) {
        return reply.status(403).send({ error: 'Можно удалять только свои сообщения' });
      }
      await prisma.groupMessage.update({
        where: { id: messageId },
        data: { deletedAt: new Date() },
      });
      return reply.send({ ok: true });
    },
  );

  // POST /api/groups/:id/messages/:messageId/react — переключить эмодзи-реакцию
  // Rate limit (как у DM-реакций)
  fastify.post(
    '/groups/:id/messages/:messageId/react',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const groupId = request.params.id;
      const messageId = request.params.messageId;
      const me = request.user.id;
      const member = await requireMember(groupId, me);
      if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });
      const emoji =
        typeof request.body?.emoji === 'string' ? request.body.emoji.trim().slice(0, 8) : '';
      if (!emoji) return reply.status(400).send({ error: 'emoji обязателен' });

      // Тогл реакции — атомарный jsonb-UPDATE одним запросом.
      // Раньше read-modify-write без транзакции: две одновременные реакции разных
      // участников давали last-write-wins, одна молча исчезала.
      try {
        const rows = await prisma.$queryRaw<{ reactions: unknown }[]>`
        UPDATE "GroupMessage"
        SET "reactions" = CASE
          WHEN COALESCE("reactions"::jsonb -> ${emoji}::text, '[]'::jsonb) @> to_jsonb(${me}::text)
            THEN CASE
              WHEN jsonb_array_length(COALESCE("reactions"::jsonb -> ${emoji}::text, '[]'::jsonb) - ${me}::text) = 0
                THEN COALESCE("reactions"::jsonb, '{}'::jsonb) - ${emoji}::text
              ELSE jsonb_set(
                COALESCE("reactions"::jsonb, '{}'::jsonb),
                ARRAY[${emoji}::text],
                COALESCE("reactions"::jsonb -> ${emoji}::text, '[]'::jsonb) - ${me}::text)
            END
          ELSE jsonb_set(
            COALESCE("reactions"::jsonb, '{}'::jsonb),
            ARRAY[${emoji}::text],
            COALESCE("reactions"::jsonb -> ${emoji}::text, '[]'::jsonb) || to_jsonb(${me}::text),
            true)
        END
        WHERE "id" = ${messageId} AND "groupID" = ${groupId} AND "deletedAt" IS NULL
        RETURNING "reactions"
      `;
        if (rows.length === 0) return reply.status(404).send({ error: 'Сообщение не найдено' });
        const raw = rows[0].reactions;
        // форма ответа как была: { emoji: [userIds] }
        const reactions = typeof raw === 'string' ? JSON.parse(raw) : (raw ?? {});
        return reply.send({ ok: true, reactions });
      } catch (e: any) {
        // Ревью: транспортные/таймаутные ошибки могут прилететь ПОСЛЕ коммита
        // UPDATE — повтор тогла в fallback молча отменил бы реакцию и отдал 200.
        // Такие ошибки отдаём как 503, клиент повторит.
        const code = typeof e?.code === 'string' ? e.code : '';
        const transport = ['P1001', 'P1002', 'P1008', 'P1017', 'P2024', 'P2028'].includes(code);
        fastify.log?.error?.(`[groups] atomic react failed (${code || e?.name}): ${e?.message}`);
        if (transport)
          return reply
            .status(503)
            .send({ error: 'Не удалось поставить реакцию, попробуйте ещё раз' });
        // Колонка ещё не jsonb / нестандартные данные — падаем на прежний путь
      }

      const msg = await prisma.groupMessage.findUnique({
        where: { id: messageId },
        select: { groupID: true, reactions: true, deletedAt: true },
      });
      if (!msg || msg.groupID !== groupId || msg.deletedAt)
        return reply.status(404).send({ error: 'Сообщение не найдено' });
      const reactions = (msg.reactions ?? {}) as Record<string, string[]>;
      const users = new Set(reactions[emoji] ?? []);
      if (users.has(me)) {
        users.delete(me);
      } else {
        users.add(me);
      }
      if (users.size === 0) {
        delete reactions[emoji];
      } else {
        reactions[emoji] = [...users];
      }
      await prisma.groupMessage.update({ where: { id: messageId }, data: { reactions } });
      return reply.send({ ok: true, reactions });
    },
  );

  // POST /api/groups/:id/messages — отправить текст/фото (с ИИ-модерацией)
  // Rate limit — спам и заливка base64-фото не троттлились
  fastify.post(
    '/groups/:id/messages',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const groupId = request.params.id;
      const me = request.user.id;
      const member = await requireMember(groupId, me);
      if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });

      // Активный мут в этой беседе
      const scope = `group:${groupId}`;
      const mutedSec = await muteRemainingSec(scope, me);
      if (mutedSec > 0) {
        return reply.status(403).send({
          error: `Вы замучены модератором ещё на ${mutedSec} сек`,
          code: 'MODERATION_MUTED',
          mutedForSec: mutedSec,
        });
      }

      const body = request.body ?? {};
      const content =
        typeof body.content === 'string' ? body.content.trim().slice(0, MAX_MESSAGE) : '';
      const image = body.imageData ? parseImage(body.imageData) : null;
      if (!content && !image) {
        return reply.status(400).send({ error: 'Пустое сообщение' });
      }
      if (body.imageData && !image) {
        return reply.status(400).send({ error: 'Неподдерживаемый формат фото' });
      }
      if (image && image.bytes > 2.25 * 1024 * 1024) {
        return reply.status(413).send({ error: 'Image too large (max 2.25MB)' });
      }

      // Право «участники могут отправлять медиа» (как в Telegram).
      // Владелец и админы не ограничены никогда.
      if (image && member.role !== 'owner' && member.role !== 'admin') {
        const perms = await prisma.groupChat.findUnique({
          where: { id: groupId },
          select: { membersCanSendMedia: true },
        });
        if (perms && perms.membersCanSendMedia === false) {
          return reply.status(403).send({
            error: 'В этой беседе отправлять медиа могут только администраторы',
            code: 'GROUP_MEDIA_RESTRICTED',
          });
        }
      }

      // NSFW-проверка фото
      if (image) {
        const check = await moderateImage(image.dataUrl);
        if (check.nsfw) {
          const seconds = await muteUser(scope, me, 'nsfw_image', 600);
          void auditModeration({
            roomId: scope,
            messageId: `grp-${Date.now()}`,
            subjectUserId: me,
            action: 'mute_nsfw_photo',
            reasonCode: 'nsfw_image',
          });
          return reply.status(422).send({
            error: `Фото отклонено ИИ-модератором. Мут на ${seconds} сек`,
            code: 'NSFW_BLOCKED',
            mutedForSec: seconds,
          });
        }
      }

      // Маты → мут с эскалацией
      if (content && containsProfanity(content)) {
        const seconds = await muteUser(scope, me, 'profanity');
        void auditModeration({
          roomId: scope,
          messageId: `grp-${Date.now()}`,
          subjectUserId: me,
          action: 'mute_profanity',
          reasonCode: 'profanity',
        });
        return reply.status(403).send({
          error: `Мут на ${seconds} сек за нецензурную лексику`,
          code: 'MODERATION_MUTED',
          mutedForSec: seconds,
        });
      }

      const sender = await prisma.user.findUnique({
        where: { id: me },
        select: { username: true },
      });
      const msg = await prisma.groupMessage.create({
        data: {
          groupID: groupId,
          senderID: me,
          senderName: sender?.username ?? 'Unknown',
          content,
          mediaType: image ? 'photo' : null,
          mediaData: image ? image.dataUrl : null,
        },
        select: {
          id: true,
          senderID: true,
          senderName: true,
          content: true,
          mediaType: true,
          createdAt: true,
        },
      });
      // User-level realtime hint: members refresh their own authenticated view
      // immediately. The REST response remains authoritative, so a missed hint
      // is harmless and the existing polling path is still a safety net.
      const recipients = await prisma.groupMember.findMany({
        where: { groupID: groupId, userID: { not: me } },
        select: { userID: true },
      });
      for (const recipient of recipients) {
        (fastify as any).gateway?.notifyUser(recipient.userID, {
          type: 'group:message',
          groupId,
          messageId: msg.id,
        });
      }
      return reply.status(201).send(msg);
    },
  );

  // GET /api/groups/:id/messages/:messageId/photo — отдать фото беседы
  fastify.get(
    '/groups/:id/messages/:messageId/photo',
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const { id: groupId, messageId } = request.params;
      const member = await requireMember(groupId, request.user.id);
      if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });
      const msg = await prisma.groupMessage.findUnique({
        where: { id: messageId },
        select: { groupID: true, mediaType: true, mediaData: true },
      });
      if (!msg || msg.groupID !== groupId || msg.mediaType !== 'photo' || !msg.mediaData) {
        return reply.status(404).send({ error: 'Фото не найдено' });
      }
      const m = msg.mediaData.match(/^data:(image\/[a-z.+-]+);base64,(.+)$/);
      if (!m) return reply.status(404).send({ error: 'Фото повреждено' });
      reply.header('Cache-Control', 'private, max-age=86400');
      return reply.type(m[1]).send(Buffer.from(m[2], 'base64'));
    },
  );

  // POST /api/groups/:id/members — добавить участников (owner/admin)
  // Rate limit + фильтр несуществующих/удалённых/заблокированных
  fastify.post(
    '/groups/:id/members',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 20, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const groupId = request.params.id;
      const member = await requireMember(groupId, request.user.id);
      if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });
      const isBoss = member.role === 'owner' || member.role === 'admin';
      if (!isBoss) {
        // Право «участники могут добавлять участников»
        const perms = await prisma.groupChat.findUnique({
          where: { id: groupId },
          select: { membersCanInvite: true },
        });
        if (!perms || perms.membersCanInvite === false) {
          return reply.status(403).send({
            error: 'В этой беседе добавлять участников могут только администраторы',
            code: 'GROUP_INVITE_RESTRICTED',
          });
        }
      }
      const rawIds: string[] = Array.isArray(request.body?.userIds)
        ? request.body.userIds.filter((x: unknown) => typeof x === 'string').slice(0, MAX_MEMBERS)
        : [];
      if (rawIds.length === 0) return reply.status(400).send({ error: 'userIds обязателен' });
      const ids = await filterAddableMemberIds(request.user.id, rawIds);
      if (ids.length === 0) {
        // 404, не раскрывая факт блокировки
        return reply.status(404).send({ error: 'Пользователи не найдены' });
      }
      // Повторный тап/ретрай должен быть безопасным: уже состоящие в беседе
      // пользователи не считаются новыми и не получают повторное уведомление.
      const alreadyMembers = await prisma.groupMember.findMany({
        where: { groupID: groupId, userID: { in: ids } },
        select: { userID: true },
      });
      const alreadyMemberIds = new Set(alreadyMembers.map((item) => item.userID));
      const newIds = ids.filter((id) => !alreadyMemberIds.has(id));
      if (newIds.length === 0) {
        return reply.send({ ok: true, added: 0 });
      }
      const count = await prisma.groupMember.count({ where: { groupID: groupId } });
      if (count + newIds.length > MAX_MEMBERS) {
        return reply.status(422).send({ error: `Максимум ${MAX_MEMBERS} участников` });
      }
      await prisma.groupMember.createMany({
        data: newIds.map((id) => ({ groupID: groupId, userID: id, role: 'member' })),
        skipDuplicates: true,
      });
      const group = await prisma.groupChat.findUnique({
        where: { id: groupId },
        select: { title: true },
      });
      for (const uid of newIds) {
        (fastify as any).gateway?.notifyUser(uid, {
          type: 'group:created',
          groupId,
          title: group?.title ?? '',
        });
      }
      return reply.send({ ok: true, added: newIds.length });
    },
  );

  // POST /api/groups/:id/leave — выйти из беседы (владелец выходит — беседа остаётся, роль передаётся)
  // Rate limit на все write-роуты групп
  fastify.post(
    '/groups/:id/leave',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const groupId = request.params.id;
      const me = request.user.id;
      // Выход + передача владения — одной транзакцией.
      // Раньше четыре запроса вне транзакции: падение между шагами или два
      // одновременных leave оставляли ownerID на вышедшем либо беседу без владельца.
      // Ревью: удаление опустевшей беседы вынесено ЗА транзакцию и оставлено
      // fail-soft, как было в baseline — каскад по GroupMessage (base64-фото в
      // mediaData) может выбить таймаут транзакции, и тогда откатывалось бы даже
      // удаление моей строки, т.е. выйти из беседы стало бы невозможно.
      const left = await prisma.$transaction(async (tx) => {
        const member = await tx.groupMember.findUnique({
          where: { groupID_userID: { groupID: groupId, userID: me } },
        });
        if (!member) return null;
        await tx.groupMember.deleteMany({ where: { id: member.id } });
        const rest = await tx.groupMember.findMany({
          // userID != me — на случай, если снимок ещё видит мою удалённую строку
          where: { groupID: groupId, userID: { not: me } },
          orderBy: { joinedAt: 'asc' },
          take: 1,
        });
        if (rest.length > 0 && member.role === 'owner') {
          await tx.groupMember.updateMany({ where: { id: rest[0].id }, data: { role: 'owner' } });
          await tx.groupChat.updateMany({
            where: { id: groupId },
            data: { ownerID: rest[0].userID },
          });
        }
        return { empty: rest.length === 0 };
      });
      if (!left) return reply.status(404).send({ error: 'Вы не участник беседы' });
      if (left.empty) {
        // Пустая беседа: не смогли удалить — беседа просто останется осиротевшей
        await prisma.groupChat.delete({ where: { id: groupId } }).catch(() => {});
      }
      return reply.send({ ok: true });
    },
  );

  // GET /api/groups/:id — карточка беседы: участники, роли, права, аватар.
  // Экран «Настройки беседы» как в Telegram живёт на этой ручке.
  fastify.get('/groups/:id', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const groupId = request.params.id;
    const me = request.user.id;
    const myMembership = await requireMember(groupId, me);
    if (!myMembership) return reply.status(403).send({ error: 'Вы не участник беседы' });

    const group = await prisma.groupChat.findUnique({
      where: { id: groupId },
      include: {
        members: { select: { userID: true, role: true, joinedAt: true } },
        _count: { select: { messages: true } },
      },
    });
    if (!group) return reply.status(404).send({ error: 'Беседа не найдена' });

    const ids = group.members.map((m) => m.userID);
    type MemberUserRow = {
      id: string;
      username: string;
      displayName?: string | null;
      avatarURL?: string | null;
      avatarUpdatedAt?: Date | string | null;
      isOnline?: boolean | null;
      lastSeenAt?: Date | string | null;
      deletedAt?: Date | string | null;
    };
    let users: MemberUserRow[];
    try {
      users = await prisma.user.findMany({
        where: { id: { in: ids } },
        select: {
          id: true,
          username: true,
          displayName: true,
          avatarURL: true,
          avatarUpdatedAt: true,
          isOnline: true,
          lastSeenAt: true,
          deletedAt: true,
        },
      });
    } catch {
      // deletedAt/lastSeenAt могут отсутствовать до миграции
      users = await prisma.user.findMany({
        where: { id: { in: ids } },
        select: { id: true, username: true, displayName: true, avatarURL: true },
      });
    }
    const publicBase = config.PUBLIC_BASE_URL;
    const userById = new Map(users.map((u) => [u.id, u]));

    const members = group.members.map((m) => {
      const u = userById.get(m.userID);
      const deleted = !!u?.deletedAt || String(u?.username ?? '').startsWith('deleted_');
      if (!u || deleted) {
        return {
          id: m.userID,
          username: u?.username ?? `deleted_${String(m.userID).slice(0, 8)}`,
          displayName: 'Удалённый аккаунт',
          avatarURL: null,
          avatarVersion: null,
          isOnline: false,
          lastSeenAt: null,
          role: m.role,
          joinedAt: m.joinedAt,
          isDeleted: true,
        };
      }
      const versionMs = u.avatarUpdatedAt ? new Date(u.avatarUpdatedAt).getTime() : 0;
      const avatarURL =
        Number.isFinite(versionMs) && versionMs > 0
          ? `${publicBase}/api/users/${u.id}/avatar?v=${versionMs}`
          : `${publicBase}/api/users/${u.id}/avatar`;
      const pres = resolvePresence(u);
      return {
        id: u.id,
        username: u.username,
        displayName: u.displayName ?? null,
        avatarURL,
        avatarVersion: versionMs > 0 ? versionMs : null,
        isOnline: pres.isOnline,
        lastSeenAt: pres.lastSeenAt,
        role: m.role,
        joinedAt: m.joinedAt,
        isDeleted: false,
      };
    });

    // Порядок как в Telegram: владелец → админы → участники (в сети выше)
    const rank = (r: string) => (r === 'owner' ? 0 : r === 'admin' ? 1 : 2);
    members.sort((a, b) => {
      if (rank(a.role) !== rank(b.role)) return rank(a.role) - rank(b.role);
      if (a.isOnline !== b.isOnline) return a.isOnline ? -1 : 1;
      return String(a.displayName || a.username).localeCompare(
        String(b.displayName || b.username),
        'ru',
      );
    });

    const isBoss = myMembership.role === 'owner' || myMembership.role === 'admin';
    return reply.send({
      id: group.id,
      title: group.title,
      description: group.description ?? null,
      ownerID: group.ownerID,
      createdAt: group.createdAt,
      myRole: myMembership.role,
      memberCount: group.members.length,
      messageCount: group._count.messages,
      avatarVersion: avatarVersionOf(group),
      maxMembers: MAX_MEMBERS,
      permissions: {
        membersCanInvite: group.membersCanInvite,
        membersCanSendMedia: group.membersCanSendMedia,
        membersCanChangeInfo: group.membersCanChangeInfo,
      },
      myPermissions: {
        canChangeInfo: isBoss || group.membersCanChangeInfo,
        canInvite: isBoss || group.membersCanInvite,
        canSendMedia: isBoss || group.membersCanSendMedia,
        canManagePermissions: isBoss,
        canManageAdmins: myMembership.role === 'owner',
        canRemoveMembers: isBoss,
        canDeleteGroup: myMembership.role === 'owner',
      },
      members,
    });
  });

  // GET /api/groups/:id/avatar — байты аватара беседы (только участникам)
  fastify.get(
    '/groups/:id/avatar',
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const groupId = request.params.id;
      const member = await requireMember(groupId, request.user.id);
      if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });
      const group = await prisma.groupChat.findUnique({
        where: { id: groupId },
        select: { avatarData: true, avatarUpdatedAt: true },
      });
      if (!group?.avatarData) return reply.status(404).send({ error: 'Аватар не установлен' });
      const m = group.avatarData.match(/^data:(image\/[a-z.+-]+);base64,(.+)$/);
      if (!m) return reply.status(404).send({ error: 'Аватар повреждён' });
      // Как у пользовательских аватаров: без долгого кэша, клиент бустит ?v=
      reply.header('Cache-Control', 'private, max-age=0, must-revalidate');
      const ms = avatarVersionOf(group);
      if (ms) {
        reply.header('ETag', `"${groupId}-${ms}"`);
        reply.header('Last-Modified', new Date(ms).toUTCString());
      }
      return reply.type(m[1]).send(Buffer.from(m[2], 'base64'));
    },
  );

  // PATCH /api/groups/:id — название, описание, аватар, права.
  // Название/описание/аватар: owner/admin, либо участники при membersCanChangeInfo.
  // Права: только owner/admin.
  fastify.patch(
    '/groups/:id',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const groupId = request.params.id;
      const me = request.user.id;
      const member = await requireMember(groupId, me);
      if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });
      const group = await prisma.groupChat.findUnique({
        where: { id: groupId },
        select: { membersCanChangeInfo: true },
      });
      if (!group) return reply.status(404).send({ error: 'Беседа не найдена' });

      const isBoss = member.role === 'owner' || member.role === 'admin';
      const canChangeInfo = isBoss || group.membersCanChangeInfo;
      const body = request.body ?? {};
      const data: Record<string, unknown> = {};

      if (typeof body.title === 'string') {
        if (!canChangeInfo) {
          return reply
            .status(403)
            .send({ error: 'Менять данные беседы могут только администраторы' });
        }
        const title = body.title.trim().slice(0, MAX_TITLE);
        if (!title) return reply.status(400).send({ error: 'Название обязательно' });
        if (violatesContentPolicy(title) || containsProfanity(title)) {
          return reply
            .status(422)
            .send({ error: 'Название нарушает правила Plink', code: 'CONTENT_BLOCKED' });
        }
        data.title = title;
      }

      if ('description' in body) {
        if (!canChangeInfo) {
          return reply
            .status(403)
            .send({ error: 'Менять данные беседы могут только администраторы' });
        }
        if (body.description === null) {
          data.description = null;
        } else if (typeof body.description === 'string') {
          const desc = body.description.trim().slice(0, MAX_DESCRIPTION);
          if (desc && (violatesContentPolicy(desc) || containsProfanity(desc))) {
            return reply
              .status(422)
              .send({ error: 'Описание нарушает правила Plink', code: 'CONTENT_BLOCKED' });
          }
          data.description = desc || null;
        } else {
          return reply.status(400).send({ error: 'Неверное описание' });
        }
      }

      if ('avatarData' in body) {
        if (!canChangeInfo) {
          return reply
            .status(403)
            .send({ error: 'Менять данные беседы могут только администраторы' });
        }
        if (body.avatarData === null) {
          data.avatarData = null;
          data.avatarUpdatedAt = null;
        } else {
          const parsed = parseImage(body.avatarData);
          if (!parsed) return reply.status(400).send({ error: 'Неподдерживаемый формат фото' });
          if (parsed.bytes > MAX_AVATAR_BYTES) {
            return reply.status(413).send({ error: 'Фото слишком большое (максимум 2 МБ)' });
          }
          const base64 = String(body.avatarData).split(',')[1] ?? '';
          if (!isRealImage(base64)) {
            return reply.status(400).send({ error: 'Файл не является изображением' });
          }
          const check = await moderateImage(parsed.dataUrl);
          if (check.nsfw) {
            void auditModeration({
              roomId: `group:${groupId}`,
              messageId: `grp-avatar-${groupId}`,
              subjectUserId: me,
              action: 'reject_nsfw_group_avatar',
              reasonCode: 'nsfw_image',
            });
            return reply.status(422).send({
              error: 'Фото отклонено ИИ-модератором',
              code: 'NSFW_BLOCKED',
            });
          }
          data.avatarData = parsed.dataUrl;
          data.avatarUpdatedAt = new Date();
        }
      }

      for (const key of [
        'membersCanInvite',
        'membersCanSendMedia',
        'membersCanChangeInfo',
      ] as const) {
        if (key in body) {
          if (!isBoss) {
            return reply
              .status(403)
              .send({ error: 'Права участников меняет только администратор' });
          }
          if (typeof body[key] !== 'boolean') {
            return reply.status(400).send({ error: `${key} должен быть boolean` });
          }
          data[key] = body[key];
        }
      }

      if (Object.keys(data).length === 0) {
        return reply.status(400).send({ error: 'Нечего менять' });
      }

      const updated = await prisma.groupChat.update({
        where: { id: groupId },
        data: data as any,
        include: { members: { select: { userID: true } } },
      });
      const payload = {
        type: 'group:updated',
        groupId,
        title: updated.title,
        avatarVersion: avatarVersionOf(updated),
      };
      for (const m of updated.members) {
        if (m.userID === me) continue;
        (fastify as any).gateway?.notifyUser(m.userID, payload);
      }
      return reply.send({
        id: updated.id,
        title: updated.title,
        description: updated.description ?? null,
        avatarVersion: avatarVersionOf(updated),
        permissions: {
          membersCanInvite: updated.membersCanInvite,
          membersCanSendMedia: updated.membersCanSendMedia,
          membersCanChangeInfo: updated.membersCanChangeInfo,
        },
      });
    },
  );

  // POST /api/groups/:id/members/:userId/role — назначить/снять админа (только владелец)
  fastify.post(
    '/groups/:id/members/:userId/role',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 20, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const { id: groupId, userId } = request.params;
      const me = request.user.id;
      const member = await requireMember(groupId, me);
      if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });
      if (member.role !== 'owner') {
        return reply.status(403).send({ error: 'Назначать администраторов может только владелец' });
      }
      if (userId === me) {
        return reply.status(422).send({ error: 'Свою роль изменить нельзя' });
      }
      const role = request.body?.role;
      if (role !== 'admin' && role !== 'member') {
        return reply.status(400).send({ error: 'role: admin | member' });
      }
      const target = await requireMember(groupId, userId);
      if (!target) return reply.status(404).send({ error: 'Участник не найден' });
      if (target.role === 'owner') {
        return reply.status(422).send({ error: 'Роль владельца изменить нельзя' });
      }
      if (target.role === role) return reply.send({ ok: true, role });
      await prisma.groupMember.update({
        where: { groupID_userID: { groupID: groupId, userID: userId } },
        data: { role },
      });
      (fastify as any).gateway?.notifyUser(userId, { type: 'group:role', groupId, role });
      return reply.send({ ok: true, role });
    },
  );

  // DELETE /api/groups/:id/members/:userId — исключить участника.
  // owner/admin; владельца исключить нельзя, админ не может исключить админа.
  fastify.delete(
    '/groups/:id/members/:userId',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 20, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const { id: groupId, userId } = request.params;
      const me = request.user.id;
      const member = await requireMember(groupId, me);
      if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });
      if (member.role !== 'owner' && member.role !== 'admin') {
        return reply
          .status(403)
          .send({ error: 'Исключать участников могут только администраторы' });
      }
      if (userId === me) {
        return reply.status(422).send({ error: 'Чтобы выйти самому, используйте выход из беседы' });
      }
      const target = await requireMember(groupId, userId);
      if (!target) return reply.status(404).send({ error: 'Участник не найден' });
      if (target.role === 'owner') {
        return reply.status(422).send({ error: 'Владельца беседы исключить нельзя' });
      }
      if (target.role === 'admin' && member.role !== 'owner') {
        return reply.status(403).send({ error: 'Администратора может исключить только владелец' });
      }
      await prisma.groupMember.delete({
        where: { groupID_userID: { groupID: groupId, userID: userId } },
      });
      (fastify as any).gateway?.notifyUser(userId, { type: 'group:removed', groupId });
      const rest = await prisma.groupMember.findMany({
        where: { groupID: groupId },
        select: { userID: true },
      });
      for (const m of rest) {
        if (m.userID === me) continue;
        (fastify as any).gateway?.notifyUser(m.userID, { type: 'group:updated', groupId });
      }
      return reply.send({ ok: true });
    },
  );

  // DELETE /api/groups/:id — удалить беседу у всех (только владелец)
  fastify.delete(
    '/groups/:id',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 5, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const groupId = request.params.id;
      const me = request.user.id;
      const member = await requireMember(groupId, me);
      if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });
      if (member.role !== 'owner') {
        return reply.status(403).send({ error: 'Удалить беседу может только владелец' });
      }
      // Список участников снимаем ДО удаления — после каскада его уже не будет
      const members = await prisma.groupMember.findMany({
        where: { groupID: groupId },
        select: { userID: true },
      });
      await prisma.groupChat.delete({ where: { id: groupId } });
      for (const m of members) {
        if (m.userID === me) continue;
        (fastify as any).gateway?.notifyUser(m.userID, { type: 'group:removed', groupId });
      }
      return reply.send({ ok: true });
    },
  );
}
