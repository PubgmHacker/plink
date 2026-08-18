// Makes a skipped integration suite loud instead of silent.
//
// The tests in src/tests/integration/* skip themselves when Redis is not
// reachable. Without this reporter that turned "100 passed" on a machine with
// Redis into "86 passed" on a machine without it, and nothing in the output said
// which 14 were missing — so a green run meant two different things depending on
// who ran it. This prints a warning at the end of any run that skipped one.
//
// Registered alongside the default reporter in vitest.config.ts.
//
// It is written against the vitest 4 reporter API (onTestRunEnd + TestModule) on
// purpose. The vitest 3 hook it used before, onFinished(files), is no longer
// called in vitest 4 — it is not an error, the hook simply never fires, so the
// reporter stopped warning without failing. That is the exact failure it exists
// to prevent, which makes this the one part worth checking after a vitest major
// upgrade: bump the version, run the suite with Redis stopped, and confirm the
// banner still appears.

import type { Reporter, TestModule } from 'vitest/node';

export default class RedisSkipReporter implements Reporter {
  onTestRunEnd(testModules: ReadonlyArray<TestModule> = []): void {
    let skipped = 0;
    for (const mod of testModules) {
      if (!mod.moduleId.includes('tests/integration')) continue;
      for (const test of mod.children.allTests()) {
        if (test.result().state === 'skipped') skipped++;
      }
    }
    if (skipped === 0) return;

    const reason = process.env.REDIS_URL
      ? `Redis unreachable at REDIS_URL=${process.env.REDIS_URL}`
      : 'REDIS_URL is not set';
    // stderr and a box, deliberately: this has to survive being the second-last
    // thing printed before a wall of passing test names.
    console.error('');
    console.error('──────────────────────────────────────────────────────────────');
    console.error(`⚠ ${skipped} integration test(s) skipped: ${reason}`);
    console.error('  Start Redis and run: npm run test:integration');
    console.error('──────────────────────────────────────────────────────────────');
  }
}
