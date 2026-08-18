// Vitest configuration for the Plink backend.
//
// RedisSkipReporter is registered alongside the default reporter so an
// integration suite that skipped itself for want of Redis says so out loud. See
// src/tests/redisSkipReporter.ts for why a silent skip was worth a custom
// reporter.
// The `.js` extension is required, not stylistic. Vite's native config loader —
// planned to become the default — cannot resolve an extensionless specifier and warns
// on every run without it. It stays a typed `import` rather than the untyped
// `reporters: ['./path/to/reporter.ts']` form so that renaming or deleting the
// reporter is a compile error; this reporter has already gone silent once across a
// vitest major, and a runtime-resolved path would hide that recurrence.
import { defineConfig } from 'vitest/config';
import RedisSkipReporter from './src/tests/redisSkipReporter.js';

export default defineConfig({
  test: {
    // Source tests only. Without this, vitest 4 also collects the compiled copies
    // under dist/: the run doubles, and a stale dist/ fails contracts that the
    // current source passes.
    include: ['src/tests/**/*.test.ts'],
    reporters: ['default', new RedisSkipReporter()],
  },
});
