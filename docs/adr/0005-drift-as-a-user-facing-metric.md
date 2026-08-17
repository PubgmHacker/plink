# ADR-0005: Drift as a user-facing metric

- **Status:** Accepted
- **Date:** 2026-08-15
- **Deciders:** iOS maintainers, product

## Context

Plink's promise is that everyone in the room is watching the same moment. That promise
is unverifiable from inside the app unless the app tells you.

Perfect synchronisation is not achievable. Clocks differ, networks vary, players buffer,
and a client returning from the background has to catch up. The realistic goal is a small
and _known_ offset — the protocol targets a median under 500 ms and a p95 under 1.5 s.

That leaves a product question: when a participant is 900 ms behind the host, what does
the app show?

The conventional answer is nothing. Sync is presented as binary — in sync or
reconnecting — and the residual offset is hidden as an implementation detail. The problem
is that users detect the offset anyway, through the one channel the app does not control:
the other person in the room saying "wait, I'm not there yet." At that point the app has
been quietly wrong, and the user has no way to tell whether it is 200 ms or 4 seconds
wrong, or whether it is getting better.

## Decision

The room shows the current drift, as a number, continuously.

- Drift is the difference between where this client's player actually is and where the
  host's asserted timeline says it should be, projected through the measured clock
  offset. Both inputs are already available: the host's assertion arrives in
  `sync.state`, and the offset comes from `clock.probe` round trips.
- The display is banded, so the number is readable rather than jittering: comfortably in
  sync, drifting, and badly out. The exact figure is available; the band is what carries
  at a glance.
- A correction is visible in the same place. A client that seeks to catch up says so
  rather than jumping silently.

The metric is a product surface, not diagnostics. It is not behind a debug flag, not
gated on a developer build, and not hidden in settings.

## Consequences

### What this makes easier

- **The promise becomes checkable.** A user who can see 120 ms trusts the room. A user
  who cannot see anything trusts it only until the first disagreement.
- Support conversations get concrete. "It says 3 seconds" is a report; "it feels laggy"
  is not.
- Regressions in the sync path are visible to users, which means they are reported. A
  hidden metric regresses silently between releases.
- It makes the sync work legible. The engineering behind
  [host-authoritative playback](0002-host-authoritative-playback.md) is invisible when it
  works; the badge is where it shows.

### What this makes harder

- **A number invites attention to itself.** Some users will watch the badge instead of
  the film, and a 400 ms reading that nobody could perceive will generate complaints
  that a hidden metric would not have.
- It commits us to accuracy. A drift figure that is wrong is worse than no figure,
  because it is now a false claim rather than an absent one. The measurement path needs
  tests, and the clock estimate has to be filtered rather than sampled once.
- The banding thresholds are a product decision that will be argued about, and changing
  them changes what users believe about a build whose sync did not change.
- It occupies room chrome during a film, where space is scarce and every element is
  competing with the content.

### What has to be true for this to keep working

- That typical drift stays small enough for the number to be reassuring. If it routinely
  read 2 s, showing it would advertise a broken product, and the correct response would
  be to fix the sync rather than hide the badge.
- That the measurement stays trustworthy. If the clock estimate degrades — a change in
  probe cadence, or filtering that lags reality — the badge becomes confidently wrong,
  which is the worst state for it to be in.

## Alternatives considered

**Binary in-sync indicator.** Simpler, and it never invites scrutiny of a number nobody
can perceive. Rejected because it discards the information that makes the promise
checkable, and because "in sync" shown while a user is 3 s behind is a lie the app tells
with confidence.

**Show it only when it is bad.** Appealing: no chrome in the good case, information when
it matters. Rejected because an indicator that appears only during problems trains users
to read it as an error state, and it cannot build the trust that a steadily small number
builds. It also hides the transition — the interesting moment is drift _growing_, before
it crosses a threshold.

**Developer-only, behind a flag.** What the metric started as. Rejected: it made the
sync work legible to us and to nobody else, and the people who most need to know whether
the room is synchronised are the people in it.

## References

- [Realtime protocol v2 — clock synchronization](../architecture/realtime-protocol.md#clock-synchronization)
- `ios/Plink/Realtime/ClockSynchronizer.swift` — offset estimation
- `ios/Plink/Realtime/SyncTelemetryCollector.swift` — drift and correction accounting
- `ios/Plink/Features/WatchRoom/PlayerControlLayer.swift` — where it is displayed
- `ios/scripts/drift-lab.mjs` — the harness the targets are measured with
