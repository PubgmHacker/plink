// src/services/telemetry.ts — OpenTelemetry tracing helpers
//
// `@opentelemetry/api` is the only OpenTelemetry dependency here, and no SDK is
// registered. `trace.getTracer()` therefore returns a no-op tracer, which means
// `withSpan`, `setSpanAttribute` and `addSpanEvent` are safe to call from
// anywhere: they preserve the wrapped function's result and exceptions, and
// record nothing. `initTelemetry()` reports that state rather than logging
// success, and warns when OTEL_ENDPOINT is set to something (it is empty in
// both .env and .env.example) so a configured endpoint that leads nowhere is
// visible in the log.
//
// Tracing as such is not missing: `@sentry/node` is initialised in app.ts with
// `tracesSampleRate` and collects its own traces.
//
// Real OTLP export, if it is ever wanted alongside Sentry, needs
// `@opentelemetry/sdk-node` + `@opentelemetry/exporter-trace-otlp-http` and an
// explicit `new NodeSDK({...}).start()` — worth adding only once there is a live
// collector to receive spans. Keep `@opentelemetry/auto-instrumentations-node`
// out of it: it drags in roughly 194 transitive packages (155 of them
// @opentelemetry/*) and with them the bulk of the backend's production
// advisories. It also does not export `registerOTel` — that symbol belongs to
// `@vercel/otel`; this package exports `getNodeAutoInstrumentations` and
// `getResourceDetectors`.
import { trace, context, SpanStatusCode, SpanKind } from '@opentelemetry/api';

const SERVICE_NAME = 'plink-backend';
const SERVICE_VERSION = '1.5.0';

let isInitialized = false;

/**
 * Ранняя точка инициализации трассировки.
 *
 * Сейчас OTLP-экспортёр не подключён (см. комментарий выше), поэтому функция
 * честно сообщает состояние вместо ложного успеха. Подпись сохранена —
 * app.ts вызывает `initTelemetry(process.env.OTEL_ENDPOINT)`.
 */
export async function initTelemetry(endpoint?: string) {
  if (isInitialized) return;
  isInitialized = true;

  if (endpoint) {
    console.warn(
      `[Telemetry] OTEL_ENDPOINT задан (${endpoint}), но OTLP-экспортёр не собран: ` +
        'нужны @opentelemetry/sdk-node и exporter-trace-otlp-http. ' +
        'Спаны через withSpan() сейчас no-op; трейсы ведёт Sentry.',
    );
    return;
  }

  console.log(
    '[Telemetry] OTLP-экспортёр не настроен — withSpan() работает как no-op. ' +
      'Трассировку ведёт Sentry (см. Sentry.init в app.ts).',
  );
}

// Helper: create span for manual tracing
export function withSpan<T>(
  name: string,
  fn: (span: any) => T | Promise<T>,
  options?: { kind?: SpanKind; attributes?: Record<string, any> },
): T | Promise<T> {
  const tracer = trace.getTracer(SERVICE_NAME);
  return tracer.startActiveSpan(name, { kind: options?.kind }, async (span) => {
    if (options?.attributes) {
      for (const [k, v] of Object.entries(options.attributes)) {
        span.setAttribute(k, v);
      }
    }
    try {
      const result = await fn(span);
      span.setStatus({ code: SpanStatusCode.OK });
      return result;
    } catch (e: any) {
      span.setStatus({ code: SpanStatusCode.ERROR, message: e.message });
      span.recordException(e);
      throw e;
    } finally {
      span.end();
    }
  });
}

// Helper: add attributes to current span
export function setSpanAttribute(key: string, value: any) {
  const span = trace.getActiveSpan();
  if (span) span.setAttribute(key, value);
}

// Helper: add event to current span
export function addSpanEvent(name: string, attributes?: Record<string, any>) {
  const span = trace.getActiveSpan();
  if (span) span.addEvent(name, attributes);
}
