# Changelog

All notable changes to Plink are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries are written for whoever reads release notes, not for whoever reviewed the
diff. Add yours under `[Unreleased]` in the same pull request as the change — see
[CONTRIBUTING.md](CONTRIBUTING.md#changelog-and-releases).

Plink has not published a release yet. Everything below is staged for **1.0.0**;
versioned sections and git tags begin there.

## [Unreleased]

### Added

- **Synchronized playback with a visible drift figure.** One participant owns the
  timeline; every other client reconciles against it continuously and shows its own
  offset in the room header, so "are we actually in sync?" is answered on screen
  rather than guessed at.
- **Watch without installing the app.** A room link opens a web guest player that
  plays YouTube and follows the host's timeline, so someone can join from a laptop
  or an Android phone with no download.
- **Sign in with Apple**, alongside email and phone sign-in.
- **Screen share for services that cannot play in-app**, with the service catalog
  labelling which sources play directly and which need sharing. Nothing is presented
  as playable when it is not.
- **Voice and video in rooms** for Plink+ subscribers, with the microphone control
  in the room bar.
- **Voice input in room chat** and a voice-first AI assistant, with the text chat on
  its own screen so the two do not fight over the same surface.
- **Room queue panel** with drag-to-reorder, replacing the earlier strip of chips.
- **Clipboard link detection on Home** — a copied video link becomes a room in one
  tap instead of three.
- **Home-screen widget** and full-screen swipeable trailer feed.
- **Early Android client** (build and unit tests verified in CI; not yet shipped).
- Dynamic Type up to XXL, and VoiceOver labels for conversation rows.
- **Terms, Privacy and Support pages**, served by the app's own backend and linked
  from the paywall, the settings screen and the web player. The subscription screen's
  legal links now resolve to something readable instead of dead-ending, and the
  support page states where to write and what to include.
- Voice input reports its failures inline. A denied microphone or speech permission,
  or an audio-session error, shows a small banner with the action to take instead of
  terminating the app or leaving the microphone button stuck in the recording state.

### Changed

- **One accent color across the whole app** instead of the three palettes that had
  drifted apart, with the admin surfaces moved onto shared design tokens rather
  than ad-hoc fills.
- **Sign-in and registration merged into a single screen**, and onboarding rebuilt
  around three animated scenes.
- **Rooms and Home tabs rebuilt** — tiles, friends currently watching, segmented
  filters, and a list rather than a grid; Home lost its LIVE-rooms shelf in favour
  of compact posters and a top-3.
- New app icon and wordmark, with the landing favicon and Open Graph image
  generated from the same mark. All remaining assets from the previous visual
  identity were removed.
- Landing shipped 135 MB lighter after removing 240 unused background frames.
- Health checking split into liveness (`/health/live`, used by the container
  runtime) and dependency readiness (`/health/ready`, which gates Railway
  promotion so a build that cannot reach Postgres or Redis is never promoted).
- **Sign-in, session and onboarding screens follow the app language** (Russian,
  English, Chinese) instead of always Russian, and a first launch starts in the
  device language.
- The login screen offers email and Sign in with Apple only; the inert Yandex
  button that opened a "coming soon" panel is gone.
- **Video search no longer spends YouTube Data API quota on every keystroke.**
  Results come from the public YouTube results page (the API key is only a
  provider-local fallback when YouTube serves a consent page), live streams and
  scheduled premieres are filtered out because they have no shared timeline, and
  Rutube results hide hidden, deleted, adult, live and paid cards. The backend caches
  web-search results under a new cache version.
- Room creation in this beta is limited to YouTube and RuTube, the two sources with a
  verified official embed player. Other catalog entries open the service's own page
  instead of an empty room with a website inside it.
- RuTube plays through the official embed inside its own web view, driven by the
  player's `postMessage` bridge (play, pause, seek); Plink never extracts a media URL
  or relays a stream.
- On iPad, settings are no longer a separate sidebar section; the sidebar carries the
  same five sections as the iPhone tab bar.

### Fixed

- **The "return to room" capsule no longer sticks around after you left.** It
  disappears the moment you leave, refreshes when the app comes back to the
  foreground and every 45 seconds while it is showing, and can be swiped down
  to leave the room. On the server, participants whose app was force-quit are
  removed from live rooms after a three-minute grace period, and a vanished
  host hands the role to the longest-present viewer.
- **One room the app cannot fully read no longer hides your whole rooms list.**
  If a room's video entry was written by a newer client, that room now lists as
  "no video yet" instead of blanking every room and the "return to room" capsule.
- **Choosing a video no longer ends in a black screen.** The YouTube, RuTube and
  VK Video catalogue opens full screen and fills the display on every iPhone; a
  pasted link from any of the three works on any of their steps. VK Video joins
  the first release as the third playable service; the remaining services are
  labelled as coming soon instead of opening an empty page.
- **A host losing connection no longer ends the room.** The role moves to another
  participant and playback continues.
- **Commands from a superseded host are rejected.** A host that reconnects after a
  network drop can no longer yank playback backwards for everyone with stale
  in-flight commands.
- Trending content loads immediately, with a skeleton instead of a premature
  "nothing here" state, and search failures surface instead of being swallowed.
- The tab bar can no longer be stretched horizontally by a room cover, a loading
  skeleton, or an oversized tab label.
- The assistant stops speaking when you leave the AI tab, close the chat, or send
  the app to the background — and the text chat never speaks at all.
- The service browser has real loading and error states.
- `402` (payment required) and `503` (unavailable) are handled distinctly by the
  API client, so a paywall no longer looks like an outage.
- **Face ID and Touch ID prompts work.** The app declared no Face ID usage
  description, so iOS would have terminated it on the first biometric prompt.
- **Release builds always talk to the production backend.** The launch-argument
  backend override, the simulator proxy and the design-review hooks now compile only
  into Debug builds.
- A fatal signal is reported once and then handed back to the system, so the OS
  crash log is no longer lost behind the in-app crash reporter.
- The landing site's download buttons no longer point at a placeholder App Store id.
  Without a configured store or TestFlight URL they read "coming soon", and the
  platform status says the same.
- **Creating a group conversation is idempotent across backend replicas.** The
  request id is reserved with `SET NX` and released with compare-and-set scripts, so a
  double tap, a retry, or two replicas racing no longer create two conversations, and
  members already in the conversation are not notified again.
- Group chat no longer flickers: a slower, older list response cannot erase a group
  that just arrived through the realtime hint, and one history request per group at a
  time stops realtime and the two-second poll from showing the same message twice.
- Reactions are not queued while offline. After a reconnect, stale taps no longer
  arrive in the room as a burst that tripped the rate limiter.
- In search results the "watch later" bookmark is its own control, so tapping it no
  longer creates a room (it used to be nested inside the result button).
- The onboarding poster wall loads the Ivi shelf only, so it appears within seconds on
  a cold install instead of waiting for the PREMIER pool to build.

### Security

- **Admin endpoints require authentication.** A set of moderation and
  administration routes was reachable without a session; they now verify the
  caller's role, re-read from the database rather than trusted from the token.
- **The realtime paywall fails closed.** Subscriber-only voice and video are gated
  before any capability check, so a deployment without media credentials cannot
  present a paid feature it is unable to deliver.
- **Request validation fails closed.** `validateQuery` and `validateParams` used to
  let a request through when validation raised anything other than a Zod error;
  they now reject it.
- **A provider API key was removed from a landing helper script.** It remains in
  git history and must be treated as compromised — see
  [docs/runbooks/incident-response.md](docs/runbooks/incident-response.md) for the
  rotation procedure.

### Internal

Not user-visible, but part of this release:

- Repository restructured for a team rather than a single author: `LICENSE`,
  `CONTRIBUTING.md`, `SECURITY.md`, `SUPPORT.md`, `CODEOWNERS`, issue and pull
  request templates, Dependabot, and a `docs/` tree carrying architecture notes,
  decision records (ADRs), runbooks, and the QA strategy.
- Iteration-era directory names (`ios-2`, `backend-3`, `brand-v2`, `brand-v3`)
  replaced with semantic ones. Fifty-six milestone, sprint and audit documents were
  removed from the tree: they described states the code had already left, and several
  documented mechanisms that no longer existed in it. Anything still true was folded
  into this changelog, an ADR, or a runbook first. The component READMEs that remain
  are the ones live code or a build step actually points at.
- Linting and formatting are now enforced rather than described: ESLint and
  Prettier for TypeScript, SwiftLint and SwiftFormat for Swift, EditorConfig for
  everything, and a root `Makefile` whose `make check` target runs exactly what CI
  runs.
- CI now runs typecheck, lint, the backend suite, a landing build, dependency audit
  and security-invariant checks on every push, plus an unsigned iOS simulator build
  and its 458 unit tests on any change to the client. Dependabot opens grouped
  weekly updates. A dead duplicate workflow that appeared to test iOS — and never
  ran, because it sat outside `.github/` at the repository root — was deleted.
- The Prettier and SwiftFormat ratchets run on direct pushes as well as on pull
  requests. Both used to skip on a push for want of a base branch, which made a
  direct push to `main` the one way into the tree that nothing checked formatting on;
  they now diff against the commit the push landed on.
- Every URL the iOS client opens or shares comes from one place
  (`Networking/PlinkURLs.swift`), so the legal pages follow whichever backend the
  build points at while share links keep the brand host.
- iOS signing is split by configuration: Debug signs with an empty entitlements file
  (the current team is a Personal Team), Release carries Sign in with Apple and the
  widget App Group. The widget gained its privacy manifest; the app declares export
  compliance, iPad orientations, and version keys driven by `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION`.
- Auth and onboarding strings live in `LocalizationAuthStrings.swift`, read through
  a nonisolated `L10n.text(_:)` accessor, which keeps the main strings table inside
  the SwiftLint budget.
- Backend housekeeping: `.env.example` lists the mail, VK search and RTC paywall
  variables the code reads; the duplicate `backend/railway.json` is gone (the root
  file is the one Railway uses); the Dockerfile has a `HEALTHCHECK`; a dead test
  bootstrap was removed and the QA strategy counts re-measured.
- Landing: store buttons are driven by `NEXT_PUBLIC_APP_STORE_URL` and
  `NEXT_PUBLIC_TESTFLIGHT_URL`, every route sends security headers, unused animation
  dependencies and the leftover i18n table were removed, and the icons, manifest and
  Open Graph image are copied from `brand/platforms/web`.
- The user event bus logs through the Fastify logger instead of `console`, and the
  rate-limiter warnings say what actually happens when Redis is unreachable: the
  affected request is allowed through uncounted.
- The web player page and the link-preview poster draw the brand mark as vectors, so
  the backend ships no raster brand assets.
- The avatar picker and the push-style cover presentation were extracted from the
  profile and direct-message screens into their own files.
- `backend/.prettierignore` mirrors the root ignore list so `npm run format:check`
  inside `backend/` no longer scans `dist/`, and the backend sources were formatted
  with Prettier in one pass.

## Before 1.0.0

Plink started on **2026-07-25** as a monorepo holding a SwiftUI client and a
Fastify backend. Development ran in three phases, all pre-release and untagged:

| Period             | Focus                                                                                                           |
| ------------------ | --------------------------------------------------------------------------------------------------------------- |
| 2026-07-25 → 07-31 | Realtime sync foundation, room lifecycle, Railway deployment, marketing site                                    |
| 2026-08-01 → 08-08 | Interface rebuild onto a single design language; AI assistant; Plink+ subscription                              |
| 2026-08-09 → 08-15 | Hardening for release: web guest, Sign in with Apple, honest service catalog, repository and process groundwork |

Detailed history is in `git log`; architectural decisions from this period are
written up in [docs/adr/](docs/adr/).
