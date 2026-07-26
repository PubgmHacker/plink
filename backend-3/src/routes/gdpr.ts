// src/routes/gdpr.ts — Pack 5: GDPR Data Subject Rights
// Endpoints: export data, delete account, see what we store
import { prisma } from '../config/db.js';
import { revokeAllUserTokens } from '../utils/tokens.js';
import { logAudit } from '../utils/audit.js';
import bcrypt from 'bcryptjs';

export default async function gdprRoutes(fastify) {
  
  // GET /api/gdpr/export — экспорт всех данных пользователя (JSON)
  fastify.get('/gdpr/export', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 3, timeWindow: '1 hour' } }
  }, async (request, reply) => {
    const userId = request.user.id;
    
    const userData = await prisma.user.findUnique({
      where: { id: userId },
      include: {
        hostedRooms: { select: { id: true, name: true, code: true, createdAt: true } },
        participations: { 
          include: { 
            room: { select: { id: true, name: true, code: true } }
          } 
        },
        sentMessages: { 
          select: { id: true, text: true, createdAt: true, roomID: true },
          orderBy: { createdAt: 'desc' },
          take: 1000
        },
        sentDMs: {
          select: { id: true, content: true, createdAt: true, receiverID: true },
          orderBy: { createdAt: 'desc' },
          take: 1000
        },
        receivedDMs: {
          select: { id: true, content: true, createdAt: true, senderID: true },
          orderBy: { createdAt: 'desc' },
          take: 1000
        },
        friendRequestsSent: true,
        friendRequestsReceived: true,
        friendshipsInitiated: true,
        friendshipsReceived: true,
        watchHistory: true,
        subscriptions: true,
        blockedUsers: true,
        blockedBy: true,
        reports: true,
        refreshTokens: { select: { id: true, createdAt: true, expiresAt: true, revokedAt: true } },
        auditLogs: { orderBy: { createdAt: 'desc' }, take: 500 },
      }
    });
    
    if (!userData) return reply.status(404).send({ error: 'User not found' });
    
    // Удалить пароль из экспорта
    const { password, ...safeData } = userData as any;
    
    await logAudit({
      userId,
      action: 'gdpr.export',
      ip: request.ip,
    });
    
    reply
      .header('Content-Disposition', `attachment; filename="plink-data-${userId}.json"`)
      .send({
        exportedAt: new Date().toISOString(),
        version: '1.0',
        data: safeData,
      });
  });
  
  // GET /api/gdpr/summary — короткая сводка (без скачивания)
  fastify.get('/gdpr/summary', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    const userId = request.user.id;
    
    const [
      roomsHosted,
      roomsJoined,
      messagesSent,
      dmsSent,
      dmsReceived,
      friends,
      watchHistory,
      subscriptions,
    ] = await Promise.all([
      prisma.room.count({ where: { hostID: userId } }),
      prisma.roomParticipant.count({ where: { userID: userId } }),
      prisma.chatMessage.count({ where: { senderID: userId } }),
      prisma.directMessage.count({ where: { senderID: userId } }),
      prisma.directMessage.count({ where: { receiverID: userId } }),
      prisma.friendship.count({ where: { OR: [{ userID: userId }, { friendID: userId }] } }),
      prisma.watchHistory.count({ where: { userID: userId } }),
      prisma.subscription.count({ where: { userID: userId } }),
    ]);
    
    reply.send({
      roomsHosted,
      roomsJoined,
      messagesSent,
      dmsSent,
      dmsReceived,
      friends,
      watchHistory,
      subscriptions,
      lastUpdated: new Date().toISOString(),
    });
  });
  
  // DELETE /api/gdpr/account — удалить аккаунт (с проверкой пароля)
  fastify.delete('/gdpr/account', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 3, timeWindow: '1 hour' } }
  }, async (request, reply) => {
    const { password, confirmDelete } = request.body;
    const userId = request.user.id;
    
    if (!password) {
      return reply.status(400).send({ error: 'Password required' });
    }
    if (confirmDelete !== 'DELETE') {
      return reply.status(400).send({ error: 'Type DELETE in confirmDelete field' });
    }
    
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, password: true, email: true }
    });
    
    if (!user) return reply.status(404).send({ error: 'User not found' });
    
    const valid = await bcrypt.compare(password, user.password);
    if (!valid) return reply.status(401).send({ error: 'Invalid password' });
    
    await logAudit({
      userId,
      action: 'gdpr.account_delete',
      ip: request.ip,
      metadata: { email: user.email, mode: 'tombstone' }
    });

    // Telegram-style: keep row as «Удалённый аккаунт» so peers still see the chat
    // as deleted, but cannot message. PII stripped + sessions revoked.
    const { tombstoneAccount } = await import('../services/accountTombstone.js');
    await tombstoneAccount(userId);

    reply.send({
      deleted: true,
      soft: true,
      message: 'Account deleted. Your profile is now shown as a deleted account.',
    });
  });
  
  // POST /api/gdpr/anonymize — анонимизировать данные (GDPR right to restrict)
  // Удаляет avatar, заменяет username на "deleted_user_xxx", чистит messages
  fastify.post('/gdpr/anonymize', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 3, timeWindow: '1 hour' } }
  }, async (request, reply) => {
    const { password } = request.body;
    const userId = request.user.id;
    
    if (!password) {
      return reply.status(400).send({ error: 'Password required' });
    }
    
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, password: true }
    });
    
    if (!user) return reply.status(404).send({ error: 'User not found' });
    
    const valid = await bcrypt.compare(password, user.password);
    if (!valid) return reply.status(401).send({ error: 'Invalid password' });
    
    // Анонимизация
    await prisma.user.update({
      where: { id: userId },
      data: {
        username: `deleted_user_${userId.slice(0, 8)}`,
        email: `deleted_${userId.slice(0, 8)}@plink.app`,
        avatarURL: null,
        fcmToken: null,
      }
    });
    
    // Удалить сообщения (или заменить на "[deleted]")
    await prisma.chatMessage.updateMany({
      where: { senderID: userId },
      data: { text: '[deleted]' }
    });
    
    await prisma.directMessage.updateMany({
      where: { senderID: userId },
      data: { content: '[deleted]' }
    });
    
    // Удалить watch history
    await prisma.watchHistory.deleteMany({
      where: { userID: userId }
    });
    
    await logAudit({
      userId,
      action: 'gdpr.anonymize',
      ip: request.ip,
    });
    
    reply.send({ 
      anonymized: true,
      message: 'Your personal data has been anonymized.',
    });
  });
}
