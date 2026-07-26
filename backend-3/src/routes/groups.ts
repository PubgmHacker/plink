// src/routes/groups.ts — M16: групповые чаты (беседы), как в Telegram.
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

export default async function groupRoutes(fastify) {
  // POST /api/groups — создать беседу
  fastify.post('/groups', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { title, memberIds } = request.body ?? {};
    const cleanTitle = typeof title === 'string' ? title.trim().slice(0, MAX_TITLE) : '';
    if (!cleanTitle) {
      return reply.status(400).send({ error: 'Название беседы обязательно' });
    }
    // M16: ИИ-модерация названия
    if (violatesContentPolicy(cleanTitle) || containsProfanity(cleanTitle)) {
      return reply.status(422).send({
        error: 'Название беседы нарушает правила Plink',
        code: 'CONTENT_BLOCKED',
      });
    }
    const ids: string[] = Array.isArray(memberIds)
      ? memberIds.filter((x: unknown) => typeof x === 'string').slice(0, MAX_MEMBERS - 1)
      : [];
    const me = request.user.id;
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
    // M17: unread-счётчики — сообщения после lastReadAt, не мои, не удалённые
    const lastReadById = new Map(memberships.map((m) => [m.groupID, m.lastReadAt]));
    const unreadById = new Map();
    await Promise.all(groups.map(async (g) => {
      const lastRead = lastReadById.get(g.id);
      const unread = await prisma.groupMessage.count({
        where: {
          groupID: g.id,
          deletedAt: null,
          senderID: { not: request.user.id },
          ...(lastRead ? { createdAt: { gt: lastRead } } : {}),
        },
      });
      unreadById.set(g.id, unread);
    }));
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

    const after = typeof request.query?.after === 'string' ? new Date(request.query.after) : null;
    const messages = await prisma.groupMessage.findMany({
      where: {
        groupID: groupId,
        deletedAt: null,
        ...(after && !Number.isNaN(after.getTime()) ? { createdAt: { gt: after } } : {}),
      },
      orderBy: { createdAt: 'asc' },
      take: 100,
      ...(after ? {} : { skip: Math.max(0, await prisma.groupMessage.count({ where: { groupID: groupId, deletedAt: null } }) - 100) }),
      select: {
        id: true, senderID: true, senderName: true, content: true,
        mediaType: true, createdAt: true, reactions: true,
      },
    });
    return reply.send({ messages });
  });

  // M17: POST /api/groups/:id/read — отметить беседу прочитанной
  fastify.post('/groups/:id/read', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const groupId = request.params.id;
    const member = await requireMember(groupId, request.user.id);
    if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });
    await prisma.groupMember.update({
      where: { groupID_userID: { groupID: groupId, userID: request.user.id } },
      data: { lastReadAt: new Date() },
    });
    return reply.send({ ok: true });
  });

  // M17: DELETE /api/groups/:id/messages/:messageId — удалить сообщение (soft delete).
  // Своё — любой участник; чужое — owner/admin беседы.
  fastify.delete('/groups/:id/messages/:messageId', { preHandler: [fastify.authenticate] }, async (request, reply) => {
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

  // M17: POST /api/groups/:id/messages/:messageId/react — переключить эмодзи-реакцию
  fastify.post('/groups/:id/messages/:messageId/react', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const groupId = request.params.id;
    const messageId = request.params.messageId;
    const me = request.user.id;
    const member = await requireMember(groupId, me);
    if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });
    const emoji = typeof request.body?.emoji === 'string' ? request.body.emoji.trim().slice(0, 8) : '';
    if (!emoji) return reply.status(400).send({ error: 'emoji обязателен' });
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
  fastify.post('/groups/:id/messages', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const groupId = request.params.id;
    const me = request.user.id;
    const member = await requireMember(groupId, me);
    if (!member) return reply.status(403).send({ error: 'Вы не участник беседы' });

    // M16: активный мут в этой беседе
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

    // M16: NSFW-проверка фото
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

    // M16: маты → мут с эскалацией
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
  fastify.post('/groups/:id/members', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const groupId = request.params.id;
    const member = await requireMember(groupId, request.user.id);
    if (!member || (member.role !== 'owner' && member.role !== 'admin')) {
      return reply.status(403).send({ error: 'Только владелец может добавлять участников' });
    }
    const ids: string[] = Array.isArray(request.body?.userIds)
      ? request.body.userIds.filter((x: unknown) => typeof x === 'string')
      : [];
    if (ids.length === 0) return reply.status(400).send({ error: 'userIds обязателен' });
    const count = await prisma.groupMember.count({ where: { groupID: groupId } });
    if (count + ids.length > MAX_MEMBERS) {
      return reply.status(422).send({ error: `Максимум ${MAX_MEMBERS} участников` });
    }
    await prisma.groupMember.createMany({
      data: ids.map((id) => ({ groupID: groupId, userID: id, role: 'member' })),
      skipDuplicates: true,
    });
    return reply.send({ ok: true });
  });

  // POST /api/groups/:id/leave — выйти из беседы (владелец выходит — беседа остаётся, роль передаётся)
  fastify.post('/groups/:id/leave', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const groupId = request.params.id;
    const me = request.user.id;
    const member = await requireMember(groupId, me);
    if (!member) return reply.status(404).send({ error: 'Вы не участник беседы' });
    await prisma.groupMember.delete({ where: { id: member.id } });
    const rest = await prisma.groupMember.findMany({
      where: { groupID: groupId },
      orderBy: { joinedAt: 'asc' },
      take: 1,
    });
    if (rest.length === 0) {
      await prisma.groupChat.delete({ where: { id: groupId } }).catch(() => {});
    } else if (member.role === 'owner') {
      await prisma.groupMember.update({ where: { id: rest[0].id }, data: { role: 'owner' } });
      await prisma.groupChat.update({ where: { id: groupId }, data: { ownerID: rest[0].userID } });
    }
    return reply.send({ ok: true });
  });

  // PATCH /api/groups/:id — переименовать (owner/admin, с модерацией)
  fastify.patch('/groups/:id', { preHandler: [fastify.authenticate] }, async (request, reply) => {
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
