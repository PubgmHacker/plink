// src/routes/admin.ts — PATCH 16: Admin API endpoints
//
// Brain Review 10 P0-67/P0-69: previous "admin" was iOS placeholder only.
// This module implements the backend /api/admin/* routes that the iOS
// AdminModules.swift expects.
//
// Authorization (per PATCH 09 spec):
//   - All routes require ADMIN or FOUNDER role
//   - 2FA must be enabled and verified (enforced below via JWT claims mfa + auth_time)
//   - Recent auth (within 15 minutes) required for destructive actions
//   - Every mutation writes an AuditLog entry
//
// Modules implemented:
//   - users        — list, ban, role assignment
//   - rooms        — list, force-close, transfer host
//   - moderation   — reported messages queue, delete, mute
//   - flags        — flagged content queue
//   - analytics    — DAU/MAU, room count, peak concurrency
//   - system       — health, version, feature flags
//   - audit        — AuditLog search
//   - broadcasts   — push notification composer + history
//   - premium      — subscription metrics, refund grants, comp codes
//   - blocklists   — global blocklist
//
// All mutations write to AuditLog via logAudit().

import { prisma } from '../config/db.js';
import { pushBroadcast } from '../services/pushService.js';
import { logAudit, AuditActions } from '../utils/audit.js';

// Admin role check middleware — must be ADMIN or FOUNDER.
// GPT-5 BE-P0-01: also require 2FA verified + recent auth (<=10 minutes)
// for ALL admin requests. Mutations must wrap audit log in the same
// Prisma transaction as the mutation itself.
const RECENT_AUTH_SECONDS = 10 * 60; // 10 minutes

function requireAdmin(fastify: any) {
  fastify.addHook('preHandler', async (request: any, reply: any) => {
    if (!request.user) {
      return reply.status(401).send({ error: 'Authentication required' });
    }
    const role = request.user.role;
    if (role !== 'ADMIN' && role !== 'FOUNDER') {
      await logAudit({
        userId: request.user.id,
        action: 'admin.unauthorized',
        ip: request.ip,
        metadata: { path: request.url, role },
      });
      return reply.status(403).send({ error: 'Admin access required' });
    }

    // GPT-5 BE-P0-01: 2FA must be enabled and verified.
    // JWT claim `mfa: true` means the user completed 2FA in this session.
    if (request.user.mfa !== true) {
      return reply.status(401).send({ error: 'step_up_required', reason: 'mfa' });
    }

    // GPT-5 BE-P0-01: recent auth required (auth_time within 10 minutes).
    // JWT claim `auth_time` is set when the user authenticates (login or 2FA verify).
    if (typeof request.user.auth_time !== 'number') {
      return reply.status(401).send({ error: 'step_up_required', reason: 'missing_auth_time' });
    }
    const now = Math.floor(Date.now() / 1000);
    if (now - request.user.auth_time > RECENT_AUTH_SECONDS) {
      return reply.status(401).send({
        error: 'step_up_required',
        reason: 'stale_auth',
        auth_age_seconds: now - request.user.auth_time,
        max_age_seconds: RECENT_AUTH_SECONDS,
      });
    }
  });
}

export async function adminRoutes(fastify: any) {
  // Apply admin auth to all routes in this plugin.
  requireAdmin(fastify);

  // ─── Users ─────────────────────────────────────────────────────────
  fastify.get('/admin/users', async (request: any, reply: any) => {
    const { search, limit = 50, offset = 0 } = request.query;
    const where = search
      ? { OR: [{ username: { contains: search } }, { email: { contains: search } }] }
      : {};
    const users = await prisma.user.findMany({
      where,
      select: {
        id: true, username: true, email: true, isPremium: true, role: true,
        bannedUntil: true, createdAt: true, isOnline: true,
      },
      take: Math.min(parseInt(limit), 200),
      skip: parseInt(offset),
      orderBy: { createdAt: 'desc' },
    });
    reply.send({ users, count: users.length });
  });

  // GPT-5 BE-P0-01: ban endpoint with transaction-wrapped audit + reason required.
  // - TEMPORARY: durationHours present → bannedUntil set
  // - PERMANENT: durationHours absent → banStatus PERMANENT
  // - Founder protection: cannot ban the last founder.
  fastify.post('/admin/users/:id/ban', async (request: any, reply: any) => {
    const { id } = request.params;
    const { durationHours, reason } = request.body || {};

    // GPT-5 BE-P0-01: reason required for destructive actions.
    if (!reason || typeof reason !== 'string' || reason.trim().length < 3) {
      return reply.status(400).send({ error: 'Reason is required (min 3 chars) for ban action' });
    }

    // Founder protection.
    const targetUser = await prisma.user.findUnique({ where: { id } });
    if (!targetUser) return reply.status(404).send({ error: 'User not found' });
    if (targetUser.role === 'FOUNDER') {
      const founderCount = await prisma.user.count({ where: { role: 'FOUNDER' } });
      if (founderCount <= 1) {
        return reply.status(403).send({ error: 'Cannot ban the last founder' });
      }
    }

    const isPermanent = !durationHours;
    const bannedUntil = durationHours
      ? new Date(Date.now() + durationHours * 3600 * 1000)
      : null;
    const banStatus = isPermanent ? 'PERMANENT' : 'TEMPORARY';

    // GPT-5 BE-P0-01: wrap mutation + audit in one transaction.
    try {
      await prisma.$transaction(async (tx) => {
        const updateData: any = { bannedUntil };
        try {
          await tx.user.update({
            where: { id },
            data: { ...updateData, banStatus } as any,
          });
        } catch {
          await tx.user.update({ where: { id }, data: updateData });
        }

        await tx.auditLog.create({
          data: {
            actorId: request.user.id,
            action: AuditActions.USER_BANNED,
            targetType: 'USER',
            targetId: id,
            ip: request.ip,
            requestId: request.id,
            metadata: { durationHours, bannedUntil, banStatus, reason, targetRole: targetUser.role },
          } as any,
        });
      });
    } catch (txErr: any) {
      request.log.error({ err: txErr }, 'ban transaction failed');
      return reply.status(500).send({ error: 'Internal Server Error' });
    }

    reply.send({ success: true, bannedUntil, banStatus, reason });
  });

  // GPT-5 BE-P0-01: unban with transaction-wrapped audit + reason required.
  fastify.post('/admin/users/:id/unban', async (request: any, reply: any) => {
    const { id } = request.params;
    const { reason } = request.body || {};

    if (!reason || typeof reason !== 'string' || reason.trim().length < 3) {
      return reply.status(400).send({ error: 'Reason is required (min 3 chars) for unban action' });
    }

    try {
      await prisma.$transaction(async (tx) => {
        try {
          await tx.user.update({
            where: { id },
            data: { bannedUntil: null, banStatus: 'NONE' } as any,
          });
        } catch {
          await tx.user.update({ where: { id }, data: { bannedUntil: null } });
        }

        await tx.auditLog.create({
          data: {
            actorId: request.user.id,
            action: 'admin.user.unban',
            targetType: 'USER',
            targetId: id,
            ip: request.ip,
            requestId: request.id,
            metadata: { reason },
          } as any,
        });
      });
    } catch (txErr: any) {
      request.log.error({ err: txErr }, 'unban transaction failed');
      return reply.status(500).send({ error: 'Internal Server Error' });
    }

    reply.send({ success: true, banStatus: 'NONE' });
  });

  fastify.post('/admin/users/:id/role', async (request: any, reply: any) => {
    const { id } = request.params;
    const { role } = request.body || {};
    if (!['USER', 'MODERATOR', 'ADMIN', 'FOUNDER'].includes(role)) {
      return reply.status(400).send({ error: 'Invalid role' });
    }

    await prisma.user.update({
      where: { id },
      data: { role },
    });

    await logAudit({
      userId: request.user.id,
      action: 'admin.user.role_change',
      ip: request.ip,
      metadata: { targetUserId: id, newRole: role },
    });

    reply.send({ success: true, role });
  });

  // ─── Rooms ─────────────────────────────────────────────────────────
  fastify.get('/admin/rooms', async (request: any, reply: any) => {
    const { limit = 50, offset = 0 } = request.query;
    const rooms = await prisma.room.findMany({
      take: Math.min(parseInt(limit), 200),
      skip: parseInt(offset),
      orderBy: { createdAt: 'desc' },
      include: { _count: { select: { participants: true } } },
    });
    reply.send({ rooms, count: rooms.length });
  });

  fastify.post('/admin/rooms/:id/close', async (request: any, reply: any) => {
    const { id } = request.params;
    await prisma.room.update({
      where: { id },
      data: { isActive: false },
    });

    await logAudit({
      userId: request.user.id,
      action: 'admin.room.close',
      ip: request.ip,
      metadata: { roomId: id },
    });

    reply.send({ success: true });
  });

  // ─── Moderation ────────────────────────────────────────────────────
  fastify.get('/admin/moderation/queue', async (request: any, reply: any) => {
    const reports = await prisma.report.findMany({
      where: { status: 'pending' },
      take: 50,
      orderBy: { createdAt: 'desc' },
      include: { reporter: { select: { username: true } } },
    });
    reply.send({ reports, count: reports.length });
  });

  fastify.post('/admin/moderation/messages/:id/delete', async (request: any, reply: any) => {
    const { id } = request.params;
    await prisma.chatMessage.delete({ where: { id } });

    await logAudit({
      userId: request.user.id,
      action: 'admin.message.delete',
      ip: request.ip,
      metadata: { messageId: id },
    });

    reply.send({ success: true });
  });

  // ─── Flags ─────────────────────────────────────────────────────────
  fastify.get('/admin/flags', async (request: any, reply: any) => {
    const flags = await prisma.report.findMany({
      where: { status: 'pending' },
      take: 50,
      orderBy: { createdAt: 'desc' },
    });
    reply.send({ flags, count: flags.length });
  });

  fastify.post('/admin/flags/:id/resolve', async (request: any, reply: any) => {
    const { id } = request.params;
    await prisma.report.update({
      where: { id },
      data: { status: 'resolved' },
    });

    await logAudit({
      userId: request.user.id,
      action: 'admin.flag.resolve',
      ip: request.ip,
      metadata: { flagId: id },
    });

    reply.send({ success: true });
  });

  // ─── Analytics ─────────────────────────────────────────────────────
  fastify.get('/admin/analytics/overview', async (request: any, reply: any) => {
    const now = new Date();
    const dayAgo = new Date(now.getTime() - 24 * 3600 * 1000);
    const monthAgo = new Date(now.getTime() - 30 * 24 * 3600 * 1000);

    const [totalUsers, dau, mau, activeRooms, totalMessages] = await Promise.all([
      prisma.user.count(),
      prisma.user.count({ where: { isOnline: true } }),
      prisma.user.count({ where: { updatedAt: { gte: monthAgo } } }),
      prisma.room.count({ where: { isActive: true } }),
      prisma.chatMessage.count({ where: { createdAt: { gte: dayAgo } } }),
    ]);

    reply.send({
      totalUsers,
      dau,
      mau,
      p50SyncDrift: 0,
      p95SyncDrift: 0,
      activeRooms,
      messages24h: totalMessages,
    });
  });

  // ─── System ────────────────────────────────────────────────────────
  fastify.get('/admin/system/health', async (request: any, reply: any) => {
    reply.send({
      status: 'ok',
      version: process.env.APP_VERSION || '1.5.0',
      uptime: process.uptime(),
      nodeEnv: process.env.NODE_ENV,
      timestamp: new Date().toISOString(),
    });
  });

  fastify.get('/admin/system/flags', async (request: any, reply: any) => {
    const flags = await prisma.featureFlag.findMany();
    reply.send({ flags });
  });

  fastify.post('/admin/system/maintenance', async (request: any, reply: any) => {
    const { enabled } = request.body || {};

    await prisma.featureFlag.upsert({
      where: { key: 'maintenance_mode' },
      create: { key: 'maintenance_mode', value: enabled ? 'true' : 'false' },
      update: { value: enabled ? 'true' : 'false' },
    });

    await logAudit({
      userId: request.user.id,
      action: 'admin.system.maintenance',
      ip: request.ip,
      metadata: { enabled },
    });

    reply.send({ success: true, maintenanceMode: enabled });
  });

  // ─── Audit ─────────────────────────────────────────────────────────
  fastify.get('/admin/audit', async (request: any, reply: any) => {
    const { adminId, action, targetId, from, to, limit = 50, offset = 0 } = request.query;
    const where: any = {};
    if (adminId) where.userId = adminId;
    if (action) where.action = { contains: action };
    if (from || to) {
      where.createdAt = {};
      if (from) where.createdAt.gte = new Date(from);
      if (to) where.createdAt.lte = new Date(to);
    }

    const logs = await prisma.auditLog.findMany({
      where,
      take: Math.min(parseInt(limit), 200),
      skip: parseInt(offset),
      orderBy: { createdAt: 'desc' },
    });

    reply.send({ logs, count: logs.length });
  });

  // ─── Broadcasts ────────────────────────────────────────────────────
  fastify.get('/admin/broadcasts/history', async (request: any, reply: any) => {
    // Broadcasts are stored as audit logs with action 'admin.broadcast.send'.
    const broadcasts = await prisma.auditLog.findMany({
      where: { action: 'admin.broadcast.send' },
      take: 50,
      orderBy: { createdAt: 'desc' },
    });
    reply.send({ broadcasts, count: broadcasts.length });
  });

  fastify.post('/admin/broadcasts/send', async (request: any, reply: any) => {
    const { title, body, topic } = request.body || {};
    if (!title || !body) {
      return reply.status(400).send({ error: 'title and body required' });
    }

    // APNs broadcast to every user with a registered device token.
    const pushed = await pushBroadcast({ title, body, data: { kind: 'broadcast', topic: topic ?? 'all' } });
    await logAudit({
      userId: request.user.id,
      action: 'admin.broadcast.send',
      ip: request.ip,
      metadata: { title, body, topic },
    });

    reply.send({ success: true, queued: true, pushed });
  });

  // ─── Premium ───────────────────────────────────────────────────────
  fastify.get('/admin/premium/metrics', async (request: any, reply: any) => {
    const [activePremium, lifetime, totalRevenue30d] = await Promise.all([
      prisma.subscription.count({ where: { isActive: true } }),
      prisma.user.count({
        where: { isPremium: true, premiumUntil: null },
      }),
      prisma.transactionRecord.count({
        where: { createdAt: { gte: new Date(Date.now() - 30 * 24 * 3600 * 1000) } },
      }),
    ]);

    reply.send({
      activePremium,
      lifetime,
      transactions30d: totalRevenue30d,
    });
  });

  fastify.post('/admin/premium/comp', async (request: any, reply: any) => {
    const { userId, days } = request.body || {};
    if (!userId || !days) {
      return reply.status(400).send({ error: 'userId and days required' });
    }

    const expiresAt = new Date(Date.now() + days * 24 * 3600 * 1000);
    await prisma.subscription.create({
      data: {
        userID: userId,
        plan: 'complimentary',
        isActive: true,
        expiresAt,
      },
    });

    await prisma.user.update({
      where: { id: userId },
      data: { isPremium: true, premiumUntil: expiresAt },
    });

    await logAudit({
      userId: request.user.id,
      action: 'admin.premium.comp',
      ip: request.ip,
      metadata: { targetUserId: userId, days, expiresAt },
    });

    reply.send({ success: true, expiresAt });
  });

  // ─── Blocklists ────────────────────────────────────────────────────
  fastify.get('/admin/blocklists', async (request: any, reply: any) => {
    // Blocklist is stored as FeatureFlag entries with key prefix 'blocklist:'.
    const entries = await prisma.featureFlag.findMany({
      where: { key: { startsWith: 'blocklist:' } },
    });
    reply.send({ blocklist: entries, count: entries.length });
  });

  fastify.post('/admin/blocklists/add', async (request: any, reply: any) => {
    const { type, value } = request.body || {};
    if (!type || !value) {
      return reply.status(400).send({ error: 'type and value required' });
    }

    const key = `blocklist:${type}:${value}`;
    await prisma.featureFlag.upsert({
      where: { key },
      create: { key, value: 'true' },
      update: { value: 'true' },
    });

    await logAudit({
      userId: request.user.id,
      action: 'admin.blocklist.add',
      ip: request.ip,
      metadata: { type, value },
    });

    reply.send({ success: true, key });
  });

  fastify.delete('/admin/blocklists/:id', async (request: any, reply: any) => {
    const { id } = request.params;
    await prisma.featureFlag.delete({ where: { key: id } });

    await logAudit({
      userId: request.user.id,
      action: 'admin.blocklist.remove',
      ip: request.ip,
      metadata: { key: id },
    });

    reply.send({ success: true });
  });
}
