import { prisma } from '../config/db.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { config } from '../config/index.js';
import { logAudit, AuditActions } from '../utils/audit.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function avatarPublicURL(userId: string, versionMs?: number): string {
  const base = `${config.PUBLIC_BASE_URL}/api/users/${userId}/avatar`;
  if (versionMs && Number.isFinite(versionMs) && versionMs > 0) {
    return `${base}?v=${Math.floor(versionMs)}`;
  }
  return base;
}

function parseAvatarDataURL(avatarData: string): { mime: string; buffer: Buffer } | null {
  const match = avatarData.match(/^data:(image\/(jpeg|jpg|png|webp));base64,(.+)$/);
  if (!match) return null;
  const mime = match[1];
  const buffer = Buffer.from(match[3], 'base64');
  return { mime, buffer };
}

export default async function profileRoutes(fastify) {
  // POST /users/me/avatar — upload avatar as base64 data URL, persist in DB.
  // B6: rate limited + MIME validation + size limit.
  fastify.post('/users/me/avatar', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 5, timeWindow: '1 minute' } }
  }, async (request, reply) => {
    const body = request.body as { avatar?: string; avatarData?: string };
    const avatarInput = body.avatar ?? body.avatarData;

    if (!avatarInput || typeof avatarInput !== 'string') {
      return reply.status(400).send({ error: 'Avatar data required' });
    }

    const mimeMatch = avatarInput.match(/^data:(image\/(jpeg|jpg|png|webp));base64,/);
    if (!mimeMatch) {
      return reply.status(400).send({
        error: 'Invalid avatar format. Expected data:image/(jpeg|png|webp);base64,...'
      });
    }

    const base64Data = avatarInput.replace(/^data:image\/\w+;base64,/, '');
    const buffer = Buffer.from(base64Data, 'base64');

    if (buffer.length > 2 * 1024 * 1024) {
      return reply.status(413).send({ error: 'Avatar too large. Max 2MB.' });
    }

    let isValidImage = false;
    if (buffer[0] === 0xFF && buffer[1] === 0xD8 && buffer[2] === 0xFF) {
      isValidImage = true;
    } else if (buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4E && buffer[3] === 0x47) {
      isValidImage = true;
    } else if (buffer[0] === 0x52 && buffer[1] === 0x49 && buffer[2] === 0x46 && buffer[3] === 0x46) {
      isValidImage = true;
    }
    if (!isValidImage) {
      return reply.status(400).send({ error: 'Invalid image data. Magic bytes do not match JPEG/PNG/WebP.' });
    }

    const avatarData = avatarInput;
    const now = new Date();
    const avatarURL = avatarPublicURL(request.user.id, now.getTime());

    await prisma.user.update({
      where: { id: request.user.id },
      data: {
        avatarData,
        avatarURL,
        avatarUpdatedAt: now,
      },
    });

    // Best-effort: push avatar change to online friends (legacy presence WS)
    try {
      const { presence } = await import('../services/presence.js');
      const me = request.user.id;
      const friendships = await prisma.friendship.findMany({
        where: { OR: [{ userID: me }, { friendID: me }] },
        select: { userID: true, friendID: true },
        take: 500,
      });
      const friendIds = new Set<string>();
      for (const f of friendships) {
        if (f.userID === me) friendIds.add(f.friendID);
        else friendIds.add(f.userID);
      }
      const payload = JSON.stringify({
        type: 'friend.avatar_updated',
        userId: me,
        avatarURL,
        avatarVersion: now.getTime(),
        at: now.toISOString(),
      });
      for (const fid of friendIds) {
        presence.sendToUser(fid, payload);
      }
    } catch (e: any) {
      console.warn('[avatar] friend notify failed:', e?.message || e);
    }

    reply.send({ avatarData, avatarURL, avatarVersion: now.getTime() });
  });

  // GET /users/:id/avatar — serve avatar image bytes from DB (no ephemeral disk).
  fastify.get('/users/:id/avatar', async (request, reply) => {
    const { id } = request.params;
    const user = await prisma.user.findUnique({
      where: { id },
      select: { avatarData: true, avatarURL: true, updatedAt: true }
    });
    if (!user) return reply.status(404).send({ error: 'User not found' });

    // No long HTTP cache — friends must see new avatars immediately.
    // Clients also append ?v=avatarUpdatedAt for URL-level bust.
    reply.header('Cache-Control', 'public, max-age=0, must-revalidate');
    if (user.updatedAt) {
      reply.header('Last-Modified', new Date(user.updatedAt).toUTCString());
      reply.header('ETag', `"${id}-${new Date(user.updatedAt).getTime()}"`);
    }

    if (user.avatarData) {
      const parsed = parseAvatarDataURL(user.avatarData);
      if (parsed) {
        return reply.type(parsed.mime).send(parsed.buffer);
      }
    }

    // Legacy: disk-based uploads from older builds
    if (user.avatarURL?.includes('/uploads/avatars/')) {
      const filename = path.basename(user.avatarURL);
      const filepath = path.join(__dirname, '..', '..', 'uploads', 'avatars', filename);
      if (fs.existsSync(filepath)) {
        return reply.type('image/jpeg').send(fs.createReadStream(filepath));
      }
    }

    return reply.status(404).send({ error: 'Avatar not found' });
  });

  // Serve uploaded files
  fastify.get('/uploads/*', async (request, reply) => {
    const filePath = path.join(__dirname, '..', '..', request.url);
    if (fs.existsSync(filePath)) {
      reply.type('image/jpeg').send(fs.createReadStream(filePath));
    } else {
      reply.status(404).send({ error: 'File not found' });
    }
  });
  fastify.get('/users/me', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const found = await prisma.user.findUnique({
      where: { id: request.user.id },
      select: {
        id: true,
        username: true,
        email: true,
        avatarURL: true,
        avatarData: true,
        displayName: true,
        coverURL: true,
        isPremium: true,
        premiumUntil: true,
        role: true,
        createdAt: true,
      },
    });
    if (!found) {
      return reply.status(404).send({ error: 'User not found' });
    }

    // Narrowed non-null — never pass possibly-null user into helpers
    let user: {
      id: string;
      username: string;
      email: string;
      avatarURL: string | null;
      avatarData: string | null;
      displayName: string | null;
      coverURL: string | null;
      isPremium: boolean;
      premiumUntil: Date | null;
      role: string;
      createdAt: Date;
    } = found as any;

    try {
      const { ensurePrivilegedRole } = await import('../utils/privilegedUsers.js');
      const privileged = await ensurePrivilegedRole(user as any);
      if (privileged && typeof privileged === 'object' && privileged.id) {
        user = { ...user, ...privileged };
      }
    } catch {
      /* optional promote */
    }

    // Presence heartbeat on profile poll
    try {
      const { presence } = await import('../services/presence.js');
      await presence.restHeartbeat(user.id, user.username);
    } catch {
      /* optional */
    }

    return reply.send(user);
  });

  // POST /users/me/presence — app foreground heartbeat (online + lastSeen)
  fastify.post('/users/me/presence', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    try {
      const { presence } = await import('../services/presence.js');
      const u = await prisma.user.findUnique({
        where: { id: request.user.id },
        select: { username: true },
      });
      await presence.restHeartbeat(request.user.id, u?.username);
      reply.send({ success: true, isOnline: true, lastSeenAt: new Date().toISOString() });
    } catch (e: any) {
      reply.status(500).send({ error: e?.message || 'presence failed' });
    }
  });

  // 🔧 Pack v3: PATCH /users/me — обновление username + avatarURL + displayName + coverURL
  // 🔧 v11 (July 2026): added displayName + coverURL (Telegram-style naming split).
  fastify.patch('/users/me', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { username, avatarURL, displayName, coverURL } = request.body;
    const data: any = {};
    if (username && username.trim().length >= 2) data.username = username.trim();
    if (avatarURL !== undefined) data.avatarURL = avatarURL;
    // 🔧 v11: displayName — optional Telegram-style display name (1-50 chars).
    // Empty string clears it (user wants to fall back to @username).
    if (displayName !== undefined) {
      const trimmed = String(displayName).trim();
      if (trimmed.length === 0) {
        data.displayName = null;  // clear → backend uses username as display
      } else if (trimmed.length <= 50) {
        data.displayName = trimmed;
      }
    }
    if (coverURL !== undefined) data.coverURL = coverURL;

    if (Object.keys(data).length === 0) {
      return reply.status(400).send({ error: 'No fields to update' });
    }

    // Проверка уникальности username + Telegram-style validation
    if (data.username) {
      // P0.5: same regex as signup — ^[A-Za-z][A-Za-z0-9_]{4,31}$
      const usernameRegex = /^[A-Za-z][A-Za-z0-9_]{4,31}$/;
      if (!usernameRegex.test(data.username)) {
        return reply.status(400).send({
          error: 'Username must be 5-32 characters, start with a letter, and contain only letters, numbers, and underscores'
        });
      }
      // Normalize to lowercase for case-insensitive uniqueness
      data.username = data.username.toLowerCase();
      const existing = await prisma.user.findFirst({
        where: {
          username: { equals: data.username, mode: 'insensitive' },
          NOT: { id: request.user.id }
        }
      });
      if (existing) return reply.status(409).send({ error: 'Username already taken' });
    }

    const updated = await prisma.user.update({
      where: { id: request.user.id },
      data,
      select: { id: true, username: true, email: true, avatarURL: true, avatarData: true,
                displayName: true, coverURL: true,
                isPremium: true, premiumUntil: true, role: true, createdAt: true }
    });
    reply.send(updated);
  });

  // DELETE /users/me — Telegram-style soft delete (tombstone, not hard cascade)
  fastify.delete('/users/me', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    try {
      const { tombstoneAccount } = await import('../services/accountTombstone.js');
      const result = await tombstoneAccount(request.user.id);
      reply.send({
        deleted: true,
        soft: true,
        alreadyDeleted: result.alreadyDeleted,
        message: 'Account deleted. Profile is now «Удалённый аккаунт».',
      });
    } catch (e: any) {
      const code = e?.statusCode || 500;
      reply.status(code).send({ error: 'Failed to delete account: ' + (e?.message || String(e)) });
    }
  });

  // ─────────────────────────────────────────────────────────────────────
  // V5 endpoints (Phase 4 of PLINK_MASTER_PLAN_10_OF_10.md)
  // ─────────────────────────────────────────────────────────────────────

  // GET /api/profile/appearance
  // Phase 4: returns the user's saved appearance selection (cross-device restore).
  // Values are stored as JSON on the User row in `appearancePrefs`.
  fastify.get('/profile/appearance', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const user = await prisma.user.findUnique({
      where: { id: request.user.id },
      select: { appearancePrefs: true }
    });

    // Defaults if user has never selected anything.
    const defaults = {
      appThemeID: 'electric-static',
      bubbleStyleID: 'bubble-quiet',
      emojiPackID: 'system-unicode'
    };

    if (!user?.appearancePrefs) {
      return reply.send(defaults);
    }
    try {
      const parsed = JSON.parse(user.appearancePrefs);
      reply.send({
        appThemeID: parsed.appThemeID ?? defaults.appThemeID,
        bubbleStyleID: parsed.bubbleStyleID ?? defaults.bubbleStyleID,
        emojiPackID: parsed.emojiPackID ?? defaults.emojiPackID
      });
    } catch {
      reply.send(defaults);
    }
  });

  // PUT /api/profile/appearance
  // Phase 4: persists the user's appearance selection for cross-device restore.
  fastify.put('/profile/appearance', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { appThemeID, bubbleStyleID, emojiPackID } = request.body;

    if (typeof appThemeID !== 'string' ||
        typeof bubbleStyleID !== 'string' ||
        typeof emojiPackID !== 'string') {
      return reply.status(400).send({ error: 'appThemeID, bubbleStyleID, emojiPackID required' });
    }

    const prefs = JSON.stringify({ appThemeID, bubbleStyleID, emojiPackID });

    await prisma.user.update({
      where: { id: request.user.id },
      data: { appearancePrefs: prefs }
    });

    await logAudit({
      userId: request.user.id,
      action: AuditActions.PROFILE_APPEARANCE_UPDATE,
      ip: request.ip,
      metadata: { appThemeID, bubbleStyleID, emojiPackID }
    });

    reply.status(204).send();
  });

  // POST /api/profile/delete
  // Phase 2.7: scheduled account deletion with grace period (14 days).
  // Marks the user as `scheduledForDeletionAt = now + 14d`; a cron job
  // (see services/gdpr.ts) performs the actual cascade delete after the
  // grace period expires. User can cancel by signing in before then.
  fastify.post('/profile/delete', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { confirmAccountId, reason } = request.body;

    if (confirmAccountId !== request.user.id) {
      return reply.status(400).send({
        error: 'Account ID confirmation does not match'
      });
    }

    const scheduledForDeletionAt = new Date();
    scheduledForDeletionAt.setDate(scheduledForDeletionAt.getDate() + 14);

    await prisma.user.update({
      where: { id: request.user.id },
      data: { scheduledForDeletionAt }
    });

    // Revoke all refresh tokens immediately — keeps access token valid until
    // expiry (max 24h) but blocks long-lived session extension.
    // (Import happens lazily to avoid circular import with tokens.js.)
    const { revokeAllUserTokens } = await import('../utils/tokens.js');
    await revokeAllUserTokens(request.user.id);

    await logAudit({
      userId: request.user.id,
      action: AuditActions.ACCOUNT_DELETION_REQUESTED,
      ip: request.ip,
      metadata: { reason: reason ?? 'user_initiated', scheduledForDeletionAt }
    });

    reply.send({
      scheduledForDeletionAt,
      message: 'Account scheduled for deletion in 14 days. Sign in before then to cancel.'
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // /users/me endpoints (existing)
  // ─────────────────────────────────────────────────────────────────────

  fastify.get('/users/:id', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { id } = request.params;
    const user = await prisma.user.findUnique({
      where: { id },
      select: { id: true, username: true, avatarURL: true, isOnline: true }
    });
    if (!user) return reply.status(404).send({ error: 'User not found' });
    reply.send(user);
  });

  // GET /api/users/:id/profile — public social profile + watch stats + badges
  fastify.get('/users/:id/profile', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { id } = request.params as { id: string };

    // Load with any — avoid Prisma select/type drift on optional columns (lastSeenAt)
    let raw: any = null;
    try {
      raw = await prisma.user.findUnique({
        where: { id },
        select: {
          id: true,
          username: true,
          displayName: true,
          avatarURL: true,
          coverURL: true,
          isOnline: true,
          lastSeenAt: true,
          isPremium: true,
          createdAt: true,
          updatedAt: true,
          deletedAt: true,
        } as any,
      });
    } catch {
      raw = await prisma.user.findUnique({
        where: { id },
        select: {
          id: true,
          username: true,
          displayName: true,
          avatarURL: true,
          coverURL: true,
          isOnline: true,
          isPremium: true,
          createdAt: true,
          updatedAt: true,
        },
      });
    }
    if (!raw || typeof raw.id !== 'string') {
      return reply.status(404).send({ error: 'User not found' });
    }

    // Telegram tombstone profile
    const { isDeletedUser } = await import('../services/accountTombstone.js');
    if (isDeletedUser(raw)) {
      return reply.send({
        id: String(raw.id),
        username: String(raw.username ?? 'deleted'),
        displayName: 'Удалённый аккаунт',
        avatarURL: null,
        coverURL: null,
        isOnline: false,
        lastSeenAt: null,
        isPremium: false,
        isDeleted: true,
        friendsCount: 0,
        roomsCreated: 0,
        filmsWatched: 0,
        watchTimeMinutes: 0,
        watchHistory: [],
        badges: [],
        joinedAt: raw.createdAt ?? null,
      });
    }

    const profileUser = {
      id: String(raw.id),
      username: String(raw.username ?? 'user'),
      displayName: (raw.displayName as string | null) ?? null,
      avatarURL: (raw.avatarURL as string | null) ?? null,
      coverURL: (raw.coverURL as string | null) ?? null,
      isOnline: Boolean(raw.isOnline),
      lastSeenAt: (raw.lastSeenAt as Date | null | undefined) ?? null,
      isPremium: Boolean(raw.isPremium),
      createdAt: raw.createdAt as Date,
      updatedAt: (raw.updatedAt as Date | null | undefined) ?? null,
    };

    // Explicit tuple types — never let Promise.all collapse into a giant union
    const friendsCount: number = await prisma.friendship.count({ where: { userID: id } });
    const roomsCreated: number = await prisma.room.count({ where: { hostID: id } });
    const watchHistory: Array<{
      id: string;
      mediaTitle: string | null;
      watchedAt: Date;
      roomID: string | null;
    }> = await prisma.watchHistory.findMany({
      where: { userID: id },
      orderBy: { watchedAt: 'desc' },
      take: 20,
      select: {
        id: true,
        mediaTitle: true,
        watchedAt: true,
        roomID: true,
      },
    });
    const totalHistory: number = await prisma.watchHistory.count({ where: { userID: id } });
    const watchTimeMinutes = totalHistory * 90;

    const badges: string[] = [];
    if (totalHistory >= 100) badges.push('cinemaniac');
    if (friendsCount >= 50) badges.push('social');
    if (roomsCreated >= 100) badges.push('host');
    if (roomsCreated >= 10) badges.push('host_rising');
    if (totalHistory >= 10) badges.push('regular');
    if (profileUser.isPremium) badges.push('plink_plus');

    let isOnline: boolean = profileUser.isOnline;
    let lastSeenAt: string | null = null;
    try {
      const { resolvePresence } = await import('../services/presence.js');
      const p = resolvePresence({
        id: profileUser.id,
        isOnline: profileUser.isOnline,
        lastSeenAt: profileUser.lastSeenAt ?? null,
        updatedAt: profileUser.updatedAt ?? profileUser.createdAt,
      });
      isOnline = Boolean(p.isOnline);
      lastSeenAt = p.lastSeenAt ?? null;
    } catch {
      /* optional */
    }

    return reply.send({
      id: profileUser.id,
      username: profileUser.username,
      displayName: profileUser.displayName ?? profileUser.username,
      avatarURL: profileUser.avatarURL,
      coverURL: profileUser.coverURL,
      isOnline,
      lastSeenAt,
      isPremium: profileUser.isPremium,
      isDeleted: false,
      friendsCount,
      roomsCreated,
      filmsWatched: totalHistory,
      watchTimeMinutes,
      watchHistory: watchHistory.map((h) => ({
        id: h.id,
        title: h.mediaTitle ?? 'Без названия',
        watchedAt: h.watchedAt,
        roomId: h.roomID,
      })),
      badges,
      joinedAt: profileUser.createdAt,
    });
  });

  // GET /api/users/me/profile — self profile (same shape)
  fastify.get('/users/me/profile', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const id = request.user.id;
    // Reuse logic by internal call shape
    const user = await prisma.user.findUnique({
      where: { id },
      select: {
        id: true,
        username: true,
        displayName: true,
        avatarURL: true,
        coverURL: true,
        isOnline: true,
        isPremium: true,
        createdAt: true,
      },
    });
    if (!user) return reply.status(404).send({ error: 'User not found' });

    const [friendsCount, roomsCreated, watchHistory, totalHistory] = await Promise.all([
      prisma.friendship.count({ where: { userID: id } }),
      prisma.room.count({ where: { hostID: id } }),
      prisma.watchHistory.findMany({
        where: { userID: id },
        orderBy: { watchedAt: 'desc' },
        take: 20,
        select: { id: true, mediaTitle: true, watchedAt: true, roomID: true },
      }),
      prisma.watchHistory.count({ where: { userID: id } }),
    ]);

    const badges: string[] = [];
    if (totalHistory >= 100) badges.push('cinemaniac');
    if (friendsCount >= 50) badges.push('social');
    if (roomsCreated >= 100) badges.push('host');
    if (roomsCreated >= 10) badges.push('host_rising');
    if (totalHistory >= 10) badges.push('regular');
    if (user.isPremium) badges.push('plink_plus');

    reply.send({
      id: user.id,
      username: user.username,
      displayName: user.displayName ?? user.username,
      avatarURL: user.avatarURL,
      coverURL: user.coverURL,
      isOnline: user.isOnline,
      isPremium: user.isPremium,
      friendsCount,
      roomsCreated,
      filmsWatched: totalHistory,
      watchTimeMinutes: totalHistory * 90,
      watchHistory: watchHistory.map((h: any) => ({
        id: h.id,
        title: h.mediaTitle ?? 'Без названия',
        watchedAt: h.watchedAt,
        roomId: h.roomID,
      })),
      badges,
      joinedAt: user.createdAt,
    });
  });

  fastify.post('/users/me/create-subscription', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { plan } = request.body;
    const expiresAt = new Date();
    expiresAt.setMonth(expiresAt.getMonth() + 1);

    await prisma.user.update({
      where: { id: request.user.id },
      data: { isPremium: true, premiumUntil: expiresAt }
    });
    await prisma.subscription.create({
      data: { userID: request.user.id, plan: plan || 'monthly', expiresAt }
    });
    reply.send({ success: true, expiresAt });
  });

  fastify.get('/users/me/history', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const history = await prisma.watchHistory.findMany({
      where: { userID: request.user.id },
      orderBy: { watchedAt: 'desc' },
      take: 50,
    });
    reply.send(history);
  });
}
