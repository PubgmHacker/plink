# Testing strategy

What is tested, where, what actually gates a merge, and what does not. Every number
here was measured on 2026-08-20; the commands to re-measure are in each section.

## The shape of it

| Where       | Framework      | Files  | Tests | Runs in CI                  |
| ----------- | -------------- | -----: | ----: | --------------------------- |
| `backend/`  | vitest 4       |     21 |   202 | Yes — gates every PR        |
| `ios/`      | XCTest         |     38 |   458 | Yes, on changes under `ios/` — [why it is filtered](#why-the-ios-job-is-its-own-workflow) |
| `android-client/` | JUnit    |      1 |     1 | Yes — `testDebugUnitTest`   |
| `landing/`  | none           |      0 |     0 | Typecheck, lint, format, build only |

`landing/` has no tests at all. That is a real gap, stated rather than papered over:
the marketing site is checked by `tsc --noEmit`, ESLint, Prettier and a production
`next build`, which catches type and syntax breakage but nothing about behaviour.

The `Files` column counts files that hold at least one test. `ios/PlinkTests/` has
41 Swift files, of which 37 hold tests; the other four are fakes and fixtures
(`FakeAuthService`, `FakeRoomService`, `FakePlaybackController`, `RegressionMatrix`).
The 38th file in the column is the funnel test in `ios/PlinkUITests/`, which the CI
job deliberately does not run.

## Backend: three tiers, and what puts a test in each

```
backend/src/tests/
├── unit/          9 files,  59 tests   pure functions, no I/O
├── contract/      7 files, 121 tests   shapes and invariants, no I/O
├── integration/   5 files,  22 tests   real Redis, real Postgres
├── setup.ts                            shared bootstrap
└── redisSkipReporter.ts                makes a skipped suite loud
```

**Unit** — a function, called directly, no network, no database, no Redis. The
constraint that decides this tier is not taste, it is [ADR-0006](../adr/0006-fail-fast-configuration.md):
`src/config/index.ts` validates the environment at *module scope* and throws
`Missing env: DATABASE_URL` if it cannot. Any module that imports `config`, however
indirectly, drags that into the test process.

That is not hypothetical. `appleIdentity.unit.test.ts` imported one pure string
function from `utils/appleIdentity.ts`, which imports `config` and builds a remote JWKS
client at module scope — so the test failed on any machine without `DATABASE_URL`
exported, for reasons having nothing to do with the function under test. The fix was to
move the pure function to `utils/appleUsername.ts` and re-export it from the original
module, so the single production call site did not change.

The rule that follows: **if a unit test needs an env var, the boundary is wrong.**
Extract the pure part into its own module rather than reaching for `vi.mock` on
`config` — a mock hides the coupling, an extraction removes it.

**Contract** — the shapes both sides of the wire agree on, verified without I/O. This
is the largest tier (121 of 202 tests) and deliberately so: the realtime protocol is
where a client and a server drift apart silently.

`protocol-parity.contract.test.ts` is worth reading as the pattern. It does not
hand-maintain a list of message types the iOS client understands; it reads
`ios/Plink/Realtime/RealtimeEnvelope.swift`, extracts the `case "…":` literals from the
decoder's `switch`, and compares that set against `SERVER_MESSAGE_TYPES` in both
directions. A backend type with no Swift case fails; a Swift case no backend code sends
fails. It also asserts that it parsed more than five cases at all, so that a refactor
which breaks the parser fails loudly instead of passing vacuously on an empty set.

**Integration** — talks to real Redis and real Postgres. Skipped, not failed, when
`REDIS_URL` is unset, which is why the reporter below exists.

Re-measure any tier:

```bash
cd backend
npx vitest run src/tests/unit          # or contract, or integration
npx vitest run                         # everything
```

## Skips are loud

A skipped test that says nothing is indistinguishable from a passing one. Running the
full suite without Redis prints:

```
 Test Files  20 passed | 1 skipped (21)
      Tests  201 passed | 1 skipped (202)

──────────────────────────────────────────────────────────────
⚠ 1 integration test(s) skipped: REDIS_URL is not set
  Start Redis and run: npm run test:integration
──────────────────────────────────────────────────────────────
```

That banner comes from [`redisSkipReporter.ts`](../../backend/src/tests/redisSkipReporter.ts),
registered in `vitest.config.ts`. It exists because "100 passed" on a machine with
Redis and "86 passed" on a machine without it are both green, and the second one is a
lie by omission.

The reporter has already failed once in exactly the way it was built to prevent: it was
written against the vitest 3 `onFinished(files)` hook, which vitest 4 simply stops
calling — not an error, just silence. It now uses `onTestRunEnd`. **After any vitest
major upgrade, stop Redis, run the suite, and confirm the banner still appears.** That
is the one manual check this repository genuinely needs.

For the same reason the config imports the reporter as a typed module rather than
naming it as a path string: renaming or deleting the file is then a compile error, not
a silent runtime miss.

## iOS: 458 tests, on a path-filtered macOS runner

Measured by running them:

```
Executed 458 tests, with 32 tests skipped and 0 failures (0 unexpected) in 1.809 seconds
Test Suite 'All tests' passed
```

41 files under `ios/PlinkTests/` (37 `XCTestCase` subclasses, 458 test methods) plus one
UI test in `ios/PlinkUITests/`. To run them yourself:

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

`CODE_SIGNING_ALLOWED=NO` is what lets this run without provisioning; the simulator
does not need a signed binary. Splitting build from run is not ceremony — it is how you
tell a compile failure apart from a test failure in the log.

No `-only-testing:PlinkTests` is needed. The `Plink` scheme's test action names that
bundle and only that bundle, so the default is already correct — see below.

### The 32 skips are all opt-in, and all say why

| Class | Skipped | Enabled by |
| ----- | ------: | ---------- |
| `DesignAuditShots` | 16 | `DESIGN_AUDIT=1`, or a flag file `/tmp/plink-design-audit` |
| `YouTubePlaybackControllerRuntimeTests` | 10 | `YOUTUBE_RUNTIME_TESTS=1` (needs network and a device) |
| `MarketingShots` | 4 | `MARKETING_SHOTS=1`, or `/tmp/plink-marketing-shots` |
| `ThemeSnapshotTests` | 2 | `SNAPSHOT_TESTS=1` (results depend on simulator model) |

`DesignAuditShots` and `MarketingShots` are not regression tests and do not assert on
pixels — they render real product screens offscreen and write PNGs, for design review
and for the landing page respectively. Their headers document two findings worth
knowing before touching them:

- `xcodebuild test` does **not** forward the shell environment into the simulator
  process, which is why a flag file exists alongside the env var. The env var only works
  when running the bundle directly or when set in the scheme.
- The flag file must live in `/tmp`. An app on the simulator is an ordinary macOS
  process, so reading a file under `~/Desktop` or `~/Documents` hangs the test on a TCC
  permission prompt with nobody there to answer it.

The remaining two are environment-dependent by nature: snapshot comparisons vary by
simulator model, and the YouTube runtime tests need a real network and a real device.

### Why the iOS job is its own workflow

It runs from [`.github/workflows/ios.yml`](../../.github/workflows/ios.yml) rather than
`ci.yml`, and it is filtered to changes under `ios/`. The reason is cost, not
architecture: this repository is private, so macOS runner minutes bill at **10×** the
Linux rate. Every job in `ci.yml` is cheap enough to run unconditionally; a full Xcode
build on a backend-only pull request would cost more than it tells us.

⚠️ **The filter is why this job must not be a required status check.** A path-filtered
job does not run at all on a pull request that touches nothing under `ios/`, and a
required check that never runs blocks that pull request forever. If it should gate
merges, drop the filter first and accept the per-PR cost.

Three things were named as blockers before it existed. Only the first turned out to be
one:

1. **No macOS runner was provisioned.** True, and the only real blocker. `runs-on:
   macos-15` resolves it.
2. **Signing credentials are not in CI secrets.** Irrelevant to a simulator build. With
   `CODE_SIGNING_ALLOWED=NO` there is no certificate and no provisioning profile in the
   picture at all — measured, `** TEST BUILD SUCCEEDED **`. Device builds and archives
   still happen locally, and those do need credentials.
3. **No shared scheme was under version control.** This one was real and had to be fixed
   first. The `.xcodeproj` is generated and gitignored on purpose
   ([ADR-0007](../adr/0007-generated-xcode-project.md)), and `ios/project.yml` declared
   no `schemes:` key — so `xcodebuild` synthesized `Plink` and `PlinkWidget` per-user, in
   memory, neither of them referencing a test bundle. Whether `xcodebuild test` found
   anything to run depended on whether someone had opened the project in Xcode.
   `project.yml` now declares the schemes explicitly, and XcodeGen writes them into
   `xcshareddata` where a reviewer can read what CI runs.

Two schemes are declared, and the split is deliberate:

| Scheme | Test action | Runs in CI |
| ------ | ----------- | ---------- |
| `Plink` | `PlinkTests`, with coverage | Yes |
| `Plink-UITests` | `PlinkUITests` | No |

`PlinkUITests` drives the real UI against a backend on `localhost`. In CI it would fail
for a reason that is not a defect, so it is kept out of the default test action: a red
`Plink` scheme always means something is actually broken.

The job also asserts the skip count rather than trusting the exit code. A test that
starts skipping itself has stopped running, and a run where that happened is
indistinguishable from a green one. Growth past 32 fails the job; a drop does not,
because that means a suite was made hermetic.

## What gates a merge

From [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml), on every push:

| Job | Steps |
| --- | ----- |
| `backend` | Prisma generate → `tsc --noEmit` → `eslint .` → `vitest run` → `npm audit --audit-level=high` |
| `landing` | `tsc --noEmit` → `eslint .` → `prettier --check` → `next build` → `npm audit` |
| `format` | Prettier, **on files changed by the PR only** |
| `security` | No external scripts in server-rendered pages · host matching goes through `PlinkHost` · no committed private keys |
| `android` | `assembleDebug` → `testDebugUnitTest` |

From [`.github/workflows/ios.yml`](../../.github/workflows/ios.yml), only when `ios/`
changes — and **not** as required checks, for the reason given above:

| Job | Steps |
| --- | ----- |
| `build-and-test` | `xcodegen generate` → `build-for-testing` → `test-without-building` → assert the skip count |
| `lint` | SwiftLint (errors gate) → SwiftFormat, **on files changed by the PR only** |

Three of these are worth understanding rather than just obeying:

The **`format` job checks only changed files.** A full Prettier pass would rewrite
history across the tree, so the formatted share grows as files are touched. The same
ratchet applies to Swift via `make format-ios`. See [CONTRIBUTING.md](../../CONTRIBUTING.md).

The **audit gate is `high` because the count is currently zero.** The remaining moderate
advisories share one root (`@opentelemetry/core` via `@sentry/node` 8) and clear only on
a major upgrade. A gate set below existing debt reports nothing, so it stays above them
— deliberately, and written down here rather than left as a silent exception.

The **iOS lint job asserts its own tools are installed.** `make lint-ios` and `make
format-check-ios` print a skip notice and exit 0 when SwiftLint or SwiftFormat is absent,
which is correct on a Linux development machine and dangerous in CI — a failed `brew
install` would make both steps pass without checking anything. The job checks for the
binaries on `PATH` in a separate step, so the skip path cannot produce a green run.

## Adding a test

Pick the tier by what the test touches, not by what it is about:

- Touches nothing but arguments and a return value → `unit/`. If it needs an env var,
  extract the pure function first.
- Asserts on a shape, a schema, an enum, or agreement between two sides → `contract/`.
- Needs Redis or Postgres → `integration/`, and it must skip rather than fail when they
  are absent.
- Concerns a SwiftUI view, a controller, or client state → `ios/PlinkTests/`.

Two rules that come from defects already fixed here:

**Never assert against rendered copy.** A view once decided whether to draw the online
dot with `headerPresence == "в сети"`, reconstructing a predicate from display text.
Compare against the predicate — `FriendPresence.isEffectivelyOnline(isOnline:lastSeenAt:)`
— not the string it renders. [Localization](../architecture/localization.md) covers why
presence copy is output only.

**A test that cannot fail is worse than no test.** If a test parses, greps, or
enumerates something, assert that it found a plausible amount before asserting on the
contents. `protocol-parity.contract.test.ts` checks it parsed more than five cases for
exactly this reason.

## Known gaps

Recorded so nobody has to rediscover them:

- `landing/` has no tests. It typechecks, lints and builds in CI, and nothing asserts
  behaviour — the largest single gap on this page.
- The iOS workflow is path-filtered to `ios/**`, so a change that breaks the client
  from outside that directory — a backend contract, a shared protocol constant — does
  not run it. The contract tests in `backend/src/tests/contract/` exist to cover that
  seam; they are not a substitute for the client build.
- Both formatting checks gate pull requests only — the Prettier `format` job in
  `ci.yml` and the SwiftFormat step in `ios.yml` are each guarded by
  `if: github.event_name == 'pull_request'`, because the changed-file comparison has
  no base branch to diff against on a push. A commit pushed straight to `main` is
  never format-checked; on the run for `0455e57` the `format` job reports `skipped`.
- The Android client has a single smoke test.
- Coverage is collected (`npm run test:coverage`) but no threshold is enforced, so the
  number is informational.
