# Realtime protocol v2

Everything that keeps a room in sync travels over one WebSocket connection per
client. This page describes the wire format, the connection lifecycle, and the
invariants that make the timeline trustworthy.

The schemas are the authority, not this page. They live in
[`backend/src/contracts/realtime-v2.ts`](../../backend/src/contracts/realtime-v2.ts)
and are mirrored by the Swift decoders in `ios/Plink/Realtime/`. The contract tests
in `backend/src/tests/contract/` fail if the two drift apart.

## Design premise

One participant — the host — owns the timeline. Everyone else reconciles against
it. The server does not average positions, vote on them, or attempt to be clever:
it records what the host asserted, stamps it, and fans it out.

This is the whole reason drift is _measurable_. Every client knows the host's
asserted position, the server time it took effect, and its own offset from the
server clock, so it can compute how far off it is and show that number. See
[ADR-0002](../adr/0002-host-authoritative-playback.md) for why this beat the
alternatives.

## Connecting

```
wss://<host>/realtime/rooms/<roomId>
Sec-WebSocket-Protocol: plink.ticket.<ticket>
```

The ticket is a short-lived, **single-use** credential obtained over HTTPS before
the upgrade. It is passed as a subprotocol rather than a query parameter because
query strings end up in access logs, proxy logs, and browser history; a leaked
room URL should not be a leaked session.

The ticket is bound to one `roomId`. The gateway compares it against the path and
refuses a mismatch, so a valid ticket for one room cannot be replayed against
another.

Two things are deliberately _not_ trusted from the ticket:

- **Identity** is read from the authenticated user record, never from a payload field.
- **Role** is derived from a fresh database query at session start. A ticket minted
  while you were host does not make you host after the role moved on.

`roomId` may be the literal `@me`, which opens a user-level channel for direct
messages with no room binding.

### Close codes

| Code   | Meaning                                                                  |
| ------ | ------------------------------------------------------------------------ |
| `4001` | No ticket in `Sec-WebSocket-Protocol`, or the ticket failed verification |
| `4003` | Ticket is valid but its `roomId` does not match the connection path      |
| `1001` | Server is draining — reconnect after `retryInMs` (see `server.draining`) |

A `4001` or `4003` is terminal for that ticket: request a new one rather than
retrying the same upgrade.

## Envelope

Every message, in both directions, is JSON with two mandatory fields:

```json
{ "type": "sync.command", "protocolVersion": 2, "...": "..." }
```

`protocolVersion` is the literal `2`. There is no negotiation and no implicit
upgrade — a client speaking a different version is rejected rather than partially
understood, because a half-understood sync command is worse than no connection.

Field names are camelCase everywhere. Schemas are `.strict()`, so an unknown field
is an error rather than something silently ignored.

## Messages

### Client → server

| Type                 | Purpose                                                                |
| -------------------- | ---------------------------------------------------------------------- |
| `sync.command`       | Host asserts a playback intent: media, position, playing, rate         |
| `sync.state.request` | Ask for the authoritative snapshot, optionally after a `seq` watermark |
| `chat.send`          | Send a room message, carrying a `clientMessageId` for echo matching    |
| `reaction.send`      | Send an emoji reaction                                                 |
| `clock.probe`        | Measure offset against the server clock                                |
| `pause.request`      | A viewer asks the host to pause, with an optional short reason         |
| `pause.resolve`      | The host answers a pause request                                       |

Constraints worth knowing: `positionMs` is capped at 24 hours, `rate` is clamped to
`0.5`–`2.0`, chat text to 2000 characters, a reaction emoji to 32, and a pause
reason to 120. These are schema-level, so an out-of-range value is rejected at the
boundary rather than reaching the room.

### Server → client

| Type                                      | Purpose                                                                        |
| ----------------------------------------- | ------------------------------------------------------------------------------ |
| `session.ready`                           | Handshake complete; carries your role as the server currently sees it          |
| `sync.state`                              | A new authoritative state, following a host command                            |
| `sync.state.snapshot`                     | Reply to `sync.state.request`; `state` is null for a room with no timeline yet |
| `clock.probe.reply`                       | Echoes `clientSentMs`, adds `serverMs`                                         |
| `chat.broadcast`                          | A room message, including your own echoed back                                 |
| `reaction.broadcast`                      | An emoji reaction                                                              |
| `participant.joined` / `participant.left` | Membership change                                                              |
| `role.changed`                            | Host migration, carrying the new `epoch`                                       |
| `room.appearance.updated`                 | The host changed the room's look                                               |
| `pause.requested` / `pause.resolved`      | A pause was asked for, and answered                                            |
| `server.draining`                         | Graceful shutdown; reconnect after `retryInMs`                                 |
| `error`                                   | A `code` and a human-readable `message`                                        |

## Authoritative state

Every `sync.state` carries the same object:

```json
{
  "protocolVersion": 2,
  "roomId": "…",
  "epoch": 3,
  "seq": 128,
  "mediaId": "…",
  "positionMs": 754300,
  "playing": true,
  "rate": 1,
  "effectiveAtServerMs": 1755280000123,
  "issuedBy": "…"
}
```

Five of these fields are **server-assigned**: `epoch`, `seq`, `effectiveAtServerMs`,
`issuedBy`, and `protocolVersion`. None of them appears in any client→server schema,
which means a client has no vocabulary for claiming a sequence position or forging
authorship. The guarantee is structural rather than a validation rule someone can
forget to apply.

### `seq` — ordering

Monotonic within a single `(roomId, epoch)` pair. A client that receives `seq` 130
after 131 discards it. Reordering happens; there is no need to reason about _why_
when the rule is this simple.

`sync.state.request` takes an `afterSeq` watermark so a reconnecting client asks
for what it missed rather than replaying the room's whole history.

### `epoch` — authority generation

Bumped on host migration and on timeline reset. This is the mechanism that makes
handoff safe.

When a host drops off a flaky connection, its client may still have commands in
flight. Those commands are valid, correctly signed, and completely wrong — the room
has moved on. Rather than racing them, the epoch bump is published _before_
`role.changed`, so a late command from the previous host fails the epoch check
deterministically. Without this, a host reconnecting mid-film would yank playback
backwards for everyone.

### `actionId` — idempotency

Each `sync.command` carries a client-generated UUID. Room state is mutated through
Redis Lua scripts that record it, so a command re-sent after a dropped
acknowledgement applies once. Retrying is always safe, which is what lets the
client retry aggressively on a bad network.

### Atomicity

State transitions run as Lua inside Redis. A command either applies wholly or not
at all — there is no window in which `seq` has advanced but `positionMs` has not.
Since Redis also carries the pub/sub fan-out, any backend replica can serve any
socket: the connection holds no authority the room state does not already have.

## Clock synchronization

Sync needs a shared clock, not a shared stopwatch. The client round-trips
`clock.probe` and computes offset and round-trip time from
`clientSentMs`/`serverMs`/receipt time, keeping a filtered estimate rather than
trusting a single sample.

`clientSentMs` is a floating-point millisecond value. It was originally
integer-constrained, which rejected every probe the Swift client sent, since its
timestamps are sub-millisecond. Both directions now accept fractional values.

Drift shown to the user is the difference between where this client's player
actually is and where the host's asserted timeline says it should be, projected
through the clock offset. That figure is displayed rather than hidden — see
[ADR-0005](../adr/0005-drift-as-a-user-facing-metric.md).

## Presence and liveness

Presence is a Redis lease with a **60 s TTL**, refreshed when a client answers a
heartbeat ping — every **20 s**. Two missed heartbeats still leave a full interval
of headroom, so a brief stall on mobile data does not evict someone mid-film.

The lease has a useful property on the failure path: if a backend instance dies
without running its cleanup, the lease simply expires. Nothing has to be reconciled
by hand, and a crash cannot leave a room permanently holding a participant who is
not there.

Participant counts come from that Redis presence set rather than from a single
instance's socket registry, so the count is correct with more than one replica
running.

## Connection teardown

Disconnect cleanup is ordered so that it only undoes what actually happened:
rejection paths — no such room, ticket mismatch, banned user, not a member, pub/sub
failure — must not decrement presence or metrics they never incremented. Cleanup
that touches Redis is bounded by a timeout; if it expires, the lease TTL is the
backstop.

## Changing the protocol

`protocolVersion` is a literal, so any incompatible change is a new version rather
than a new optional field with special meaning. Additive changes that both clients
can ignore are fine within v2.

A protocol change is not done until it lands on both sides in the same pull
request: the Zod schema and the Swift decoder together. The contract tests exist
specifically to make a one-sided change fail in CI rather than in a room with four
people in it.
