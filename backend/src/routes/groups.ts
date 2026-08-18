// Групповые чаты (беседы), как в Telegram.
// Полноценный мессенджер внутри приложения синхронного просмотра.
// Встроенный ИИ-модератор: муты за маты, NSFW-фото, запрещённые названия.
import { prisma } from '../config/db.js';
import {
  containsProfanity,
  violatesContentPolicy,
  moderateImage,
  muteUser,
  muteRemainingSec,
  auditModeration,
} from '../moderation/autoMod.js';

const MAX_MEMBERS = 64;
const MAX_TITLE = 60;
const MAX_MESSAGE = 2000;

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
  fastify.post('/groups', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 5, timeWindow: '1 minute' } },
  }, async (request, reply) => {
    const { title, memberIds } = request.body ?? {};
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
    // Фильтруем несуществующих/удалённых и блокировки
    const ids = await filterAddableMemberIds(me, rawIds);
    const group = await prisma.groupChat.create({
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
    return reply.status(201).send({
      id: group.id,
      title: group.title,
      ownerID: group.ownerID,
      createdAt: group.createdAt,
      memberCount: group.members.length,
    });
  });

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
          lastMessageText: last ? (last.mediaType === 'photo' ? '\u{1F4F7} Фото' : last.content) : null,
          lastMessageSender: last?.senderName ?? null,
          lastMessageAt: last?.createdAt ?? g.createdAt,
        };
      })
      .sort((a, b) => new Date(b.lastMessageAt).getTime() - new Date(a.lastMessageAt).getTime());
    return reply.send({ groups: result });
  });

  // GET /api/groups/:id/messages — история (последние 100, опционально after=ISO)
  fastify.get('/groups/:id/messages', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const groupId = request.params.id;
    const member = await requireMember(groupId, request.user.id);
    if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });

    const parsed = typeof request.query?.after === 'string' ? new Date(request.query.after) : null;
    const after = parsed && !Number.isNaN(parsed.getTime()) ? parsed : null;
    const select = {
      id: true, senderID: true, senderName: true, content: true,
      mediaType: true, createdAt: true, reactions: true,
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
  });

  // POST /api/groups/:id/read — отметить беседу прочитанной
  // Rate limit на все write-роуты групп
  fastify.post('/groups/:id/read', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
  }, async (request, reply) => {
    const groupId = request.params.id;
    const member = await requireMember(groupId, request.user.id);
    if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });
    await prisma.groupMember.update({
      where: { groupID_userID: { groupID: groupId, userID: request.user.id } },
      data: { lastReadAt: new Date() },
    });
    return reply.send({ ok: true });
  });

  // DELETE /api/groups/:id/messages/:messageId — удалить сообщение (soft delete).
  // Своё — любой участник; чужое — owner/admin беседы.
  fastify.delete('/groups/:id/messages/:messageId', {
    preHandler: [fastify.authenticate],
    // Rate limit на все write-роуты групп
    config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
  }, async (request, reply) => {
    const groupId = request.params.id;
    const messageId = request.params.messageId;
    const member = await requireMember(groupId, request.user.id);
    if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });
    const msg = await prisma.groupMessage.findUnique({
      where: { id: messageId },
      select: { senderID: true, groupID: true },
    });
    if (!msg || msg.groupID !== groupId) return reply.status(404).send({ error: 'Сообщение не найдено' });
    const isOwnerOrAdmin = member.role === 'owner' || member.role === 'admin';
    if (msg.senderID !== request.user.id && !isOwnerOrAdmin) {
      return reply.status(403).send({ error: 'Можно удалять только свои сообщения' });
    }
    await prisma.groupMessage.update({ where: { id: messageId }, data: { deletedAt: new Date() } });
    return reply.send({ ok: true });
  });

  // POST /api/groups/:id/messages/:messageId/react — переключить эмодзи-реакцию
  // Rate limit (как у DM-реакций)
  fastify.post('/groups/:id/messages/:messageId/react', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
  }, async (request, reply) => {
    const groupId = request.params.id;
    const messageId = request.params.messageId;
    const me = request.user.id;
    const member = await requireMember(groupId, me);
    if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });
    const emoji = typeof request.body?.emoji === 'string' ? request.body.emoji.trim().slice(0, 8) : '';
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
      if (transport) return reply.status(503).send({ error: 'Не удалось поставить реакцию, попробуйте ещё раз' });
      // Колонка ещё не jsonb / нестандартные данные — падаем на прежний путь
    }

    const msg = await prisma.groupMessage.findUnique({
      where: { id: messageId },
      select: { groupID: true, reactions: true, deletedAt: true },
    });
    if (!msg || msg.groupID !== groupId || msg.deletedAt) return reply.status(404).send({ error: 'Сообщение не найдено' });
    const reactions = (msg.reactions ?? {}) as Record<string, string[]>;
    const users = new Set(reactions[emoji] ?? []);
    if (users.has(me)) { users.delete(me); } else { users.add(me); }
    if (users.size === 0) { delete reactions[emoji]; } else { reactions[emoji] = [...users]; }
    await prisma.groupMessage.update({ where: { id: messageId }, data: { reactions } });
    return reply.send({ ok: true, reactions });
  });

  // POST /api/groups/:id/messages — отправить текст/фото (с ИИ-модерацией)
  // Rate limit — спам и заливка base64-фото не троттлились
  fastify.post('/groups/:id/messages', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
  }, async (request, reply) => {
    const groupId = request.params.id;
    const me = request.user.id;
    const member = await requireMember(groupId, me);
    if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });

    // Активный мут в этой беседе
    const scope = `group:${groupId}`;
    const mutedSec = muteRemainingSec(scope, me);
    if (mutedSec > 0) {
      return reply.status(403).send({
        error: `Вы замучены модератором ещё на ${mutedSec} сек`,
        code: 'MODERATION_MUTED',
        mutedForSec: mutedSec,
      });
    }

    const body = request.body ?? {};
    const content = typeof body.content === 'string' ? body.content.trim().slice(0, MAX_MESSAGE) : '';
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

    // NSFW-проверка фото
    if (image) {
      const check = await moderateImage(image.dataUrl);
      if (check.nsfw) {
        const seconds = muteUser(scope, me, 'nsfw_image', 600);
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
      const seconds = muteUser(scope, me, 'profanity');
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
      select: { id: true, senderID: true, senderName: true, content: true, mediaType: true, createdAt: true },
    });
    return reply.status(201).send(msg);
  });

  // GET /api/groups/:id/messages/:messageId/photo — отдать фото беседы
  fastify.get('/groups/:id/messages/:messageId/photo', { preHandler: [fastify.authenticate] }, async (request, reply) => {
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
  });

  // POST /api/groups/:id/members — добавить участников (owner/admin)
  // Rate limit + фильтр несуществующих/удалённых/заблокированных
  fastify.post('/groups/:id/members', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 20, timeWindow: '1 minute' } },
  }, async (request, reply) => {
    const groupId = request.params.id;
    const member = await requireMember(groupId, request.user.id);
    if (!member || (member.role !== 'owner' && member.role !== 'admin')) {
      return reply.status(403).send({ error: 'Только владелец может добавлять участников' });
    }
    const rawIds: string[] = Array.isArray(request.body?.userIds)
      ? request.body.userIds.filter((x: unknown) => typeof x === 'string')
      : [];
    if (rawIds.length === 0) return reply.status(400).send({ error: 'userIds обязателен' });
    const ids = await filterAddableMemberIds(request.user.id, rawIds);
    if (ids.length === 0) {
      // 404, не раскрывая факт блокировки
      return reply.status(404).send({ error: 'Пользователи не найдены' });
    }
    const count = await prisma.groupMember.count({ where: { groupID: groupId } });
    if (count + ids.length > MAX_MEMBERS) {
      return reply.status(422).send({ error: `Максимум ${MAX_MEMBERS} участников` });
    }
    await prisma.groupMember.createMany({
      data: ids.map((id) => ({ groupID: groupId, userID: id, role: 'member' })),
      skipDuplicates: true,
    });
    return reply.send({ ok: true, added: ids.length });
  });

  // POST /api/groups/:id/leave — выйти из беседы (владелец выходит — беседа остаётся, роль передаётся)
  // Rate limit на все write-роуты групп
  fastify.post('/groups/:id/leave', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
  }, async (request, reply) => {
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
        await tx.groupChat.updateMany({ where: { id: groupId }, data: { ownerID: rest[0].userID } });
      }
      return { empty: rest.length === 0 };
    });
    if (!left) return reply.status(404).send({ error: 'Вы не участник беседы' });
    if (left.empty) {
      // Пустая беседа: не смогли удалить — беседа просто останется осиротевшей
      await prisma.groupChat.delete({ where: { id: groupId } }).catch(() => {});
    }
    return reply.send({ ok: true });
  });

  // PATCH /api/groups/:id — переименовать (owner/admin, с модерацией)
  // Rate limit на все write-роуты групп
  fastify.patch('/groups/:id', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
  }, async (request, reply) => {
    const groupId = request.params.id;
    const member = await requireMember(groupId, request.user.id);
    if (!member || (member.role !== 'owner' && member.role !== 'admin')) {
      return reply.status(403).send({ error: 'Только владелец может переименовать беседу' });
    }
    const title = typeof request.body?.title === 'string' ? request.body.title.trim().slice(0, MAX_TITLE) : '';
    if (!title) return reply.status(400).send({ error: 'Название обязательно' });
    if (violatesContentPolicy(title) || containsProfanity(title)) {
      return reply.status(422).send({ error: 'Название нарушает правила Plink', code: 'CONTENT_BLOCKED' });
    }
    const updated = await prisma.groupChat.update({ where: { id: groupId }, data: { title } });
    return reply.send({ id: updated.id, title: updated.title });
  });
}
