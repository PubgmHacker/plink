// src/services/telemetry.ts — Pack 5: OpenTelemetry tracing
//
// Аудит 11.08.2026. Здесь был мёртвый код, который отчитывался об успехе.
//
// Прошлая версия делала `await import('@opentelemetry/auto-instrumentations-node')`
// и искала в модуле экспорт `registerOTel`. Такого экспорта в этом пакете нет
// и никогда не было — пакет отдаёт `getNodeAutoInstrumentations` и
// `getResourceDetectors`, а `registerOTel` живёт в `@vercel/otel`. Поэтому
// `_registerOTel` всегда оставался null, регистрация не происходила НИ РАЗУ,
// но в лог всё равно уходило «✅ OpenTelemetry initialized».
//
// Вторая причина, по которой это не работало: `OTEL_ENDPOINT=""` в .env и
// .env.example, а функция выходит раньше при пустом endpoint. То есть путь
// был мёртв дважды.
//
// Цена этого кода: `@opentelemetry/auto-instrumentations-node` тянул 194
// пакета (155 из них @opentelemetry/*) и держал 4 high + 30 moderate
// уязвимостей — 30 из 49 всех prod-уязвимостей бэкенда приходились на
// трейсер, который ни разу не собрал ни одного спана. Пакет удалён.
//
// Что осталось и почему это не потеря: `@opentelemetry/api` (лёгкий, без
// адвизори) остаётся, `withSpan`/`setSpanAttribute`/`addSpanEvent` работают
// как раньше. Без зарегистрированного SDK `trace.getTracer()` возвращает
// no-op трейсер — ровно то поведение, которое в проекте и было все эти
// месяцы. Ничего не сломалось, потому что ничего и не работало.
//
// Трассировка при этом НЕ потеряна: `@sentry/node` инициализируется в
// app.ts с `tracesSampleRate` и ведёт свои трейсы сам.
//
// Если понадобится настоящий OTLP-экспорт в дополнение к Sentry, нужны
// `@opentelemetry/sdk-node` + `@opentelemetry/exporter-trace-otlp-http` и
// явный `new NodeSDK({...}).start()` — но добавлять их стоит только когда
// появится живой коллектор, а не «на будущее».
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
      'Спаны через withSpan() сейчас no-op; трейсы ведёт Sentry.'
    );
    return;
  }

  console.log(
    '[Telemetry] OTLP-экспортёр не настроен — withSpan() работает как no-op. ' +
    'Трассировку ведёт Sentry (см. Sentry.init в app.ts).'
  );
}

// Helper: create span for manual tracing
export function withSpan<T>(
  name: string,
  fn: (span: any) => T | Promise<T>,
  options?: { kind?: SpanKind; attributes?: Record<string, any> }
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
