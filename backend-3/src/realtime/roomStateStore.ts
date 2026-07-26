// src/realtime/roomStateStore.ts — Authoritative room state in Redis (runbook §4)
//
// Replaces the in-memory Map<roomId, state> in ws-handler.ts. Two key properties:
//
// 1. Atomic apply with idempotency: a single Lua script checks actionId for
//    replay, increments seq atomically, validates epoch monotonicity, persists
//    state, and publishes the new snapshot — all inside one Redis EVAL.
//    Multi-replica safe: two backend instances applying the same actionId
//    concurrently will see exactly one state transition.
//
// 2. Pub/Sub fanout: applying a command publishes the new state to
//    room:<roomId>. Other replicas subscribe and rebroadcast to their local
//    WebSocket connections. This is how a room with users connected to two
//    backends gets a single ordered event stream.
//
// Important: the connection that EVALs this script MUST NOT be the same
// connection that SUBSCRIBEs — ioredis multiplexes commands but enters
// subscribe mode on the connection. We use a dedicated subscriber client
// (see roomPubSub.ts).

import type Redis from 'ioredis';
import type { RoomState } from '../contracts/realtime-v2.js';

// ─────────────────────────────────────────────────────────────────────────────
// Lua: APPLY_COMMAND
//   KEYS[1] = room:<roomId>:state
//   KEYS[2] = room:<roomId>:action:<actionId>   (idempotency tombstone)
//   ARGV[1] = epoch (number)
//   ARGV[2] = roomId (string)
//   ARGV[3] = mediaId (JSON-encoded: "null" or "string")
//   ARGV[4] = positionMs (number)
//   ARGV[5] = playing ("1" | "0")
//   ARGV[6] = rate (number)
//   ARGV[7] = effectiveAtServerMs (number)
//   ARGV[8] = issuedBy (uuid string)
//
// Returns: { code, encodedState }
//   code = 1  → applied, encodedState is the new state JSON
//   code = 0  → replayed actionId, encodedState is current state (no-op)
//   code = -1 → STALE_EPOCH (caller rejects)
// ─────────────────────────────────────────────────────────────────────────────
const APPLY_COMMAND = `
local stateKey = KEYS[1]
local actionKey = KEYS[2]
if redis.call('EXISTS', actionKey) == 1 then
  return {0, redis.call('GET', stateKey) or ''}
end
local previous = redis.call('GET', stateKey)
local seq = 1
local epoch = tonumber(ARGV[1])
if previous then
  local decoded = cjson.decode(previous)
  seq = tonumber(decoded.seq) + 1
  if epoch < tonumber(decoded.epoch) then
    return {-1, previous}
  end
  if epoch == tonumber(decoded.epoch) and tonumber(decoded.seq) >= seq then
    -- Should not happen (seq is monotonically incremented), but guard anyway
    seq = tonumber(decoded.seq) + 1
  end
end
local state = {
  protocolVersion = 2,
  roomId = ARGV[2],
  epoch = epoch,
  seq = seq,
  mediaId = cjson.decode(ARGV[3]),
  positionMs = tonumber(ARGV[4]),
  playing = ARGV[5] == '1',
  rate = tonumber(ARGV[6]),
  effectiveAtServerMs = tonumber(ARGV[7]),
  issuedBy = ARGV[8]
}
local encoded = cjson.encode(state)
redis.call('SET', stateKey, encoded, 'EX', 86400)
redis.call('SET', actionKey, '1', 'EX', 300)
redis.call('PUBLISH', 'room:' .. ARGV[2], encoded)
return {1, encoded}
`;

// ─────────────────────────────────────────────────────────────────────────────
// Lua: BUMP_EPOCH
//   Called on host migration / explicit timeline reset. Returns the new epoch.
//   KEYS[1] = room:<roomId>:state
//   ARGV[1] = roomId
// ─────────────────────────────────────────────────────────────────────────────
const BUMP_EPOCH = `
local stateKey = KEYS[1]
local previous = redis.call('GET', stateKey)
local newEpoch = 1
if previous then
  local decoded = cjson.decode(previous)
  newEpoch = tonumber(decoded.epoch) + 1
end
return newEpoch
`;

export type ApplyResult =
  | { kind: 'applied'; state: RoomState }
  | { kind: 'replay'; state: RoomState | null }
  | { kind: 'stale_epoch'; currentState: RoomState | null };

export class RoomStateStore {
  constructor(private readonly redis: Redis) {}

  /** Read-only snapshot fetch (used by sync.state.request). */
  async get(roomId: string): Promise<RoomState | null> {
    const raw = await this.redis.get(`room:${roomId}:state`);
    if (!raw) return null;
    try {
      return JSON.parse(raw) as RoomState;
    } catch {
      return null;
    }
  }

  /**
   * Apply a host command atomically.
   *
   * - actionId deduplicates: replaying the same UUID is a no-op (returns current state).
   * - epoch must be >= the current state's epoch; lower is rejected (STALE_EPOCH).
   * - seq is incremented server-side; client cannot influence it.
   * - On success, the new state is PUBLISHED to room:<roomId> so other replicas
   *   can fan it out to their local connections.
   *
   * `effectiveAtServerMs` is set by the caller (gateway) to `Date.now() + 80ms`
   * so the client applies the state slightly in the future — this is the
   * 80ms "scheduled transition" gap from the runbook's sync policy.
   */
  async apply(input: {
    roomId: string;
    actionId: string;
    epoch: number;
    mediaId: string | null;
    positionMs: number;
    playing: boolean;
    rate: number;
    issuedBy: string;
  }): Promise<ApplyResult> {
    const now = Date.now();
    const effectiveAt = now + 80;
    const result = (await this.redis.eval(
      APPLY_COMMAND,
      2,
      `room:${input.roomId}:state`,
      `room:${input.roomId}:action:${input.actionId}`,
      String(input.epoch),
      input.roomId,
      JSON.stringify(input.mediaId),
      String(input.positionMs),
      input.playing ? '1' : '0',
      String(input.rate),
      String(effectiveAt),
      input.issuedBy,
    )) as [number, string];

    const code = result[0];
    const encoded = result[1];

    if (code === 1) {
      return { kind: 'applied', state: JSON.parse(encoded) as RoomState };
    }
    if (code === 0) {
      return {
        kind: 'replay',
        state: encoded ? (JSON.parse(encoded) as RoomState) : null,
      };
    }
    if (code === -1) {
      return {
        kind: 'stale_epoch',
        currentState: encoded ? (JSON.parse(encoded) as RoomState) : null,
      };
    }
    throw new Error(`RoomStateStore.apply: unexpected Lua return code ${code}`);
  }

  /**
   * Bump epoch on host migration or explicit timeline reset.
   * Returns the new epoch. Caller then issues a sync.command with this epoch.
   */
  async bumpEpoch(roomId: string): Promise<number> {
    const result = (await this.redis.eval(
      BUMP_EPOCH,
      1,
      `room:${roomId}:state`,
      roomId,
    )) as number;
    return result;
  }

  /** Clear state (used on room teardown / explicit reset). */
  async clear(roomId: string): Promise<void> {
    await this.redis.del(`room:${roomId}:state`);
  }
}
