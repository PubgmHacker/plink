// src/config/redis.ts — Redis client (опциональный, с graceful fallback)
import Redis from 'ioredis';
import { config } from './index.js';

let redisClient: Redis | null = null;

// Flipped by server.ts right before it quit()s the clients at shutdown, so the
// 'end' watchdog below can tell an intentional close from a permanent failure.
let redisShuttingDown = false;
export function markRedisShuttingDown(): void {
  redisShuttingDown = true;
}

if (config.REDIS_URL) {
  try {
    redisClient = new Redis(config.REDIS_URL, {
      maxRetriesPerRequest: 3,
      enableReadyCheck: true,
      lazyConnect: false,
      // Never null: returning a non-number makes ioredis close() the client
      // PERMANENTLY, and this client is not a cache — it is the realtime
      // substrate (WS ticket nonces, presence leases, room state). A permanent
      // give-up turns the instance into a zombie that rejects every handshake
      // and join until a redeploy, and the likeliest trigger is an ordinary
      // cold start where the app container comes up before Redis does.
      // Individual commands still fail fast via maxRetriesPerRequest: 3.
      retryStrategy: (times) => Math.min(times * 200, 5000),
    });

    redisClient.on('connect', () => console.log('✅ Redis connected'));
    redisClient.on('error', (err) => console.warn('[Redis] error:', err.message));
    // 'end' fires only when ioredis gives up for good (it cannot with the
    // retryStrategy above, but a future edit could break that). A dead command
    // client means every WS handshake and room join fails while /health/live
    // keeps answering 200 — so in production, exit and let Railway's
    // ON_FAILURE policy recycle the container instead of serving errors.
    redisClient.on('end', () => {
      if (redisShuttingDown) return;
      console.error('[Redis] connection ended permanently — command client is dead');
      if (config.isProduction) process.exit(1);
    });
  } catch (e: any) {
    console.warn('[Redis] init failed, running without cache:', e.message);
    redisClient = null;
  }
}

export const redis = redisClient;

// A SECOND connection, for @fastify/rate-limit only.
//
// Two reasons it is not the shared client above. First, the limiter runs in the
// request path on every rate-limited route, and the shared client is tuned for
// throughput — `maxRetriesPerRequest: 3` with a backoff up to 1s means a Redis
// blip makes the limiter check *wait* before it can answer, adding latency to the
// very requests it is meant to shed. This connection fails fast instead: one
// retry, a 500ms connect timeout, and `enableOfflineQueue: false` so a command
// issued while disconnected errors immediately rather than queueing until the
// socket returns. Second, ioredis serialises commands on one socket, so limiter
// traffic on the shared client would queue behind realtime fan-out at exactly the
// moment load is highest.
//
// `enableOfflineQueue: false` has a consequence the caller must handle: commands
// issued before this socket reaches `ready` reject, and the limiter is registered
// with `skipOnError: true`, so those requests go *unlimited* rather than being
// counted. buildApp() therefore waits (bounded, 3s) for this client's `ready`
// event before registering the plugin. A ping cannot do that job — with the
// offline queue disabled it rejects instantly while the socket is connecting.
// Do not remove that wait thinking it is a health check — it is what closes the
// unlimited window at boot.
//
// `null` when REDIS_URL is unset, which is only reachable outside production:
// buildApp() throws on a missing REDIS_URL when isProduction.
let rateLimitClient: Redis | null = null;

if (config.REDIS_URL) {
  try {
    rateLimitClient = new Redis(config.REDIS_URL, {
      connectionName: 'plink-rate-limit',
      connectTimeout: 500,
      maxRetriesPerRequest: 1,
      enableOfflineQueue: false,
      enableReadyCheck: true,
      lazyConnect: false,
      // Never null: giving up permanently would leave the limiter dead (and, with
      // skipOnError, all limits off) until a redeploy. Reconnection attempts do not
      // slow requests down — enableOfflineQueue:false already rejects commands
      // instantly while disconnected. Capped at 1s so recovery after an outage is fast.
      retryStrategy: (times) => Math.min(times * 200, 1000),
    });

    // Logged at warn, not error: skipOnError means this is a degradation
    // (the affected request is allowed without a counter), not an outage.
    rateLimitClient.on('error', (err) =>
      console.warn('[Redis:rate-limit] error, affected requests are not counted:', err.message),
    );
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.warn('[Redis:rate-limit] init failed, affected requests are not counted:', message);
    rateLimitClient = null;
  }
}

export const rateLimitRedis = rateLimitClient;

// Helper: cached get/set with JSON serialization
export async function cacheGet<T>(key: string): Promise<T | null> {
  if (!redisClient) return null;
  try {
    const raw = await redisClient.get(key);
    if (!raw) return null;
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

export async function cacheSet<T>(key: string, value: T, ttlSeconds = 30): Promise<void> {
  if (!redisClient) return;
  try {
    await redisClient.setex(key, ttlSeconds, JSON.stringify(value));
  } catch (e: any) {
    console.warn('[Redis] setex failed:', e.message);
  }
}

export async function cacheDel(key: string): Promise<void> {
  if (!redisClient) return;
  try {
    await redisClient.del(key);
  } catch (e: any) {
    console.warn('[Redis] del failed:', e.message);
  }
}

export async function checkRedis(): Promise<boolean> {
  if (!redisClient) return false;
  try {
    const pong = await redisClient.ping();
    return pong === 'PONG';
  } catch {
    return false;
  }
}
