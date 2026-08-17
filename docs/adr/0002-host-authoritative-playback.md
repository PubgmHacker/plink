# ADR-0002: Host-authoritative playback

- **Status:** Accepted
- **Date:** 2026-08-15
- **Deciders:** iOS and backend maintainers

This records a decision already in force; the reasoning is written down here because it
constrains every future change to the sync path.

## Context

A room is several people watching one thing at the same time. Somebody has to decide
what "the same time" means.

The hard part is not distributing a position — it is that every participant's player
disagrees, continuously and legitimately. Buffering stalls one client. Another is
watching over cellular with a variable round trip. A third put the app in the
background and came back forty seconds later. Their players are at different positions
because the world made them different, not because of a bug.

Three consistency models were plausible:

1. One participant's timeline is the truth; everyone else reconciles to it.
2. The server maintains a timeline and clients report into it.
3. Clients agree among themselves — averaging positions, or voting.

The product also needs to _show_ how far out of sync you are
([ADR-0005](0005-drift-as-a-user-facing-metric.md)), which requires a single number to
be out of sync _from_. Any model where the reference is an aggregate has no such number:
you can be 400 ms from the mean while nobody in the room is where you are.

## Decision

The host owns the timeline. The server records what the host asserted, stamps it, and
fans it out. Everyone else reconciles.

Concretely:

- A `sync.command` from the host is an assertion of intent: media, position, playing,
  rate.
- The server assigns `epoch`, `seq`, `effectiveAtServerMs`, and `issuedBy`. None of
  these appears in any client→server schema, so a client has no vocabulary for claiming
  a sequence position or forging authorship. The guarantee is structural, not a
  validation rule someone can forget.
- Commands from a non-host are rejected, not merged.
- Host migration bumps `epoch`. The bump is published _before_ `role.changed`, so a
  command still in flight from the previous host fails the epoch check deterministically
  rather than racing it.
- The server never derives position from what clients report. Client positions are
  telemetry.

Non-hosts reconcile locally: seek if the gap is large, adjust rate if it is small, and
otherwise leave the player alone. That policy belongs to the client, because it is a
judgement about perceptibility, not about correctness.

## Consequences

### What this makes easier

- Drift is well defined and computable on the client, from data it already has: the
  host's asserted position, the server time it took effect, and its own clock offset.
- Conflict resolution disappears. There is one writer per epoch, so there is nothing to
  reconcile.
- The server stays simple enough to be stateless per connection. It stamps and fans out;
  the room state lives in Redis ([ADR-0009](0009-redis-as-room-state-authority.md)), so
  any replica can serve any socket.
- Debugging is tractable. "What did the host assert, and when?" has one answer, and it
  is in the state history.

### What this makes harder

- **The host's experience is privileged.** If the host has a bad connection, everyone
  gets a bad session. There is no averaging to hide behind.
- **Host migration is a real mechanism, not a footnote.** It needs the epoch, the
  ordering guarantee around `role.changed`, and tests. A model with no host would not
  need any of it.
- **A malicious host can ruin a room** by seeking constantly. This is accepted: the host
  is someone the participants chose to watch with, and the answer is social, plus the
  ability to leave.
- Non-host clients must implement reconciliation carefully. Correcting too eagerly is
  visible as stutter, which is worse than the drift it fixes.

### What has to be true for this to keep working

- Rooms stay small enough that one participant's connection quality is an acceptable
  single point of failure. At tens of participants — a broadcast rather than a watch
  party — a server-owned timeline becomes the better model.
- The host is a participant, not a broadcaster. If Plink grows a one-to-many mode, that
  mode needs its own decision rather than an extension of this one.

## Alternatives considered

**Server-owned timeline.** The server runs the clock and clients follow. Robust against
a bad host, and the natural choice for streaming. Rejected because the host is watching
too: the server would have to either drive the host's player (making it follow a
timeline it cannot influence, which feels broken when you press pause and the film keeps
going for 200 ms) or accept host input anyway — which is this decision with extra
machinery.

**Consensus among clients.** Average the positions, or take a median. Rejected on two
grounds. It makes drift meaningless as a user-facing number, since the reference is a
point where nobody is. And it converges towards the worst connection: one client stalled
in a buffer drags the room's notion of "now" backwards, which is exactly the participant
whose experience should not determine everyone else's.

**No authority — everyone seeks independently, with chat for coordination.** What
watching "together" over a video call already is. Rejected because synchronisation is the
product.

## References

- [Realtime protocol v2](../architecture/realtime-protocol.md)
- `backend/src/contracts/realtime-v2.ts` — the schemas, which are the authority
- `backend/src/realtime/roomStateStore.ts` — atomic apply, epoch and `seq` handling
- `ios/Plink/Realtime/OrderedSyncController.swift` — client-side ordering and reconciliation
- [ADR-0005](0005-drift-as-a-user-facing-metric.md), [ADR-0009](0009-redis-as-room-state-authority.md)
