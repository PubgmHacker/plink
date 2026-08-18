// Sync-drift telemetry ingestion. Raw samples go to the structured log,
// aggregates to Redis and the database.
import { prisma } from '../config/db.js';
import { redis } from '../config/redis.js';
import { logAudit } from '../utils/audit.js';

export default async function telemetryRoutes(fastify) {
  // POST /api/telemetry/sync-sample — приём одного sync sample от клиента
  fastify.post('/telemetry/sync-sample', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 120, timeWindow: '1 minute' } }  // 2s interval = 30/min
  }, async (request, reply) => {
    const sample = request.body;

    // Validate required fields
    if (!sample.sessionId || !sample.roomId || typeof sample.absoluteDriftMs !== 'number') {
      return reply.status(400).send({ error: 'sessionId, roomId, absoluteDriftMs required' });
    }

    // Structured log (not Prisma
    request.log.info({
      type: 'sync_sample',
      userId: request.user.id,
      sessionId: sample.sessionId,
      roomId: sample.roomId,
      role: sample.role,
      absoluteDriftMs: sample.absoluteDriftMs,
      signedDriftMs: sample.signedDriftMs,
      correctionType: sample.correctionType,
      correctionMagnitude: sample.correctionMagnitude,
      playbackState: sample.playbackState,
      networkType: sample.networkType,
      provider: sample.provider,
      appBuild: sample.appBuild,
      timestamp: new Date().toISOString()
    }, 'sync_sample');

    // Aggregate in Redis for session summaries (24h TTL, best-effort)
    if (redis) {
      try {
        const key = `plink:telemetry:sync:${(sample as any)?.roomId ?? 'global'}`;
        const pipeline = redis.multi();
        pipeline.hincrby(key, 'samples', 1);
        pipeline.hincrbyfloat(key, 'absDriftSumMs', Math.abs(Number((sample as any)?.absoluteDriftMs ?? 0)));
        if (((sample as any)?.correctionType ?? 'none') !== 'none') {
          pipeline.hincrby(key, 'corrections', 1);
        }
        pipeline.expire(key, 24 * 60 * 60);
        await pipeline.exec();
      } catch { /* telemetry must never fail the request */ }
    }

    reply.send({ received: true });
  });

  // POST /api/telemetry/sync-session — финальный session aggregate
  fastify.post('/telemetry/sync-session', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 10, timeWindow: '1 hour' } }
  }, async (request, reply) => {
    const agg = request.body;

    if (!agg.sessionId || !agg.roomId) {
      return reply.status(400).send({ error: 'sessionId, roomId required' });
    }

    // Log aggregate
    request.log.info({
      type: 'sync_session_aggregate',
      userId: request.user.id,
      sessionId: agg.sessionId,
      roomId: agg.roomId,
      sampleCount: agg.sampleCount,
      medianDriftMs: agg.medianDriftMs,
      p95DriftMs: agg.p95DriftMs,
      maxDriftMs: agg.maxDriftMs,
      correctionCount: agg.correctionCount,
      reconnectDurations: agg.reconnectDurations,
      bufferingDurationMs: agg.bufferingDurationMs,
      provider: agg.provider,
      networkTypes: agg.networkTypes,
      appBuild: agg.appBuild,
      duration: agg.duration,
      timestamp: new Date().toISOString()
    }, 'sync_session_aggregate');

    reply.send({ received: true, sessionId: agg.sessionId });
  });

  // POST /api/telemetry/crash — accepts crash reports from the iOS CrashReporter.
  // Authentication is NOT required: the crash may have happened before login.
  fastify.post('/telemetry/crash', {
    config: { rateLimit: { max: 20, timeWindow: '1 hour' } }
  }, async (request, reply) => {
    const report = request.body ?? {};
    if (!report.kind || !report.timestamp) {
      return reply.status(400).send({ error: 'kind, timestamp required' });
    }
    // Structured log — тот же подход, что и sync telemetry (ADR-004)
    request.log.error({
      type: 'client_crash',
      kind: report.kind,
      name: report.name,
      reason: String(report.reason ?? '').slice(0, 2000),
      stack: Array.isArray(report.stack) ? report.stack.slice(0, 50) : undefined,
      appVersion: report.appVersion,
      build: report.build,
      os: report.os,
      timestamp: report.timestamp,
    }, 'client_crash');
    reply.send({ received: true });
  });

  // POST /api/telemetry/feedback — shake-to-report из приложения (M20)
  fastify.post('/telemetry/feedback', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 10, timeWindow: '10 minutes' } }
  }, async (request, reply) => {
    const { type, text, appVersion, osVersion, device, userId } = request.body as any;
    if (!text || String(text).trim().length === 0) {
      return reply.status(400).send({ error: 'text required' });
    }
    request.log.info({
      type: 'user_feedback',
      feedbackType: type ?? 'other',
      text: String(text).slice(0, 2000),
      appVersion, osVersion, device,
      userId: request.user.id,
      timestamp: new Date().toISOString()
    }, 'user_feedback');
    reply.send({ received: true });
  });
}
