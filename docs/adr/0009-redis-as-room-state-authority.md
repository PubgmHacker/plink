# ADR-0009: Redis as the authority for room state

- **Status:** Accepted
- **Date:** 2026-08-15
- **Deciders:** backend maintainers

## Context

Room state — which media, what position, playing or paused, at what rate, as of what server
time — began life as a `Map<roomId, state>` inside the WebSocket handler. That works
perfectly for exactly one backend process.

It breaks the moment there are two. Railway scales by adding replicas, and connections are
distributed across them without regard for which room they belong to, so a room with four
participants can easily have two on replica A and two on replica B. With per-process state:

- each replica has its own idea of the timeline, and neither is wrong from where it stands;
- a `sync.state` broadcast reaches only the connections on the replica that handled the
  command, so half the room never hears about the pause;
- sequence numbers restart per process, so the ordering guarantee the protocol depends on
  ([ADR-0002](0002-host-authoritative-playback.md)) is only meaningful within one replica;
- a deploy replaces the process, and every room in flight loses its state silently — the
  clients stay connected and stop receiving updates.

The two properties that actually matter are harder than "put the state somewhere shared".
Applying a command has to be atomic against concurrent applies (two replicas processing the
same command must produce exactly one transition), and the resulting state has to reach
every connection in the room regardless of which process holds it.

## Decision

Room state lives in Redis, and Redis is the authority. `backend/src/realtime/roomStateStore.ts`
owns it; no process keeps a durable copy.

**One Lua script per command.** `APPLY_COMMAND` runs inside a single `EVAL`, which Redis
executes atomically, and does all of the following in that one step:

1. checks `room:<roomId>:action:<actionId>` — if present, this command has already been
   applied, so it returns the current state unchanged (`code = 0`);
2. rejects an epoch lower than the stored one (`code = -1`, `STALE_EPOCH`), which is how a
   command from a demoted host is refused;
3. increments `seq` server-side — the client cannot influence it;
4. writes the new state to `room:<roomId>:state`;
5. `PUBLISH`es the new snapshot to `room:<roomId>`.

Because those five steps are one Redis operation, there is no window in which state is
persisted but not published, or published with a sequence number another replica also used.
Idempotency is not a retry convention layered on top; it is the first line of the script.

**Pub/sub for fan-out.** Every replica subscribes to `room:<roomId>` and rebroadcasts to its
own local sockets. A room split across processes therefore observes one ordered event
stream, produced by whichever process happened to receive the command.

**Separate subscriber connection.** ioredis multiplexes normal commands but a connection that
`SUBSCRIBE`s enters subscribe mode and can no longer `EVAL`. The subscriber is a dedicated
client (`roomPubSub.ts`). This is not a style preference — sharing the connection breaks the
apply path.

**Deliberate expiry.** State keys carry a 24-hour TTL; idempotency tombstones carry five
minutes. Room state is ephemeral by design — an abandoned room evaporates rather than
accumulating, and a replayed command is only deduplicated for as long as a client might
plausibly retry it.

## Consequences

### What this makes easier

- Horizontal scaling is a replica count, not a project. Nothing in the realtime path assumes
  it is the only process.
- A deploy no longer drops rooms. The new process reads the same state the old one wrote, so
  a rolling restart is invisible to a room mid-film.
- The ordering guarantee is global. `seq` comes from one place, so "the client applies the
  highest `seq` it has seen and ignores anything older" is actually sound.
- Duplicate delivery stops being a correctness concern anywhere upstream. A client can retry
  a command freely, and the WebSocket layer does not need at-most-once delivery.
- Host migration is a single atomic epoch bump rather than a negotiation between replicas.

### What this makes harder

- **Redis down means the product is down.** Rooms cannot be created, joined, or advanced.
  The HTTP surface keeps answering, which is the dangerous part: `/health` looks fine while
  the app is unusable. `/health/ready` reports Redis separately for exactly this reason, and
  the readiness check is what the platform must be configured to watch.
- Room state is not durable. A Redis flush, an eviction under memory pressure, or a
  twenty-four-hour-old room means participants resynchronise from the host's next assertion.
  Acceptable for playback position; it would not be acceptable for anything a user believes
  they saved.
- **Logic in Lua is logic outside the type system.** The script is not type-checked, not
  covered by the TypeScript tests directly, and a mistake in it is a mistake in the atomic
  core of the protocol. It has already bitten once: an earlier `BUMP_EPOCH` computed the new
  epoch but never wrote it, so replicas disagreed about the current epoch until the next
  apply. The Lua stays small and is reviewed as carefully as a migration.
- Every command is now a network round trip. Sub-millisecond on the same platform, but it is
  no longer free, and it is a dependency in the hot path.
- Two Redis clients per process, and a connection-mode rule a newcomer cannot infer from the
  code that violates it.

### What has to be true for this to keep working

- Redis stays a single logical instance, or at least a single keyspace. Both properties
  depend on it: `EVAL` is atomic per instance, and pub/sub does not cross shards in cluster
  mode without care. Sharding by room would preserve this; sharding arbitrarily would not.
- The Lua script stays the only writer of `room:<roomId>:state`. A convenience `SET` from
  TypeScript would bypass the epoch check, the sequence increment, and the publish at once —
  and would look entirely reasonable in review.
- Redis latency stays low. The apply path is synchronous with respect to the command, so
  Redis p99 is a floor on the room's responsiveness.

## Alternatives considered

**Sticky sessions — route a room's connections to one replica.** Keeps the in-memory map and
is much simpler. Rejected because it makes a replica a single point of failure for its rooms
(losing it drops those rooms entirely), it does not survive a deploy, and it requires the
load balancer to route on application-level identity — which Railway does not offer.

**Postgres as the state store.** Already a dependency, durable, transactional, and
type-checked through Prisma. Rejected on write volume and latency: playback state changes
several times a second per active room, and none of it is worth persisting. It would also
need a separate fan-out mechanism, since `LISTEN`/`NOTIFY` is not built for this.

**A dedicated state service.** Full control, correct in principle. Rejected as inventing
infrastructure — it would need its own consensus, deployment, monitoring, and on-call story
to arrive at what Redis already provides.

**Optimistic locking with `WATCH`/`MULTI` instead of Lua.** Idiomatic Redis and avoids
embedding logic in a scripting language. Rejected because retry-on-conflict under a stream of
concurrent commands is worse than one atomic script, and the publish would still be a
separate step — reintroducing the persisted-but-not-published window this design removes.

## References

- `backend/src/realtime/roomStateStore.ts` — `APPLY_COMMAND`, `BUMP_EPOCH`
- `backend/src/realtime/roomPubSub.ts` — the dedicated subscriber client
- [Realtime protocol v2](../architecture/realtime-protocol.md)
- [ADR-0002](0002-host-authoritative-playback.md) — what the ordering guarantee is for
- [Deployment runbook — health checks](../runbooks/deployment.md)
