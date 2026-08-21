# Contributing to Plink

This document is the working agreement for this repository. It exists so that any
engineer — on day one or year three — can tell what "done" means here without
asking.

## Table of contents

- [Before you start](#before-you-start)
- [Branches](#branches)
- [Commits](#commits)
- [Pull requests](#pull-requests)
- [Code style](#code-style)
- [Language policy](#language-policy)
- [Comments](#comments)
- [Architecture decisions](#architecture-decisions)
- [Tests](#tests)
- [Changelog and releases](#changelog-and-releases)
- [Things we do not do](#things-we-do-not-do)

## Before you start

```bash
make setup      # backend + landing dependencies, Prisma client, Xcode project
make check      # lint, typecheck, tests, landing build
```

`make check` runs what CI runs on a Linux runner, in the same order. Run it before
you push; it is much cheaper than a red pipeline.

It does **not** build the iOS app. CI does, in a separate workflow
([`ios.yml`](.github/workflows/ios.yml)) on a `macos-15` runner — but only when the
change touches `ios/`, because macOS runner minutes bill at 10× the Linux rate on a
private repository. A change that breaks the client from outside that directory will
not be caught there, so build it locally when you touch a shared contract. Device
builds and archives are local regardless
([runbook](docs/runbooks/ios-build-and-release.md)). `make xcode` regenerates the
project; `make android` builds the Android client, which CI does check but `check`
leaves out because a Gradle build is slow enough that nobody would run the target.

If you are touching an area you have not worked in before, read the relevant page
under [`docs/architecture/`](docs/architecture/) first. The realtime protocol in
particular has invariants that are not obvious from the call sites — see
[`docs/architecture/realtime-protocol.md`](docs/architecture/realtime-protocol.md).

## Branches

`main` is protected, always deployable, and only ever receives squashed pull
requests. There is no `develop` branch.

Branch from `main` using `<type>/<short-slug>`:

```
feat/host-migration-badge
fix/drift-badge-ipad-landscape
chore/bump-fastify-5
docs/adr-realtime-epoch
```

Delete your branch after the merge. Long-lived branches are how a monorepo rots.

## Commits

We use [Conventional Commits](https://www.conventionalcommits.org/). CI validates
the pull request title against this format, and the changelog is assembled from it.

```
<type>(<scope>): <summary in the imperative, lowercase, no trailing period>
```

**Types:** `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`,
`chore`, `revert`.

**Scopes:** `ios`, `backend`, `landing`, `android`, `realtime`, `auth`, `rooms`,
`billing`, `admin`, `design`, `docs`, `ci`, `deps`.

```
feat(realtime): migrate host to longest-present member on disconnect
fix(ios): stop the room cover from stretching the tab bar
perf(backend): batch presence lease renewals into one Redis round trip
```

The body answers **why**, not what — the diff already says what. If the change
carries risk, say what you verified and what you did not:

```
fix(backend): reject commands from a superseded host by epoch

A host that reconnected after a network drop kept sending commands with the
old epoch, and the gateway applied them, yanking playback backwards for every
participant.

Epoch is now bumped before role.changed is published, so in-flight commands
from the previous host fail the epoch check rather than racing it.

Verified: 7 new contract tests, two-device manual run on 17 Pro + 15.
Not verified: three-way host handoff under packet loss.
```

Breaking changes carry `!` and a `BREAKING CHANGE:` footer explaining the
migration. For the realtime protocol, a breaking change means **both** the
TypeScript contract and the Swift decoder in the same pull request — the parity
test exists to enforce that.

## Pull requests

Keep them reviewable. A pull request that touches three systems and 60 files will
get a shallow review, which is worse than a slow one.

Requirements:

1. `make check` passes locally.
2. The description follows [the template](.github/pull_request_template.md) and says
   how you verified the change — not "tested locally".
3. New behaviour has a test. Bug fixes have a test that fails before the fix.
4. User-visible strings are localized in every supported locale
   ([localization guide](docs/architecture/localization.md)).
5. At least one approval from a code owner ([CODEOWNERS](.github/CODEOWNERS)).
6. Screenshots or a screen recording for any UI change, light **and** dark.

Reviewers: comment on correctness, boundaries, and naming. Formatting is the
linter's job — if you find yourself arguing about whitespace, the tooling is
misconfigured and that is the bug to file.

## Code style

Style is enforced by tools, not by review. The TypeScript half runs from `make lint`;
the Swift half runs from `make ios`, which is separate because it needs macOS and the
two Homebrew tools.

| System     | Tools                                   | Config                                                                                                         |
| ---------- | --------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `backend/` | ESLint (typescript-eslint), Prettier    | [`backend/eslint.config.js`](backend/eslint.config.js), [`.prettierrc.json`](.prettierrc.json)                 |
| `landing/` | ESLint (next/core-web-vitals), Prettier | [`landing/eslint.config.mjs`](landing/eslint.config.mjs), [`landing/.prettierrc.mjs`](landing/.prettierrc.mjs) |
| `ios/`     | SwiftLint, SwiftFormat                  | [`ios/.swiftlint.yml`](ios/.swiftlint.yml), [`ios/.swiftformat`](ios/.swiftformat)                             |
| everything | EditorConfig                            | [`.editorconfig`](.editorconfig)                                                                               |

`make format` applies every fix that can be applied automatically. Do not commit a
formatting-only change mixed into a behavioural one; split it.

The two Swift tools have a strict division of labour, and it is worth knowing before
you edit either config: **SwiftFormat owns whitespace and layout and rewrites files;
SwiftLint owns semantics and project policy and only reports.** Every rule SwiftFormat
can fix is disabled in `.swiftlint.yml`. Re-enabling one gives you two tools with
opinions about the same comma, and the linter will start failing on what the formatter
just wrote.

### Formatting is a ratchet, not a wall

`backend/src` predates `.prettierrc.json` by roughly 13,000 lines of whitespace, so
`npm run format:check` there does **not** pass on a clean checkout. That is a known
debt, recorded rather than hidden.

CI therefore checks formatting on the files a change touches, not on the whole tree
— the `format` job in [`ci.yml`](.github/workflows/ci.yml). The consequence for you
is simple: **a file you edit has to come out formatted**, which for most edits means
running `make format` before pushing. The formatted share of the repository only
grows.

`landing/` is already fully formatted and is checked absolutely, in its own job. When
`backend/src` is finally reformatted it must be its own commit with nothing else in
it, and its SHA goes into [`.git-blame-ignore-revs`](.git-blame-ignore-revs) so
`git blame` keeps working.

`ios/` works the same way and for the same reason. A full SwiftFormat pass reports
1,937 findings across 137 of the 220 files it reads — more than half the client, and a
`git blame` rewrite of all of it. So `make format-ios` formats only the Swift files
changed against `origin/main`, and `make format-check-ios` checks only those. The
`lint` job in [`ios.yml`](.github/workflows/ios.yml) runs both on a `macos-15` runner
and asserts the two binaries are on `PATH` first — the Make recipes exit 0 with a skip
notice when a tool is missing, which is right on a Linux development machine and would
otherwise let a failed `brew install` produce a green run that checked nothing.

Three things about the configs are load-bearing and easy to undo by accident:

- `landing/` composes its ESLint config from `@next/eslint-plugin-next` directly
  instead of extending `eslint-config-next`, because that package bundles an
  ESLint-9-era toolchain and throws under ESLint 10. The reason is written at the
  top of the file; read it before "simplifying" it.
- `backend/eslint.config.js` ends in an enumerated list of files exempted from the
  `console.*` and `process.env` rules. That list may shrink and must never grow. A
  file not on it fails the build on a new violation.
- `ios/.swiftlint.yml` splits severities on purpose: **`error` is for invariants that
  are currently at zero**, so a failure is a real regression rather than accumulated
  debt, and **`warning` is for measured debt with the count written next to the
  rule**. Today that is 0 errors and 4,697 warnings. Do not promote a warning to an
  error without first clearing it, and do not raise a threshold to silence a hit —
  a threshold set above the existing debt reports nothing at all, which is worse than
  a warning nobody has cleared yet.

### The rules, and what they actually enforce today

Some of these are gates. Some are ratchets on debt that already exists. The
difference matters, so it is written down rather than implied — a rule described as
absolute when the tree has four thousand violations of it teaches you to ignore the
linter.

Gates — at zero, and the check is what keeps them there:

- **No `as!` or `try!` in Swift.** A failed force cast takes the whole process down,
  and this app runs for the length of a film — a crash costs the session, not one
  screen. Three legitimate sites carry an inline `swiftlint:disable:next` with the
  reason; add a fourth only with one.
- **No `TODO`/`FIXME` on `main`.** Fix it, or file an issue and link it.
- **No substring host matching.** `evil-vk.com.ru` contains `vk.com`, so a substring
  check accepts it and every participant in the room loads the attacker's page. Match
  through `PlinkHost.matches` only. See
  [ADR-0004](docs/adr/0004-strict-host-matching.md). The `security` job in
  [`ci.yml`](.github/workflows/ci.yml) greps for the same thing.
- **No `console.log` in the backend.** Use the Fastify logger so output is
  structured, correlated by request id, and redacted.
- **No raw `process.env` outside `backend/src/config/`.** Configuration is
  validated once at boot. See [ADR-0006](docs/adr/0006-fail-fast-configuration.md).

Ratchets — real debt, counted, allowed to fall and not to rise:

- **Prefer no force unwrapping in Swift.** 36 sites in `ios/Plink/` across 22 files,
  plus 18 in tests. Most are `URL(string: <literal>)!` and safe by construction; a
  handful are not. Clearing one means deciding what the non-crashing behaviour should
  be, which needs the test suite rather than a lint pass — hence a warning.
- **Prefer the design tokens over hardcoded typography and colour.** 457 hardcoded
  font sizes and 260 colour literals outside the token directories. Three UI
  generations drifted apart once and the token layer is what stops the fourth, but it
  is not yet universal and the config does not pretend otherwise. New code uses
  tokens; existing code converts as you touch it. See
  [ADR-0010](docs/adr/0010-design-tokens-as-the-only-style-source.md).
- **English comments** (ADR-0001). 3,773 Russian comment lines remain, across 152
  files; the ten worst hold a quarter of them. Translate the ones in a file you are
  already editing rather than opening a translation pull request — a bulk pass over
  comments you are not otherwise reading is how a wrong explanation gets confidently
  restated in English. Re-measure with the rule's own pattern:

  ```bash
  grep -rnE '(//|///|\*)[ \t]*.{0,60}[А-Яа-яЁё]{4,}' ios \
    --include='*.swift' | grep -v '/Localization/' | wc -l
  ```

  Run it from the repository root, and note that it walks `ios/.spm-cache/` if a
  build has populated it — 1.4 GB of dependency checkouts, none of them ours. They
  hold no Cyrillic, so the number is unaffected; it is only slow.

  `swiftlint` reports 3,555 for the same regex rather than 3,773, and the gap is not
  drift: the rule counts matched regions while this counts matching lines, and
  SwiftLint's reported line numbers wander on files this dense with multibyte text.
  The grep is the figure to quote.

  `Localization/` is excluded because `LocalizationManager.swift` is the Russian
  string catalog itself, not a file commented in Russian. Russian _string literals_
  are a separate matter and not covered by this rule — they are correct product copy
  sitting in the wrong layer; see
  [docs/architecture/localization.md](docs/architecture/localization.md).

- **No ticket references in comments.** 74 remaining (`Pack v3:`, `Phase 2.6:`,
  `FIX C3:`). They point at documents that no longer exist, so the reader learns
  nothing and can verify nothing. Rewrite the ones you touch to state the constraint
  instead. History is in `git log`; decisions are in `docs/adr/`.

The token layer is four directories, not one, and the boundary is not where you would
guess: `ios/Plink/V4/` holds colour (`V4Theme.swift` is the source of truth for it,
and it is **not** under `Design/`), `Design/Cinematic/` holds density,
`Design/Glass/` holds surface treatment, `Design/Identity/` holds identity rings.

### Xcode project file

`ios/Plink.xcodeproj` is **generated** and not committed. Change
[`ios/project.yml`](ios/project.yml) and run `xcodegen generate`. A pull request
containing `project.pbxproj` will be rejected.

## Language policy

Plink ships in Russian first and is expanding internationally, so the two audiences
are kept strictly apart:

| What                                        | Language                        |
| ------------------------------------------- | ------------------------------- |
| Identifiers, types, functions, files        | English                         |
| Code comments                               | English                         |
| Commit messages, pull requests, code review | English                         |
| Documentation in `docs/`, `README`, ADRs    | English                         |
| **User-facing product copy**                | **Localized — never hardcoded** |

Rationale: the product is Russian-language, but the codebase is a shared
engineering artifact that new contributors from any locale must be able to read.
Mixing both languages inside one file — which this repository did for a long time —
makes it unsearchable and unreviewable. Recorded as
[ADR-0001](docs/adr/0001-english-as-the-engineering-language.md).

User-facing text never appears as a literal in a view. Add a key to the string
catalog and reference it, so translators can work without touching Swift.

## Comments

Write comments a stranger can act on. The test: **if this comment is still here in
two years, does it help or mislead?**

Do explain _why_ — the constraint, the failure it prevents, the alternative that
was rejected:

```swift
// Presence leases renew at 20s against a 60s TTL. Two missed renewals still
// leave a full interval of headroom, so a brief network stall does not evict a
// participant mid-film.
```

Do not narrate the project's history in the source. These are all real examples
that used to be in this codebase, and all of them are now forbidden:

```swift
// ❌ Audit 2026-08-07 (finding #14): this used to be broken, now fixed
// ❌ PATCH 15: re-enabled LiveKit
// ❌ §20 rule: app.ts builds the Fastify instance for tests
// ❌ P1-64: schema exists but nobody calls it
// ❌ M16: group chats
```

They fail for the same reason: they reference a document, ticket tracker, or
session that no longer exists, so the reader learns nothing and cannot verify
anything. History belongs in `git log`, decisions belong in
[`docs/adr/`](docs/adr/), and release notes belong in
[`CHANGELOG.md`](CHANGELOG.md).

If a comment needs to point at a decision, link the ADR: `// See ADR-0004.`

`TODO` and `FIXME` are not allowed on `main`. Either fix it, or file an issue and
link it: `// Known gap: three-way host handoff is untested — see issue #142.`

## Architecture decisions

Anything that constrains future work gets an ADR: protocol shape, storage
authority, a dependency we cannot easily remove, a deliberate product limitation.

```bash
cp docs/adr/template.md docs/adr/00NN-short-title.md
```

Keep them short — context, decision, consequences — and never rewrite an accepted
one. Superseding an ADR means writing a new one that says so. Index:
[`docs/adr/README.md`](docs/adr/README.md).

## Tests

```bash
cd backend
npm test                   # unit + contract + integration
npm run test:integration   # Redis-backed only; requires REDIS_URL
npm run test:coverage      # enforces the configured thresholds
```

The suite must be green on a clean checkout with no environment file. A test that
needs a real service either provisions it or skips loudly — silent skips are how a
suite quietly stops testing anything, so the reporter prints every skip at the end
of the run.

Three categories carry specific weight:

- **Contract tests** (`backend/src/tests/contract/`) compare realtime schemas
  against the Swift decoders. They fail when one side of the protocol changes
  alone.
- **Integration tests** (`backend/src/tests/integration/`) run against real Redis.
- **Funnel UI tests** (`ios/PlinkUITests/`) walk sign-in → create room → join.

See [`docs/qa/testing-strategy.md`](docs/qa/testing-strategy.md) for what belongs
at which level.

## Changelog and releases

[`CHANGELOG.md`](CHANGELOG.md) follows [Keep a Changelog](https://keepachangelog.com)
and the project follows [Semantic Versioning](https://semver.org).

Add your entry under `## [Unreleased]` in the same pull request as the change.
Write it for whoever reads release notes, not for the reviewer:

```markdown
### Fixed

- A host losing connection no longer ends the room for everyone; the role moves
  to the longest-present participant and playback continues.
```

Release process, version bumps, and tagging: [`docs/runbooks/release.md`](docs/runbooks/release.md).

## Things we do not do

Hard lines. If a change requires one of these, it needs a discussion and an ADR,
not a pull request.

- **No DRM circumvention.** Netflix, Disney+, and similar are never loaded into an
  embedded player pretending it will work. They are supported through screen share
  and labelled as such. See [ADR-0003](docs/adr/0003-honest-service-catalog.md).
- **No placeholder content in shipped surfaces.** A screen with invented data is
  worse than a screen that says the feature is not ready.
- **No feature flags that fail open.** A flag guarding an unfinished paid feature
  defaults to off, so a fresh deployment cannot sell something that does not work.
- **No secrets in the repository**, including in tests and fixtures.
- **No silently disabled tests.** Skips are reported at the end of every run.
