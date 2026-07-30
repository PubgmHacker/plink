// src/realtime/gateway.ts — WebSocket gateway (runbook §5 + Brain Review 2 fixes)
//
// Brain Review 2 fixes:
//
// P0-15: cleanup handlers registered IMMEDIATELY after onConnection entry,
//   before any await. Idempotent cleanup tracks what was committed
//   (presence, metrics, registry, listeners) and only rolls back what
//   actually happened. Rejection paths (no room, ticket mismatch, banned,
//   not member, PubSub failure) no longer leak presence/metrics/registry.
//
// P0-16: session.ready role derived from CURRENT DB query, not stale ticket
//   claim. isMemberOrHost() now returns { allowed, isHost } from a single
//   DB check, and that current isHost is used for session.ready.
//
// P1-12: participant events use Redis-backed presence count. We publish
//   participant.joined only when the user's first connection for this room
//   joins (count 0 → 1), and participant.left only when the last connection
//   leaves (count 1 → 0). Multi-device users no longer spam join/leave.

import type { WebSocketServer } from 'ws';
import type { FastifyInstance } from 'fastify';
import type { PrismaClient } from '@prisma/client';
import type { Redis } from 'ioredis';
import { randomUUID } from 'node:crypto';
import { config, NATIVE_CLIENT_ORIGINS } from '../config/index.js';
import { RoomStateStore } from './roomStateStore.js';
import { RoomPubSub, type RoomStateListener } from './roomPubSub.js';
import { RoomEventBus, type RoomEvent, type RoomEventListener } from './roomEventBus.js';
import { ConnectionRegistry, type PlinkSocket } from './connectionRegistry.js';
import { createMessageRouter, makeSessionReady, makeParticipantEvent } from './messageRouter.js';
import { Heartbeat } from './heartbeat.js';
import { wsConnections, wsMessages, usersOnline } from '../services/metrics.js';
import { presence } from '../services/presence.js';
import type { ServerMessage } from '../contracts/realtime-v2.js';

export interface GatewayDeps {
  fastify: FastifyInstance;
  prisma: PrismaClient;
  redis: Redis;
  wss: WebSocketServer;
}

export class RealtimeGateway {
  private readonly registry = new ConnectionRegistry();
  private readonly store: RoomStateStore;
  private readonly pubsub: RoomPubSub;
  private readonly eventBus: RoomEventBus;
  private readonly router: ReturnType<typeof createMessageRouter>;
  private readonly heartbeat: Heartbeat;

  private readonly roomListeners = new Map<string, RoomStateListener>();
  private readonly roomEventListeners = new Map<string, RoomEventListener>();
  private shuttingDown = false;

  constructor(private readonly deps: GatewayDeps) {
    this.store = new RoomStateStore(deps.redis);
    this.pubsub = new RoomPubSub(config.REDIS_URL);
    this.eventBus = new RoomEventBus(config.REDIS_URL);

    this.router = createMessageRouter({
      prisma: deps.prisma,
      store: this.store,
      pubsub: this.pubsub,
      registry: this.registry,
      eventBus: this.eventBus,
      currentEpoch: async (roomId) => {
        const s = await this.store.get(roomId);
        return s?.epoch ?? 1;
      },
    });
    // P0-25: Heartbeat now takes callbacks for presence lease refresh.
    // onPong refreshes the lease; onDead is informational only (finalize
    // handles cleanup via 'close' event).
    this.heartbeat = new Heartbeat(deps.wss, {
      onPong: (socket) => {
        // Coalesced refresh — onPong fires every 20s, lease TTL is 60s,
        // so refreshing on every pong keeps lease alive with 3x margin.
        if (socket.activeRoomId && socket.userId && socket.connectionId) {
          this.refreshPresenceLease(socket.activeRoomId, socket.userId, socket.connectionId)
            .catch((err) => {
              console.warn('[Heartbeat] lease refresh failed:', err);
            });
        }
      },
      onDead: (socket) => {
        // P1-28: do NOT disconnect registry here — finalize does it.
        // Just log for observability.
        console.debug('[Heartbeat] dead socket terminated:', socket.userId);
      },
    });

    deps.wss.on('connection', (socket: PlinkSocket, req) => this.onConnection(socket, req));
  }

  private async onConnection(socket: PlinkSocket, req: any): Promise<void> {
    if (this.shuttingDown) {
      socket.close(1001, 'Server shutting down');
      return;
    }

    // ── P0-15/P0-22/P0-23: register finalize handler IMMEDIATELY, before
    // any await. Single socket.once('close', finalize) for entire lifecycle.
    // No removeAllListeners. Idempotent. Tracks ALL committed state.
    let finalized = false;
    let connectedPresence = false;
    let incrementedMetrics = false;
    let joinedRoomId: string | undefined;
    let retainedRoom = false;
    let presenceCountBumped = false;  // P0-22
    let presenceBumpedFor: { roomId: string; userId: string; connectionId?: string } | undefined;
    // capturedUser is set after banned check — finalize uses it for username
    let capturedUser: { id: string; username: string } | undefined;

    const finalize = async () => {
      if (finalized) return;
      finalized = true;
      // P1-27: local synchronous cleanup FIRST — never block on Redis.
      // Registry disconnect, presence/metrics decrement, listener release
      // all happen synchronously before any Redis call.
      if (joinedRoomId) {
        this.registry.disconnect(socket);
      }
      if (connectedPresence) {
        presence.disconnect(socket);
        if (incrementedMetrics) {
          wsConnections.dec();
          usersOnline.set(presence.getOnlineUsers().length);
        }
      }
      // Release local room listeners if no local sockets remain
      if (joinedRoomId) {
        await this.releaseRoomIfEmpty(joinedRoomId).catch(() => {});
      }
      // P0-22/P1-27: distributed cleanup (Redis presence + event bus publish)
      // with bounded timeout — don't let Redis hang block local cleanup.
      if (presenceCountBumped && presenceBumpedFor) {
        const { roomId: prid, userId: puid, connectionId } = presenceBumpedFor;
        let cleanupSettled = false;
        const distributedCleanup = (async () => {
          const count = await this.decrementRoomPresence(prid, puid, connectionId).catch((err) => {
            // Аудит 26.07.2026 P2: молчаливый catch скрывал недоступность Redis —
            // participant.left не уходил, а в логах не было ни строки.
            console.warn(
              `[RealtimeGateway] presence decrement failed (room=${prid} user=${puid}):`,
              (err as Error).message,
            );
            return -1;
          });
          if (count === 0) {
            await this.eventBus
              .publish(prid, {
                kind: 'participant.left',
                roomId: prid,
                userId: puid,
                username: capturedUser?.username ?? 'unknown',
                timestampMs: Date.now(),
              })
              .catch(() => {});
          }
          cleanupSettled = true;
        })();
        // Bounded timeout — if Redis is down, log and move on. Presence
        // lease will expire naturally (60s TTL).
        await Promise.race([
          distributedCleanup,
          new Promise<void>((resolve) => setTimeout(resolve, 2000)),
        ]).catch(() => {});
        // Аудит 26.07.2026 P2: раньше «брошенный на полпути» decrement
        // проходил бесследно. Логируем: lease доживёт до истечения TTL,
        // participant.left в этом случае не публикуется.
        if (!cleanupSettled) {
          console.warn(
            `[RealtimeGateway] presence cleanup timed out after 2s (room=${prid} user=${puid}) — lease TTL will expire`,
          );
        }
      }
    };
    // P0-23: single 'close' listener for entire lifecycle. No replacement.
    socket.once('close', () => void finalize());
    // Error event logs and triggers close — does NOT do partial cleanup.
    socket.on('error', (err: Error) => {
      console.warn('[RealtimeGateway] socket error:', err.message);
      // socket error is followed by close — finalize runs there.
    });

    // ── GPT-5 BE-P0-06: Origin validation ───────────────────────────────
    // Reject WebSocket connections from unknown origins (CSRF protection).
    // Allow native iOS origins (null, app://, capacitor://, localhost) +
    // configured web origins via CORS_ORIGIN env.
    const origin = req.headers['origin'] as string | undefined;
    if (origin && origin !== 'null') {
      const allowedOrigins = (config.CORS_ORIGIN === '*')
        ? []  // dev mode — allow all
        : [
            ...(Array.isArray(config.CORS_ORIGIN) ? config.CORS_ORIGIN : [config.CORS_ORIGIN]),
            ...NATIVE_CLIENT_ORIGINS,
          ];
      if (allowedOrigins.length > 0 && !allowedOrigins.includes(origin)) {
        socket.close(4003, 'Origin not allowed');
        await finalize();
        return;
      }
    }

    // ── Auth via Sec-WebSocket-Protocol (runbook §2) ────────────────────
    const protocols = (req.headers['sec-websocket-protocol'] as string | undefined)
      ?.split(',')
      .map((s) => s.trim()) ?? [];
    const ticket = protocols.find((p) => p.startsWith('plink.ticket.'));

    if (!ticket) {
      socket.close(4001, 'Missing plink ticket in Sec-WebSocket-Protocol');
      await finalize();
      return;
    }

    let ticketPayload: {
      userId: string;
      username: string;
      role: string;
      roomId: string;
      isHost: boolean;
    };
    try {
      ticketPayload = await this.verifyTicket(ticket);
    } catch (err) {
      socket.close(4001, `Ticket invalid: ${(err as Error).message}`);
      await finalize();
      return;
    }

    // Banned check
    const user = await this.deps.prisma.user.findUnique({
      where: { id: ticketPayload.userId },
      select: { id: true, username: true, role: true, bannedUntil: true },
    });
    if (!user) {
      socket.close(4001, 'User not found');
      await finalize();
      return;
    }
    if (user.bannedUntil && user.bannedUntil > new Date()) {
      socket.close(4003, 'User banned');
      await finalize();
      return;
    }

    socket.userId = user.id;
    socket.username = user.username;
    socket.role = user.role;
    socket.isAlive = true;
    capturedUser = { id: user.id, username: user.username };  // for finalize

    // ── Parse roomId from URL path (NOT query) ──────────────────────────
    const url = new URL(req.url, 'http://localhost');
    const pathParts = url.pathname.split('/').filter(Boolean);
    let wsRoomId: string | undefined;
    if (pathParts.length >= 3 && pathParts[1] === 'room') {
      wsRoomId = pathParts[2];
    }
    if (!wsRoomId) {
      wsRoomId = url.searchParams.get('roomId') ?? undefined;
    }

    // ── User-level DM channel ('@me' ticket) — no room binding ─────────
    if (ticketPayload.roomId === '@me') {
      socket.userId = user.id;
      socket.username = user.username;
      presence.connect(socket, user.id, user.username);
      wsConnections.inc();
      usersOnline.set(presence.getOnlineUsers().length);
      connectedPresence = true;
      incrementedMetrics = true;
      this.registry.registerUser(socket);
      // finalize() only detaches registry for room sockets — handle here.
      socket.once('close', () => this.registry.disconnect(socket));
      socket.on('message', () => {
        // Inbound messages are not routed on the user channel.
        wsMessages.inc({ type: 'inbound', direction: 'in' });
      });
      socket.send(JSON.stringify({ type: 'session.ready', roomId: '@me', role: 'viewer', epoch: 0 }));
      return;
    }

    if (!wsRoomId) {
      sendError(socket, 'NO_ROOM', 'roomId required in WS path');
      socket.close(4001, 'roomId required');
      await finalize();
      return;
    }

    // P0-1: ticket is bound to roomId — WS path must match ticket.roomId.
    if (wsRoomId !== ticketPayload.roomId) {
      sendError(socket, 'ROOM_MISMATCH', 'Ticket roomId does not match WS path roomId');
      socket.close(4003, 'Ticket room mismatch');
      await finalize();
      return;
    }
    const roomId = wsRoomId;

    // P0-16: derive current role from DB, not stale ticket claim.
    // isMemberOrHost returns { allowed, isHost } from single DB check.
    const membership = await this.isMemberOrHost(user.id, roomId);
    if (!membership.allowed) {
      sendError(socket, 'NOT_MEMBER', 'User is not a member or host of this room');
      socket.close(4003, 'Not a room member or host');
      await finalize();
      return;
    }
    const currentIsHost = membership.isHost;

    // ── Commit presence + metrics (after all rejection paths) ───────────
    presence.connect(socket, user.id, user.username);
    wsConnections.inc();
    usersOnline.set(presence.getOnlineUsers().length);
    connectedPresence = true;
    incrementedMetrics = true;

    this.registry.join(socket, roomId);
    presence.joinRoom(socket, roomId);
    joinedRoomId = roomId;

    // P0-2: retain ONE pubsub listener for this room on this replica.
    try {
      await this.retainRoom(roomId);
      retainedRoom = true;
    } catch (err) {
      sendError(socket, 'PUBSUB_FAILED', `Failed to subscribe: ${(err as Error).message}`);
      socket.close(1011, 'PubSub subscribe failed');
      await finalize();
      return;
    }

    // P0-22/P1-12/P0-24/P0-25: Redis ZSET presence leases with proper cleanup tracking.
    // If bumpRoomPresence succeeds but eventBus.publish throws, finalize()
    // will decrement the count — no stale presence.
    try {
      const presence = await this.bumpRoomPresence(roomId, user.id);
      // P0-25: store connectionId on socket so heartbeat can refresh lease
      socket.connectionId = presence.connectionId;
      presenceCountBumped = true;  // P0-22: track for cleanup
      presenceBumpedFor = { roomId, userId: user.id, connectionId: presence.connectionId };
      if (presence.count === 1) {
        const joinTimestamp = Date.now();
        try {
          await this.eventBus.publish(roomId, {
            kind: 'participant.joined',
            roomId,
            userId: user.id,
            username: user.username,
            timestampMs: joinTimestamp,  // P1-22/P1-26: preserve original timestamp
          });
        } catch (publishErr) {
          // P0-22: publish failed — finalize() will decrement presence count
          console.error('[RealtimeGateway] participant.joined publish failed:', publishErr);
          sendError(socket, 'PUBLISH_FAILED', 'Failed to announce join');
          socket.close(1011, 'Join publish failed');
          await finalize();
          return;
        }
      }
    } catch (bumpErr) {
      // P0-22: bumpRoomPresence itself failed — no presence to clean up
      console.error('[RealtimeGateway] bumpRoomPresence failed:', bumpErr);
      sendError(socket, 'PRESENCE_FAILED', 'Failed to track presence');
      socket.close(1011, 'Presence tracking failed');
      await finalize();
      return;
    }

    // P0-16: session.ready role from CURRENT DB state, not ticket claim.
    socket.send(JSON.stringify(makeSessionReady(roomId, currentIsHost ? 'host' : 'viewer')));

    socket.on('message', (raw: Buffer) => {
      wsMessages.inc({ type: 'inbound', direction: 'in' });
      this.router.handleMessage(socket, raw).catch((err) => {
        console.error('[RealtimeGateway] router error:', err);
        sendError(socket, 'INTERNAL', 'Internal server error');
      });
    });

    // P0-23: NO removeAllListeners. The single socket.once('close', finalize)
    // registered at the top handles all cleanup — including presence
    // decrement and participant.left publish. No late handler replacement.
  }

  /** DM fanout: deliver an event to all of a user's sockets on this replica. */
  notifyUser(userId: string, payload: unknown): number {
    try {
      return this.registry.sendToUser(userId, payload);
    } catch {
      return 0;
    }
  }

  // ── P0-24: Redis ZSET connection leases with heartbeat refresh ────────
  // Each connection gets a unique connectionId (UUID). ZSET member is the
  // connectionId; score is leaseExpiresAtMs. Heartbeat refreshes the lease.
  // Atomic Lua: remove expired members + count active.
  private static readonly PRESENCE_LEASE_TTL_MS = 60_000;  // 60s, refreshed by heartbeat
  private static readonly PRESENCE_LEASE_KEY = (roomId: string, userId: string) =>
    `plink:presence:${roomId}:${userId}`;

  private async bumpRoomPresence(roomId: string, userId: string): Promise<{ count: number; connectionId: string }> {
    const connectionId = randomUUID();
    const key = RealtimeGateway.PRESENCE_LEASE_KEY(roomId, userId);
    const roomIndexKey = `plink:room:${roomId}:activeUsers`;
    const now = Date.now();
    const expiresAt = now + RealtimeGateway.PRESENCE_LEASE_TTL_MS;
    // P0-56: maintain BOTH per-user ZSET and room-level index ZSET
    const pipeline = this.deps.redis.multi();
    pipeline.zremrangebyscore(key, '-inf', now);  // remove expired from user key
    pipeline.zadd(key, expiresAt, connectionId);   // add new connection
    pipeline.pexpire(key, RealtimeGateway.PRESENCE_LEASE_TTL_MS * 2);
    pipeline.zcount(key, now, '+inf');              // count active connections
    // P0-56: update room-level index — userId → latestLeaseExpiresAtMs
    pipeline.zadd(roomIndexKey, expiresAt, userId);
    pipeline.pexpire(roomIndexKey, RealtimeGateway.PRESENCE_LEASE_TTL_MS * 2);
    const results = await pipeline.exec();
    const count = results ? Number(results[3][1]) : 0;
    return { count, connectionId };
  }

  // Аудит 26.07.2026 P2: снятие lease было неатомарным (ZREM, потом ZCOUNT
  // отдельными командами) — два одновременно закрывающихся сокета одного
  // юзера могли ОБА увидеть count 0 и оба опубликовать participant.left.
  // Теперь ровно один вызывающий получает 0: удаление, чистка просроченных,
  // подсчёт и обновление room-index — внутри одного EVAL.
  //   KEYS[1] = plink:presence:<roomId>:<userId>
  //   KEYS[2] = plink:room:<roomId>:activeUsers
  //   ARGV[1] = now (ms), ARGV[2] = connectionId ('' → снять все), ARGV[3] = userId
  private static readonly DECREMENT_PRESENCE = `
local key = KEYS[1]
local indexKey = KEYS[2]
local now = ARGV[1]
local connectionId = ARGV[2]
local userId = ARGV[3]
if connectionId ~= '' then
  redis.call('ZREM', key, connectionId)
else
  redis.call('DEL', key)
end
redis.call('ZREMRANGEBYSCORE', key, '-inf', now)
local count = redis.call('ZCOUNT', key, now, '+inf')
if count == 0 then
  redis.call('DEL', key)
  redis.call('ZREM', indexKey, userId)
  return 0
end
local remaining = redis.call('ZRANGEBYSCORE', key, now, '+inf', 'WITHSCORES')
local maxExpiry = 0
local maxExpiryRaw = nil
for i = 2, #remaining, 2 do
  local score = tonumber(remaining[i])
  if score and score > maxExpiry then
    maxExpiry = score
    maxExpiryRaw = remaining[i]
  end
end
if maxExpiryRaw then
  redis.call('ZADD', indexKey, maxExpiryRaw, userId)
end
return count
`;

  private async decrementRoomPresence(roomId: string, userId: string, connectionId?: string): Promise<number> {
    const key = RealtimeGateway.PRESENCE_LEASE_KEY(roomId, userId);
    const roomIndexKey = `plink:room:${roomId}:activeUsers`;
    const count = (await this.deps.redis.eval(
      RealtimeGateway.DECREMENT_PRESENCE,
      2,
      key,
      roomIndexKey,
      String(Date.now()),
      connectionId ?? '',
      userId,
    )) as number;
    return Number(count);
  }

  // P0-24: refresh presence lease on heartbeat — called from Heartbeat class
  async refreshPresenceLease(roomId: string, userId: string, connectionId: string): Promise<void> {
    const key = RealtimeGateway.PRESENCE_LEASE_KEY(roomId, userId);
    const roomIndexKey = `plink:room:${roomId}:activeUsers`;
    const expiresAt = Date.now() + RealtimeGateway.PRESENCE_LEASE_TTL_MS;
    // P0-56: refresh BOTH per-user ZSET and room-level index
    const pipeline = this.deps.redis.multi();
    pipeline.zadd(key, expiresAt, connectionId);
    pipeline.pexpire(key, RealtimeGateway.PRESENCE_LEASE_TTL_MS * 2);
    pipeline.zadd(roomIndexKey, expiresAt, userId);
    pipeline.pexpire(roomIndexKey, RealtimeGateway.PRESENCE_LEASE_TTL_MS * 2);
    await pipeline.exec();
  }

  // ── P0-2 + GPT-5 BE-P0-02: ref-counted room listeners with race-free retain/release ──
  //
  // GPT-5 BE-P0-02: previous Map.has() then awaited subscribe() pattern was
  // race-prone under concurrent joins. Now we store the in-flight promise and
  // reference count before awaiting. This guarantees exactly one Redis
  // subscription pair per room per replica, even under 100 concurrent joins.
  private roomRefs = new Map<string, number>();
  private roomRetainInFlight = new Map<string, Promise<void>>();
  // Аудит 26.07.2026 P1: явный признак «подписка реально установлена».
  // roomListeners заполняется ДО await внутри doRetainRoom, поэтому сам по
  // себе он не доказывает завершённую Redis-подписку.
  private readonly roomSubscribed = new Set<string>();

  private async retainRoom(roomId: string): Promise<void> {
    // GPT-5 BE-P0-02: increment ref count FIRST, before any async work.
    const currentRefs = this.roomRefs.get(roomId) ?? 0;
    this.roomRefs.set(roomId, currentRefs + 1);

    // Аудит 26.07.2026 P1: быстрый выход только если подписка РЕАЛЬНО
    // установлена. Раньше `currentRefs > 0` отпускал второй конкурентный
    // join до завершения in-flight подписки (session.ready до fanout), а
    // ошибка doRetainRoom навсегда отравляла refcount — комната на реплике
    // оставалась без fanout до полного опустошения.
    if (this.roomSubscribed.has(roomId)) return;

    let inFlight = this.roomRetainInFlight.get(roomId);
    if (!inFlight) {
      inFlight = this.doRetainRoom(roomId)
        .then(() => {
          this.roomSubscribed.add(roomId);
        })
        .catch((err) => {
          // Откат частично созданных листенеров — следующий join повторит subscribe.
          this.rollbackPartialRetain(roomId);
          throw err;
        })
        .finally(() => {
          this.roomRetainInFlight.delete(roomId);
        });
      this.roomRetainInFlight.set(roomId, inFlight);
    }
    // Все конкурентные join ждут фактического завершения подписки; ошибка
    // пробрасывается каждому — их сокеты закроются, finalize откатит refs.
    await inFlight;
  }

  // Аудит 26.07.2026 P1: убрать листенеры, созданные упавшим doRetainRoom,
  // чтобы повторный retain заново выполнил Redis SUBSCRIBE.
  private rollbackPartialRetain(roomId: string): void {
    this.roomSubscribed.delete(roomId);
    const stateListener = this.roomListeners.get(roomId);
    if (stateListener) {
      this.roomListeners.delete(roomId);
      void this.pubsub.unsubscribe(roomId, stateListener).catch(() => {});
    }
    const eventListener = this.roomEventListeners.get(roomId);
    if (eventListener) {
      this.roomEventListeners.delete(roomId);
      void this.eventBus.unsubscribe(roomId, eventListener).catch(() => {});
    }
  }

  private async doRetainRoom(roomId: string): Promise<void> {
    if (!this.roomListeners.has(roomId)) {
      const listener: RoomStateListener = (state) => {
        const msg: ServerMessage = {
          type: 'sync.state',
          protocolVersion: 2,
          roomId,
          state,
          serverTimeMs: Date.now(),
        };
        this.registry.broadcastLocal(roomId, msg);
      };
      this.roomListeners.set(roomId, listener);
      await this.pubsub.subscribe(roomId, listener);
    }

    if (!this.roomEventListeners.has(roomId)) {
      const eventListener: RoomEventListener = (event) => {
        // Аудит 26.07.2026 P1: кик — закрываем локальные сокеты кикнутого,
        // а не броадкастим (отзыв доступа, presence чистит finalize).
        if (event.kind === 'participant.kicked') {
          this.closeKickedSockets(event.roomId, event.userId);
          return;
        }
        const msg = eventToServerMessage(event);
        if (msg) this.registry.broadcastLocal(roomId, msg);
      };
      this.roomEventListeners.set(roomId, eventListener);
      await this.eventBus.subscribe(roomId, eventListener);
    }
  }

  private async releaseRoomIfEmpty(roomId: string): Promise<void> {
    // GPT-5 BE-P0-02: decrement ref count. Only unsubscribe when refs hit 0.
    const currentRefs = this.roomRefs.get(roomId) ?? 0;
    if (currentRefs > 1) {
      this.roomRefs.set(roomId, currentRefs - 1);
      return;
    }

    // Refs would hit 0 — wait for any in-flight retain first.
    // Аудит 26.07.2026 P1: ошибка чужого in-flight retain не должна ронять release.
    const inFlight = this.roomRetainInFlight.get(roomId);
    if (inFlight) {
      await inFlight.catch(() => {});
    }

    // Re-check ref count after waiting (a concurrent retain may have incremented).
    const refsAfterWait = this.roomRefs.get(roomId) ?? 0;
    if (refsAfterWait > 1) {
      this.roomRefs.set(roomId, refsAfterWait - 1);
      return;
    }

    // Refs hit 0 — safe to unsubscribe.
    this.roomRefs.set(roomId, 0);

    // Double-check no local sockets remain.
    if (this.registry.getRoomSockets(roomId).length > 0) return;

    // Аудит 26.07.2026 P1: снимаем признак установленной подписки при teardown
    this.roomSubscribed.delete(roomId);
    const stateListener = this.roomListeners.get(roomId);
    if (stateListener) {
      this.roomListeners.delete(roomId);
      await this.pubsub.unsubscribe(roomId, stateListener);
    }
    const eventListener = this.roomEventListeners.get(roomId);
    if (eventListener) {
      this.roomEventListeners.delete(roomId);
      await this.eventBus.unsubscribe(roomId, eventListener);
    }
  }

  async publishChatMessage(event: Extract<RoomEvent, { kind: 'chat.broadcast' }>): Promise<void> {
    await this.eventBus.publish(event.roomId, event);
  }

  /**
   * Аудит 26.07.2026 P2: живая доставка темы комнаты. rooms.ts после успешного
   * сохранения appearance зовёт этот метод; событие уходит в RoomEventBus, и
   * каждая реплика с сокетами комнаты сама рассылает room.appearance.updated
   * своим клиентам (публикатор НЕ шлёт локально — иначе двойная доставка).
   */
  async publishRoomAppearance(event: Extract<RoomEvent, { kind: 'room.appearance.updated' }>): Promise<void> {
    await this.eventBus.publish(event.roomId, event);
  }

  /**
   * Аудит 26.07.2026 P1: отзыв WS-доступа при кике. rooms.ts раньше звал
   * несуществующий broadcastToRoom (no-op за optional chaining) — сокет
   * кикнутого оставался в ConnectionRegistry и продолжал получать
   * chat.broadcast/sync.state. Публикуем типизированное событие через
   * RoomEventBus; каждая реплика с сокетами комнаты закрывает локальные
   * сокеты этого userId (код 4003), presence-lease чистит finalize по close.
   */
  async kickUser(roomId: string, userId: string, byUserId: string): Promise<void> {
    await this.eventBus.publish(roomId, {
      kind: 'participant.kicked',
      roomId,
      userId,
      byUserId,
      timestampMs: Date.now(),
    });
  }

  // Аудит 26.07.2026 P1: закрыть локальные сокеты кикнутого пользователя
  private closeKickedSockets(roomId: string, userId: string): void {
    for (const s of this.registry.getRoomSockets(roomId)) {
      if (s.userId !== userId) continue;
      try {
        s.close(4003, 'Kicked from room');
      } catch {
        /* noop */
      }
    }
  }

  // ── P0-16: isMemberOrHost returns { allowed, isHost } from single DB check ─
  private async isMemberOrHost(userId: string, roomId: string): Promise<{ allowed: boolean; isHost: boolean }> {
    const [participant, room] = await Promise.all([
      this.deps.prisma.roomParticipant
        .findUnique({
          where: { roomID_userID: { roomID: roomId, userID: userId } },
          select: { id: true },
        })
        .catch(() => null),
      this.deps.prisma.room.findUnique({
        where: { id: roomId },
        select: { hostID: true, isActive: true },
      }),
    ]);
    if (!room || !room.isActive) return { allowed: false, isHost: false };
    const isHost = room.hostID === userId;
    const isMember = participant !== null;
    return { allowed: isHost || isMember, isHost };
  }

  private async verifyTicket(ticket: string): Promise<{
    userId: string;
    username: string;
    role: string;
    roomId: string;
    isHost: boolean;
  }> {
    const token = ticket.substring('plink.ticket.'.length);
    const payload = this.deps.fastify.jwt.verify(token) as {
      id: string;
      username: string;
      role: string;
      roomId: string;
      nonce: string;
      host?: boolean;
      typ?: string;
    };
    if (payload.typ !== 'realtime_ticket') {
      throw new Error('not a realtime ticket');
    }
    if (!payload.roomId || !payload.nonce) {
      throw new Error('ticket missing roomId or nonce');
    }
    const ok = await this.deps.redis.del(`plink:ticket:${payload.id}:${payload.nonce}`);
    if (ok === 0) throw new Error('ticket already used or expired');
    return {
      userId: payload.id,
      username: payload.username,
      role: payload.role,
      roomId: payload.roomId,
      isHost: payload.host === true,
    };
  }

  /** Graceful shutdown (runbook §5, P1-6). */
  async shutdown(): Promise<void> {
    this.shuttingDown = true;
    this.heartbeat.close();

    // P1-20: typed ServerDraining message (was inline JSON)
    const drainMessage: ServerMessage = {
      type: 'server.draining',
      protocolVersion: 2,
      message: 'Server shutting down — please reconnect',
      retryInMs: 2000,
    };
    const encoded = JSON.stringify(drainMessage);
    for (const sock of this.deps.wss.clients) {
      const s = sock as PlinkSocket;
      if (s.readyState === s.OPEN) {
        try {
          s.send(encoded);
        } catch {}
      }
    }

    const drainDeadline = Date.now() + 10_000;
    while (Date.now() < drainDeadline) {
      if (this.deps.wss.clients.size === 0) break;
      await new Promise((r) => setTimeout(r, 250));
    }

    for (const sock of this.deps.wss.clients) {
      const s = sock as PlinkSocket;
      try {
        s.close(1001, 'Server shutting down');
      } catch {}
    }
    await Promise.allSettled([this.pubsub.close(), this.eventBus.close()]);
  }
}

/**
 * Событие шины → wire-сообщение протокола v2.
 *
 * Аудит 26.07.2026 P2: раньше это был приватный метод класса, и единственный
 * способ его «проверить» был ручной копией в тесте — то есть тест зеленел даже
 * когда реальный маппинг ломался. Функция чистая (никакого this), поэтому
 * вынесена на уровень модуля и экспортируется: контрактные тесты гоняют
 * НАСТОЯЩИЙ код и парсят его результат ServerMessageSchema.
 */
export function eventToServerMessage(event: RoomEvent): ServerMessage | null {
  switch (event.kind) {
    case 'participant.joined':
      // P1-26: preserve original event timestampMs
      return makeParticipantEvent('participant.joined', event.roomId, event.userId, event.username, event.timestampMs);
    case 'participant.left':
      return makeParticipantEvent('participant.left', event.roomId, event.userId, event.username, event.timestampMs);
    case 'chat.broadcast':
      return {
        type: 'chat.broadcast',
        protocolVersion: 2,
        roomId: event.roomId,
        messageId: event.messageId,
        clientMessageId: event.clientMessageId ?? null,
        senderId: event.senderId,
        senderName: event.senderName,
        text: event.text,
        createdAtMs: event.createdAtMs,
        mediaType: event.mediaType ?? null,
        hasMedia: event.hasMedia ?? false,
      };
    case 'reaction.broadcast':
      return {
        type: 'reaction.broadcast',
        protocolVersion: 2,
        roomId: event.roomId,
        userId: event.userId,
        username: event.username,
        emoji: event.emoji,
        serverTimeMs: event.serverTimeMs,
      };
    case 'room.appearance.updated':
      // Аудит 26.07.2026 P2: живая тема комнаты. Событие приходит из шины на
      // ВСЕ реплики, каждая разворачивает плоские поля в wire-формат v2 и
      // отдаёт своим локальным сокетам — хост больше не единственный, кто
      // видит новую тему до перезахода в комнату.
      return {
        type: 'room.appearance.updated',
        protocolVersion: 2,
        roomId: event.roomId,
        appearance: {
          themeId: event.themeId,
          themeRevision: event.themeRevision,
          intensity: event.intensity,
          motionEnabled: event.motionEnabled,
        },
        serverTimeMs: event.serverTimeMs,
      };
    default:
      return null;
  }
}

function sendError(socket: PlinkSocket, code: string, message: string): void {
  if (socket.readyState !== socket.OPEN) return;
  socket.send(
    JSON.stringify({
      type: 'error',
      protocolVersion: 2,
      code,
      message,
    }),
  );
}
