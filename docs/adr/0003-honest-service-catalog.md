# ADR-0003: Honest service catalog instead of DRM circumvention

- **Status:** Accepted
- **Date:** 2026-08-15
- **Deciders:** project maintainers

## Context

Plink synchronises playback. Users want to synchronise the things they actually watch,
which in this market means Kinopoisk, ivi, Okko, Wink, Start, Premier, Kion, and —
outside it — Netflix and Disney+.

Almost none of those can be synchronised the way YouTube can. Their players are not
embeddable, their streams are DRM-protected, and their terms of service prohibit
redistribution. There are three ways to respond:

1. Extract the stream and play it in our own player.
2. Present them as supported and let the room discover that sync does not work.
3. Support them in the way they can actually be supported, and say so.

Option 1 is DRM circumvention. It is illegal in most of the jurisdictions Plink ships
to, it violates App Store Guideline 5.2, and it breaks whenever a provider changes
anything.

Option 2 is what a feature list wants. It is also the choice that generates the worst
possible user experience: a room where four people picked a film, pressed play, and
watched their app fail to do the one thing it is named after.

## Decision

The catalog states, per service, what will actually happen.

- **Synchronised playback** — YouTube (official IFrame player), VK, Rutube, and direct
  media URLs. These have embeddable players or open streams, and the host's commands
  move everyone's timeline.
- **Watch alongside** — subscription services. The host signs into their own account in
  a WebView. Guests see the host's session through screen sync. Playback is not
  controlled by the protocol, and the UI says so, in the room and before the room is
  created.
- **Never** — extracting a protected stream, proxying it, stripping DRM, or presenting
  an embedded player that is expected to fail.

Direct CDN extraction URLs are blocked in Release builds, so this is not only a policy
but a property of the shipped binary.

The labelling is load-bearing. It is what makes the App Review answer to Guideline 5.2
true: Plink does not stream, redistribute, or circumvent DRM; the host uses their own
subscription, and no content is copied, downloaded, or re-streamed.

## Consequences

### What this makes easier

- App Review has a straight answer, and it is the same answer every submission.
- No legal exposure from circumvention, and no dependency on a provider's private
  playback API that will change without notice.
- Support load drops. A user who reads "watch alongside" before creating the room does
  not file a bug when sync does not happen.
- The sync path only has to work for services where it can work, so its failures are
  real failures rather than expected ones.

### What this makes harder

- **The feature list looks shorter than a competitor's** that lists every logo without
  qualification. This is a real competitive cost and it is accepted knowingly.
- Every new service needs a classification decision before it can be added, which is
  slower than adding a logo.
- Screen-sync quality is bounded by the host's upload bandwidth, and that path will
  always feel worse than embedded playback. Users will compare them.
- The UI carries permanent explanatory copy — a disclaimer in the room, and a label in
  the picker — that a less honest product would not need.

### What has to be true for this to keep working

- That providers keep declining to offer embeddable, syncable players. If one ships a
  co-watching API, that service moves category and this record stays as the reason the
  others have not.
- That the labelling stays visible. A redesign that hides the watch-alongside label to
  make the catalog look cleaner silently converts this decision into option 2.

## Alternatives considered

**Extract and re-stream.** Technically achievable, and it is what a "watch anything
together" pitch implies. Rejected: illegal, against Guideline 5.2, and permanently
fragile.

**List everything and let sync fail quietly.** Best-looking catalog, no legal risk.
Rejected because it makes the product's core promise unreliable, and the failure lands
at the worst moment — four people, film chosen, press play.

**Support only what syncs.** Drop subscription services entirely. Clean, honest, and
much less useful: watching a Kinopoisk film with a friend over screen sync is a real
thing people do, and refusing to help with it does not make the sync path better.

## References

- `ios/Plink/Utilities/PlinkHost.swift` — the domain allowlist, per service
- [ADR-0004](0004-strict-host-matching.md) — why host matching is exact
- [Hard lines in CONTRIBUTING.md](../../CONTRIBUTING.md#things-we-do-not-do)
- [iOS release runbook](../runbooks/ios-build-and-release.md#guideline-exposure)
