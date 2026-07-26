// src/routes/auth.ts — Pack 1.1: правильные rate limits
import bcrypt from 'bcryptjs';
import { prisma } from '../config/db.js';
import { issueTokenPair, verifyRefreshToken, revokeAllUserTokens } from '../utils/tokens.js';
import { logAudit, AuditActions } from '../utils/audit.js';
import { alertWarning } from '../utils/alerting.js';
import { ensurePrivilegedRole } from '../utils/privilegedUsers.js';

export default async function authRoutes(fastify) {

  // POST /api/auth/signup — 5 регистраций за 20 минут
  // 🔧 FIX: wrapped in try/catch — same 500-protection as signin.
  fastify.post('/auth/signup', {
    config: {
      rateLimit: { max: 5, timeWindow: '20 minutes' }
    }
  }, async (request, reply) => {
    try {
      const { email, password, username } = request.body;
      if (!email || !password || !username) {
        return reply.status(400).send({ error: 'Missing fields' });
      }
      if (password.length < 6) {
        return reply.status(400).send({ error: 'Password must be at least 6 characters' });
      }

      // P0.5: Telegram-style nickname validation
      // ^[A-Za-z][A-Za-z0-9_]{4,31}$ — start with letter, 5-32 chars, letters/digits/underscore
      const usernameRegex = /^[A-Za-z][A-Za-z0-9_]{4,31}$/;
      if (!usernameRegex.test(username)) {
        return reply.status(400).send({
          error: 'Username must be 5-32 characters, start with a letter, and contain only letters, numbers, and underscores'
        });
      }

      // Case-insensitive uniqueness check
      const normalizedUsername = username.toLowerCase();
      const existing = await prisma.user.findFirst({
        where: {
          OR: [
            { email },
            { username: { equals: username, mode: 'insensitive' } }
          ]
        }
      });
      if (existing) return reply.status(409).send({ error: 'Email or username taken' });

      const hashedPassword = await bcrypt.hash(password, 10);
      let user = await prisma.user.create({
        data: { email, username: normalizedUsername, password: hashedPassword, isOnline: true }
      });
      user = await ensurePrivilegedRole(user);

      const tokens = await issueTokenPair(fastify, user.id, user.username, { role: user.role });

      await logAudit({
        userId: user.id,
        action: AuditActions.SIGNUP,
        ip: request.ip,
        userAgent: request.headers['user-agent'],
      });

      const { password: _, ...userWithoutPassword } = user;
      reply.send({
        token: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        accessExpiresAt: tokens.accessExpiresAt,
        user: userWithoutPassword,
      });
    } catch (err: any) {
      console.error('[auth/signup] FATAL:', err?.message || err);
      console.error('[auth/signup] Stack:', err?.stack);
      return reply.status(500).send({
        error: 'Server error during sign up',
        hint: 'Database schema may be out of sync. Check server logs.',
        requestId: request.id,
      });
    }
  });

  // POST /api/auth/signin — 10 попыток входа за 5 минут
  // 🔧 FIX 500-on-signin: wrapped in try/catch with detailed error log.
  // Previously, when the DB schema was out of sync (e.g. displayName column
  // missing), prisma.user.findUnique threw "column does not exist" and the
  // generic error handler returned 500 with no useful context. Now we log
  // the actual prisma error message so future schema drift is debuggable.
  fastify.post('/auth/signin', {
    config: {
      rateLimit: { max: 10, timeWindow: '5 minutes' }
    }
  }, async (request, reply) => {
    try {
      const { email, password } = request.body;
      const user = await prisma.user.findUnique({ where: { email } });
      if (!user) {
        await logAudit({ action: AuditActions.LOGIN_FAILED, ip: request.ip, metadata: { email } });
        return reply.status(401).send({ error: 'Invalid credentials' });
      }

      const valid = await bcrypt.compare(password, user.password);
      if (!valid) {
        await logAudit({ userId: user.id, action: AuditActions.LOGIN_FAILED, ip: request.ip });
        return reply.status(401).send({ error: 'Invalid credentials' });
      }

      if (user.bannedUntil && user.bannedUntil > new Date()) {
        return reply.status(403).send({ error: 'Account banned' });
      }

      // Soft-deleted (Telegram tombstone) — cannot sign in again
      if ((user as any).deletedAt || String(user.username || '').startsWith('deleted_')) {
        return reply.status(403).send({
          error: 'Account deleted',
          code: 'ACCOUNT_DELETED',
        });
      }

      // V5 (Phase 2.7): signing in cancels any pending scheduled deletion.
      // User changed their mind — restore the account to good standing.
      if (user.scheduledForDeletionAt) {
        await prisma.user.update({
          where: { id: user.id },
          data: { scheduledForDeletionAt: null }
        });
        await logAudit({
          userId: user.id,
          action: AuditActions.ACCOUNT_DELETION_CANCELLED,
          ip: request.ip,
          metadata: { previouslyScheduledFor: user.scheduledForDeletionAt }
        });
      }

      await prisma.user.update({
        where: { id: user.id },
        data: { isOnline: true, lastSeenAt: new Date() } as any,
      }).catch(async () => {
        await prisma.user.update({ where: { id: user.id }, data: { isOnline: true } });
      });

      // Promote founder/admin emails (e.g. koslakandrej@gmail.com → ADMIN)
      const privileged = await ensurePrivilegedRole(user);

      const tokens = await issueTokenPair(fastify, privileged.id, privileged.username, {
        role: privileged.role,
      });

      await logAudit({
        userId: privileged.id,
        action: AuditActions.LOGIN,
        ip: request.ip,
        userAgent: request.headers['user-agent'],
      });

      const { password: _, ...userWithoutPassword } = privileged;
      reply.send({
        token: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        accessExpiresAt: tokens.accessExpiresAt,
        user: userWithoutPassword,
      });
    } catch (err: any) {
      console.error('[auth/signin] FATAL:', err?.message || err);
      console.error('[auth/signin] Stack:', err?.stack);
      // Don't leak internal details to client — just say server error.
      return reply.status(500).send({
        error: 'Server error during sign in',
        hint: 'Database schema may be out of sync. Check server logs for prisma error.',
        requestId: request.id,
      });
    }
  });

  // POST /api/auth/admin-verify — step-up 2FA for existing ADMIN/FOUNDER users.
  //
  // GPT-5.6 SOL fix: this endpoint was previously granting ADMIN role to anyone
  // with the code, which is a privilege escalation. Now it ONLY issues a
  // short-lived mfaVerified=true token to users who ALREADY have ADMIN or
  // FOUNDER role in the DB. Role assignment must happen through a separate,
  // audited admin flow (or DB migration for initial founder).
  //
  // Flow:
  //   1. User signs in normally (gets USER role token).
  //   2. Founder/Admin runs DB migration or separate admin-promote endpoint.
  //   3. User calls /auth/admin-verify with 2FA code → gets mfaVerified=true token.
  //   4. Token allows /api/admin/* access for 10 minutes.
  fastify.post('/auth/admin-verify', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 5, timeWindow: '10 minutes' } }
  }, async (request, reply) => {
    const { email, code } = request.body;
    if (!email || !code) {
      return reply.status(400).send({ error: 'Email and code required' });
    }

    // GPT-5.6 SOL: require authenticated session — admin-verify is step-up,
    // not login. The caller must already be signed in.
    if (!request.user || !request.user.id) {
      return reply.status(401).send({ error: 'Authentication required for admin step-up' });
    }

    // 2FA code verification (single-use would be ideal; for now static code).
    const ADMIN_CODE = 'ADM873IN7';
    if (code !== ADMIN_CODE) {
      return reply.status(401).send({ error: 'Invalid admin code' });
    }

    // GPT-5.6 SOL: load user from DB and verify they ALREADY have ADMIN/FOUNDER role.
    // This endpoint does NOT grant ADMIN — it only verifies 2FA for existing admins.
    const user = await prisma.user.findUnique({
      where: { id: request.user.id },
      select: { id: true, username: true, email: true, role: true, isPremium: true },
    });
    if (!user) {
      return reply.status(404).send({ error: 'User not found' });
    }

    // GPT-5.6 SOL: reject if user is not already ADMIN or FOUNDER.
    if (user.role !== 'ADMIN' && user.role !== 'FOUNDER') {
      await logAudit({
        userId: user.id,
        action: 'admin.verify_denied',
        ip: request.ip,
        metadata: { reason: 'insufficient_role', userRole: user.role },
      });
      return reply.status(403).send({
        error: 'Admin role required. Contact a founder to request admin access.',
      });
    }

    // GPT-5.6 SOL: verify email matches the authenticated user (extra safety).
    if (user.email.toLowerCase() !== email.toLowerCase()) {
      return reply.status(403).send({ error: 'Email does not match authenticated user' });
    }

    await logAudit({
      userId: user.id,
      action: 'admin.verified',
      ip: request.ip,
      metadata: { role: user.role, method: '2fa_code' },
    });

    // Issue token with mfaVerified=true (admin step-up complete).
    // auth_time is set to now, so admin has 10 minutes before re-verification.
    // Role comes from DB (user.role), NOT hardcoded 'ADMIN'.
    const tokens = await issueTokenPair(fastify, user.id, user.username, {
      role: user.role,
      mfaVerified: true,
    });

    reply.send({
      token: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessExpiresAt: tokens.accessExpiresAt,
      user: { id: user.id, username: user.username, email: user.email, role: user.role, isPremium: user.isPremium },
    });
  });

  // POST /api/auth/refresh — 60 в минуту (часто, т.к. каждый запуск приложения)
  // 🔧 FIX: wrapped in try/catch — same 500-protection as signin/signup.
  fastify.post('/auth/refresh', {
    config: {
      rateLimit: { max: 60, timeWindow: '1 minute' }
    }
  }, async (request, reply) => {
    try {
      const { refreshToken } = request.body;
      if (!refreshToken) {
        return reply.status(400).send({ error: 'Refresh token required' });
      }

      const verified = await verifyRefreshToken(fastify, refreshToken);
      if (!verified) {
        await alertWarning('Invalid refresh token attempt');
        return reply.status(401).send({ error: 'Invalid or expired refresh token' });
      }

      const user = await prisma.user.findUnique({
        where: { id: verified.userId },
        select: { id: true, username: true, email: true, role: true, isPremium: true, bannedUntil: true }
      });
      if (!user) return reply.status(401).send({ error: 'User not found' });
      if (user.bannedUntil && user.bannedUntil > new Date()) {
        return reply.status(403).send({ error: 'Account banned' });
      }

      const tokens = await issueTokenPair(fastify, user.id, user.username, { role: user.role });

      await logAudit({
        userId: user.id,
        action: AuditActions.TOKEN_REFRESH,
        ip: request.ip,
      });

      reply.send({
        token: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        accessExpiresAt: tokens.accessExpiresAt,
        user,
      });
    } catch (err: any) {
      console.error('[auth/refresh] FATAL:', err?.message || err);
      console.error('[auth/refresh] Stack:', err?.stack);
      return reply.status(500).send({
        error: 'Server error during token refresh',
        hint: 'Database schema may be out of sync. Check server logs.',
        requestId: request.id,
      });
    }
  });

  // POST /api/auth/logout
  fastify.post('/auth/logout', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    await revokeAllUserTokens(request.user.id);
    await prisma.user.update({
      where: { id: request.user.id },
      data: { isOnline: false }
    });
    
    await logAudit({
      userId: request.user.id,
      action: AuditActions.LOGOUT,
      ip: request.ip,
    });
    
    reply.send({ success: true });
  });

  // POST /api/auth/fcm-token
  fastify.post('/auth/fcm-token', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    const { token: fcmToken } = request.body;
    await prisma.user.update({
      where: { id: request.user.id },
      data: { fcmToken }
    });
    reply.send({ success: true });
  });

  // ─────────────────────────────────────────────────────────────────────
  // V5 endpoints (Phase 4 of PLINK_MASTER_PLAN_10_OF_10.md)
  // ─────────────────────────────────────────────────────────────────────

  // GET /api/auth/check-username?username=...
  // Phase 2.6: returns true if nickname is available for registration.
  // B6: rate limited to prevent enumeration.
  fastify.get('/auth/check-username', {
    config: { rateLimit: { max: 20, timeWindow: '1 minute' } }
  }, async (request, reply) => {
    const username = String(request.query?.username ?? '').trim();
    if (username.length < 3) {
      return reply.send({ available: false });
    }
    const existing = await prisma.user.findFirst({
      where: { username: { equals: username, mode: 'insensitive' } },
      select: { id: true }
    });
    reply.send({ available: !existing });
  });

  // POST /api/auth/heartbeat
  // Phase 4: returns active sessions list + current device flag.
  // Lightweight — just confirms the token is valid and returns session metadata.
  fastify.post('/auth/heartbeat', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    const userId = request.user.id;
    const userAgent = String(request.headers['user-agent'] ?? 'unknown');

    // Update lastSeen on the user row (cheap upsert).
    await prisma.user.update({
      where: { id: userId },
      data: { isOnline: true }
    }).catch(() => { /* ignore — heartbeat is best-effort */ });

    // Build a single pseudo-session row from current request.
    // (Real per-device session tracking requires a Session table; until that
    // lands, we return the current device only and mark it as primary.)
    const sessions = [{
      id: `${userId}-${userAgent}`,
      device: userAgent,
      location: null,
      lastSeen: new Date(),
      isCurrent: true
    }];

    reply.send({
      sessions,
      currentDeviceIsPrimary: true,
      primaryDevice: userAgent,
      primarySince: new Date(),
      lastAuthAt: new Date()
    });
  });

  // POST /api/auth/signout-others
  // Phase 4: revokes all refresh tokens for the user (which kicks other
  // devices on their next /auth/refresh call), then re-issues a fresh pair
  // for the current device so the caller stays signed in.
  fastify.post('/auth/signout-others', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    const userId = request.user.id;
    const username = request.user.username;

    // Revoke everything, then issue a new pair for this device.
    await revokeAllUserTokens(userId);
    const tokens = await issueTokenPair(fastify, userId, username);

    await logAudit({
      userId,
      action: AuditActions.SIGNOUT_OTHERS,
      ip: request.ip,
      metadata: { reason: 'signout-others' }
    });

    reply.send({
      success: true,
      token: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessExpiresAt: tokens.accessExpiresAt
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // B1 REMOVED: POST /api/auth/promote-self
  // ─────────────────────────────────────────────────────────────────────
  // GPT-5.6 ADR-002: публичный endpoint самоповышения — security blocker.
  // Bootstrap admin ролей выполняется через scripts/bootstrap-admin.js
  // (idempotent, allowlist, audit log, требует production secrets access).
  // Дальнейшие изменения ролей — только через admin flow с recent-auth.
}
