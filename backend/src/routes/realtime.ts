// src/routes/realtime.ts — Realtime ticket endpoint
//
// 'JWT для WebSocket передавать через Sec-WebSocket-Protocol с
// короткоживущим ticket, не query string. Выпустить endpoint
// POST /api/realtime/ticket, TTL 60 секунд, одноразовый nonce.'
//
// The nonce key must match between issue (here) and verify (gateway.ts):
// both sides use the FULL nonce UUID, never a truncated slice.
// The ticket is also BOUND to roomId — the gateway rejects a connection
// whose WS path roomId differs from the ticket roomId.
//
// Host membership: the host of a room may not have a RoomParticipant row,
// because the room-creation flow creates the Room without a RoomParticipant
// for the host. Ticket issuance therefore accepts EITHER:
//   (a) a RoomParticipant row exists for (roomId, userId), OR
//   (b) userId === Room.hostID
//
// Flow:
//   1. Client has a normal access JWT (Authorization: Bearer).
//   2. Before opening WS, client calls POST /api/realtime/ticket with
//      { roomId } in body.
//   3. Server verifies access JWT, confirms room membership OR host role,
//      mints a short-lived (60s) realtime ticket JWT with typ='realtime_ticket',
//      embedding { id, username, role, roomId, nonce }.
//   4. Server stores the FULL nonce in Redis (TTL 60s) under
//      plink:ticket:<userId>:<nonce> — single-use.
//   5. Client opens WS with Sec-WebSocket-Protocol: plink.v2, plink.ticket.<jwt>
//   6. Gateway verifies ticket signature + expiry, then DELs the nonce key.
//      Second attempt → DEL returns 0 → rejected.
//   7. Gateway also verifies ticket.roomId matches WS path roomId.

import type { FastifyPluginAsync } from 'fastify';
import { randomUUID } from 'node:crypto';
import { config } from '../config/index.js';
import { redis } from '../config/redis.js';
import { prisma } from '../config/db.js';

export const realtimeTicketRoutes: FastifyPluginAsync = async (fastify) => {
  // Authoritative server clock — REST fallback для клиентского clock-sync.
  // Клиент меряет RTT и считает offset = serverTime - (t0 + rtt/2).
  fastify.get(
    '/realtime/time',
    {
      config: { rateLimit: { max: 120, timeWindow: '1 minute' } },
    },
    async () => ({ serverTime: Date.now() }),
  );

  fastify.post(
    '/realtime/ticket',
    {
      preHandler: [(fastify as any).authenticate],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request: any, reply: any) => {
      const userId = request.user.id;
      const { roomId } = request.body ?? {};
      if (!roomId || typeof roomId !== 'string') {
        return reply.status(400).send({ error: 'roomId required' });
      }

      // ── '@me' — user-level DM channel ticket (no room binding) ──────────
      if (roomId === '@me') {
        const nonce = randomUUID();
        const ticket = fastify.jwt.sign(
          {
            id: userId,
            username: request.user.username,
            role: request.user.role,
            roomId: '@me',
            nonce,
            host: false,
            typ: 'realtime_ticket',
          },
          { expiresIn: `${config.REALTIME_TICKET_TTL_SEC}s` },
        );
        if (!redis) {
          return reply.status(503).send({ error: 'Realtime unavailable (Redis not configured)' });
        }
        await redis.set(
          `plink:ticket:${userId}:${nonce}`,
          JSON.stringify({ roomId: '@me', issuedAt: Date.now() }),
          'EX',
          config.REALTIME_TICKET_TTL_SEC,
        );
        return reply.send({
          ticket,
          expiresInSec: config.REALTIME_TICKET_TTL_SEC,
          protocol: ['plink.v2', `plink.ticket.${ticket}`],
        });
      }

      // ── Membership / host check ──────────────────────────────────────────
      // Accept either RoomParticipant row OR host-of-room status.
      const [participant, room] = await Promise.all([
        prisma.roomParticipant
          .findUnique({
            where: { roomID_userID: { roomID: roomId, userID: userId } },
            select: { id: true },
          })
          .catch(() => null),
        prisma.room.findUnique({
          where: { id: roomId },
          select: { hostID: true, isActive: true },
        }),
      ]);

      if (!room) {
        return reply.status(404).send({ error: 'Room not found' });
      }
      if (!room.isActive) {
        return reply.status(403).send({ error: 'Room is not active' });
      }
      const isHost = room.hostID === userId;
      const isMember = participant !== null;
      if (!isHost && !isMember) {
        return reply.status(403).send({ error: 'Not a room member or host' });
      }

      // ── Issue ticket ─────────────────────────────────────────────────────
      const nonce = randomUUID();
      const ticket = fastify.jwt.sign(
        {
          id: userId,
          username: request.user.username,
          role: request.user.role,
          roomId, // Bound to room — gateway will verify
          nonce, // Full UUID, not slice(-12)
          host: isHost,
          typ: 'realtime_ticket',
        },
        { expiresIn: `${config.REALTIME_TICKET_TTL_SEC}s` },
      );

      // single-use nonce stored under FULL nonce UUID.
      // Gateway will DEL plink:ticket:<userId>:<nonce> on first use.
      // Redis is REQUIRED for v2 — fail-fast if not configured.
      if (!redis) {
        request.log.error('Redis not configured — cannot issue realtime ticket');
        return reply.status(503).send({ error: 'Realtime unavailable (Redis not configured)' });
      }
      await redis.set(
        `plink:ticket:${userId}:${nonce}`,
        JSON.stringify({ roomId, issuedAt: Date.now() }),
        'EX',
        config.REALTIME_TICKET_TTL_SEC,
      );

      return reply.send({
        ticket,
        expiresInSec: config.REALTIME_TICKET_TTL_SEC,
        protocol: ['plink.v2', `plink.ticket.${ticket}`],
      });
    },
  );
};
