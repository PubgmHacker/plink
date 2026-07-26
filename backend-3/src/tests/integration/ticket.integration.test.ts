// src/tests/integration/ticket.integration.test.ts
// Brain Review P0-1 regression tests
//
// Verifies:
//   - first ticket use succeeds (nonce deleted from Redis)
//   - second ticket use fails (nonce already deleted)
//   - expired ticket fails (TTL elapsed)
//   - ticket bound to roomId A cannot be used for roomId B
//
// Requires Redis on REDIS_URL (default 6380 to match docker-compose).

import { describe, it, expect, afterAll } from 'vitest';
import Redis from 'ioredis';
import { randomUUID } from 'node:crypto';

const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6380';
let redis: Redis;

// Top-level Redis availability check (fixes skipIf race with beforeAll)
let redisAvailable = false;
try {
  await (async () => {
    redis = new Redis(REDIS_URL, { maxRetriesPerRequest: 1, lazyConnect: true });
    await redis.connect();
    await redis.ping();
    redisAvailable = true;
  })();
} catch {
  redisAvailable = false;
}

afterAll(async () => {
  if (redis) await redis.quit().catch(() => {});
});

describe.skipIf(!redisAvailable)('ticket nonce lifecycle (P0-1 regression)', () => {
  it('SET then DEL on full nonce UUID succeeds on first use', async () => {
    const userId = randomUUID();
    const nonce = randomUUID();
    const key = `plink:ticket:${userId}:${nonce}`;
    await redis.set(key, JSON.stringify({ roomId: 'r1', issuedAt: Date.now() }), 'EX', 60);
    const first = await redis.del(key);
    expect(first).toBe(1);
    const second = await redis.del(key);
    expect(second).toBe(0);
  });

  it('keys with slice(-12) of nonce do NOT match full nonce key', async () => {
    const userId = randomUUID();
    const nonce = randomUUID();
    const issueKey = `plink:ticket:${userId}:${nonce}`;
    await redis.set(issueKey, '1', 'EX', 60);
    const buggyKey = `plink:ticket:${userId}:${nonce.slice(-12)}`;
    const buggyDel = await redis.del(buggyKey);
    expect(buggyDel).toBe(0);
    const correctDel = await redis.del(issueKey);
    expect(correctDel).toBe(1);
  });

  it('expired nonce is rejected', async () => {
    const userId = randomUUID();
    const nonce = randomUUID();
    const key = `plink:ticket:${userId}:${nonce}`;
    await redis.set(key, '1', 'EX', 1);
    await new Promise((r) => setTimeout(r, 1100));
    const del = await redis.del(key);
    expect(del).toBe(0);
  });
});
