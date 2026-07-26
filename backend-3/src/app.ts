// src/app.ts — Fastify application factory (runbook §20)
//
// Builds the Fastify instance for both runtime (server.ts) and tests.
// server.ts only adds listener + shutdown hooks; everything else lives here
// so tests can spin up the app without binding a port.
//
// §20 rule: 'app.ts строит Fastify instance для tests. server.ts только
// запускает listeners и shutdown hooks. Не оставлять 20+ KB inline media
// implementation в index.ts.'

import Fastify, { type FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import websocket from '@fastify/websocket';
import * as Sentry from '@sentry/node';
import { config, assertProductionInvariants, resolveCorsOrigin } from './config/index.js';
import { prisma } from './config/db.js';
import { redis } from './config/redis.js';
import { authenticate } from './middleware/auth.js';
import { securityHeaders } from './middleware/security.js';
import { register } from './services/metrics.js';
import { initTelemetry } from './services/telemetry.js';
import { RealtimeGateway } from './realtime/gateway.js';

import authRoutes from './routes/auth.js';
import roomRoutes from './routes/rooms.js';
import friendRoutes from './routes/friends.js';
import messageRoutes from './routes/messages.js';
import profileRoutes from './routes/profile.js';
import mediaRoutes from './routes/media.js';
import billingRoutes from './routes/billing.js';
import { adminRoutes } from './routes/admin.js';
import gdprRoutes from './routes/gdpr.js';
import featureFlagRoutes from './routes/featureFlags.js';
import aiRoutes from './routes/ai.js';
import moderationRoutes from './routes/moderation.js';
import groupRoutes from './routes/groups.js';  // M16: беседы
import { livekitRoutes } from "./routes/livekit.js";
import telemetryRoutes from './routes/telemetry.js';
import { roomJoinDuration, syncDrift, syncHardCorrections, wsReconnectCount, presenceLeaseCount } from "./observability/slo-metrics.js";
import { realtimeTicketRoutes } from './routes/realtime.js';
import devRoutes from './routes/dev.js';

export async function buildApp(): Promise<{
  app: FastifyInstance;
  // P1-13: gateway is null when Redis is unavailable. Callers MUST handle null.
  gateway: RealtimeGateway | null;
}> {
  // §2: refuse to boot in production on weak secret / CORS '*' / no audiences
  assertProductionInvariants();

  // P1-4: Redis is REQUIRED for realtime v2 (RoomStateStore, RoomPubSub,
  // RoomEventBus, ticket nonce). Refuse to start the gateway if missing.
  if (!redis) {
    if (config.isProduction) {
      throw new Error(
        'FATAL: REDIS_URL is required for realtime v2 in production. ' +
          'Set REDIS_URL or disable realtime (REALTIME_PROTOCOL_V2=false) and rebuild.',
      );
    }
    console.warn('[app] Redis not configured — realtime v2 routes will 503');
  }

  initTelemetry(process.env.OTEL_ENDPOINT);

  if (config.SENTRY_DSN) {
    Sentry.init({
      dsn: config.SENTRY_DSN,
      environment: config.NODE_ENV,
      tracesSampleRate: config.isProduction ? 0.1 : 1.0,
    });
  }

  const fastify = Fastify({
    // Voice notes (base64 m4a ~up to 60s) + avatars need >1MB default
    bodyLimit: 2 * 1024 * 1024,
    logger: {
      level: config.isProduction ? 'info' : 'debug',
      transport: config.isProduction ? undefined : { target: 'pino-pretty' },
      redact: [
        'req.headers.authorization',
        'req.body.password',
        '*.password',
        'req.body.receipt',
        'req.headers.cookie',
        'req.headers["sec-websocket-protocol"]',
      ],
    },
  });

  fastify.decorate('prisma', prisma);

  await fastify.register(cors, {
    // Dev: reflect any origin. Prod: CORS_ORIGIN + Tauri desktop (tauri://localhost).
    origin: resolveCorsOrigin(),
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type', 'X-Request-ID'],
  });
  // @fastify/jwt's TS types don't expose audience/issuer in verify opts
  // directly — cast to any to set them. These are picked up by jwt.verify().
  await fastify.register(jwt, {
    secret: config.JWT_SECRET,
    sign: { algorithm: 'HS256', iss: config.JWT_ISSUER },
    verify: { audience: config.JWT_AUDIENCES, issuer: config.JWT_ISSUER } as any,
  } as any);
  await fastify.register(rateLimit, {
    global: false,
    max: 100,
    timeWindow: '1 minute',
    cache: 10000,
    ban: 5,
  });
  await fastify.register(websocket, { options: { maxPayload: 64 * 1024 } });

  // Empty application/json body → {} (leave room, wipe-db probes, etc.)
  // Default Fastify JSON parser throws FST_ERR_CTP_EMPTY_JSON_BODY otherwise.
  fastify.removeContentTypeParser('application/json');
  fastify.addContentTypeParser(
    'application/json',
    { parseAs: 'string' },
    (req, body, done) => {
      try {
        const raw = typeof body === 'string' ? body : String(body ?? '');
        if (!raw || raw.trim() === '') {
          done(null, {});
          return;
        }
        done(null, JSON.parse(raw));
      } catch (err) {
        done(err as Error, undefined);
      }
    },
  );

  fastify.decorate('authenticate', authenticate);
  fastify.addHook('onRequest', securityHeaders);

  // ── API routes ────────────────────────────────────────────────────────
  await fastify.register(authRoutes, { prefix: '/api' });
  await fastify.register(roomRoutes, { prefix: '/api' });
  await fastify.register(friendRoutes, { prefix: '/api' });
  await fastify.register(messageRoutes, { prefix: '/api' });
  await fastify.register(profileRoutes, { prefix: '/api' });
  await fastify.register(mediaRoutes, { prefix: '/api' });
  await fastify.register(billingRoutes, { prefix: '/api' });
  // PATCH 16: Admin API — Brain Review 10 P0-67/P0-69
  await fastify.register(adminRoutes, { prefix: '/api' });
  await fastify.register(gdprRoutes, { prefix: '/api' });
  await fastify.register(featureFlagRoutes, { prefix: '/api' });
  await fastify.register(aiRoutes, { prefix: '/api' });
  await fastify.register(moderationRoutes, { prefix: '/api' });
  await fastify.register(groupRoutes, { prefix: '/api' });  // M16: групповые чаты (беседы)
await fastify.register(livekitRoutes, { prefix: '/api' });  // Stage 9
  await fastify.register(realtimeTicketRoutes, { prefix: '/api' });
  await fastify.register(telemetryRoutes, { prefix: '/api' });  // B3: sync telemetry
  await fastify.register(devRoutes, { prefix: '/api' });

  fastify.log.info('✅ App Store compliant build — legacy stream relay removed.');

  // ── Realtime gateway (replaces setupWebSocketHandler) ─────────────────
  // P1-4: only construct gateway when Redis is available — gateway's
  // constructor eagerly creates RoomStateStore/RoomPubSub/RoomEventBus
  // which require a live Redis connection.
  let gateway: RealtimeGateway | null = null;
  if (redis) {
    gateway = new RealtimeGateway({
      fastify,
      prisma,
      redis,
      wss: fastify.websocketServer,
    });
    (fastify as any).gateway = gateway;
  } else {
    fastify.log.warn('Realtime gateway NOT constructed — Redis unavailable');
  }

  // Register /ws and /ws/room/:id as websocket routes (no-op handlers —
  // the gateway subscribes to 'connection' events on the websocketServer)
  fastify.get('/ws', { websocket: true }, async () => {});
  fastify.get('/ws/room/:id', { websocket: true }, async () => {});

  // ── Health (split into liveness + readiness — runbook §19) ────────────
  // P1-3: /health/ready returns 503 when DB or Redis is down, so
  // orchestrators (k8s, Railway, ELB) stop sending traffic.
  // ── M12: Universal Links / App Links association files ──────────────────
  // iOS AASA — TEAMID подставляется через env, когда появится
  // Apple Developer аккаунт (APPLE_TEAM_ID).
  fastify.get('/.well-known/apple-app-site-association', async (_req, reply) => {
    const teamId = process.env.APPLE_TEAM_ID ?? 'TEAMID';
    reply.header('content-type', 'application/json');
    return {
      applinks: {
        apps: [],
        details: [
          {
            appIDs: [`${teamId}.com.plink.app`],
            paths: ['/r/*', '/u/*'],
          },
        ],
      },
    };
  });
  // Android App Links — SHA256 отпечаток release-сертификата из env
  fastify.get('/.well-known/assetlinks.json', async (_req, reply) => {
    reply.header('content-type', 'application/json');
    return [
      {
        relation: ['delegate_permission/common.handle_all_urls'],
        target: {
          namespace: 'android_app',
          package_name: 'com.plink.app',
          sha256_cert_fingerprints: [
            process.env.ANDROID_CERT_SHA256 ?? 'REPLACE_WITH_RELEASE_CERT_SHA256',
          ],
        },
      },
    ];
  });

  fastify.get('/health/live', async () => ({ status: 'alive', ts: Date.now() }));
  fastify.get('/health/ready', async (_req, reply) => {
    const [db, r] = await Promise.all([checkDatabase(), checkRedis()]);
    const ready = db && r === true;
    if (!ready) {
      reply.status(503);
    }
    return {
      status: ready ? 'ready' : 'degraded',
      services: {
        database: db ? 'up' : 'down',
        redis: r === null ? 'not_configured' : r ? 'up' : 'down',
      },
    };
  });
  // Backwards-compatible /health for old monitors
  fastify.get('/health', async (_req, reply) => {
    const [db, r] = await Promise.all([checkDatabase(), checkRedis()]);
    const ok = db && r === true;
    if (!ok) reply.status(503);
    return {
      status: ok ? 'ok' : 'degraded',
      timestamp: Date.now(),
      uptime: process.uptime(),
      version: '2.0.0-stabilize',
      environment: config.NODE_ENV,
      services: {
        database: db ? 'up' : 'down',
        redis: r === null ? 'not_configured' : r ? 'up' : 'down',
        appStoreCompliant: config.APP_STORE_COMPLIANT,
        legacyRelay: false,
        realtimeV2: config.REALTIME_PROTOCOL_V2,
        livekitSfu: !!(config.LIVEKIT_URL && config.LIVEKIT_API_KEY && config.LIVEKIT_API_SECRET),
        livekitSfuFlag: config.LIVEKIT_SFU,
      },
      memory: process.memoryUsage(),
    };
  });

  fastify.get('/metrics', async (_req, reply) => {
    reply.type('text/plain').send(await register.metrics());
  });

  // 404 RADAR (debug aid — kept from v1)
  fastify.setNotFoundHandler((request, reply) => {
    fastify.log.debug({ method: request.method, url: request.url.substring(0, 200) }, '404');
    reply.code(404).send({ error: 'Not Found' });
  });

  // Error handler — P1-5: never leak internal error messages in production
  // for 5xx (return generic 'Internal Server Error'). For 4xx validation/
  // auth errors, return the safe mapped message. Stack traces are logged
  // and sent to Sentry, never sent to client.
  fastify.setErrorHandler((error: any, request, reply) => {
    const status = error.statusCode || 500;
    const isProd = config.isProduction;
    if (status >= 500) {
      Sentry.captureException(error);
      request.log.error({ err: error, requestId: request.id }, 'server error');
    }
    // Safe message mapping
    let safeMessage: string;
    if (status >= 500 && isProd) {
      safeMessage = 'Internal Server Error';
    } else if (status === 401) {
      safeMessage = 'Unauthorized';
    } else if (status === 403) {
      safeMessage = 'Forbidden';
    } else if (status === 404) {
      safeMessage = 'Not Found';
    } else if (status === 429) {
      safeMessage = 'Rate limit exceeded';
    } else {
      // 4xx validation errors — Fastify validation messages are safe to echo
      safeMessage = error.message || 'Bad Request';
    }
    reply.status(status).send({
      error: safeMessage,
      statusCode: status,
      requestId: request.id,
      ...(isProd ? {} : { stack: error.stack }),
    });
  });

  return { app: fastify, gateway: gateway };  // P1-13: gateway is RealtimeGateway | null
}

async function checkDatabase(): Promise<boolean> {
  try {
    await prisma.$queryRaw`SELECT 1`;
    return true;
  } catch {
    return false;
  }
}

async function checkRedis(): Promise<boolean | null> {
  if (!redis) return null;
  try {
    const pong = await redis.ping();
    return pong === 'PONG';
  } catch {
    return false;
  }
}
