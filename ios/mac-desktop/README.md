# Plink for macOS — not built

There is no desktop client. This directory contains this file and nothing else; it
exists to hold the decision, not an implementation. What follows is two options for
whenever desktop is picked up, with the reasoning that applies today.

An earlier version of this file recommended "Option B: wrap `windows-client/` in
Tauri." **There has never been a `windows-client/` directory in this repository.** The
`desktop:dev`, `desktop:build`, and `desktop:dmg` scripts in `ios/package.json` pointed
at it and have been removed. Treat any surviving reference to a Windows client as
fiction.

## Option A — Mac Catalyst

Add `macCatalyst` to the existing `Plink` target in `project.yml`. This reuses all 174
Swift files in `ios/Plink/` as they are, which is what makes it the cheap option.

Guards needed behind `#if targetEnvironment(macCatalyst)`:

- `UIDevice.orientation` and haptics (`UIImpactFeedbackGenerator`) — neither exists on
  macOS.
- `AVAudioSession` — a different model on macOS.
- Danmaku and canvas effects — measure before shipping; the iOS Metal paths are not a
  given here.
- Push notifications — Catalyst needs its own APNs entitlement.

Rough cost: 3–5 days to a build that runs, and about as long again to make the UI
behave for a cursor and a resizable window. The second half is the part that gets
underestimated: a phone layout that merely compiles on a Mac is not a Mac app.

## Option B — web wrapper (Tauri or Electron)

The premise here has changed and the old estimate no longer applies. A web guest player
now exists — `backend/src/web/watchPage.ts`, served from `backend/src/routes/web.ts`. It
renders a YouTube IFrame and follows the host's timeline over the realtime socket, so
the hard part (sync in a browser) is already solved and tested.

What it is not is a full client. It is a guest surface: no chat, no sign-in, no room
creation. Wrapping it as-is produces a viewer, not Plink. Closing that gap is the real
work in this option, and it means building web UI for features that currently exist only
in Swift.

Prefer this only if a browser client is wanted for its own sake — joining a room with no
install is a genuinely different product capability from a Mac app.

## Recommendation

Do not start either before the iOS app ships.

The synchronisation protocol has not yet been measured across three physical devices;
the closed-beta gate still asks only for two, and that gate is not met yet — see
[the release runbook § 6](../../docs/runbooks/ios-build-and-release.md#6-closed-beta) and
[ADR-0005](../../docs/adr/0005-drift-as-a-user-facing-metric.md) for the drift targets
and the harness they are measured with. A third platform added now would multiply an
instability that has not been characterised on the first one.
