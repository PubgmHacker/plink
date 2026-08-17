// src/tests/integration/roomStateStore.integration.test.ts
// Integration tests for RoomStateStore against a real Redis (runbook §12)
//
// Test cases from runbook §12:
//   - Duplicate actionId не увеличивает seq
//   - Outdated epoch отклоняется
//   - Late join получает актуальное media state
//   - stateRequest возвращает state
//
// Requires a running Redis on REDIS_URL (default 6380 to match docker-compose).

import { describe, it, expect, afterAll, beforeEach } from 'vitest';
import Redis from 'ioredis';
import { RoomStateStore } from '../../realtime/roomStateStore.js';

const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6380';
let redis: Redis;
let store: RoomStateStore;

// Top-level Redis availability check (fixes skipIf race with beforeAll)
let redisAvailable = false;
try {
  await (async () => {
    redis = new Redis(REDIS_URL, { maxRetriesPerRequest: 1, lazyConnect: true });
    await redis.connect();
    await redis.ping();
    store = new RoomStateStore(redis);
    redisAvailable = true;
  })();
} catch {
  redisAvailable = false;
}

afterAll(async () => {
  if (redis) await redis.quit().catch(() => {});
});

beforeEach(async () => {
  if (!redisAvailable) return;
  await redis.del('room:test-room:state');
  const keys = await redis.keys('room:test-room:action:*');
  if (keys.length > 0) await redis.del(...keys);
});

describe.skipIf(!redisAvailable)('RoomStateStore integration', () => {
  const ROOM_ID = 'test-room';
  const USER_ID = '00000000-0000-4000-8000-000000000001';

  it('apply() returns applied=true on first call', async () => {
    const result = await store.apply({
      roomId: ROOM_ID,
      actionId: '00000000-0000-4000-8000-000000000001',
      epoch: 1,
      mediaId: 'yt:abc',
      positionMs: 1000,
      playing: true,
      rate: 1,
      issuedBy: USER_ID,
    });
    expect(result.kind).toBe('applied');
    if (result.kind === 'applied') {
      expect(result.state.seq).toBe(1);
      expect(result.state.epoch).toBe(1);
      expect(result.state.playing).toBe(true);
    }
  });

  it('duplicate actionId does NOT increment seq (replay)', async () => {
    const actionId = '00000000-0000-4000-8000-000000000002';
    await store.apply({
      roomId: ROOM_ID,
      actionId,
      epoch: 1,
      mediaId: null,
      positionMs: 5000,
      playing: false,
      rate: 1,
      issuedBy: USER_ID,
    });
    const second = await store.apply({
      roomId: ROOM_ID,
      actionId,
      epoch: 1,
      mediaId: null,
      positionMs: 9999,
      playing: true,
      rate: 1,
      issuedBy: USER_ID,
    });
    expect(second.kind).toBe('replay');
    if (second.kind === 'replay' && second.state) {
      expect(second.state.seq).toBe(1);
      expect(second.state.positionMs).toBe(5000);
    }
  });

  it('outdated epoch is rejected (STALE_EPOCH)', async () => {
    await store.apply({
      roomId: ROOM_ID,
      actionId: '00000000-0000-4000-8000-000000000003',
      epoch: 5,
      mediaId: null,
      positionMs: 0,
      playing: true,
      rate: 1,
      issuedBy: USER_ID,
    });
    const result = await store.apply({
      roomId: ROOM_ID,
      actionId: '00000000-0000-4000-8000-000000000004',
      epoch: 4,
      mediaId: null,
      positionMs: 0,
      playing: true,
      rate: 1,
      issuedBy: USER_ID,
    });
    expect(result.kind).toBe('stale_epoch');
  });

  it('seq is monotonically incremented within (roomId, epoch)', async () => {
    const seqs: number[] = [];
    for (let i = 0; i < 5; i++) {
      const result = await store.apply({
        roomId: ROOM_ID,
        actionId: `00000000-0000-4000-8000-0000000000${10 + i}`,
        epoch: 1,
        mediaId: null,
        positionMs: i * 1000,
        playing: true,
        rate: 1,
        issuedBy: USER_ID,
      });
      if (result.kind === 'applied') seqs.push(result.state.seq);
    }
    expect(seqs).toEqual([1, 2, 3, 4, 5]);
  });

  it('get() returns null for empty room (late join with no host activity)', async () => {
    const state = await store.get('empty-room-' + Date.now());
    expect(state).toBeNull();
  });

  it('get() returns the latest applied state', async () => {
    await store.apply({
      roomId: ROOM_ID,
      actionId: '00000000-0000-4000-8000-000000000099',
      epoch: 1,
      mediaId: 'yt:late-join-test',
      positionMs: 42000,
      playing: true,
      rate: 1,
      issuedBy: USER_ID,
    });
    const state = await store.get(ROOM_ID);
    expect(state).not.toBeNull();
    expect(state!.mediaId).toBe('yt:late-join-test');
    expect(state!.positionMs).toBe(42000);
    expect(state!.playing).toBe(true);
  });

  it('bumpEpoch() returns current+1', async () => {
    await store.apply({
      roomId: ROOM_ID,
      actionId: '00000000-0000-4000-8000-0000000000a0',
      epoch: 3,
      mediaId: null,
      positionMs: 0,
      playing: false,
      rate: 1,
      issuedBy: USER_ID,
    });
    const newEpoch = await store.bumpEpoch(ROOM_ID);
    expect(newEpoch).toBe(4);
  });

  it('bumpEpoch() returns 1 for room with no prior state', async () => {
    const newEpoch = await store.bumpEpoch('fresh-room-' + Date.now());
    expect(newEpoch).toBe(1);
  });
});
