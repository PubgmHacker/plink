// src/server.ts — Process entrypoint (runbook §20)
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
import { redis } from './config/redis.js';
import { config } from './config/index.js';
import * as Sentry from '@sentry/node';
import { alertCritical } from './utils/alerting.js';

const start = async () => {
  const { app, gateway } = await buildApp();

  try {
    await app.listen({ port: config.PORT, host: '0.0.0.0' });
    console.log(`🚀 Plink backend v2.0 (stabilize/protocol-v2) on port ${config.PORT} [${config.NODE_ENV}]`);
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

  const shutdown = async (signal: string) => {
    console.log(`\n${signal} received, shutting down...`);
    // P1-13: gateway may be null if Redis was unavailable
    if (gateway) {
      try {
        await gateway.shutdown();
      } catch (e) {
        console.error('gateway shutdown error:', e);
      }
    }
    await app.close();
    await prisma.$disconnect();
    if (redis) await redis.quit().catch(() => {});
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
