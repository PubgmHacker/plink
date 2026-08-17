// backend/eslint.config.js — ESLint flat config for the backend.
//
// Two jobs, in order of importance.
//
// 1. Enforce the invariants that documentation cannot enforce. `no-restricted-*`
//    rules below are the mechanical form of rules stated in CONTRIBUTING.md and
//    in the ADRs: configuration is read in one place, logging goes through the
//    Fastify logger. A rule that exists only in prose is a rule that gets broken
//    by someone who never read the prose.
//
// 2. Catch the ordinary mistakes typescript-eslint catches.
//
// Deliberately NOT type-aware. `projectService` would give better rules
// (no-floating-promises, no-misused-promises) at the cost of a full type-check
// per lint run — and `npm run typecheck` already does that separately. If the
// floating-promise rules become worth the wall-clock, switch to
// tseslint.configs.recommendedTypeChecked and add languageOptions.parserOptions
// .projectService = true.
//
// Severity policy: the invariants are errors. The style rules are warnings where
// the existing code cannot yet satisfy them, so that `make lint` is usable today
// rather than a wall of 2000 errors everyone learns to ignore. A warning here is
// a debt marker, not a preference.

import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  // ── What is not linted ───────────────────────────────────────────────────
  {
    ignores: [
      'dist/**',
      'node_modules/**',
      'coverage/**',
      'src/generated/**',
      'prisma/migrations/**',
      '*.config.js',
    ],
  },

  js.configs.recommended,
  ...tseslint.configs.recommended,

  // ── Applies to every linted file, whatever its language ──────────────────
  //
  // Stated once here rather than per-tree, because the reasoning does not
  // change between src/ and scripts/: an empty catch is allowed because several
  // paths swallow a failure deliberately (a cache miss, a best-effort cleanup,
  // an unparseable frame on a diagnostic probe). What is never intentional is an
  // empty `if`, `else`, or loop body.
  {
    rules: {
      'no-empty': ['error', { allowEmptyCatch: true }],
    },
  },

  // ── Project-wide rules ───────────────────────────────────────────────────
  {
    files: ['src/**/*.ts'],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'module',
    },
    rules: {
      // ── Invariants (errors) ──────────────────────────────────────────────

      // ADR-0006: configuration is read once, at boot, in src/config/.
      // Overridden for src/config/** below, which is the one place allowed to
      // touch the environment.
      'no-restricted-properties': [
        'error',
        {
          object: 'process',
          property: 'env',
          message:
            'Read configuration from src/config/ instead of process.env. See docs/adr/0006-fail-fast-configuration.md.',
        },
      ],

      // Output goes through the Fastify logger: structured, correlated by
      // request id, and redacted. console.* is unredacted and uncorrelated,
      // which in a request path means secrets in plaintext logs.
      // Boot-time diagnostics run before a logger exists; those files are
      // exempted individually below rather than by allowing methods globally.
      'no-console': 'error',

      // `catch {}` that swallows an error silently is how a failure becomes
      // invisible; see the repository-wide `no-empty` block above for the one
      // exception this codebase makes.

      eqeqeq: ['error', 'always', { null: 'ignore' }],
      'no-var': 'error',
      // ignoreReadBeforeAssign: the gateway declares `let joinedRoomId` and
      // `let capturedUser` up front so that `finalize`, defined below them, can
      // close over the values assigned later. ESLint counts one write and
      // suggests const; applying that suggestion would break the closure.
      'prefer-const': ['error', { ignoreReadBeforeAssign: true }],
      'no-throw-literal': 'error',

      // Off, not warn: every occurrence is a sanitizer stripping control
      // characters out of user input, which is the correct thing to do and the
      // only way to express it. See middleware/security.ts and routes/friends.ts.
      'no-control-regex': 'off',

      // ── Debt markers (warnings) ──────────────────────────────────────────
      // The existing code does not satisfy these. They are warnings so the
      // count is visible and shrinking rather than suppressed.

      // Declare-then-assign (`let x = null; ... x = await …`) is used
      // deliberately in several handlers. Worth flagging, not worth blocking.
      'no-useless-assignment': 'warn',

      // ESLint 10: a rethrow should carry `{ cause }`. Correct, and adopting it
      // means touching error paths one at a time.
      'preserve-caught-error': 'warn',

      // Fastify's plugin signature is untyped throughout this codebase
      // (`fastify: any`), and JWT payloads are `any` by construction.
      '@typescript-eslint/no-explicit-any': 'warn',

      '@typescript-eslint/no-unused-vars': [
        'warn',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
        },
      ],

      '@typescript-eslint/no-non-null-assertion': 'warn',
      '@typescript-eslint/ban-ts-comment': [
        'warn',
        { 'ts-expect-error': 'allow-with-description' },
      ],
    },
  },

  // ── src/config/ — the only place that may read the environment ───────────
  {
    files: ['src/config/**/*.ts'],
    rules: {
      'no-restricted-properties': 'off',
      // Certificate loading and invariant assertions report before the logger
      // is constructed. See src/utils/jose-config.ts and src/config/index.ts.
      'no-console': 'off',
    },
  },

  // ── Bootstrap and CLI entry points ───────────────────────────────────────
  // These run before, or instead of, a Fastify instance.
  {
    files: ['src/server.ts', 'src/utils/jose-config.ts', 'src/scripts/**/*.ts'],
    rules: {
      'no-console': 'off',
      'no-restricted-properties': 'off',
    },
  },

  // ── Tests ────────────────────────────────────────────────────────────────
  {
    files: ['src/tests/**/*.ts'],
    rules: {
      'no-console': 'off',
      'no-restricted-properties': 'off',
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
      // Vitest assertions on deliberately malformed input need loose types.
      '@typescript-eslint/no-unsafe-function-type': 'off',
    },
  },

  // ── Operational scripts ──────────────────────────────────────────────────
  //
  // scripts/ holds one-shot and diagnostic programs: migration baselines, an
  // admin bootstrap, live-database probes. They are run by a person from a
  // terminal, not served, so stdout *is* their output and the environment is
  // their only input — the two rules that matter most in src/ do not apply.
  //
  // These are plain .js/.mjs, so typescript-eslint's `eslint-recommended` layer
  // does not cover them and `no-undef` stays live. Node's globals are declared
  // explicitly rather than by pulling in the `globals` package for six names;
  // add to the list when a script needs one, and if the list grows past a
  // screen, take the dependency instead.
  {
    files: ['scripts/**/*.{js,mjs}'],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'module',
      globals: {
        process: 'readonly',
        console: 'readonly',
        Buffer: 'readonly',
        URL: 'readonly',
        fetch: 'readonly',
        setTimeout: 'readonly',
        clearTimeout: 'readonly',
        TextEncoder: 'readonly',
        TextDecoder: 'readonly',
      },
    },
    rules: {
      'no-console': 'off',
      'no-restricted-properties': 'off',
    },
  },

  // ═════════════════════════════════════════════════════════════════════════
  // LEGACY BASELINE — this list may shrink. It must never grow.
  // ═════════════════════════════════════════════════════════════════════════
  //
  // Both invariants above are errors project-wide, which is what CONTRIBUTING.md
  // and ADR-0006 say. The files below predate the rules and violate them. They
  // are exempted individually rather than by downgrading the rule to a warning,
  // because a warning applies everywhere — including to code written tomorrow —
  // and a warning that nobody clears is indistinguishable from no rule at all.
  //
  // What this buys: any file NOT on this list fails the build on a new
  // `console.*` or a new `process.env`, and that is currently most of the source
  // tree. A new file is never exempt.
  //
  // Clearing an entry means, for logging, routing the call through `request.log`
  // or `fastify.log` — structured, correlated by request id, redacted — and for
  // configuration, moving the read into `src/config/` so it is validated at boot.
  // Delete the entry in the same change. The counts are there so a partial
  // cleanup is visible.
  //
  // Do not add to this list. If a change needs a new exemption, the change is
  // going the wrong way.
  {
    files: [
      // console.* — 100 occurrences across 27 files
      'src/app.ts', // 1
      'src/middleware/security.ts', // 3
      'src/moderation/autoMod.ts', // 1
      'src/realtime/connectionRegistry.ts', // 1
      'src/realtime/gateway.ts', // 8
      'src/realtime/heartbeat.ts', // 1
      'src/realtime/roomEventBus.ts', // 4
      'src/realtime/roomPubSub.ts', // 2
      'src/realtime/roomQueueStore.ts', // 4
      'src/routes/ai.ts', // 5
      'src/routes/auth.ts', // 10
      'src/routes/billing.ts', // 8
      'src/routes/friends.ts', // 2
      'src/routes/media.ts', // 11
      'src/routes/messages.ts', // 14
      'src/routes/profile.ts', // 1
      'src/routes/rooms.ts', // 7
      'src/services/accountTombstone.ts', // 3
      'src/services/moderation/moderationAudit.ts', // 1
      'src/services/passwordReset.ts', // 1
      'src/services/pushService.ts', // 2
      'src/services/roomLifecycle.ts', // 1
      'src/services/streamExtractor.ts', // 3
      'src/services/telemetry.ts', // 2
      'src/utils/alerting.ts', // 1
      'src/utils/audit.ts', // 1
      'src/utils/privilegedUsers.ts', // 2
    ],
    rules: { 'no-console': 'off' },
  },
  {
    files: [
      // process.env — 37 occurrences across 14 files
      'src/app.ts', // 5
      'src/moderation/autoMod.ts', // 3
      'src/routes/admin.ts', // 2
      'src/routes/ai.ts', // 3
      'src/routes/auth.ts', // 1
      'src/routes/billing.ts', // 1
      'src/routes/friends.ts', // 1
      'src/routes/livekit.ts', // 1
      'src/routes/media.ts', // 1
      'src/routes/web.ts', // 6
      'src/routes/webpay.ts', // 7
      'src/services/passwordReset.ts', // 3
      'src/utils/privilegedUsers.ts', // 2
      'src/utils/secretBox.ts', // 1
    ],
    rules: { 'no-restricted-properties': 'off' },
  },
);
