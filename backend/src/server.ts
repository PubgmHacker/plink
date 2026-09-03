// src/server.ts — Process entrypoint
//
// server.ts only:
//   - Builds the app via buildApp()
//   - Listens on PORT
//   - Wires shutdown hooks (SIGTERM, SIGINT)
//
// All application wiring lives in app.ts so tests can call buildApp() without
// binding a port.

import { buildApp } from './app.js';
import { prisma } from './config/db.js';
import { redis, rateLimitRedis, markRedisShuttingDown } from './config/redis.js';
import { config } from './config/index.js';
import * as Sentry from '@sentry/node';
import { alertCritical } from './utils/alerting.js';

const start = async () => {
  const { app, gateway } = await buildApp();

  try {
    await app.listen({ port: config.PORT, host: '0.0.0.0' });
    console.log(
      `🚀 Plink backend v2.0 (stabilize/protocol-v2) on port ${config.PORT} [${config.NODE_ENV}]`,
    );
    console.log(`   App Store compliant: ${config.APP_STORE_COMPLIANT}`);
    console.log('   Legacy stream relay: removed');
    console.log(`   Realtime v2:         ${config.REALTIME_PROTOCOL_V2 ? 'enabled' : 'disabled'}`);
    console.log(`   LiveKit SFU:         ${config.LIVEKIT_SFU ? 'enabled' : 'disabled'}`);

    await app.ready();
    console.log('📋 Registered routes:');
    console.log(app.printRoutes());
  } catch (err) {
    Sentry.captureException(err);
    await alertCritical('Backend failed to start', err as Error);
    app.log.error(err);
    process.exit(1);
  }

  // Shutdown runs on every Railway deploy, so at 10k users it runs with 10k live
  // WebSockets attached. Three properties matter, and the original had none of them.
  //
  // 1. Every step runs. The steps used to be bare awaits in sequence, so if
  //    `app.close()` rejected — which it can, it is draining sockets — then
  //    `prisma.$disconnect()` and the Redis quits never ran and `process.exit(0)`
  //    was never reached. The process then sat until Railway's SIGKILL, holding its
  //    Postgres connections the whole time. Each step is now isolated.
  // 2. It cannot hang. `gateway.shutdown()` and `app.close()` both wait on remote
  //    peers. A watchdog exits at 15s regardless — Railway's own grace period is
  //    finite, and losing the last few sockets beats being killed mid-flush with
  //    Postgres connections still checked out.
  // 3. It runs once. Railway sends SIGTERM and can follow with more signals; a
  //    second concurrent shutdown would double-close and throw.
  let shuttingDown = false;

  const shutdown = async (signal: string) => {
    if (shuttingDown) {
      console.log(`${signal} received during shutdown — ignoring`);
      return;
    }
    shuttingDown = true;
    markRedisShuttingDown();
    console.log(`\n${signal} received, shutting down...`);

    const watchdog = setTimeout(() => {
      console.error('shutdown exceeded 15s — forcing exit, some connections were not drained');
      process.exit(1);
    }, 15_000);
    watchdog.unref();

    const step = async (name: string, fn: () => Promise<unknown>) => {
      try {
        await fn();
      } catch (e) {
        console.error(`shutdown: ${name} failed:`, e);
      }
    };

    // Order matters: stop accepting and drain first, then release backing services.
    // Gateway may be null if Redis was unavailable at boot. Each client is bound to a
    // local const so the null check narrows inside the closure.
    if (gateway) await step('gateway', () => gateway.shutdown());
    await step('http', () => app.close());
    await step('prisma', () => prisma.$disconnect());
    const shared = redis;
    if (shared) await step('redis', () => shared.quit());
    const limiter = rateLimitRedis;
    if (limiter) await step('redis:rate-limit', () => limiter.quit());

    clearTimeout(watchdog);
    process.exit(0);
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('uncaughtException', async (err) => {
    Sentry.captureException(err);
    await alertCritical('Uncaught exception', err);
  });
  process.on('unhandledRejection', async (reason) => {
    Sentry.captureException(reason as Error);
    await alertCritical('Unhandled rejection', reason as Error);
  });
};

start();
