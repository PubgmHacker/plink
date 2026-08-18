#!/usr/bin/env node
// Guard for `npm run test:integration`.
//
// The integration tests skip themselves when Redis is unreachable, so without
// this an "integration run" can exit green having verified nothing. Refusing to
// start is the honest failure.
if (!process.env.REDIS_URL) {
  console.error('Error: REDIS_URL is not set — the integration tests need a live Redis.');
  console.error('Example: REDIS_URL="redis://localhost:6380" npm run test:integration');
  process.exit(1);
}
