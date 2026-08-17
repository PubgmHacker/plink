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
import { JoseConfig } from './utils/jose-config.js';
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
import { webRoutes } from './routes/web.js';
import assetsRoutes from './routes/assets.js';  // самохост шрифтов/кадров лендинга (строгий CSP запрещает CDN)
import groupRoutes from './routes/groups.js';  // M16: беседы
import { livekitRoutes } from "./routes/livekit.js";
import telemetryRoutes from './routes/telemetry.js';
import { roomJoinDuration, syncDrift, syncHardCorrections, wsReconnectCount, presenceLeaseCount } from "./observability/slo-metrics.js";
import { realtimeTicketRoutes } from './routes/realtime.js';
import devRoutes from './routes/dev.js';
import webpayRoutes from './routes/webpay.js';  // веб-оплата Plink+ (ЮKassa)

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
    // Аудит 26.07.2026: за прокси Railway `request.ip` возвращал IP прокси,
    // а не клиента. Из-за этого ВСЕ лимиты по IP складывались в одно общее
    // ведро (один злоумышленник исчерпывал лимит для всех пользователей),
    // а в аудит-логи писался неверный адрес. С trustProxy Fastify читает
    // X-Forwarded-For и видит настоящего клиента.
    trustProxy: true,
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
  // ── Аудит 26.07.2026 (P2): aud/iss теперь ДЕЙСТВИТЕЛЬНО проверяются ───
  //
  // Было: `verify: { audience: config.JWT_AUDIENCES, issuer: config.JWT_ISSUER }`.
  // Под @fastify/jwt работает fast-jwt, а он ждёт ключи `allowedAud` /
  // `allowedIss`; незнакомые имена просто игнорировались — то есть ни
  // allowlist аудиторий, ни сверка issuer не выполнялись вовсе.
  // Вдобавок `sign` не проставлял claim `aud`, а fast-jwt пропускает
  // валидатор для ОТСУТСТВУЮЩЕГО claim-а: даже с правильным именем опции
  // проверка осталась бы пустой.
  //
  // Теперь подписываем первым значением из JWT_AUDIENCES, а на verify
  // принимаем любое из списка (ios/android/desktop) и сверяем issuer.
  //
  // Совместимость: уже выданные токены без `aud` продолжают проходить
  // verify (пропуск отсутствующего claim-а) и сами истекут в течение
  // ACCESS_TOKEN_TTL — массового разлогина при деплое не будет.
  //
  // ⚠️ ВНИМАНИЕ (ревью 26.07.2026): строгий режим `requiredClaims: ['aud']`
  // ВКЛЮЧАТЬ НЕЛЬЗЯ, пока не исправлены остальные call-site'ы подписи.
  // @fastify/jwt при передаче опций во второй аргумент `sign()` НЕ мерджит
  // их с этим глобальным блоком, а ЗАМЕНЯЕТ (jwt.js checkAndMergeOptions →
  // `mergeOptionsWithKey(options || defaultOptions)`). Поэтому aud/iss тут
  // получают только токены, подписанные БЕЗ опций (utils/tokens.ts —
  // access-токен), а realtime-тикеты (routes/realtime.ts, `{ expiresIn }`)
  // и media stream-token (routes/media.ts, `{ expiresIn: '45m' }`) выходят
  // вообще без `aud` и без `iss`. Сейчас они проходят verify только потому,
  // что fast-jwt пропускает валидатор для отсутствующего claim-а; включение
  // requiredClaims положило бы весь WS и проксирование видео.
  // Сначала — проставить aud/iss в тех двух местах, потом requiredClaims.
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

  // ── Самопроверка проверки покупок (аудит 26.07.2026, P0) ──────────────
  // До фикса подпись StoreKit проверялась против сертификата, присланного
  // самим клиентом: любой мог выдать себе Premium навсегда. Здесь на старте
  // прогоняется заведомо поддельный JWS — он ОБЯЗАН быть отвергнут.
  // Если однажды проверка снова начнёт пропускать всё, мы узнаем об этом
  // из логов запуска, а не из отчёта о бесплатных подписках.
  if (!JoseConfig.selfTest()) {
    const message = '[iap] САМОПРОВЕРКА ПРОВАЛЕНА: поддельный JWS принят как валидный';
    if (config.isProduction) {
      fastify.log.fatal(message);
      throw new Error(message);
    }
    fastify.log.error(message);
  } else {
    fastify.log.info('[iap] самопроверка проверки покупок пройдена');
  }
  // Самопроверка выше гоняет криптотракт с выключенным обходом, поэтому
  // включённый ALLOW_UNVERIFIED_IAP больше не маскируется под «проверка
  // сломана» — но молчать о нём нельзя: подписи покупок реально не проверяются.
  if (JoseConfig.unverifiedBypassActive()) {
    fastify.log.warn('[iap] ALLOW_UNVERIFIED_IAP=true — подписи покупок НЕ проверяются (допустимо только в разработке)');
  }

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

  // Аудит 26.07.2026: публичные страницы БЕЗ префикса /api.
  //
  // Модуль содержал готовый фикс XSS на лендингах комнаты и профиля
  // (`/r/:code`, `/u/:username`), но НЕ БЫЛ ПОДКЛЮЧЁН — то есть исправление
  // просто не работало. Здесь же живёт `/.well-known/apple-app-site-association`,
  // без которого не работают Universal Links: ссылка-приглашение открывала
  // сайт вместо приложения.
  await fastify.register(assetsRoutes);  // до webRoutes: /assets/* не должен попасть в 404-страницу лендинга
  await fastify.register(webRoutes);
  await fastify.register(webpayRoutes, { prefix: '/api' });  // веб-подписка Plink+
  await fastify.register(telemetryRoutes, { prefix: '/api' });  // B3: sync telemetry
  // Аудит 26.07.2026: маршруты разработки (включая полную очистку БД)
  // регистрировались ВСЕГДА и защищались только переменной окружения.
  // Одна опечатка в конфиге прода = потеря всех данных. Теперь в проде
  // они не существуют вовсе — защита не зависит от значения флага.
  if (!config.isProduction) {
    await fastify.register(devRoutes, { prefix: '/api' });
  }

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
  // Аудит 26.07.2026: дубликат iOS AASA удалён — маршрут
  // /.well-known/apple-app-site-association регистрирует webRoutes (web.ts)
  // с корректным appID (2QAMUC4Z4P.com.syncwatch.plink). Двойная регистрация
  // роняла сервер на старте (FST_ERR_DUPLICATED_ROUTE).
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

  // Аудит 26.07.2026: /metrics был публичным — раскрывал внутренние счётчики
  // (онлайн, комнаты, ошибки) любому. В проде доступ только с METRICS_TOKEN;
  // без заданного токена маршрут в проде отвечает 404, как несуществующий.
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
