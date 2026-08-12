// src/utils/jose-config.ts — проверка JWS App Store Server API V2
//
// ⚠️ АУДИТ 26.07.2026 — ИСПРАВЛЕНА КРИТИЧЕСКАЯ УЯЗВИМОСТЬ (P0).
//
// Как было сломано:
//   1. Подпись JWS проверялась против сертификата, взятого из САМОГО JWS
//      (`x5c[0]`), то есть против ключа, который прислал клиент. Любой человек
//      с curl мог сгенерировать самоподписанный сертификат, подписать им
//      произвольный payload и получить пожизненный Premium.
//   2. Корневые сертификаты Apple загружались, но использовались лишь как
//      флаг «есть/нет» — цепочка leaf ← intermediate ← root НИКОГДА
//      не валидировалась.
//   3. Алгоритм был указан RS256, тогда как Apple подписывает ES256.
//      Доверие было вывернуто наизнанку: настоящие транзакции Apple
//      отвергались, а поддельные RSA — принимались.
//   4. Вне production при отсутствии сертификатов принималось ВСЁ подряд.
//
// Как стало:
//   • обязателен `alg === 'ES256'` и цепочка `x5c` минимум из двух звеньев;
//   • каждое звено проверяется подписью следующего (leaf ← intermediate ← root);
//   • корень сверяется с закреплённым Apple Root CA по отпечатку SHA-256;
//   • проверяются сроки действия всех сертификатов цепочки;
//   • подпись проверяется в формате IEEE P1363 (именно его использует ECDSA
//      в JWS, а не DER — это частая причина «валидная подпись не проходит»);
//   • при отсутствии корневого сертификата система ПАДАЕТ ЗАКРЫТО в любом
//     окружении. Открыть можно только явным `ALLOW_UNVERIFIED_IAP=true`,
//     который дополнительно запрещён в production.
//
// Корень задаётся любым из способов:
//   APPLE_ROOT_CA_PEM   — PEM-строка в переменной окружения (предпочтительно);
//   APPLE_ROOT_CERT_PATH — путь к .cer/.pem на диске;
//   стандартные пути ниже.

import { X509Certificate, verify as cryptoVerify } from 'node:crypto';
import fs from 'node:fs';

const APPLE_ROOT_CA_PATHS = [
  process.env.APPLE_ROOT_CERT_PATH,
  '/etc/apple-certs/AppleRootCA-G3.cer',
  './certs/AppleRootCA-G3.cer',
];

interface VerifiedTransaction {
  originalTransactionId: string;
  environment: 'Sandbox' | 'Production';
  expiresAt: number | null;  // ms since epoch, or null for lifetime
  revocationDate: number | null;
  productId?: string;
  transactionId?: string;
  /// Раньше это поле не возвращалось, из-за чего проверка bundleId
  /// в billing.ts была мёртвым кодом (`verified.bundleId` === undefined).
  bundleId?: string;
  /// Момент подписи транзакции Apple (мс). Нужен для приоритета по времени:
  /// устаревший DID_RENEW не должен отменять более свежий REFUND/REVOKE.
  signedDate: number | null;
}

interface VerifiedNotification {
  notificationType: string;
  /// Уникальный идентификатор доставки — ключ дедупликации вебхука.
  notificationUUID?: string;
  /// Момент подписи уведомления (мс) — порядок событий у Apple.
  signedDate: number | null;
  data: {
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
}

let cachedRoot: X509Certificate | null | undefined;

/// Разрешать непроверенные покупки можно только явным флагом и никогда в проде.
function unverifiedAllowed(): boolean {
  if (process.env.NODE_ENV === 'production') return false;
  return process.env.ALLOW_UNVERIFIED_IAP === 'true';
}

function loadAppleRootCert(): X509Certificate | null {
  if (cachedRoot !== undefined) return cachedRoot;

  const pem = process.env.APPLE_ROOT_CA_PEM;
  if (pem && pem.includes('BEGIN CERTIFICATE')) {
    try {
      cachedRoot = new X509Certificate(pem);
      console.log('[iap] Apple root CA загружен из APPLE_ROOT_CA_PEM');
      return cachedRoot;
    } catch (e: any) {
      console.error('[iap] APPLE_ROOT_CA_PEM не разобран:', e.message);
    }
  }

  for (const path of APPLE_ROOT_CA_PATHS) {
    if (!path) continue;
    try {
      // Синхронное чтение намеренно: сертификат нужен на горячем пути
      // проверки покупки, а файл читается один раз за жизнь процесса.
      if (fs.existsSync(path)) {
        // .cer от Apple — DER; X509Certificate принимает и DER, и PEM.
        cachedRoot = new X509Certificate(fs.readFileSync(path));
        console.log('[iap] Apple root CA загружен из', path);
        return cachedRoot;
      }
    } catch {
      // пробуем следующий путь
    }
  }

  // Скачивание корня по сети сознательно убрано: доверять корню, полученному
  // из непроверенного канала в момент проверки платежа, — это не проверка.
  console.error('[iap] Apple root CA не найден. Проверка покупок ОТКЛЮЧЕНА (fail-closed).');
  cachedRoot = null;
  return cachedRoot;
}

function base64UrlToBuffer(input: string): Buffer {
  return Buffer.from(input.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

function certFromBase64(b64: string): X509Certificate {
  return new X509Certificate(Buffer.from(b64, 'base64'));
}

function certIsCurrent(cert: X509Certificate, now: number): boolean {
  const from = Date.parse(cert.validFrom);
  const to = Date.parse(cert.validTo);
  if (Number.isNaN(from) || Number.isNaN(to)) return false;
  return now >= from && now <= to;
}

/// Полная проверка цепочки: каждое звено подписано следующим,
/// все сертификаты действительны, корень совпадает с закреплённым Apple Root CA.
function verifyCertChain(x5c: string[]): X509Certificate | null {
  if (!Array.isArray(x5c) || x5c.length < 2) return null;

  const root = loadAppleRootCert();
  if (!root) return null;

  let certs: X509Certificate[];
  try {
    certs = x5c.map(certFromBase64);
  } catch {
    return null;
  }

  const now = Date.now();
  for (const cert of certs) {
    if (!certIsCurrent(cert, now)) return null;
  }

  for (let i = 0; i < certs.length - 1; i++) {
    if (!certs[i].verify(certs[i + 1].publicKey)) return null;
  }

  // Последнее звено цепочки должно быть именно корнем Apple.
  // Сравниваем по отпечатку, а не по имени — имя подделывается тривиально.
  const chainRoot = certs[certs.length - 1];
  if (chainRoot.fingerprint256 !== root.fingerprint256) return null;

  return certs[0];  // leaf — им проверяем подпись самого JWS
}

function verifyJWSSignature(
  jws: string,
  // Параметр нужен самопроверке: она обязана тестировать криптотракт
  // с выключенным dev-обходом, иначе ALLOW_UNVERIFIED_IAP=true в .env
  // превращает «проверка сломана» и «проверка обойдена» в одну строку лога.
  allowUnverified: boolean = unverifiedAllowed(),
): Record<string, any> | null {
  const parts = jws.split('.');
  if (parts.length !== 3) return null;
  const [headerB64, payloadB64, signatureB64] = parts;

  let header: any;
  let payload: any;
  try {
    header = JSON.parse(base64UrlToBuffer(headerB64).toString('utf8'));
    payload = JSON.parse(base64UrlToBuffer(payloadB64).toString('utf8'));
  } catch {
    return null;
  }

  // Apple подписывает ES256. Любой другой алгоритм — попытка обхода.
  if (header.alg !== 'ES256') {
    console.warn('[iap] отклонено: alg =', header.alg, '(ожидался ES256)');
    return null;
  }

  const leaf = verifyCertChain(header.x5c);
  if (!leaf) {
    if (allowUnverified) {
      console.warn('[iap] ALLOW_UNVERIFIED_IAP=true — подпись НЕ проверена (только для разработки)');
      return payload;
    }
    console.warn('[iap] отклонено: цепочка сертификатов не ведёт к Apple Root CA');
    return null;
  }

  // ECDSA в JWS использует «сырой» формат IEEE P1363, а не DER.
  const ok = cryptoVerify(
    'sha256',
    Buffer.from(`${headerB64}.${payloadB64}`),
    { key: leaf.publicKey, dsaEncoding: 'ieee-p1363' },
    base64UrlToBuffer(signatureB64),
  );
  if (!ok) {
    console.warn('[iap] отклонено: подпись не соответствует leaf-сертификату');
    return null;
  }

  return payload;
}

/// Apple отдаёт даты то числом мс, то строкой — приводим к одному виду.
function toMillis(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const n = Number(value);
    if (Number.isFinite(n)) return n;
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

export const JoseConfig = {
  verifySignedTransaction(jws: string): VerifiedTransaction | null {
    const payload = verifyJWSSignature(jws);
    if (!payload) return null;

    const environment = payload.environment === 'Sandbox' ? 'Sandbox' : 'Production';
    // В production покупка из песочницы не даёт прав — иначе Premium
    // выдаётся бесплатно через сандбокс-аккаунт.
    if (process.env.NODE_ENV === 'production' && environment === 'Sandbox'
        && process.env.ALLOW_SANDBOX_IAP !== 'true') {
      console.warn('[iap] отклонено: Sandbox-транзакция в production');
      return null;
    }

    return {
      originalTransactionId: String(payload.originalTransactionId || payload.transactionId || ''),
      environment,
      expiresAt: toMillis(payload.expiresDate ?? payload.expiresDateMs),
      revocationDate: toMillis(payload.revocationDate),
      productId: payload.productId,
      transactionId: payload.transactionId ? String(payload.transactionId) : undefined,
      bundleId: payload.bundleId,
      signedDate: toMillis(payload.signedDate),
    };
  },

  verifyNotificationV2(signedPayload: string): VerifiedNotification | null {
    const payload = verifyJWSSignature(signedPayload);
    if (!payload) return null;

    return {
      notificationType: payload.notificationType,
      notificationUUID: typeof payload.notificationUUID === 'string' && payload.notificationUUID
        ? payload.notificationUUID
        : undefined,
      signedDate: toMillis(payload.signedDate),
      data: payload.data || {},
    };
  },

  /// Самопроверка на старте: заведомо некорректный JWS обязан быть отвергнут.
  /// Ловит ситуацию «проверка снова стала пропускать всё» до того, как это
  /// обнаружат в проде по бесплатным подпискам.
  ///
  /// Обход ALLOW_UNVERIFIED_IAP здесь сознательно выключен: самопроверка
  /// отвечает на вопрос «цел ли криптотракт», а не «в каком режиме окружение».
  /// О включённом dev-обходе app.ts предупреждает отдельной строкой.
  selfTest(): boolean {
    const fakeHeader = Buffer.from(JSON.stringify({ alg: 'ES256', x5c: ['AAAA'] })).toString('base64url');
    const fakePayload = Buffer.from(JSON.stringify({ productId: 'x', bundleId: 'y' })).toString('base64url');
    const forged = `${fakeHeader}.${fakePayload}.AAAA`;
    return verifyJWSSignature(forged, false) === null;
  },

  /// Активен ли dev-обход проверки подписи (ALLOW_UNVERIFIED_IAP=true вне
  /// production). app.ts печатает об этом честный warn на старте.
  unverifiedBypassActive(): boolean {
    return unverifiedAllowed();
  },
};
