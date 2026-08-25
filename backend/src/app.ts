// src/app.ts — Fastify application factory
//
// Builds the Fastify instance for both runtime (server.ts) and tests.
// server.ts only adds listener + shutdown hooks; everything else lives here
// so tests can spin up the app without binding a port.

import Fastify, { type FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import websocket from '@fastify/websocket';
import * as Sentry from '@sentry/node';
import { config, assertProductionInvariants, resolveCorsOrigin } from './config/index.js';
import { JoseConfig } from './utils/jose-config.js';
import { prisma } from './config/db.js';
import { redis, rateLimitRedis } from './config/redis.js';
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
import { webRoutes } from './routes/web.js';
import assetsRoutes from './routes/assets.js';  // self-hosted landing fonts/screenshots (the strict CSP forbids a CDN)
import groupRoutes from './routes/groups.js';  // group chats
import { livekitRoutes } from "./routes/livekit.js";
import telemetryRoutes from './routes/telemetry.js';
import { roomJoinDuration, syncDrift, syncHardCorrections, wsReconnectCount, presenceLeaseCount } from "./observability/slo-metrics.js";
import { realtimeTicketRoutes } from './routes/realtime.js';
import devRoutes from './routes/dev.js';
import webpayRoutes from './routes/webpay.js';  // Plink+ purchase from the web, via YooKassa
import { startGuestTombstoneLoop } from './services/accountTombstone.js';

export async function buildApp(): Promise<{
  app: FastifyInstance;
  // Gateway is null when Redis is unavailable. Callers MUST handle null.
  gateway: RealtimeGateway | null;
}> {
  // Refuse to boot in production on weak secret / CORS '*' / no audiences
  assertProductionInvariants();

  // Redis is REQUIRED for realtime v2 (RoomStateStore, RoomPubSub,
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
    // Required because we run behind Railway's proxy. Without it `request.ip` is the
    // proxy's address, not the client's, which had two consequences: every per-IP rate
    // limit shared a single bucket — so one attacker exhausted the limit for all users —
    // and the audit log recorded the wrong address for every request. With trustProxy,
    // Fastify reads X-Forwarded-For and sees the real client.
    trustProxy: true,
    // Voice notes (base64 m4a ~up to 60s) + avatars need >1MB default
    bodyLimit: 2 * 1024 * 1024,
    // На close рвём ИДЛОВЫЕ keep-alive сокеты (iOS держит их подолгу — без
    // этого graceful shutdown ждал их таймаута и упирался в watchdog).
    // Не `true`: активным запросам даём дожить, страховка — watchdog 15с.
    forceCloseConnections: 'idle',
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
  // JWT: the `aud` and `iss` claims are actually checked here.
  //
  // "Actually" because they used to be configured and silently not checked. The old
  // options were `verify: { audience: …, issuer: … }`, but @fastify/jwt is backed by
  // fast-jwt, which expects `allowedAud` / `allowedIss`. Unknown option names are
  // ignored rather than rejected, so neither the audience allowlist nor the issuer check
  // ran at all. `sign` also never set an `aud` claim, and fast-jwt skips a validator for
  // a claim that is ABSENT — so even with the right option name the check would have
  // passed vacuously.
  //
  // Now: sign with the first entry in JWT_AUDIENCES, and on verify accept any entry in
  // the list (ios/android/desktop) and compare the issuer.
  //
  // Already-issued tokens have no `aud` and still verify, by that same skip-if-absent
  // rule. They expire within ACCESS_TOKEN_TTL, so the fix does not sign everyone out on
  // deploy.
  //
  // Do NOT add `requiredClaims: ['aud']` yet. It would close the skip-if-absent hole,
  // and two other signing call sites are still going through it:
  //
  //   - realtime tickets — routes/realtime.ts, `sign({ expiresIn })`
  //   - media stream tokens — routes/media.ts, `sign({ expiresIn: '45m' })`
  //
  // Both emit tokens with no `aud` and no `iss`, because @fastify/jwt REPLACES this
  // global block rather than merging into it when `sign()` is given its own options
  // (jwt.js `checkAndMergeOptions` → `mergeOptionsWithKey(options || defaultOptions)`).
  // Only tokens signed with no options at all — the access token in utils/tokens.ts —
  // pick up the values below. Turning on requiredClaims today would break every
  // websocket connection and all video proxying.
  //
  // The order is: set aud/iss at those two call sites, then add requiredClaims.
  const jwtAudiences = config.JWT_AUDIENCES;
  await fastify.register(jwt, {
    secret: config.JWT_SECRET,
    sign: {
      algorithm: 'HS256',
      iss: config.JWT_ISSUER,
      ...(jwtAudiences.length > 0 ? { aud: jwtAudiences[0] } : {}),
    } as any,
    verify: {
      ...(jwtAudiences.length > 0 ? { allowedAud: jwtAudiences } : {}),
      allowedIss: config.JWT_ISSUER,
    } as any,
  } as any);
  // Rate limits are counted in Redis, not in this process's memory.
  //
  // Without a store the plugin uses a per-process LRU, so every limit silently
  // multiplies by the number of instances: `max: 100` across four Railway replicas
  // is 400 requests a minute per IP, and which bucket a request lands in depends on
  // which replica the proxy picked. At one instance that is invisible. It is the
  // first thing that breaks on scaling out, and it breaks quietly — the limit still
  // *works*, it is just wrong by a factor nobody wrote down. Measured, two instances
  // against one Redis: 8 alternating requests against `max: 5` yields 5 × 200 and
  // 3 × 429, one key, TTL 59990ms. Per-process it was 8 × 200.
  //
  // `skipOnError: true` is a deliberate trade, and it is worth being precise about
  // what it does: on a store error the plugin leaves the counter at 0 and **allows
  // the request**. It does not fall back to the local LRU — there is no degraded
  // counting, only no counting. That is still the right default here, because the
  // alternative (the plugin's own) is to propagate the error, and an unreachable
  // Redis would then 500 every rate-limited route: an outage caused by the component
  // meant to prevent one. Losing limits during a Redis outage is recoverable; losing
  // the API is not.
  //
  // The cost of that trade is a window at boot. `rateLimitRedis` is created with
  // `enableOfflineQueue: false`, so commands issued before the socket reaches `ready`
  // reject immediately, and with skipOnError those requests are unlimited. A ping()
  // here cannot close that window: with the offline queue disabled the ping itself
  // rejects instantly while the socket is still connecting — the slow-connect case
  // is exactly the case it fails in. Measured with a real buildApp() boot under
  // load: the ping variant warned and let every pre-connect request through
  // unlimited. So wait for the client's own `ready` event, bounded at 3s: a live
  // Redis is ready in milliseconds and the wait costs nothing; a down Redis delays
  // boot by 3s instead of blocking it, and the limiter then stays out of the way
  // (skipOnError) until the client reconnects.
  if (rateLimitRedis && rateLimitRedis.status !== 'ready') {
    const client = rateLimitRedis;
    const ready = await new Promise<boolean>((resolve) => {
      let timer: ReturnType<typeof setTimeout>;
      const onReady = () => {
        clearTimeout(timer);
        resolve(true);
      };
      timer = setTimeout(() => {
        client.off('ready', onReady);
        resolve(false);
      }, 3_000);
      client.once('ready', onReady);
    });
    if (!ready) {
      // Not fatal: skipOnError means the limiter stays out of the way rather than
      // failing requests. Loud, because until it connects, limits are not enforced.
      fastify.log.warn(
        '[rate-limit] Redis not ready 3s into boot — limits are NOT enforced until it connects',
      );
    }
  }

  await fastify.register(rateLimit, {
    global: false,
    max: 100,
    timeWindow: '1 minute',
    cache: 10000,
    ban: 5,
    ...(rateLimitRedis ? { redis: rateLimitRedis } : {}),
    skipOnError: true,
    nameSpace: 'plink-rl:',
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

  // ── Purchase-verification self-test ───────────────────────────────────
  // StoreKit signatures were once verified against a certificate supplied by the client
  // making the claim, which meant anyone could grant themselves Premium permanently.
  // So on every boot we feed the verifier a JWS we know is forged: it MUST be rejected.
  //
  // The point is the failure mode. If this check ever regresses to accepting everything
  // again, we find out from a startup log rather than from a report about free
  // subscriptions.
  if (!JoseConfig.selfTest()) {
    const message = '[iap] self-test FAILED: a forged JWS was accepted as valid';
    if (config.isProduction) {
      fastify.log.fatal(message);
      throw new Error(message);
    }
    fastify.log.error(message);
  } else {
    fastify.log.info('[iap] purchase-verification self-test passed');
  }
  // The self-test above exercises the crypto path with the bypass forced off, so an
  // enabled ALLOW_UNVERIFIED_IAP can no longer hide behind a "verification is broken"
  // reading. It still has to be said out loud, because purchase signatures genuinely
  // are not being checked.
  if (JoseConfig.unverifiedBypassActive()) {
    fastify.log.warn('[iap] ALLOW_UNVERIFIED_IAP=true — purchase signatures are NOT verified (development only)');
  }

  // ── API routes ────────────────────────────────────────────────────────
  await fastify.register(authRoutes, { prefix: '/api' });
  await fastify.register(roomRoutes, { prefix: '/api' });
  await fastify.register(friendRoutes, { prefix: '/api' });
  await fastify.register(messageRoutes, { prefix: '/api' });
  await fastify.register(profileRoutes, { prefix: '/api' });
  await fastify.register(mediaRoutes, { prefix: '/api' });
  await fastify.register(billingRoutes, { prefix: '/api' });
  // Admin API
  await fastify.register(adminRoutes, { prefix: '/api' });
  await fastify.register(gdprRoutes, { prefix: '/api' });
  await fastify.register(featureFlagRoutes, { prefix: '/api' });
  await fastify.register(aiRoutes, { prefix: '/api' });
  await fastify.register(moderationRoutes, { prefix: '/api' });
  await fastify.register(groupRoutes, { prefix: '/api' });  // group chats
  await fastify.register(livekitRoutes, { prefix: '/api' });  // voice; stubbed, see docs/architecture/README.md
  await fastify.register(realtimeTicketRoutes, { prefix: '/api' });

  // Public pages, deliberately WITHOUT the /api prefix.
  //
  // web.ts was written and then never registered, which made two fixes inside it
  // inert: an XSS fix on the room and profile share pages (`/r/:code`, `/u/:username`),
  // and `/.well-known/apple-app-site-association`, without which Universal Links do not
  // resolve and an invite link opens the website instead of the app.
  //
  // Registration order below is behavioural, not stylistic: assetsRoutes must come
  // before webRoutes, or `/assets/*` is swallowed by the landing 404 page.
  await fastify.register(assetsRoutes);
  await fastify.register(webRoutes);
  await fastify.register(webpayRoutes, { prefix: '/api' });  // Plink+ web subscription
  await fastify.register(telemetryRoutes, { prefix: '/api' });  // sync-drift telemetry
  // The development routes — which include a full database wipe — were once registered
  // unconditionally and guarded only by an environment variable. One typo in the
  // production config would have meant total data loss. They now do not exist in
  // production at all, so the protection does not depend on the value of a flag.
  if (!config.isProduction) {
    await fastify.register(devRoutes, { prefix: '/api' });
  }

  fastify.log.info('✅ App Store compliant build — legacy stream relay removed.');

  // ── Realtime gateway (replaces setupWebSocketHandler) ─────────────────
  // Only construct gateway when Redis is available — gateway's
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

  // ── Health (split into liveness + readiness) ────────────
  // /health/ready returns 503 when DB or Redis is down, so
  // orchestrators (k8s, Railway, ELB) stop sending traffic.
  // ── Universal Links / App Links association files ──────────────────
  // Only the Android file is served here. The iOS one
  // (`/.well-known/apple-app-site-association`) belongs to webRoutes (web.ts), which
  // serves it with the correct appID. A duplicate registration lived here once and
  // crashed the server on boot with FST_ERR_DUPLICATED_ROUTE — Fastify rejects a
  // duplicate path rather than letting one shadow the other, which is how it was found.
  //
  // The SHA-256 fingerprint is the release signing certificate's, read from the
  // environment.
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
      version: '2.1.0-sync',
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

  // /metrics was public, which exposed internal counters — users online, room counts,
  // error rates — to anyone who asked. In production it now requires METRICS_TOKEN.
  //
  // With no token configured it answers 404 rather than 401: the endpoint does not
  // advertise its own existence to someone probing for it.
  fastify.get('/metrics', async (req, reply) => {
    const token = process.env.METRICS_TOKEN;
    if (process.env.NODE_ENV === 'production') {
      if (!token || req.headers.authorization !== `Bearer ${token}`) {
        return reply.code(404).send({ error: 'Not found' });
      }
    }
    reply.type('text/plain').send(await register.metrics());
  });

  // 404 RADAR (debug aid — kept from v1)
  fastify.setNotFoundHandler((request, reply) => {
    fastify.log.debug({ method: request.method, url: request.url.substring(0, 200) }, '404');
    reply.code(404).send({ error: 'Not Found' });
  });

  // Error handler — internal error messages never leak in production
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

  if (process.env.NODE_ENV !== 'test') {
    startGuestTombstoneLoop();
  }

  return { app: fastify, gateway: gateway };  // Gateway is RealtimeGateway | null
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
