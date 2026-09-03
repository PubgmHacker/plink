# Cutting a release

Coordinating a release across the four surfaces: which version numbers move, in what
order things ship, and how the tag is cut. The mechanics of each surface live elsewhere —
this page is the order of operations and the checks between the steps.

- **Backend only:** you do not need this page. Go to [deployment.md](deployment.md).
- **iOS build mechanics:** [ios-build-and-release.md](ios-build-and-release.md).
- **Something is broken in production:** [incident-response.md](incident-response.md).

---

## 0. Read this before your first release

**Nothing has been released yet.** `git tag` returns nothing, and `CHANGELOG.md` says so
in as many words. The first tag will be `v1.0.0`.

The four surfaces do **not** share a version number, and today they disagree:

| Surface | Where the version lives                                                  | Today             |
| ------- | ------------------------------------------------------------------------ | ----------------- |
| iOS     | `ios/project.yml` → `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`       | `1.0`, build `1`  |
| Backend | `backend/package.json` → `version`                                       | `1.5.2`           |
| Landing | `landing/package.json` → `version`                                       | `0.1.0`           |
| Android | `ios/android-client/app/build.gradle.kts` → `versionName`, `versionCode` | `1.0.0`, code `1` |

That spread is not a scheme, it is drift from before there was a process. **The release
tag tracks the iOS marketing version**, because that is the version a user can see and
name in a support message. The backend and landing versions are internal and move
independently; nothing reads them at runtime.

There is also a fifth number, and it is the one that will mislead you: `GET /health`
reports `"version": "2.0.0-stabilize"`, a string literal in `backend/src/app.ts`. It
tracks nothing and has never been bumped. **Do not use it to confirm a deploy** — use the
commit SHA in the platform's deploy log. Making it read `package.json` is a small change
nobody has made yet.

Before the first release, reconcile the rest: set `backend/package.json` and
`landing/package.json` to `1.0.0` so that "which version is this" has one answer. Do it
as its own pull request, not inside a release.

---

## 1. Decide the version

Semantic versioning, judged from the user's side rather than the diff's:

- **Patch** (`1.0.0` → `1.0.1`) — fixes only. Nothing new appears in the app.
- **Minor** (`1.0.0` → `1.1.0`) — a user can do something they could not do before.
- **Major** (`1.0.0` → `2.0.0`) — something a user relied on works differently, or a
  realtime protocol change is not backward compatible with a shipped client.

The third case is the one that bites. A client in the wild that cannot decode a message
the server now sends is a major change even if the code diff is three lines. Check the
[realtime protocol](../architecture/realtime-protocol.md) contract before deciding, and
check that `protocol-parity.contract.test.ts` still passes — if it does not, you are
shipping a break.

---

## 2. Roll the changelog

1. Open [`CHANGELOG.md`](../../CHANGELOG.md).
2. Rename `## [Unreleased]` to `## [1.0.0] — 2026-08-16`, using today's date in
   ISO-8601.
3. Add a fresh empty `## [Unreleased]` above it.
4. Read the entries as a user would. Delete anything that describes a refactor, a test,
   or a build change — those belong in the pull request, not in release notes. If a
   section ends up empty, remove the heading.

**Check:** the new version section has at least one entry, and no entry mentions a file
path, a class name, or a ticket number.

Entries are written under `[Unreleased]` in the same pull request as the change, so this
step is a review, not a writing session. If it turns into a writing session, the process
upstream of it failed — see [CONTRIBUTING.md](../../CONTRIBUTING.md#changelog-and-releases).

---

## 3. Bump the versions

```bash
# iOS — the version the tag will track
$EDITOR ios/project.yml          # MARKETING_VERSION, and CURRENT_PROJECT_VERSION += 1

# Backend and landing, if they are moving
$EDITOR backend/package.json     # "version"
$EDITOR landing/package.json     # "version"
```

The iOS pair is explained in [ios-build-and-release.md
§2](ios-build-and-release.md#2-version-and-build-number). The rule that matters here:
`CURRENT_PROJECT_VERSION` must increase on **every** upload to App Store Connect, not
only on a release — a duplicate build number is rejected after the upload finishes and
the archive is wasted.

**Check:**

```bash
cd ios && xcodegen generate && grep -m2 -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" \
  Plink.xcodeproj/project.pbxproj
```

The regenerated project must show the values you just set. If it does not, you edited a
generated file instead of `project.yml`.

---

## 4. Verify before shipping anything

From the repository root:

```bash
make check          # lint, typecheck, backend tests, landing build
make integration    # backend integration suite — refuses to run without REDIS_URL
make android        # only if the Android client changed
```

`make check` already runs the backend unit and contract suites, so there is no need for a
separate `make test` here. `make integration` is separate on purpose: it needs a live
Redis, and it fails rather than skipping itself when `REDIS_URL` is missing, so a green
result means it actually executed.

The iOS checks need a macOS host and the Homebrew tools:

```bash
make ios            # SwiftLint (errors gate) + SwiftFormat check on changed files
```

The iOS **test** suite is not in `make check`. CI runs it on every change under `ios/`
([`ios.yml`](../../.github/workflows/ios.yml)), but that workflow is path-filtered and is
therefore not a required check — so on a release commit, confirm the run yourself rather
than assuming it happened:

```bash
cd ios
xcodegen generate
xcodebuild build-for-testing -project Plink.xcodeproj -scheme Plink \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/plink-dd CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building -project Plink.xcodeproj -scheme Plink \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/plink-dd CODE_SIGNING_ALLOWED=NO
```

**Check:** `make check`, `make integration` and `make ios` exit 0, and the iOS run
reports **0 failures**. 32 skips are expected and correct — they are opt-in screenshot
and network suites, each of which prints its reason
([testing strategy](../qa/testing-strategy.md#the-32-skips-are-all-opt-in-and-all-say-why)).

Do not proceed on a red suite. There is no version of this where you tag first and fix
after; the tag is the thing people will bisect against.

---

## 5. Ship the backend first

**Order matters and it is not arbitrary.** The backend goes out before the client,
because a client that sends a request the server does not understand yet is broken for
every user who updated, while a server that supports a message no client sends yet is
inert.

1. Follow [deployment.md §1](deployment.md#1-a-normal-deploy).
2. Wait for `/health/ready` to return 200 with both services `up`.
3. Run the end-to-end happy path against the deployed host. It signs up two throwaway
   accounts (`e2e_*@plink.lab`), creates a room, connects both over WebSocket and
   checks that a host play command and a chat message reach the viewer:

   ```bash
   cd backend && E2E=1 API_BASE=https://<host> \
     npx vitest run src/tests/integration/happyPath.e2e.test.ts
   ```

**Check:**

```bash
curl -s https://<host>/health | python3 -m json.tool | head -20
```

`status` is `ok`, `services.database` and `services.redis` are both `up`, and the
happy path reports `1 passed`.

Two traps in that response. `status: "degraded"` with a 503 is what you get when Redis
reports `not_configured` — that is a missing `REDIS_URL`, not a dead Redis, and it means
the realtime gateway was never constructed, so the API is up and nobody can watch
together. And the `version` field is the hardcoded string from step 0; ignore it and
confirm the deploy from the commit SHA instead.

If this step fails, stop. Nothing after it has happened yet, so there is nothing to roll
back beyond the backend itself — [deployment.md §6](deployment.md#6-rollback).

---

## 6. Ship the landing site

Only if it changed. It deploys from the same push; verify the `/plus` page loads and the
purchase flow reaches YooKassa's confirmation URL before you consider it done.

**Check:** `/plus` renders, and a share link (`/r/<code>`) still unfurls with an Open
Graph image.

---

## 7. Submit the iOS build

Follow [ios-build-and-release.md §3](ios-build-and-release.md#3-testflight-build) for
TestFlight, then [§4](ios-build-and-release.md#4-app-store-submission) for the
submission.

**Check:** the build appears in App Store Connect with the build number you set in step
3, and TestFlight installs and launches against the deployed backend.

---

## 8. Tag

Tag only once the App Store build is submitted and the backend is live. The tag records
what shipped, so cutting it earlier makes it a statement about intent instead.

```bash
git tag -a v1.0.0 -m "1.0.0"
git push origin v1.0.0
```

Annotated, not lightweight — a lightweight tag carries no author or date. The `v` prefix
is the convention here; `1.0.0` without it is not.

**Check:**

```bash
git tag -n1 v1.0.0
git show v1.0.0 --stat | head -5
```

The tag points at the commit that contains the changelog roll and the version bumps.

---

## 9. Rollback

What you can actually undo, in the order you will want it:

| Shipped         | Can you roll it back?                                                                                                                 |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Backend         | Yes — [deployment.md §6](deployment.md#6-rollback).                                                                                   |
| Landing         | Yes, same mechanism.                                                                                                                  |
| Tag             | Yes: `git tag -d v1.0.0 && git push origin :refs/tags/v1.0.0`. Only worth doing within minutes; after that, tag the fix instead.      |
| App Store build | **No.** You can pull it from review or halt a phased release, but a build that shipped is shipped. The only forward is another build. |

Because the last row cannot be undone, the iOS submission is deliberately the last thing
in this runbook that changes the world. Everything reversible happens first, and every
step before it has a check that would have caught the problem.

If a release is already out and broken, this is not the page you want —
[incident-response.md](incident-response.md).

---

## What this runbook does not cover

- **Schema changes.** A migration is a deploy concern with its own ordering rules:
  [deployment.md §4](deployment.md#4-deploying-a-schema-change).
- **Subscription and App Store metadata**, which have their own review surface:
  [ios-build-and-release.md §4](ios-build-and-release.md#4-app-store-submission).
- **The Android client**, which has no release process yet. It is built from source and
  distributed by hand; `versionCode` still reads `1`. When that changes, it gets a
  section here.
