// src/config/redis.ts — Redis client (опциональный, с graceful fallback)
import Redis from 'ioredis';
import { config } from './index.js';

let redisClient: Redis | null = null;

if (config.REDIS_URL) {
  try {
    redisClient = new Redis(config.REDIS_URL, {
      maxRetriesPerRequest: 3,
      enableReadyCheck: true,
      lazyConnect: false,
      retryStrategy: (times) => {
        if (times > 3) {
          console.warn('[Redis] Giving up after 3 retries — running without cache');
          return null;
        }
        return Math.min(times * 200, 1000);
      },
    });

    redisClient.on('connect', () => console.log('✅ Redis connected'));
    redisClient.on('error', (err) => console.warn('[Redis] error:', err.message));
  } catch (e: any) {
    console.warn('[Redis] init failed, running without cache:', e.message);
    redisClient = null;
  }
}

export const redis = redisClient;

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
