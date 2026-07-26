// src/tests/integration/roomEventBus.integration.test.ts
// Brain Review P0-3 regression tests
//
// Verifies:
//   - published event reaches subscriber on same replica
//   - published event reaches subscriber on a SECOND subscriber instance
//   - listener is NOT called after unsubscribe (leak prevention)
//   - publishing to room A does NOT deliver to room B subscriber
//
// Requires Redis on REDIS_URL (default 6380 to match docker-compose.yml).

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { randomUUID } from 'node:crypto';
import { RoomEventBus } from '../../realtime/roomEventBus.js';

const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6380';
const VALID_UUID = () => randomUUID();

// P0-25 fix: check Redis availability at TOP LEVEL (not in beforeAll).
// describe.skipIf reads the value synchronously at declaration time —
// beforeAll runs later, so redisOk would still be false.
// Top-level IIFE sets redisOk before describe.skipIf is evaluated.
let redisOk = false;
try {
  // Synchronous probe — use a child process or just try ioredis synchronously
  // ioredis is async, so we use a top-level await via IIFE
  await (async () => {
    const probe = new (await import('ioredis')).default(REDIS_URL, {
      maxRetriesPerRequest: 1,
      lazyConnect: true,
    });
    await probe.connect();
    await probe.ping();
    await probe.quit();
    redisOk = true;
  })();
} catch {
  redisOk = false;
}

describe.skipIf(!redisOk)('RoomEventBus cross-replica distribution (P0-3 regression)', () => {
  it('event published on replica A reaches subscriber on replica B', async () => {
    const replicaA = new RoomEventBus(REDIS_URL);
    const replicaB = new RoomEventBus(REDIS_URL);
    const roomId = VALID_UUID();
    const received: string[] = [];
    await replicaB.subscribe(roomId, (event) => {
      if (event.kind === 'chat.broadcast') {
        received.push(event.text);
      }
    });
    await new Promise((r) => setTimeout(r, 100));
    await replicaA.publish(roomId, {
      kind: 'chat.broadcast',
      roomId,
      messageId: 'm1',
      clientMessageId: null,
      senderId: VALID_UUID(),
      senderName: 'tester',
      text: 'hello from A',
      createdAtMs: Date.now(),
    });
    await new Promise((r) => setTimeout(r, 200));
    expect(received).toEqual(['hello from A']);
    await replicaA.close();
    await replicaB.close();
  });

  it('listener is not called after unsubscribe (no leak)', async () => {
    const bus = new RoomEventBus(REDIS_URL);
    const roomId = VALID_UUID();
    const received: string[] = [];
    const listener = (event: any) => {
      if (event.kind === 'chat.broadcast') received.push(event.text);
    };
    await bus.subscribe(roomId, listener);
    await bus.unsubscribe(roomId, listener);
    await new Promise((r) => setTimeout(r, 100));
    await bus.publish(roomId, {
      kind: 'chat.broadcast',
      roomId,
      messageId: 'm2',
      clientMessageId: null,
      senderId: VALID_UUID(),
      senderName: 'tester',
      text: 'should not arrive',
      createdAtMs: Date.now(),
    });
    await new Promise((r) => setTimeout(r, 200));
    expect(received).toEqual([]);
    await bus.close();
  });

  it('event for room A does not deliver to room B subscriber', async () => {
    const bus = new RoomEventBus(REDIS_URL);
    const roomA = VALID_UUID();
    const roomB = VALID_UUID();
    const receivedA: string[] = [];
    const receivedB: string[] = [];
    await bus.subscribe(roomA, (e) => {
      if (e.kind === 'chat.broadcast') receivedA.push(e.text);
    });
    await bus.subscribe(roomB, (e) => {
      if (e.kind === 'chat.broadcast') receivedB.push(e.text);
    });
    await new Promise((r) => setTimeout(r, 100));
    await bus.publish(roomA, {
      kind: 'chat.broadcast',
      roomId: roomA,
      messageId: 'm3',
      clientMessageId: null,
      senderId: VALID_UUID(),
      senderName: 'tester',
      text: 'only for A',
      createdAtMs: Date.now(),
    });
    await new Promise((r) => setTimeout(r, 200));
    expect(receivedA).toEqual(['only for A']);
    expect(receivedB).toEqual([]);
    await bus.close();
  });
});
