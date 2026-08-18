// src/routes/auth.ts — Pack 1.1: правильные rate limits
import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';
import { prisma } from '../config/db.js';
import { issueTokenPair, verifyRefreshToken, revokeAllUserTokens } from '../utils/tokens.js';
import { logAudit, AuditActions } from '../utils/audit.js';
import { alertWarning } from '../utils/alerting.js';
import { ensurePrivilegedRole } from '../utils/privilegedUsers.js';
import { verifyTOTP } from '../middleware/security.js';
import { decryptSecret } from '../utils/secretBox.js';
import { validateBody } from '../middleware/validate.js';
import { signupBody, signinBody, refreshBody, adminVerifyBody, appleAuthBody, guestAuthBody, forgotPasswordBody, resetPasswordBody } from '../schemas/requests.js';
import { usernameFromAppleSub, verifyAppleIdentityToken } from '../utils/appleIdentity.js';
import {
  generateResetCode,
  storeResetCode,
  consumeResetCode,
  sendPasswordResetEmail,
} from '../services/passwordReset.js';

// Сравнение строк за постоянное время; разная длина → false без исключения.
function timingSafeEqualStr(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ab.length !== bb.length) return false;
  return crypto.timingSafeEqual(ab, bb);
}

export default async function authRoutes(fastify) {

  // POST /api/auth/signup — 5 регистраций за 20 минут
  // Wrapped in try/catch — same 500-protection as signin.
  fastify.post('/auth/signup', {
    preHandler: [validateBody(signupBody)],
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

      // Префикс `deleted_` зарезервирован под
      // tombstone-аккаунты (services/accountTombstone.ts). По нему signin и
      // refresh отличают удалённый аккаунт, а UI рисует «Удалённый аккаунт»,
      // поэтому регистрировать такой ник нельзя: иначе живой пользователь
      // сразу окажется заблокирован, а чужой профиль — подделан.
      if (username.toLowerCase().startsWith('deleted_')) {
        return reply.status(400).send({ error: 'This username prefix is reserved' });
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

  // POST /api/auth/signin — 10 attempts per 5 minutes.
  //
  // Wrapped in try/catch that logs the underlying Prisma error. When the
  // database schema lags the client (a migration not yet applied, so a column
  // is missing), findUnique throws "column does not exist" and the generic
  // handler turns it into a bare 500 — indistinguishable from a wrong password
  // in the logs.
  fastify.post('/auth/signin', {
    preHandler: [validateBody(signinBody)],
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

  // POST /api/auth/forgot-password — всегда 200, чтобы не светить, есть ли почта.
  fastify.post('/auth/forgot-password', {
    preHandler: [validateBody(forgotPasswordBody)],
    config: { rateLimit: { max: 5, timeWindow: '15 minutes' } },
  }, async (request, reply) => {
    const email = String(request.body?.email ?? '').trim().toLowerCase();
    try {
      if (email.endsWith('@plink.guest.local')) {
        return reply.send({ ok: true });
      }
      const user = await prisma.user.findFirst({
        where: {
          email: { equals: email, mode: 'insensitive' },
          deletedAt: null,
        },
        select: { id: true, email: true },
      });
      if (user) {
        const code = generateResetCode();
        await storeResetCode(user.email, code);
        await sendPasswordResetEmail(user.email, code);
        await logAudit({
          userId: user.id,
          action: AuditActions.PASSWORD_RESET_REQUESTED,
          ip: request.ip,
        });
      }
    } catch (err: any) {
      console.error('[auth/forgot-password]', err?.message || err);
    }
    return reply.send({ ok: true });
  });

  // POST /api/auth/reset-password — код из письма + новый пароль.
  fastify.post('/auth/reset-password', {
    preHandler: [validateBody(resetPasswordBody)],
    config: { rateLimit: { max: 10, timeWindow: '15 minutes' } },
  }, async (request, reply) => {
    const email = String(request.body?.email ?? '').trim().toLowerCase();
    const code = String(request.body?.code ?? '').trim();
    const newPassword = String(request.body?.newPassword ?? '');
    const user = await prisma.user.findFirst({
      where: {
        email: { equals: email, mode: 'insensitive' },
        deletedAt: null,
      },
      select: { id: true, email: true },
    });
    if (!user) {
      return reply.status(400).send({ error: 'Неверный или просроченный код' });
    }
    const result = await consumeResetCode(user.email, code);
    if (result !== 'ok') {
      const message =
        result === 'locked'
          ? 'Слишком много попыток. Запросите код заново'
          : 'Неверный или просроченный код';
      return reply.status(400).send({ error: message });
    }
    const hashedPassword = await bcrypt.hash(newPassword, 10);
    await prisma.user.update({
      where: { id: user.id },
      data: { password: hashedPassword },
    });
    await revokeAllUserTokens(user.id);
    await logAudit({
      userId: user.id,
      action: AuditActions.PASSWORD_RESET,
      ip: request.ip,
    });
    return reply.send({ ok: true });
  });

  // POST /api/auth/admin-verify — step-up 2FA for existing ADMIN/FOUNDER users.
  //
  // This endpoint was previously granting ADMIN role to anyone
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
    preHandler: [fastify.authenticate, validateBody(adminVerifyBody)],
    config: { rateLimit: { max: 5, timeWindow: '10 minutes' } }
  }, async (request, reply) => {
    const { email, code } = request.body;
    if (!email || !code) {
      return reply.status(400).send({ error: 'Email and code required' });
    }

    // Require authenticated session — admin-verify is step-up,
    // not login. The caller must already be signed in.
    if (!request.user || !request.user.id) {
      return reply.status(401).send({ error: 'Authentication required for admin step-up' });
    }

    // Load user from DB and verify they ALREADY have ADMIN/FOUNDER role.
    // This endpoint does NOT grant ADMIN — it only verifies 2FA for existing admins.
    const user = await prisma.user.findUnique({
      where: { id: request.user.id },
      select: {
        id: true, username: true, email: true, role: true, isPremium: true,
        twofaEnabled: true, twofaSecret: true,
      },
    });
    if (!user) {
      return reply.status(404).send({ error: 'User not found' });
    }

    // Статичный код ADM873IN7 удалён из исходников.
    // Порядок проверки:
    //   1) у пользователя включён TOTP (twofaEnabled + twofaSecret) — проверяем его;
    //      секрет расшифровывается, если зашифрован ключом TWOFA_ENC_KEY;
    //   2) иначе — код из окружения ADMIN_STEPUP_CODE (временный мост, пока
    //      у админов нет TOTP-энролмента); сравнение за постоянное время;
    //   3) нет ни того, ни другого — шаг-ап невозможен.
    let codeOk = false;
    let stepupMethod = 'env_code';
    if (user.twofaEnabled && user.twofaSecret) {
      stepupMethod = 'totp';
      const secret = decryptSecret(user.twofaSecret);
      codeOk = !!secret && verifyTOTP(secret, String(code));
    } else {
      const envCode = process.env.ADMIN_STEPUP_CODE;
      if (!envCode) {
        return reply.status(503).send({
          error: 'Admin step-up is not configured. Set ADMIN_STEPUP_CODE or enroll TOTP.',
        });
      }
      codeOk = timingSafeEqualStr(String(code), envCode);
    }
    if (!codeOk) {
      await logAudit({
        userId: user.id,
        action: 'admin.verify_denied',
        ip: request.ip,
        metadata: { reason: 'bad_code', method: stepupMethod },
      });
      return reply.status(401).send({ error: 'Invalid admin code' });
    }

    // Reject if user is not already ADMIN or FOUNDER.
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

    // Verify email matches the authenticated user (extra safety).
    if (user.email.toLowerCase() !== email.toLowerCase()) {
      return reply.status(403).send({ error: 'Email does not match authenticated user' });
    }

    await logAudit({
      userId: user.id,
      action: 'admin.verified',
      ip: request.ip,
      metadata: { role: user.role, method: stepupMethod },
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
  // Wrapped in try/catch — same 500-protection as signin/signup.
  fastify.post('/auth/refresh', {
    preHandler: [validateBody(refreshBody)],
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
        select: {
          id: true, username: true, email: true, role: true, isPremium: true,
          bannedUntil: true,
          // deletedAt раньше не выбирался и не
          // проверялся. tombstoneAccount отзывает токены best-effort
          // (`.catch(() => {})`), поэтому при сбое отзыва удалённый аккаунт
          // продолжал бесконечно обновлять сессию через /auth/refresh.
          deletedAt: true,
        }
      });
      if (!user) return reply.status(401).send({ error: 'User not found' });
      if (user.bannedUntil && user.bannedUntil > new Date()) {
        return reply.status(403).send({ error: 'Account banned' });
      }
      // Тот же критерий, что и в /auth/signin: soft-delete (Telegram tombstone).
      //
      // Ревью 26.07.2026: отзываем ВСЕ сессии только когда стоит deletedAt —
      // то есть аккаунт действительно погашен. Одного префикса `deleted_` для
      // этого недостаточно: он проверяется в signup/check-username, но НЕ в
      // PATCH /api/users/me (routes/profile.ts), поэтому живой пользователь
      // может переименоваться в `deleted_foo` — и массовый отзыв превратил бы
      // его аккаунт в кирпич без пути восстановления. Префикс по-прежнему
      // блокирует refresh (страховка на случай fallback-ветки
      // services/accountTombstone.ts, которая не выставляет deletedAt), но
      // уже выданные токены остаются валидными до истечения.
      if ((user as any).deletedAt) {
        await revokeAllUserTokens(user.id).catch(() => {});
        return reply.status(401).send({ error: 'Account deleted', code: 'ACCOUNT_DELETED' });
      }
      if (String(user.username || '').startsWith('deleted_')) {
        return reply.status(401).send({ error: 'Account deleted', code: 'ACCOUNT_DELETED' });
      }

      const tokens = await issueTokenPair(fastify, user.id, user.username, { role: user.role });

      await logAudit({
        userId: user.id,
        action: AuditActions.TOKEN_REFRESH,
        ip: request.ip,
      });

      // deletedAt выбран только для проверки выше — форму ответа не меняем.
      const { deletedAt: _deletedAt, ...safeUser } = user as any;
      reply.send({
        token: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        accessExpiresAt: tokens.accessExpiresAt,
        user: safeUser,
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
  // Username availability, session heartbeat, sign-out-other-devices,
  // guest sign-in and Sign in with Apple
  // ─────────────────────────────────────────────────────────────────────

  // GET /api/auth/check-username?username=...
  // Returns whether a nickname is free. Rate limited: unauthenticated and
  // exact-match, so without a limit it enumerates the user table.
  fastify.get('/auth/check-username', {
    config: { rateLimit: { max: 20, timeWindow: '1 minute' } }
  }, async (request, reply) => {
    const username = String(request.query?.username ?? '').trim();
    if (username.length < 3) {
      return reply.send({ available: false });
    }
    // Тот же зарезервированный префикс, что и в /auth/signup — иначе клиент
    // показал бы «ник свободен», а регистрация вернула бы 400.
    if (username.toLowerCase().startsWith('deleted_')) {
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

  // POST /api/auth/guest — ephemeral web guest (install-free /w/:code watch)
  fastify.post('/auth/guest', {
    preHandler: [validateBody(guestAuthBody)],
    config: {
      rateLimit: { max: 30, timeWindow: '10 minutes' },
    },
  }, async (request, reply) => {
    try {
      const suffix = crypto.randomBytes(4).toString('hex');
      // Matches signup regex: letter + [A-Za-z0-9_]{4,31}
      const username = `guest_${suffix}`.slice(0, 32);
      const email = `guest_${suffix}@plink.guest.local`;
      const hashedPassword = await bcrypt.hash(crypto.randomBytes(32).toString('hex'), 10);
      let user = await prisma.user.create({
        data: {
          email,
          username,
          password: hashedPassword,
          displayName: 'Гость',
          isOnline: true,
          scheduledForDeletionAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
        },
      });
      user = await ensurePrivilegedRole(user);
      const tokens = await issueTokenPair(fastify, user.id, user.username, { role: user.role });
      await logAudit({
        userId: user.id,
        action: AuditActions.SIGNUP,
        ip: request.ip,
        userAgent: request.headers['user-agent'],
        metadata: {
          provider: 'guest',
          roomCode: (request.body as { roomCode?: string } | undefined)?.roomCode ?? null,
        },
      });
      const { password: _, ...userWithoutPassword } = user;
      reply.send({
        token: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        accessExpiresAt: tokens.accessExpiresAt,
        user: userWithoutPassword,
        guest: true,
      });
    } catch (err: any) {
      console.error('[auth/guest] FATAL:', err?.message || err);
      return reply.status(500).send({ error: 'Server error during guest sign-in', requestId: request.id });
    }
  });

  // POST /api/auth/apple — Sign in with Apple (identityToken → Plink JWT pair)
  fastify.post('/auth/apple', {
    preHandler: [validateBody(appleAuthBody)],
    config: {
      rateLimit: { max: 20, timeWindow: '10 minutes' },
    },
  }, async (request, reply) => {
    try {
      const { identityToken, fullName } = request.body as {
        identityToken: string;
        fullName?: string | null;
      };

      let identity;
      try {
        identity = await verifyAppleIdentityToken(identityToken);
      } catch (err: any) {
        console.warn('[auth/apple] token verify failed:', err?.message || err);
        return reply.status(401).send({ error: 'Invalid Apple identity token' });
      }

      let user = await prisma.user.findFirst({
        where: {
          OR: [
            { appleSub: identity.sub },
            ...(identity.email ? [{ email: identity.email }] : []),
          ],
        },
      });

      if (user?.deletedAt) {
        return reply.status(403).send({ error: 'Account deleted' });
      }

      if (!user) {
        const email =
          identity.email ||
          `${identity.sub.replace(/[^a-zA-Z0-9]/g, '').slice(0, 24)}@privaterelay.appleid.com`;
        let username = usernameFromAppleSub(identity.sub);
        const taken = await prisma.user.findFirst({
          where: { username: { equals: username, mode: 'insensitive' } },
        });
        if (taken) {
          username = usernameFromAppleSub(`${identity.sub}${Date.now()}`);
        }
        // Password is unusable — Apple-only account. Random hash, never logged.
        const hashedPassword = await bcrypt.hash(crypto.randomBytes(32).toString('hex'), 10);
        const display =
          typeof fullName === 'string' && fullName.trim().length > 0
            ? fullName.trim().slice(0, 64)
            : null;
        user = await prisma.user.create({
          data: {
            email,
            username,
            password: hashedPassword,
            appleSub: identity.sub,
            displayName: display,
            isOnline: true,
          },
        });
        await logAudit({
          userId: user.id,
          action: AuditActions.SIGNUP,
          ip: request.ip,
          userAgent: request.headers['user-agent'],
          metadata: { provider: 'apple' },
        });
      } else if (!user.appleSub) {
        user = await prisma.user.update({
          where: { id: user.id },
          data: { appleSub: identity.sub, isOnline: true, lastSeenAt: new Date() },
        });
      } else {
        await prisma.user.update({
          where: { id: user.id },
          data: { isOnline: true, lastSeenAt: new Date() },
        });
      }

      user = await ensurePrivilegedRole(user);
      const tokens = await issueTokenPair(fastify, user.id, user.username, { role: user.role });

      await logAudit({
        userId: user.id,
        action: AuditActions.LOGIN,
        ip: request.ip,
        userAgent: request.headers['user-agent'],
        metadata: { provider: 'apple' },
      });

      const { password: _, ...userWithoutPassword } = user;
      reply.send({
        token: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        accessExpiresAt: tokens.accessExpiresAt,
        user: userWithoutPassword,
      });
    } catch (err: any) {
      console.error('[auth/apple] FATAL:', err?.message || err);
      return reply.status(500).send({
        error: 'Server error during Apple sign-in',
        requestId: request.id,
      });
    }
  });

  // ─────────────────────────────────────────────────────────────────────
  // B1 REMOVED: POST /api/auth/promote-self
  // ─────────────────────────────────────────────────────────────────────
  // Публичный endpoint самоповышения — security blocker.
  // Bootstrap admin ролей выполняется через scripts/bootstrap-admin.js
  // (idempotent, allowlist, audit log, требует production secrets access).
  // Дальнейшие изменения ролей — только через admin flow с recent-auth.
}
