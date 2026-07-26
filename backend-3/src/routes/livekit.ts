// src/routes/livekit.ts — Stage 9: LiveKit SFU token endpoint (runbook §9)
import type { FastifyPluginAsync } from 'fastify';
import { config } from '../config/index.js';
import { prisma } from '../config/db.js';

export const livekitRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.post('/rtc/token', {
    preHandler: [(fastify as any).authenticate],
    config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
  }, async (request: any, reply: any) => {
    const userId = request.user.id;
    const { roomId } = request.body ?? {};
    if (!roomId) return reply.status(400).send({ error: 'roomId required' });

    const [participant, room] = await Promise.all([
      prisma.roomParticipant.findUnique({
        where: { roomID_userID: { roomID: roomId, userID: userId } },
        select: { id: true },
      }).catch(() => null),
      prisma.room.findUnique({
        where: { id: roomId },
        select: { hostID: true, isActive: true },
      }),
    ]);
    if (!room || !room.isActive) return reply.status(404).send({ error: 'Room not found' });
    if (room.hostID !== userId && !participant) return reply.status(403).send({ error: 'Not a room member' });

    if (!config.LIVEKIT_URL || !config.LIVEKIT_API_KEY || !config.LIVEKIT_API_SECRET) {
      return reply.status(503).send({ error: 'RTC unavailable', reason: 'LiveKit not configured' });
    }

    const identity = userId;
    const roomName = `plink-${roomId}`;
    const isHost = room.hostID === userId;
    const now = Math.floor(Date.now() / 1000);
    const ttl = 3600;

    const { SignJWT } = await import('jose');
    const secret = new TextEncoder().encode(config.LIVEKIT_API_SECRET);
    const token = await new SignJWT({
      video: { room: roomName, roomJoin: true, canPublish: true, canSubscribe: true, canPublishData: true },
      ...(isHost ? { roomAdmin: true } : {}),
    })
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setIssuer(config.LIVEKIT_API_KEY)
      .setSubject(identity)
      .setIssuedAt(now)
      .setExpirationTime(now + ttl)
      .sign(secret);

    return reply.send({
      token, url: config.LIVEKIT_URL, roomName, identity, expiresInSec: ttl,
      audio: { codec: 'opus', echoCancellation: true, noiseSuppression: true, autoGainControl: true },
      video: { simulcast: true, adaptiveSubscription: true, dynacast: true },
      e2ee: false,
    });
  });

  const livekitConfigured = () =>
    !!(config.LIVEKIT_URL && config.LIVEKIT_API_KEY && config.LIVEKIT_API_SECRET);

  /** Public — clients poll this to show/hide mic UI (no secrets leaked). */
  fastify.get('/rtc/status', {
    config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
  }, async (_req: any, reply: any) => {
    return reply.send({
      livekitEnabled: livekitConfigured(),
      livekitSfuFlag: config.LIVEKIT_SFU,
    });
  });

  fastify.get('/rtc/config', {
    preHandler: [(fastify as any).authenticate],
  }, async (_req: any, reply: any) => {
    return reply.send({
      livekitEnabled: livekitConfigured(),
      livekitUrl: livekitConfigured() ? config.LIVEKIT_URL : null,
      meshFallbackThreshold: 4,
      e2eeSupported: false,
    });
  });
};
