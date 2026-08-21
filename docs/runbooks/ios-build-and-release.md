# Building and releasing the iOS app

Covers a local build, a TestFlight build, and an App Store submission. The Xcode
project is generated, so the first section applies to every one of those.

- **Local build:** [§1](#1-local-build)
- **TestFlight:** [§3](#3-testflight-build)
- **App Store submission:** [§4](#4-app-store-submission)
- **Screenshots:** [§5](#5-screenshots)
- **Closed beta:** [§6](#6-closed-beta)

Requirements: Xcode 16, `xcodegen` (`brew install xcodegen`), and membership in
Apple Developer team `2QAMUC4Z4P`.

---

## 1. Local build

`Plink.xcodeproj` is generated from `ios/project.yml` and is not tracked — see
[ADR-0007](../adr/0007-generated-xcode-project.md). Regenerate it after any pull that
touches `project.yml`, and after adding or removing files outside Xcode.

```bash
cd ios
cp Secrets.xcconfig.template Secrets.xcconfig   # first time only
xcodegen generate
open Plink.xcodeproj
```

Or from the repository root: `make xcode`.

`Secrets.xcconfig` holds `PLINK_AI_API_KEY` and `YANDEX_CLIENT_ID`. It is gitignored.
The app builds and runs without real values; the AI features and Yandex sign-in are
the only things that will not work.

Targets:

| Target         | Bundle ID                     | What it is                                  |
| -------------- | ----------------------------- | ------------------------------------------- |
| `Plink`        | `com.syncwatch.plink`         | The app. Deployment target iOS 17.          |
| `PlinkWidget`  | `com.syncwatch.plink.widget`  | WidgetKit extension, embedded in the app    |
| `PlinkTests`   | `com.syncwatch.plink.tests`   | Unit and snapshot tests                     |
| `PlinkUITests` | `com.syncwatch.plink.uitests` | Funnel smoke test against a running backend |

The bundle identifier says `syncwatch` for a reason that is not cosmetic — see
[ADR-0008](../adr/0008-legacy-bundle-identifier.md). Do not "fix" it.

### Tests

```bash
xcodebuild test -project Plink.xcodeproj -scheme Plink \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

No `-only-testing` is needed: the `Plink` scheme's test action names `PlinkTests` and
nothing else (`project.yml` → `schemes:`). Expect **458 tests, 32 skipped, 0 failures**.
The same run happens in CI on every change under `ios/` —
[`.github/workflows/ios.yml`](../../.github/workflows/ios.yml).

Snapshot tests are opt-in: they run only with `SNAPSHOT_TESTS=1` in the environment,
because a reference image rendered on a different simulator or OS version fails for
reasons that have nothing to do with the change under test.

`PlinkUITests` needs a backend it can register against, so it is not part of the `Plink`
scheme at all — use the `Plink-UITests` scheme, and point the build at a local server
before running it. It is a smoke test of registration → home → room, not a substitute for
the backend suite.

### Known capability limit

Associated Domains — and therefore universal links — are **not** enabled, because a
Personal Team cannot provision that capability: provisioning fails with _"Personal
development teams do not support the Associated Domains capability."_

Custom-scheme deep links (`plink://r/<code>`, `plink://u/<userId>`) work regardless and
are what `DeepLinkRouter` handles today. Once the account is on the Apple Developer
Program, re-add to the `Plink` target's entitlements in `project.yml`:

```yaml
com.apple.developer.associated-domains:
  - applinks:plink.app
```

The backend already serves `/.well-known/apple-app-site-association`, so nothing else
is needed on that side.

---

## 2. Version and build number

`project.yml` carries both:

```yaml
MARKETING_VERSION: '1.0' # the version users see
CURRENT_PROJECT_VERSION: '1' # the build number
```

**Every upload to App Store Connect needs a build number that has never been used for
this marketing version.** Bump `CURRENT_PROJECT_VERSION`, regenerate, and rebuild.
Uploading a duplicate is rejected after the upload completes, which wastes the archive.

Bump `MARKETING_VERSION` only for a user-visible release.

---

## 3. TestFlight build

1. Bump the build number ([§2](#2-version-and-build-number)) and regenerate the project.
2. Confirm the backend the build points at is the one you mean. A TestFlight build
   aimed at a local server is useless to a tester.
3. Verify the release-only behaviour you cannot see in Debug:
   - direct CDN extraction is blocked in Release builds — YouTube must play through
     the official IFrame player;
   - voice is hidden while `LIVEKIT_SFU` is off, and hidden is not the same as broken.
4. In Xcode: **Product → Archive** with the `Plink` scheme and a Release configuration.
5. **Distribute App → App Store Connect → Upload** from the Organizer.
6. Wait for processing, then add the build to a TestFlight group.
7. Install the processed build yourself before notifying testers. Sign in, create a
   room, and join it from a second device.

Step 7 is not a formality. Signing, entitlements, and configuration problems are
invisible in a simulator build and show up on first launch of the distributed one.

---

## 4. App Store submission

### Subscriptions

Create the auto-renewable subscription group **Plink+** in App Store Connect with:

| Product ID       | Duration  | Price intent |
| ---------------- | --------- | ------------ |
| `plink.plus.1m`  | 1 month   | 149 ₽        |
| `plink.plus.3m`  | 3 months  | 349 ₽        |
| `plink.plus.12m` | 12 months | 990 ₽        |

These identifiers are hardcoded in `Plink/Services/StoreManager.swift`. They must match
App Store Connect exactly — a mismatch does not error, it just returns an empty product
list and the paywall renders with nothing to buy.

Verify against a sandbox account that all three products load and that a purchase
grants premium. The backend's boot log must show `[iap] verification self-check passed`
on whichever environment the build points at; if it does not, stop and read
[incident-response.md](incident-response.md#in-app-purchase-verification-self-check-failed).

### Listing

| Field          | Value                                      |
| -------------- | ------------------------------------------ |
| Name (RU)      | Плинк — смотрите вместе                    |
| Name (EN)      | Plink — Watch Together                     |
| Subtitle (RU)  | Синхронный просмотр фильмов с друзьями     |
| Subtitle (EN)  | Watch movies in sync with friends          |
| Categories     | Entertainment (primary), Social Networking |
| Age rating     | 17+                                        |
| Localizations  | Russian, English, Chinese                  |
| Privacy policy | landing `/privacy`                         |
| Terms          | landing `/terms`                           |

Keywords, RU: `смотреть вместе, фильмы, синхронно, чат, друзья, watch party, co-watch, sync video`
Keywords, EN: `watch together, movies, sync, chat, friends, watch party, co watch, together, sync`

17+ is because room chat is user-generated and not pre-moderated. Rating it lower
invites a rejection that costs a review cycle.

Privacy declarations: no data sold; usage analytics collected; photo library access used
only for choosing an avatar.

### Review notes

Paste into App Store Connect, filling in the demo account:

```
Demo account: <email> / <password>

Core flow:
1. Sign in → Home → Create room (YouTube)
2. Join from a 2nd device with the room code
3. Host play/pause → guest follows (<2s)
4. Chat send → receive (<1s)
5. Long-press a chat message → Report / Block
6. Host can Kick a participant from the chat context menu

Content and services (Guideline 5.2):
Plink does not stream, redistribute, or circumvent DRM. The host signs
into their own subscription account in a WebView (Netflix, Disney+,
Kinopoisk, ivi, Okko and similar). Guests see the host's session through
sync technology — embedded official players or screen sync. No content is
copied, downloaded, or re-streamed by Plink. Direct CDN extraction URLs
are blocked in Release builds. YouTube uses the official IFrame player.

In-app purchases: Plink+ sandbox products plink.plus.1m / 3m / 12m.
Voice: disabled until LiveKit is configured; the microphone control is
hidden rather than non-functional.
User-generated content: Report (spam / harassment / NSFW / other), Block,
and host Kick.
```

### Demo account

- [ ] A real account on the environment the build points at, seeded with one public
      YouTube room and one friend
- [ ] Sign-in verified, and the token survives a relaunch (Keychain persistence)
- [ ] YouTube IFrame playback verified on a device, not just a simulator

### Guideline exposure

| Guideline                  | How the app stands                                                     |
| -------------------------- | ---------------------------------------------------------------------- |
| 2.1 Completeness           | Core loop works; disabled features are hidden, not broken              |
| 3.1.1 In-app purchase      | StoreKit 2 only, no external purchase path                             |
| 4.2 Minimum functionality  | Native app, not a web shell                                            |
| 5.1 Privacy                | Policy URL required and present                                        |
| 5.2 Intellectual property  | Host-subscription WebView plus in-app disclaimer; no DRM circumvention |
| 1.2 User-generated content | Report, Block, host Kick                                               |

The catalogue does not promise synchronisation it cannot deliver — see
[ADR-0003](../adr/0003-honest-service-catalog.md). Services that cannot be synced are
labelled as watch-alongside in the UI, and that labelling is what makes the 5.2 answer
above true. Do not remove it to make the catalogue look better.

### Upload

1. Archive (Release, team signing).
2. Upload via Organizer or Transporter.
3. Attach screenshots and the review notes.
4. Submit.

---

## 5. Screenshots

Required sizes:

| Display     | Pixels    | Prefix      |
| ----------- | --------- | ----------- |
| 6.7" iPhone | 1290×2796 | `iphone67-` |
| 6.5" iPhone | 1242×2688 | `iphone65-` |
| 12.9" iPad  | 2048×2732 | `ipad-`     |

Capture from a booted simulator. Device names are a property of whichever Xcode is
installed, so list them rather than trusting the one below — the 6.7" frames come from
a Pro Max / Plus class device, not from the Pro:

```bash
xcrun simctl list devices available | grep iPhone
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
open -a Simulator
mkdir -p docs/screenshots

# once each screen is on-screen:
xcrun simctl io booted screenshot docs/screenshots/01-home.png
xcrun simctl io booted screenshot docs/screenshots/02-watchroom.png
xcrun simctl io booted screenshot docs/screenshots/03-ai.png
xcrun simctl io booted screenshot docs/screenshots/04-friends.png
xcrun simctl io booted screenshot docs/screenshots/05-profile.png
xcrun simctl io booted screenshot docs/screenshots/06-paywall.png
```

Rescale for a size you have no simulator for:

```bash
sips -z 2796 1290 docs/screenshots/01-home.png \
  --out docs/screenshots/iphone67-01-home.png
```

`PlinkTests/MarketingShots.swift` renders the same screens deterministically through the
snapshot harness, which is the better option when you need to retake the whole set
after a design change.

**Content rules.** Show YouTube, VK, or Rutube. Do not show Netflix, Disney+, or cinema
service logos: a screenshot implying Plink distributes that content is exactly the
Guideline 5.2 problem the review notes exist to avoid. Where a service logo is
unavoidable, the frame must include the in-app disclaimer that an active subscription is
required and that Plink does not provide the content.

Include the room code and the sync indicator where they fit — the drift figure is a
product feature ([ADR-0005](../adr/0005-drift-as-a-user-facing-metric.md)), and it
photographs well.

---

## 6. Closed beta

Target cohort: 20–25 testers, weighted towards pairs — a single tester cannot exercise
the product, since everything interesting needs two devices in one room.

**Before inviting anyone:**

- Kill switches set to off: `AI_ACTIONS_ENABLED=false`, cinema services off, voice off
  until LiveKit is configured.
- `SENTRY_DSN` set. Crash reports from a beta you cannot see are just complaints.
- The sync lab passes against the environment testers will use:

  ```bash
  cd ios
  API_BASE=https://<backend-host> node scripts/drift-lab.mjs
  ```

  Targets: median drift under 500 ms, p95 under 1.5 s.

**Day-one script for testers** — install, register, create a room from trending, have a
friend join by code, then ten minutes of play/pause and chat. Bug reports should carry
build number, device and iOS version, account role, steps, expected, actual, and a
timestamp for correlating with logs.

Triage daily, in a fixed window, with one named owner. A beta with no triage owner
produces a backlog nobody reads.

**Gates before a wider launch:**

- [ ] No P0 open for 48 hours — P0 being a security bypass, data loss, a crash in the
      core loop, a duplicated room or action, or being unable to enter or leave a room
- [ ] Every P1 has a workaround, an owner, and a date
- [ ] The core flow completes ten consecutive times on two physical devices
- [ ] A 30-minute session holds the drift targets, including a background/foreground
      cycle and a Wi-Fi ↔ cellular transition
- [ ] Crash-free sessions at or above 99%
- [ ] Rollback tested, not merely documented

The last line is the one that gets skipped. A rollback nobody has performed is a plan,
not a capability.
