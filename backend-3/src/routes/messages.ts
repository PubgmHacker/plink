import { prisma } from '../config/db.js';
import { pushToUser } from '../services/pushService.js';
// M16: ИИ-модератор в личке — муты за маты и NSFW-фото
import {
  containsProfanity,
  moderateImage,
  muteUser,
  muteRemainingSec,
  auditModeration,
} from '../moderation/autoMod.js';

/** Explicit DTO — prevents `const invites = []` → never[] under strict tsc (Railway). */
export type RoomInviteDTO = {
  id: string;
  messageId: string;
  roomID: string;
  roomCode: string;
  roomName: string;
  fromUserID: string;
  fromUsername: string;
  fromAvatarURL: string | null;
  mediaTitle: string | null;
  timestamp: Date;
  preview: string;
};

const FREE_REACT_EMOJIS = new Set([
  '❤️', '👍', '😂', '😮', '😢', '🔥', '👏', '🎉', '💯', '🥰',
  '😍', '🤔', '😭', '🙏', '✨', '🤣', '😎', '🤝', '💪', '👀',
]);

function parseImageDataURL(input: string): { mime: string; buffer: Buffer; dataUrl: string } | null {
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
  const isPNG = buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47;
  const isWebP = buffer[0] === 0x52 && buffer[1] === 0x49 && buffer[2] === 0x46 && buffer[3] === 0x46;
  if (!isJPEG && !isPNG && !isWebP) return null;
  return { mime, buffer, dataUrl: `data:${mime};base64,${match[3]}` };
}

function aggregateReactions(
  rows: { emoji: string; userID: string }[],
  me: string
): { emoji: string; count: number; includesMe: boolean }[] {
  const map = new Map<string, { count: number; includesMe: boolean }>();
  for (const r of rows) {
    const cur = map.get(r.emoji) ?? { count: 0, includesMe: false };
    cur.count += 1;
    if (r.userID === me) cur.includesMe = true;
    map.set(r.emoji, cur);
  }
  return [...map.entries()]
    .map(([emoji, v]) => ({ emoji, count: v.count, includesMe: v.includesMe }))
    .sort((a, b) => b.count - a.count || a.emoji.localeCompare(b.emoji));
}

export default async function messageRoutes(fastify) {
  // Telegram-style typing indicator: in-memory, self-expiring, no DB writes.
  // Key `${typistId}:${peerId}` -> last ping (ms since epoch).
  const TYPING_TTL_MS = 6000;
  const typingMap = new Map<string, number>();
  const pruneTyping = () => {
    if (typingMap.size < 1000) return;
    const cutoff = Date.now() - TYPING_TTL_MS;
    for (const [k, t] of typingMap) { if (t < cutoff) typingMap.delete(k); }
  };

  // GET /messages/unread — inbox summary for chat list (Telegram-style sort)
  // Returns last message + unread count per friend (including read threads).
  fastify.get('/messages/unread', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const me = request.user.id;

    // Latest activity across all DMs involving me (read + unread)
    const recent = await prisma.directMessage.findMany({
      where: {
        OR: [{ senderID: me }, { receiverID: me }],
      },
      orderBy: { createdAt: 'desc' },
      take: 800,
      select: {
        senderID: true,
        receiverID: true,
        content: true,
        createdAt: true,
        isRead: true,
        mediaType: true,
        mediaData: true,
      },
    });

    type Row = {
      friendId: string;
      unreadCount: number;
      lastPreview: string;
      lastAt: Date;
    };
    const byFriend = new Map<string, Row>();

    for (const m of recent) {
      const friendId = m.senderID === me ? m.receiverID : m.senderID;
      if (!friendId || friendId === me) continue;

      const existing = byFriend.get(friendId);
      if (!existing) {
        const rawPreview = String(m.content || '');
        const voiceish = m.mediaType === 'voice' || rawPreview.includes('[[vn:') || rawPreview.includes('🎤');
        const photoish = m.mediaType === 'photo';
        byFriend.set(friendId, {
          friendId,
          unreadCount: 0,
          lastPreview: voiceish
            ? '🎤 Голосовое сообщение'
            : photoish
              ? (rawPreview.trim() ? `📷 ${rawPreview.slice(0, 76)}` : '📷 Фото')
              : rawPreview.slice(0, 80),
          lastAt: m.createdAt,
        });
      }
      // Unread only for inbound
      if (m.receiverID === me && m.isRead === false) {
        const row = byFriend.get(friendId)!;
        row.unreadCount += 1;
      }
    }

    // Sort by last activity desc so clients can apply pin overlay easily
    const list = [...byFriend.values()].sort(
      (a, b) => new Date(b.lastAt).getTime() - new Date(a.lastAt).getTime()
    );
    reply.send(list);
  });

  // GET /messages/dm/:friendId — history; opening chat marks inbound as read
  fastify.get('/messages/dm/:friendId', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { friendId } = request.params;
    const me = request.user.id;

    // Mark everything from this friend as read (user opened the chat)
    await prisma.directMessage.updateMany({
      where: {
        senderID: friendId,
        receiverID: me,
        isRead: false,
      },
      data: { isRead: true },
    });

    // IMPORTANT: take NEWEST messages, not oldest.
    // `orderBy asc + take 100` returned the first 100 ever → inbox preview
    // showed a new message that disappeared after open (not in the oldest 100).
    let messages: any[];
    try {
      messages = await prisma.directMessage.findMany({
        where: {
          OR: [
            { senderID: me, receiverID: friendId },
            { senderID: friendId, receiverID: me },
          ],
          // Telegram: hide messages this user deleted for themselves
          NOT: { deletedForIDs: { has: me } },
        },
        orderBy: { createdAt: 'desc' },
        take: 200,
        include: {
          reactions: {
            select: { emoji: true, userID: true },
          },
          replyTo: {
            select: { id: true, content: true, senderID: true, mediaType: true },
          },
        },
      });
      messages = messages.reverse(); // chronological for the client
    } catch {
      // Table may not exist yet mid-migrate / reactions missing
      messages = await prisma.directMessage.findMany({
        where: {
          OR: [
            { senderID: me, receiverID: friendId },
            { senderID: friendId, receiverID: me },
          ],
        },
        orderBy: { createdAt: 'desc' },
        take: 200,
      });
      messages = messages.reverse();
    }

    const payload = messages.map((m: any) => ({
      id: m.id,
      senderID: m.senderID,
      receiverID: m.receiverID,
      content: m.content,
      isRead: m.isRead,
      createdAt: m.createdAt,
      mediaType: m.mediaType ?? null,
      mediaDurationSec: m.mediaDurationSec ?? null,
      // Never include mediaData in list — clients fetch via /messages/voice/:id
      hasMedia: Boolean(m.mediaType && m.mediaData),
      reactions: aggregateReactions(m.reactions ?? [], me),
      editedAt: m.editedAt ?? null,
      // Telegram-style reply/forward metadata
      replyTo: m.replyTo
        ? {
            id: m.replyTo.id,
            content: m.replyTo.content,
            senderID: m.replyTo.senderID,
            mediaType: m.replyTo.mediaType ?? null,
          }
        : null,
      forwardedFromID: m.forwardedFromID ?? null,
      forwardedFromName: m.forwardedFromName ?? null,
    }));
    reply.send(payload);
  });

  // POST /messages/dm/:friendId/read — explicit mark-read (e.g. chat stayed open)
  fastify.post('/messages/dm/:friendId/read', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { friendId } = request.params;
    const me = request.user.id;
    const result = await prisma.directMessage.updateMany({
      where: {
        senderID: friendId,
        receiverID: me,
        isRead: false,
      },
      data: { isRead: true },
    });
    reply.send({ success: true, marked: result.count });
  });

  // DELETE /messages/dm/:friendId — Telegram-style «delete chat»
  // Clears the entire DM thread between me and friendId (both directions).
  fastify.delete(
    '/messages/dm/:friendId',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request: any, reply: any) => {
      const { friendId } = request.params as { friendId: string };
      const me = request.user.id;
      if (!friendId || friendId === me) {
        return reply.status(400).send({ error: 'Invalid friendId' });
      }

      // Reactions cascade via FK on message delete when configured; otherwise clean manually.
      const thread = await prisma.directMessage.findMany({
        where: {
          OR: [
            { senderID: me, receiverID: friendId },
            { senderID: friendId, receiverID: me },
          ],
        },
        select: { id: true },
        take: 5000,
      });
      const ids = thread.map((m: { id: string }) => m.id);
      if (ids.length > 0) {
        try {
          await prisma.directMessageReaction.deleteMany({
            where: { messageID: { in: ids } },
          });
        } catch {
          /* reactions table may be missing mid-migrate */
        }
      }
      const result = await prisma.directMessage.deleteMany({
        where: {
          OR: [
            { senderID: me, receiverID: friendId },
            { senderID: friendId, receiverID: me },
          ],
        },
      });
      reply.send({ success: true, deleted: result.count });
    }
  );

  fastify.post('/messages/dm', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { receiverId, content, replyToId } = request.body;
    // 280: room invites + short chat (was 150 — invites didn't fit)
    if (!content || typeof content !== 'string' || content.length > 280) {
      return reply.status(400).send({ error: 'Invalid message (max 280 chars)' });
    }

    // M16: ИИ-модератор в личке — активный мут и фильтр матов
    {
      const dmMutedSec = muteRemainingSec('dm', request.user.id);
      if (dmMutedSec > 0) {
        return reply.status(403).send({
          error: `Вы замучены модератором ещё на ${dmMutedSec} сек`,
          code: 'MODERATION_MUTED',
          mutedForSec: dmMutedSec,
        });
      }
      if (containsProfanity(content)) {
        const seconds = muteUser('dm', request.user.id, 'profanity');
        void auditModeration({
          roomId: `dm:${receiverId}`,
          messageId: `dm-${Date.now()}`,
          subjectUserId: request.user.id,
          action: 'mute_profanity',
          reasonCode: 'profanity',
        });
        return reply.status(403).send({
          error: `Мут на ${seconds} сек за нецензурную лексику`,
          code: 'MODERATION_MUTED',
          mutedForSec: seconds,
        });
      }
    }
    if (!receiverId || typeof receiverId !== 'string') {
      return reply.status(400).send({ error: 'receiverId required' });
    }

    // Telegram: cannot message a deleted account
    try {
      const peer = await prisma.user.findUnique({
        where: { id: receiverId },
        select: { id: true, username: true, deletedAt: true } as any,
      });
      if (!peer) {
        return reply.status(404).send({ error: 'User not found', code: 'USER_NOT_FOUND' });
      }
      const { isDeletedUser } = await import('../services/accountTombstone.js');
      if (isDeletedUser(peer as any)) {
        return reply.status(403).send({
          error: 'This account has been deleted',
          code: 'ACCOUNT_DELETED',
        });
      }
      // Also block if either side blocked the other
      const blocked = await prisma.userBlock.findFirst({
        where: {
          OR: [
            { blockerID: request.user.id, blockedID: receiverId },
            { blockerID: receiverId, blockedID: request.user.id },
          ],
        },
        select: { id: true },
      });
      if (blocked) {
        return reply.status(403).send({ error: 'Messaging not allowed', code: 'BLOCKED' });
      }
    } catch (e: any) {
      console.warn('[dm] peer check:', e?.message);
    }

    // Telegram-style reply: quoted message must belong to this thread
    let replyTo: any = null;
    if (replyToId && typeof replyToId === 'string') {
      replyTo = await prisma.directMessage.findFirst({
        where: {
          id: replyToId,
          OR: [
            { senderID: request.user.id, receiverID: receiverId },
            { senderID: receiverId, receiverID: request.user.id },
          ],
        },
        select: { id: true, content: true, senderID: true, mediaType: true },
      });
      if (!replyTo) {
        return reply.status(400).send({ error: 'Reply target not in this chat', code: 'BAD_REPLY' });
      }
    }

    const msg = await prisma.directMessage.create({
      data: {
        senderID: request.user.id,
        receiverID: receiverId,
        content,
        isRead: false,
        ...(replyTo ? { replyToID: replyTo.id } : {}),
      },
    });

    // Instant fanout over the user '@me' channel (polling stays as fallback)
    try {
      (fastify as any).gateway?.notifyUser(receiverId, {
        type: 'dm.event',
        event: 'message',
        fromUserId: request.user.id,
        messageId: msg.id,
      });
    } catch { /* noop */ }
    // APNs push (no-op when not configured). Styled-bubble envelopes start
    // with '{' — don't leak raw JSON into the notification.
    void pushToUser(receiverId, {
      title: request.user.username || 'Plink',
      body: content.startsWith('{') ? 'Новое сообщение' : content.slice(0, 120),
      threadId: `dm-${request.user.id}`,
      data: { kind: 'dm', fromUserId: request.user.id },
    });

    reply.send({
      ...msg,
      mediaType: null,
      mediaDurationSec: null,
      hasMedia: false,
      reactions: [],
      replyTo,
      forwardedFromID: null,
      forwardedFromName: null,
    });
  });

  // POST /messages/dm/voice — real voice note (base64 audio + duration)
  // Free for friend DMs. Body:
  //   { receiverId, audioData: "data:audio/mp4;base64,...", durationSec, content? }
  fastify.post(
    '/messages/dm/voice',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
      bodyLimit: 2 * 1024 * 1024,
    },
    async (request: any, reply: any) => {
      const me = request.user.id;
      const body = (request.body ?? {}) as {
        receiverId?: string;
        audioData?: string;
        durationSec?: number;
        content?: string;
      };

      const receiverId = typeof body.receiverId === 'string' ? body.receiverId.trim() : '';
      if (!receiverId || receiverId === me) {
        return reply.status(400).send({ error: 'Invalid receiverId' });
      }
      try {
        const peer = await prisma.user.findUnique({
          where: { id: receiverId },
          select: { id: true, username: true, deletedAt: true } as any,
        });
        if (!peer) return reply.status(404).send({ error: 'User not found' });
        const { isDeletedUser } = await import('../services/accountTombstone.js');
        if (isDeletedUser(peer as any)) {
          return reply.status(403).send({
            error: 'This account has been deleted',
            code: 'ACCOUNT_DELETED',
          });
        }
      } catch {
        /* schema drift — allow path below */
      }

      const audioData = typeof body.audioData === 'string' ? body.audioData : '';
      // Accept data URL or raw base64; normalize to data:audio/mp4;base64,...
      let dataUrl = audioData;
      if (!dataUrl.startsWith('data:audio/')) {
        if (/^[A-Za-z0-9+/=\s]+$/.test(dataUrl) && dataUrl.replace(/\s/g, '').length > 64) {
          dataUrl = `data:audio/mp4;base64,${dataUrl.replace(/\s/g, '')}`;
        } else {
          return reply.status(400).send({
            error: 'Invalid audio. Expected data:audio/...;base64,...',
          });
        }
      }

      const mimeMatch = dataUrl.match(
        /^data:(audio\/(mp4|m4a|aac|mpeg|mp3|wav|x-m4a|caf));base64,(.+)$/i
      );
      if (!mimeMatch) {
        return reply.status(400).send({
          error: 'Unsupported audio type. Use m4a/mp4/aac/mp3/wav.',
        });
      }

      const b64 = mimeMatch[3];
      let buffer: Buffer;
      try {
        buffer = Buffer.from(b64, 'base64');
      } catch {
        return reply.status(400).send({ error: 'Invalid base64 audio' });
      }
      if (buffer.length < 200) {
        return reply.status(400).send({ error: 'Audio too short' });
      }
      if (buffer.length > 1.5 * 1024 * 1024) {
        return reply.status(413).send({ error: 'Audio too large (max 1.5MB)' });
      }

      let durationSec = Number(body.durationSec);
      if (!Number.isFinite(durationSec) || durationSec <= 0) durationSec = 1;
      durationSec = Math.min(60, Math.max(0.5, durationSec));

      const mins = Math.floor(durationSec / 60);
      const secs = Math.floor(durationSec % 60);
      const preview =
        typeof body.content === 'string' && body.content.trim().length > 0
          ? String(body.content).slice(0, 200)
          : `[[vn:${durationSec.toFixed(1)}]]🎤 ${mins}:${String(secs).padStart(2, '0')}`;

      try {
        const msg = await prisma.directMessage.create({
          data: {
            senderID: me,
            receiverID: receiverId,
            content: preview,
            isRead: false,
            mediaType: 'voice',
            mediaData: dataUrl,
            mediaDurationSec: durationSec,
          },
        });
        return reply.send({
          id: msg.id,
          senderID: msg.senderID,
          receiverID: msg.receiverID,
          content: msg.content,
          isRead: msg.isRead,
          createdAt: msg.createdAt,
          mediaType: 'voice',
          mediaDurationSec: durationSec,
          hasMedia: true,
          reactions: [],
        });
      } catch (e: any) {
        // Schema may lag mid-deploy — surface clear error
        console.error('[dm-voice]', e?.message || e);
        return reply.status(503).send({
          error: 'Voice notes unavailable',
          code: 'VOICE_UNAVAILABLE',
          detail: e?.message,
        });
      }
    }
  );

  // GET /messages/voice/:messageId — stream voice note audio (participants only)
  fastify.get(
    '/messages/voice/:messageId',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const me = request.user.id;
      const { messageId } = request.params as { messageId: string };

      let msg: any;
      try {
        msg = await prisma.directMessage.findUnique({
          where: { id: messageId },
          select: {
            id: true,
            senderID: true,
            receiverID: true,
            mediaType: true,
            mediaData: true,
          },
        });
      } catch (e: any) {
        console.warn('[dm-voice-get]', e?.message);
        return reply.status(503).send({ error: 'Voice notes unavailable' });
      }

      if (!msg) return reply.status(404).send({ error: 'Not found' });
      if (msg.senderID !== me && msg.receiverID !== me) {
        return reply.status(403).send({ error: 'Forbidden' });
      }
      if (msg.mediaType !== 'voice' || !msg.mediaData) {
        return reply.status(404).send({ error: 'No voice attachment' });
      }

      const match = String(msg.mediaData).match(
        /^data:(audio\/[a-z0-9.+-]+);base64,(.+)$/i
      );
      if (!match) {
        return reply.status(500).send({ error: 'Corrupt voice data' });
      }
      const mime = match[1].toLowerCase() === 'audio/m4a' ? 'audio/mp4' : match[1];
      const buffer = Buffer.from(match[2], 'base64');
      reply
        .header('Cache-Control', 'private, max-age=3600')
        .header('Content-Length', String(buffer.length))
        .type(mime)
        .send(buffer);
    }
  );

  // POST /messages/dm/photo — photo message (base64 image + optional caption)
  fastify.post(
    '/messages/dm/photo',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 20, timeWindow: '1 minute' } },
      bodyLimit: 3 * 1024 * 1024,
    },
    async (request: any, reply: any) => {
      const me = request.user.id;
      const body = (request.body ?? {}) as {
        receiverId?: string;
        imageData?: string;
        content?: string;
      };
      const receiverId = typeof body.receiverId === 'string' ? body.receiverId.trim() : '';
      if (!receiverId || receiverId === me) {
        return reply.status(400).send({ error: 'Invalid receiverId' });
      }

      try {
        const peer = await prisma.user.findUnique({
          where: { id: receiverId },
          select: { id: true, username: true, deletedAt: true } as any,
        });
        if (!peer) return reply.status(404).send({ error: 'User not found' });
        const { isDeletedUser } = await import('../services/accountTombstone.js');
        if (isDeletedUser(peer as any)) {
          return reply.status(403).send({ error: 'This account has been deleted', code: 'ACCOUNT_DELETED' });
        }
        const blocked = await prisma.userBlock.findFirst({
          where: {
            OR: [
              { blockerID: me, blockedID: receiverId },
              { blockerID: receiverId, blockedID: me },
            ],
          },
          select: { id: true },
        });
        if (blocked) return reply.status(403).send({ error: 'Messaging not allowed', code: 'BLOCKED' });
      } catch (e: any) {
        console.warn('[dm-photo] peer check:', e?.message);
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

      // M16: ИИ-модератор — мут и NSFW-проверка фото в личке
      const dmMutedSec = muteRemainingSec('dm', me);
      if (dmMutedSec > 0) {
        return reply.status(403).send({
          error: `Вы замучены модератором ещё на ${dmMutedSec} сек`,
          code: 'MODERATION_MUTED',
          mutedForSec: dmMutedSec,
        });
      }
      const imageCheck = await moderateImage(parsed.dataUrl);
      if (imageCheck.nsfw) {
        const seconds = muteUser('dm', me, 'nsfw_image', 600);
        void auditModeration({
          roomId: `dm:${receiverId}`,
          messageId: `dmp-${Date.now()}`,
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
      if (typeof body.content === 'string' && containsProfanity(body.content)) {
        const seconds = muteUser('dm', me, 'profanity');
        return reply.status(403).send({
          error: `Мут на ${seconds} сек за нецензурную лексику`,
          code: 'MODERATION_MUTED',
          mutedForSec: seconds,
        });
      }

      const caption = typeof body.content === 'string' ? body.content.trim().slice(0, 280) : '';
      const msg = await prisma.directMessage.create({
        data: {
          senderID: me,
          receiverID: receiverId,
          content: caption,
          isRead: false,
          mediaType: 'photo',
          mediaData: parsed.dataUrl,
        },
      });
      return reply.send({
        id: msg.id,
        senderID: msg.senderID,
        receiverID: msg.receiverID,
        content: msg.content,
        isRead: msg.isRead,
        createdAt: msg.createdAt,
        mediaType: 'photo',
        mediaDurationSec: null,
        hasMedia: true,
        reactions: [],
      });
    }
  );

  // GET /messages/photo/:messageId — stream photo attachment (participants only)
  fastify.get(
    '/messages/photo/:messageId',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const me = request.user.id;
      const { messageId } = request.params as { messageId: string };
      const msg = await prisma.directMessage.findUnique({
        where: { id: messageId },
        select: { id: true, senderID: true, receiverID: true, mediaType: true, mediaData: true },
      });
      if (!msg) return reply.status(404).send({ error: 'Not found' });
      if (msg.senderID !== me && msg.receiverID !== me) {
        return reply.status(403).send({ error: 'Forbidden' });
      }
      if (msg.mediaType !== 'photo' || !msg.mediaData) {
        return reply.status(404).send({ error: 'No photo attachment' });
      }
      const parsed = parseImageDataURL(String(msg.mediaData));
      if (!parsed) return reply.status(500).send({ error: 'Corrupt photo data' });
      reply
        .header('Cache-Control', 'private, max-age=3600')
        .header('Content-Length', String(parsed.buffer.length))
        .type(parsed.mime)
        .send(parsed.buffer);
    }
  );

  // POST /messages/dm/:messageId/react — toggle Telegram-style reaction
  // Body: { emoji: "❤️" }  — same emoji again removes; different replaces.
  fastify.post(
    '/messages/dm/:messageId/react',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
    },
    async (request: any, reply: any) => {
      const me = request.user.id;
      const { messageId } = request.params as { messageId: string };
      const { emoji } = (request.body ?? {}) as { emoji?: string };

      if (!emoji || typeof emoji !== 'string' || emoji.length > 16) {
        return reply.status(400).send({ error: 'emoji required' });
      }
      if (!FREE_REACT_EMOJIS.has(emoji)) {
        return reply.status(400).send({ error: 'Emoji not allowed', code: 'EMOJI_NOT_ALLOWED' });
      }

      const msg = await prisma.directMessage.findUnique({ where: { id: messageId } });
      if (!msg) return reply.status(404).send({ error: 'Message not found' });
      if (msg.senderID !== me && msg.receiverID !== me) {
        return reply.status(403).send({ error: 'Not a participant' });
      }

      try {
        const existing = await prisma.directMessageReaction.findUnique({
          where: { messageID_userID: { messageID: messageId, userID: me } },
        });

        if (existing && existing.emoji === emoji) {
          // Toggle off
          await prisma.directMessageReaction.delete({ where: { id: existing.id } });
        } else if (existing) {
          await prisma.directMessageReaction.update({
            where: { id: existing.id },
            data: { emoji },
          });
        } else {
          await prisma.directMessageReaction.create({
            data: { messageID: messageId, userID: me, emoji },
          });
        }

        const all = await prisma.directMessageReaction.findMany({
          where: { messageID: messageId },
          select: { emoji: true, userID: true },
        });
        return reply.send({
          success: true,
          messageId,
          reactions: aggregateReactions(all, me),
        });
      } catch (e: any) {
        console.warn('[dm-react]', e?.message);
        return reply.status(503).send({ error: 'Reactions unavailable', code: 'REACTIONS_UNAVAILABLE' });
      }
    }
  );

  // GET /messages/invites — pending room invites embedded in unread DMs
  // Format: "... plink-invite:CODE|ROOMID|RoomName"
  fastify.get('/messages/invites', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const me = request.user.id;
    const unread = await prisma.directMessage.findMany({
      where: {
        receiverID: me,
        isRead: false,
        content: { contains: 'plink-invite:' },
      },
      orderBy: { createdAt: 'desc' },
      take: 30,
      include: {
        sender: { select: { id: true, username: true, avatarURL: true, displayName: true } },
      },
    });

    // Use Array<T> constructor — never leave invites as never[] under strict tsc
    const invites = new Array<RoomInviteDTO>();
    for (const m of unread as any[]) {
      const content = String(m?.content ?? '');
      const marker = 'plink-invite:';
      const idx = content.indexOf(marker);
      if (idx < 0) continue;
      const payload = content.slice(idx + marker.length).trim();
      const parts = payload.split('|');
      const code = (parts[0] || '').trim().toUpperCase();
      const roomId = (parts[1] || '').trim();
      const roomName = (parts[2] || 'Комната').trim() || 'Комната';
      if (!code || code.length < 4) continue;
      const fromUsername =
        (m?.sender?.displayName as string | undefined) ||
        (m?.sender?.username as string | undefined) ||
        'Друг';
      const fromAvatarURL =
        m?.sender?.avatarURL != null ? String(m.sender.avatarURL) : null;
      invites.push({
        id: String(m.id),
        messageId: String(m.id),
        roomID: roomId || code,
        roomCode: code,
        roomName,
        fromUserID: String(m.senderID),
        fromUsername,
        fromAvatarURL,
        mediaTitle: null,
        timestamp: m.createdAt as Date,
        preview: content.slice(0, 120),
      });
    }
    return reply.send(invites);
  });

  // ── Telegram-style DM pins ───────────────────────────────────────────
  // POST /messages/dm/:friendId/pin { messageId, forBoth }
  // «Закрепить у себя» → one row (owner = me);
  // «Закрепить у обоих» → a row for each participant (like Telegram).
  fastify.post(
    '/messages/dm/:friendId/pin',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
    },
    async (request: any, reply: any) => {
      const { friendId } = request.params as { friendId: string };
      const me = request.user.id;
      const { messageId, forBoth } = (request.body ?? {}) as {
        messageId?: string;
        forBoth?: boolean;
      };
      if (!messageId || typeof messageId !== 'string') {
        return reply.status(400).send({ error: 'messageId required' });
      }
      // The message must belong to this thread
      const msg = await prisma.directMessage.findFirst({
        where: {
          id: messageId,
          OR: [
            { senderID: me, receiverID: friendId },
            { senderID: friendId, receiverID: me },
          ],
        },
        select: { id: true },
      });
      if (!msg) return reply.status(404).send({ error: 'Message not found in this chat' });

      const rows = [{ ownerID: me, peerID: friendId, messageID: messageId, pinnedByID: me }];
      if (forBoth === true) {
        rows.push({ ownerID: friendId, peerID: me, messageID: messageId, pinnedByID: me });
      }
      await prisma.directMessagePin.createMany({ data: rows, skipDuplicates: true });
      reply.send({ success: true, forBoth: forBoth === true });
    }
  );

  // DELETE /messages/dm/:friendId/pin/:messageId?forBoth=true — unpin
  fastify.delete(
    '/messages/dm/:friendId/pin/:messageId',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const { friendId, messageId } = request.params as { friendId: string; messageId: string };
      const me = request.user.id;
      const forBoth = String((request.query as any)?.forBoth ?? '') === 'true';
      const where = forBoth
        ? {
            messageID: messageId,
            OR: [
              { ownerID: me, peerID: friendId },
              { ownerID: friendId, peerID: me },
            ],
          }
        : { ownerID: me, peerID: friendId, messageID: messageId };
      const result = await prisma.directMessagePin.deleteMany({ where });
      reply.send({ success: true, removed: result.count });
    }
  );

  // GET /messages/dm/:friendId/pins — my pinned messages in this chat
  fastify.get(
    '/messages/dm/:friendId/pins',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const { friendId } = request.params as { friendId: string };
      const me = request.user.id;
      let pins: any[] = [];
      try {
        pins = await prisma.directMessagePin.findMany({
          where: { ownerID: me, peerID: friendId },
          include: {
            message: {
              select: { id: true, content: true, senderID: true, mediaType: true, createdAt: true },
            },
          },
          orderBy: { createdAt: 'asc' },
        });
      } catch {
        pins = []; // table may not exist yet mid-migrate
      }
      reply.send(
        pins.map((p: any) => ({
          messageId: p.messageID,
          pinnedByID: p.pinnedByID,
          pinnedAt: p.createdAt,
          content: p.message?.content ?? '',
          senderID: p.message?.senderID ?? '',
          mediaType: p.message?.mediaType ?? null,
          messageCreatedAt: p.message?.createdAt ?? null,
        }))
      );
    }
  );

  // ── Telegram-style forward ──────────────────────────────────────────────
  // POST /messages/dm/forward { toUserId, messageIds } — copies my chat
  // messages to another friend with «Переслано от …» attribution.
  fastify.post(
    '/messages/dm/forward',
    {
      preHandler: [fastify.authenticate],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request: any, reply: any) => {
      const me = request.user.id;
      const { toUserId, messageIds } = (request.body ?? {}) as {
        toUserId?: string;
        messageIds?: string[];
      };
      if (!toUserId || typeof toUserId !== 'string' || toUserId === me) {
        return reply.status(400).send({ error: 'toUserId required' });
      }
      if (!Array.isArray(messageIds) || messageIds.length === 0 || messageIds.length > 30) {
        return reply.status(400).send({ error: 'messageIds: 1–30 required' });
      }

      // Same recipient guards as POST /messages/dm
      const peer = await prisma.user.findUnique({
        where: { id: toUserId },
        select: { id: true, username: true, deletedAt: true } as any,
      });
      if (!peer) {
        return reply.status(404).send({ error: 'User not found', code: 'USER_NOT_FOUND' });
      }
      try {
        const { isDeletedUser } = await import('../services/accountTombstone.js');
        if (isDeletedUser(peer as any)) {
          return reply
            .status(403)
            .send({ error: 'This account has been deleted', code: 'ACCOUNT_DELETED' });
        }
      } catch {
        /* tombstone helper optional */
      }
      const blocked = await prisma.userBlock.findFirst({
        where: {
          OR: [
            { blockerID: me, blockedID: toUserId },
            { blockerID: toUserId, blockedID: me },
          ],
        },
        select: { id: true },
      });
      if (blocked) {
        return reply.status(403).send({ error: 'Messaging not allowed', code: 'BLOCKED' });
      }

      // Source messages must come from my own chats
      const sources = await prisma.directMessage.findMany({
        where: {
          id: { in: messageIds },
          OR: [{ senderID: me }, { receiverID: me }],
        },
        orderBy: { createdAt: 'asc' },
      });
      if (sources.length === 0) {
        return reply.status(404).send({ error: 'Nothing to forward' });
      }

      const senderIds = [...new Set(sources.map((s: any) => s.senderID))];
      const senders = await prisma.user.findMany({
        where: { id: { in: senderIds } },
        select: { id: true, username: true, displayName: true } as any,
      });
      const nameById = new Map(
        senders.map((u: any) => [u.id, (u.displayName || u.username || 'Unknown') as string])
      );

      const created: any[] = [];
      for (const src of sources as any[]) {
        const msg = await prisma.directMessage.create({
          data: {
            senderID: me,
            receiverID: toUserId,
            content: src.content,
            isRead: false,
            mediaType: src.mediaType ?? null,
            mediaData: src.mediaData ?? null,
            mediaDurationSec: src.mediaDurationSec ?? null,
            forwardedFromID: src.senderID,
            forwardedFromName: nameById.get(src.senderID) ?? 'Unknown',
          },
        });
        created.push({
          id: msg.id,
          createdAt: msg.createdAt,
          forwardedFromName: (msg as any).forwardedFromName,
        });
      }
      reply.send({ success: true, forwarded: created.length, messages: created });
    }
  );

  // ── PATCH /messages/dm/message/:messageId — Telegram-style edit ──
  fastify.patch(
    '/messages/dm/message/:messageId',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const me = request.user.id;
      const { messageId } = request.params;
      const { content } = (request.body ?? {}) as any;
      if (!content || typeof content !== 'string' || content.length > 4000) {
        return reply.status(400).send({ error: 'Valid content required' });
      }
      const msg = await prisma.directMessage.findUnique({ where: { id: messageId } });
      if (!msg) return reply.status(404).send({ error: 'Message not found' });
      if (msg.senderID !== me) {
        return reply.status(403).send({ error: 'Can only edit own messages' });
      }
      if (msg.mediaType) {
        return reply.status(400).send({ error: 'Media messages cannot be edited' });
      }
      // Telegram allows editing within 48 hours
      const ageMs = Date.now() - new Date(msg.createdAt).getTime();
      if (ageMs > 48 * 60 * 60 * 1000) {
        return reply.status(400).send({ error: 'Edit window expired', code: 'EDIT_EXPIRED' });
      }
      const updated = await prisma.directMessage.update({
        where: { id: messageId },
        data: { content, editedAt: new Date() },
      });
      try {
        (fastify as any).gateway?.notifyUser(msg.receiverID, {
          type: 'dm.event',
          event: 'edited',
          fromUserId: me,
          messageId,
        });
      } catch { /* noop */ }
      reply.send({ success: true, id: updated.id, editedAt: (updated as any).editedAt });
    }
  );

  // ── DELETE /messages/dm/message/:messageId?forBoth= — Telegram delete ──
  fastify.delete(
    '/messages/dm/message/:messageId',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const me = request.user.id;
      const { messageId } = request.params;
      const forBoth = String((request.query as any)?.forBoth ?? '') === 'true';
      const msg = await prisma.directMessage.findUnique({ where: { id: messageId } });
      if (!msg) return reply.send({ success: true, removed: 0 });
      if (msg.senderID !== me && msg.receiverID !== me) {
        return reply.status(403).send({ error: 'Not your message' });
      }
      if (forBoth) {
        // «Удалить у обоих» — only the author
        if (msg.senderID !== me) {
          return reply.status(403).send({ error: 'Only the sender can delete for both' });
        }
        await prisma.directMessage.delete({ where: { id: messageId } }); // pins cascade
        try {
          const peerId = msg.senderID === me ? msg.receiverID : msg.senderID;
          (fastify as any).gateway?.notifyUser(peerId, {
            type: 'dm.event', event: 'deleted', fromUserId: me, messageId,
          });
          (fastify as any).gateway?.notifyUser(me, {
            type: 'dm.event', event: 'deleted', fromUserId: peerId, messageId,
          });
        } catch { /* noop */ }
        return reply.send({ success: true, removed: 1, forBoth: true });
      }
      // «Удалить у себя» — hide for me only
      const ids = new Set<string>([...(((msg as any).deletedForIDs ?? []) as string[]), me]);
      await prisma.directMessage.update({
        where: { id: messageId },
        data: { deletedForIDs: [...ids] } as any,
      });
      try {
        const peerId = msg.senderID === me ? msg.receiverID : msg.senderID;
        (fastify as any).gateway?.notifyUser(me, {
          type: 'dm.event', event: 'deleted', fromUserId: peerId, messageId,
        });
      } catch { /* noop */ }
      reply.send({ success: true, removed: 1, forBoth: false });
    }
  );

  // ── Typing indicator (poll-friendly, in-memory) ──
  fastify.post(
    '/messages/dm/:friendId/typing',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      pruneTyping();
      typingMap.set(`${request.user.id}:${request.params.friendId}`, Date.now());
      try {
        (fastify as any).gateway?.notifyUser(request.params.friendId, {
          type: 'dm.event',
          event: 'typing',
          fromUserId: request.user.id,
        });
      } catch { /* noop */ }
      reply.send({ success: true });
    }
  );

  fastify.get(
    '/messages/dm/:friendId/typing',
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const last = typingMap.get(`${request.params.friendId}:${request.user.id}`) ?? 0;
      reply.send({ typing: Date.now() - last < TYPING_TTL_MS });
    }
  );
}
