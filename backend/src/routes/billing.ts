// App Store Server API V2 (JWS verification)
//
// Previous implementation used deprecated
// verifyReceipt endpoint with shared secret. Apple deprecated this API;
// the modern flow uses App Store Server API V2 with signed JWS
// transactions verified against Apple's root cert.
//
// This module implements:
//   POST /api/billing/verify           — iOS sends JWS, backend verifies
//   GET  /api/billing/entitlements     — iOS fetches current entitlement
//   POST /api/billing/webhooks/apple   — Apple Server Notifications V2
//   GET  /api/billing/status           — legacy alias for entitlements
//   POST /api/billing/cancel           — user-initiated cancel (no refund)
//
// JWS verification:
//   Apple signs transactions as JWS (RFC 7515). The signature is
//   verified against Apple's root cert chain (downloadable from
//   https://www.apple.com/certificateauthority/AppleRootCA-G3.cer).
//   We use jose library for JWS verification.
//
// Server-authoritative entitlement:
//   - iOS NEVER trusts local StoreKit state for premium features.
//   - On app launch, iOS calls GET /api/billing/entitlements.
//   - On purchase, iOS calls POST /api/billing/verify with JWS.
//   - On Server Notification V2, backend updates DB directly.
//   - Premium features gate on the DB state, not StoreKit.
//
// Offline grace:
//   - iOS may cache the last verified entitlement for 24h.
//   - After 24h offline, premium features are disabled until reconnect.

import { createHash } from 'node:crypto';
import { prisma } from '../config/db.js';
import { logAudit, AuditActions } from '../utils/audit.js';
import { JoseConfig } from '../utils/jose-config.js';
import { validateBody } from '../middleware/validate.js';
import { billingVerifyBody } from '../schemas/requests.js';

// ─── Привязка appAccountToken ─────────────────────
//
// Формула для iOS (StoreKit 2, при покупке передавать
// Product.PurchaseOption.appAccountToken):
//
//   appAccountToken = UUIDv5(namespace: PLINK_APP_ACCOUNT_NAMESPACE,
//                            name: userId в нижнем регистре, UTF-8)
//
// Namespace фиксированный и обязан побайтово совпадать на клиенте.
// Сервер мягкий: токен проверяется только если он есть в верифицированном
// JWS; старые клиенты без токена пропускаются (с записью в лог).
export const PLINK_APP_ACCOUNT_NAMESPACE = '3f2c9a1e-8d5b-4e7a-b6c4-2a9d71f0e583';

function uuidToBytes(uuid: string): Buffer {
  return Buffer.from(uuid.replace(/-/g, ''), 'hex');
}

/// RFC 4122 UUID v5: SHA-1(namespace_bytes || name_bytes), первые 16 байт,
/// затем проставляются биты версии (5) и варианта (RFC 4122).
function uuidV5(name: string, namespace: string): string {
  const hash = createHash('sha1')
    .update(uuidToBytes(namespace))
    .update(Buffer.from(name, 'utf8'))
    .digest();
  const b = Buffer.from(hash.subarray(0, 16));
  b[6] = (b[6] & 0x0f) | 0x50; // версия 5
  b[8] = (b[8] & 0x3f) | 0x80; // вариант RFC 4122
  const hex = b.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/// Достаёт appAccountToken из УЖЕ ПРОВЕРЕННОГО JWS. Подпись этой же строки
/// только что проверена JoseConfig.verifySignedTransaction, поэтому payload
/// можно декодировать локально (VerifiedTransaction это поле не пробрасывает).
function extractAppAccountToken(jws: string): string | null {
  try {
    const payloadB64 = jws.split('.')[1];
    if (!payloadB64) return null;
    const payload = JSON.parse(
      Buffer.from(payloadB64.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8'),
    );
    return typeof payload.appAccountToken === 'string' && payload.appAccountToken.length > 0
      ? payload.appAccountToken
      : null;
  } catch {
    return null;
  }
}

// Premium plans — the product IDs here MUST match iOS PlinkProductID
// (StoreManager.swift: plink.plus.1m/3m/12m), the quarterly plan included.
// This map doubles as the allowlist and is checked before the JWS signature, so
// any id the client can buy but that is missing here is rejected outright. The
// com.syncwatch.plink.premium.* entries are legacy aliases, kept so transactions
// issued under the old naming still resolve.
const PLANS: Record<string, { tier: 'premium' | 'lifetime'; durationDays: number }> = {
  'plink.plus.1m': { tier: 'premium', durationDays: 30 },
  'plink.plus.3m': { tier: 'premium', durationDays: 90 },
  'plink.plus.12m': { tier: 'premium', durationDays: 365 },
  // Легаси-алиасы (не продаются клиентом, но зачитываются, если встретятся):
  'com.syncwatch.plink.premium.monthly': { tier: 'premium', durationDays: 30 },
  'com.syncwatch.plink.premium.yearly': { tier: 'premium', durationDays: 365 },
  'com.syncwatch.plink.premium.lifetime': { tier: 'lifetime', durationDays: 36500 },
};

export default async function billingRoutes(fastify: any) {
  // ─── POST /api/billing/verify ───────────────────────────────────────
  //
  // iOS sends a signed JWS transaction from StoreKit 2. Backend verifies
  // the JWS signature against Apple's root cert, extracts transaction
  // info, and updates the user's entitlement in DB.
  //
  // Billing trust boundary improvements:
  //   - Verify bundleId matches APPLE_BUNDLE_ID
  //   - Verify productId is in ALLOWED_PRODUCT_IDS
  //   - Bind appAccountToken or originalTransactionId to authenticated user
  //   - Never let one user submit another user's JWS
  //   - Unique indexes on transactionId + originalTransactionId
  //   - Upsert transaction + entitlement + audit in one serializable tx
  //   - Webhook processing idempotent by notification UUID
  //   - Refund/revoke wins over stale purchase events using timestamps
  //   - Fail closed when roots/config are missing
  //
  // Body: { "jws": "<signed-jws>", "productId": "...", "transactionId": "..." }
  // Response: { "entitlement": { "active": Bool, "tier": "free"|"premium"|"lifetime", "expiryDate": ISO8601|null } }

  const APPLE_BUNDLE_ID = process.env.APPLE_BUNDLE_ID || 'com.syncwatch.plink';
  const ALLOWED_PRODUCT_IDS = new Set(Object.keys(PLANS));

  // Ревью 26.07.2026: лимит был 5/мин и считался по IP (глобальный
  // keyGenerator в app.ts), а глобальный `ban: 5` после пяти превышений отдаёт
  // 403. iOS трактует любой 4xx как авторитетный отказ сервера и гасит премиум
  // локально, а restore прогоняет verify по ВСЕМ currentEntitlements подряд —
  // за одним carrier-NAT это выключало премиум платящим без пути
  // восстановления. Считаем по пользователю: `hook: 'preHandler'` ставит хук
  // лимита ПОСЛЕ authenticate (он дописывается в конец массива preHandler),
  // поэтому request.user уже заполнен; бан для этой ручки снят (ban < 0).
  fastify.post(
    '/billing/verify',
    {
      preHandler: [fastify.authenticate, validateBody(billingVerifyBody)],
      config: {
        rateLimit: {
          max: 30,
          timeWindow: '1 minute',
          ban: -1,
          hook: 'preHandler',
          keyGenerator: (request: any) => request.user?.id ?? request.ip,
        },
      },
    },
    async (request: any, reply: any) => {
      const { jws, productId, transactionId } = request.body || {};

      if (!jws || typeof jws !== 'string') {
        return reply.status(400).send({ error: 'jws required' });
      }
      // Verify productId is in allowlist.
      if (!productId || !ALLOWED_PRODUCT_IDS.has(productId)) {
        return reply.status(400).send({ error: 'Invalid productId' });
      }

      try {
        // Verify JWS signature against Apple root cert.
        const verified = await JoseConfig.verifySignedTransaction(jws);
        if (!verified) {
          await logAudit({
            userId: request.user.id,
            action: 'billing.verify_failed',
            ip: request.ip,
            metadata: { productId, reason: 'jws_signature_invalid' },
          });
          return reply.status(400).send({
            entitlement: { active: false, tier: 'free', expiryDate: null },
            error: 'JWS signature verification failed',
          });
        }

        // Verify bundleId matches configured value.
        const bundleId = (verified as any).bundleId;
        if (bundleId && bundleId !== APPLE_BUNDLE_ID) {
          await logAudit({
            userId: request.user.id,
            action: 'billing.verify_failed',
            ip: request.ip,
            metadata: {
              productId,
              reason: 'bundle_id_mismatch',
              expected: APPLE_BUNDLE_ID,
              got: bundleId,
            },
          });
          return reply.status(403).send({
            entitlement: { active: false, tier: 'free', expiryDate: null },
            error: 'Bundle ID mismatch',
          });
        }

        // Verify productId in JWS matches body productId.
        const jwsProductId = (verified as any).productId;
        if (jwsProductId && jwsProductId !== productId) {
          await logAudit({
            userId: request.user.id,
            action: 'billing.verify_failed',
            ip: request.ip,
            metadata: {
              productId,
              reason: 'product_id_mismatch',
              bodyProductId: productId,
              jwsProductId,
            },
          });
          return reply.status(400).send({
            entitlement: { active: false, tier: 'free', expiryDate: null },
            error: 'Product ID mismatch between body and JWS',
          });
        }

        // Мягкая привязка appAccountToken к аккаунту.
        // Если токен присутствует в верифицированном JWS — он обязан совпадать
        // с UUIDv5(userId) (см. PLINK_APP_ACCOUNT_NAMESPACE выше). Иначе любой
        // валидный чужой JWS засчитывался первому приславшему (first-submit-wins).
        const appAccountToken = extractAppAccountToken(jws);
        if (appAccountToken) {
          const expectedToken = uuidV5(
            String(request.user.id).toLowerCase(),
            PLINK_APP_ACCOUNT_NAMESPACE,
          );
          if (appAccountToken.toLowerCase() !== expectedToken) {
            await logAudit({
              userId: request.user.id,
              action: 'billing.verify_failed',
              ip: request.ip,
              metadata: { productId, reason: 'app_account_token_mismatch', appAccountToken },
            });
            return reply.status(403).send({
              entitlement: { active: false, tier: 'free', expiryDate: null },
              error: 'appAccountToken does not match authenticated user',
            });
          }
        } else {
          // Старый клиент без appAccountToken — пропускаем как раньше, но
          // фиксируем в логе, чтобы видеть долю непривязанных покупок.
          request.log?.warn(
            { userId: request.user.id, productId },
            '[billing] JWS без appAccountToken — привязка покупки к аккаунту не проверена (старый клиент)',
          );
        }

        // Extract transaction info from verified payload.
        const { originalTransactionId, environment, expiresAt, revocationDate } = verified;

        // Ревью 26.07.2026: verifySignedTransaction отдаёт ПУСТУЮ строку, если в
        // payload нет ни originalTransactionId, ни transactionId. После появления
        // @unique пустая строка стала глобально уникальным ключом: первая такая
        // подписка занимала бы строку originalTransactionId='' навсегда, а все
        // следующие пользователи получали бы 403 ownership_mismatch (и вебхук по
        // этой строке применял бы эффект к чужому аккаунту). Такой JWS
        // непригоден как ключ идемпотентности — отвергаем.
        if (!originalTransactionId) {
          await logAudit({
            userId: request.user.id,
            action: 'billing.verify_failed',
            ip: request.ip,
            metadata: { productId, reason: 'missing_original_transaction_id' },
          });
          return reply.status(400).send({
            entitlement: { active: false, tier: 'free', expiryDate: null },
            error: 'Transaction has no originalTransactionId',
          });
        }

        // Идемпотентность и проверка владения ключуются
        // ТОЛЬКО идентификатором из подписанного payload. Раньше ключом было
        // body.transactionId — один валидный JWS можно было переиграть под
        // произвольным transactionId и наплодить записей в обход проверки.
        const verifiedTransactionId = verified.transactionId || originalTransactionId;
        if (
          transactionId &&
          verified.transactionId &&
          String(transactionId) !== verified.transactionId
        ) {
          await logAudit({
            userId: request.user.id,
            action: 'billing.verify_failed',
            ip: request.ip,
            metadata: {
              productId,
              reason: 'transaction_id_mismatch',
              bodyTransactionId: String(transactionId),
              jwsTransactionId: verified.transactionId,
            },
          });
          return reply.status(400).send({
            entitlement: { active: false, tier: 'free', expiryDate: null },
            error: 'Transaction ID mismatch between body and JWS',
          });
        }

        // Ownership check — verify this transaction belongs to the authenticated user.
        // Check if originalTransactionId is already linked to a DIFFERENT user.
        const existingTx = await prisma.transactionRecord.findUnique({
          where: { transactionId: verifiedTransactionId },
        });
        if (existingTx && existingTx.userId !== request.user.id) {
          await logAudit({
            userId: request.user.id,
            action: 'billing.verify_failed',
            ip: request.ip,
            metadata: {
              productId,
              reason: 'ownership_mismatch',
              originalTransactionId,
              ownerUserId: existingTx.userId,
            },
          });
          return reply.status(403).send({
            entitlement: { active: false, tier: 'free', expiryDate: null },
            error: 'Transaction belongs to a different user',
          });
        }

        // Ревью 26.07.2026: проверка «чек устарел после отзыва» привязана к
        // КОНКРЕТНОЙ транзакции, а не к подписке. Раньше серверный
        // Subscription.revokedAt сравнивался с signedDate чека, поэтому после
        // возврата за один период ЛЮБАЯ переверификация текущего (валидного)
        // чека получала 400 → iOS трактует 4xx как авторитетный отказ и гасил
        // премиум платящему пользователю без пути восстановления. Новая
        // транзакция продления своей записи ещё не имеет и проходит нормально.
        if (existingTx?.revocationDate) {
          await logAudit({
            userId: request.user.id,
            action: 'billing.verify_failed',
            ip: request.ip,
            metadata: {
              productId,
              reason: 'transaction_already_revoked',
              originalTransactionId,
              revocationDate: existingTx.revocationDate.toISOString(),
            },
          });
          return reply.status(400).send({
            entitlement: { active: false, tier: 'free', expiryDate: null },
            error: 'Transaction revoked',
          });
        }

        // If revoked, fail closed.
        if (revocationDate) {
          // Отозвана именно присланная транзакция — помечаем её запись, а не все
          // транзакции подписки (иначе валидный текущий период тоже блокируется).
          await revokeEntitlement(
            request.user.id,
            originalTransactionId,
            new Date(revocationDate),
            verifiedTransactionId,
          );
          await logAudit({
            userId: request.user.id,
            action: 'billing.revoked',
            ip: request.ip,
            metadata: { productId, originalTransactionId, revocationDate },
          });
          return reply.status(400).send({
            entitlement: { active: false, tier: 'free', expiryDate: null },
            error: 'Transaction revoked',
          });
        }

        // Compute expiry.
        const plan = PLANS[productId];
        const expiryDate = expiresAt
          ? new Date(expiresAt)
          : new Date(Date.now() + plan.durationDays * 24 * 3600 * 1000);

        // Wrap transaction record + subscription update in one tx.
        // Store the transaction record (idempotent on transactionId).
        // Ревью 26.07.2026: гонку двух параллельных verify разрешает уникальный
        // индекс, но раньше проигравшая сторона получала P2002 → общий catch →
        // 500 «Verification failed». Повторяем транзакцию один раз: на втором
        // заходе строка уже есть и upsert уходит в ветку update.
        await withUniqueConflictRetry(() =>
          prisma.$transaction(async (tx) => {
            await tx.transactionRecord.upsert({
              where: { transactionId: verifiedTransactionId },
              create: {
                userId: request.user.id,
                transactionId: verifiedTransactionId,
                originalTransactionId,
                productId,
                environment,
                jws,
                expiresAt: expiryDate,
                revocationDate: null,
              },
              update: {
                // On re-verify (e.g. renewal), update expiry + clear revocation.
                expiresAt: expiryDate,
                revocationDate: null,
                verifiedAt: new Date(),
              },
            });

            // Ревью 26.07.2026: ветка update ниже могла МОЛЧА переписать подписку
            // ДРУГОГО аккаунта (у продлений transactionId каждый раз новый, и
            // проверка владения по TransactionRecord выше не срабатывает). Владение
            // проверяем по самой строке подписки — и ищем её по тому же ключу, по
            // которому ниже идёт upsert (originalTransactionId, @unique).
            const existingSub = await tx.subscription.findUnique({
              where: { originalTransactionId },
              select: { userID: true },
            });
            if (existingSub && existingSub.userID !== request.user.id) {
              const err: any = new Error('Transaction belongs to a different user');
              err.plinkCode = 'subscription_ownership_mismatch';
              err.originalTransactionId = originalTransactionId;
              throw err;
            }

            // Upsert subscription.
            // Ветка update была мёртвой — Subscription.id это
            // @default(uuid()), create его не задавал, поэтому where { id:
            // originalTransactionId } не совпадал НИКОГДА и каждый verify/renew
            // плодил новую активную подписку. После миграции
            // 20260726120500_billing_idempotency у originalTransactionId есть
            // @unique, поэтому ключуем upsert по нему — по единственному реально
            // уникальному признаку подписки Apple (он стабилен между продлениями).
            // Уникальный индекс же закрывает гонку двух параллельных verify:
            // проигравшая вставка падает на ограничении БД (P2002), а не создаёт
            // дубль — повтор транзакции выше сводит её на ветку update.
            // Ревью 26.07.2026: `id: originalTransactionId` из ветки create убран.
            // upsert компилируется в ON CONFLICT ("originalTransactionId"), который
            // конфликт по ПЕРВИЧНОМУ ключу не поглощает: чужая строка с таким id
            // (или гонка) давала вечный 500 на verify. id — обычный uuid, ничего от
            // его значения не зависит. Ветка create заполняет ВСЕ поля ветки
            // update, включая revokedAt.
            await tx.subscription.upsert({
              where: { originalTransactionId },
              create: {
                userID: request.user.id,
                plan: productId,
                isActive: true,
                expiresAt: expiryDate,
                originalTransactionId,
                environment,
                lastVerifiedAt: new Date(),
                revokedAt: null,
              },
              update: {
                isActive: true,
                expiresAt: expiryDate,
                originalTransactionId,
                environment,
                lastVerifiedAt: new Date(),
                revokedAt: null,
              },
            });

            // Mark previous subscriptions for this user as inactive (only one active).
            // Исключаем каноническую строку по originalTransactionId — тому же
            // ключу, что и upsert выше (id у легаси-строк мог остаться случайным
            // uuid). `originalTransactionId: { not: null }` обязателен — иначе
            // гасились бы и комплиментарные подписки без originalTransactionId,
            // выданные админом.
            await tx.subscription.updateMany({
              where: {
                userID: request.user.id,
                isActive: true,
                originalTransactionId: { not: null },
                NOT: { originalTransactionId },
              },
              data: { isActive: false },
            });

            // Update user.isPremium + premiumUntil.
            const isLifetime = plan.tier === 'lifetime';
            await tx.user.update({
              where: { id: request.user.id },
              data: {
                isPremium: true,
                premiumUntil: isLifetime ? null : expiryDate,
              },
            });

            // Audit log inside the same transaction.
            // Ревью 26.07.2026: в модели AuditLog НЕТ полей actorId/targetType/
            // targetId/requestId (только userId/action/ip/userAgent/metadata).
            // Каст `as any` глушил tsc, а Prisma отвергала неизвестные аргументы
            // на рантайме — вся транзакция откатывалась и КАЖДЫЙ verify отдавал
            // 500. Пишем реальные поля и без каста, чтобы tsc ловил расхождения.
            await tx.auditLog.create({
              data: {
                userId: request.user.id,
                action: 'billing.verify_success',
                ip: request.ip,
                metadata: {
                  productId,
                  originalTransactionId,
                  transactionId: verifiedTransactionId,
                  requestId: String(request.id ?? ''),
                  expiresAt: expiryDate.toISOString(),
                },
              },
            });
          }),
        ); // end prisma.$transaction

        // Audit already written inside transaction above.
        // Compute lifetime flag for response.
        const isLifetime = plan.tier === 'lifetime';

        reply.send({
          entitlement: {
            active: true,
            tier: plan.tier,
            expiryDate: isLifetime ? null : expiryDate.toISOString(),
          },
        });
      } catch (e: any) {
        // Ревью 26.07.2026: конфликт владения подпиской — это 403, а не 500,
        // иначе iOS уходил в офлайн-грейс и включал премиум локально.
        if (e?.plinkCode === 'subscription_ownership_mismatch') {
          await logAudit({
            userId: request.user.id,
            action: 'billing.verify_failed',
            ip: request.ip,
            metadata: {
              productId,
              reason: 'subscription_ownership_mismatch',
              originalTransactionId: e.originalTransactionId ?? null,
            },
          });
          return reply.status(403).send({
            entitlement: { active: false, tier: 'free', expiryDate: null },
            error: 'Transaction belongs to a different user',
          });
        }
        console.error('[billing] verify error', e);
        reply.status(500).send({ error: 'Verification failed: ' + e.message });
      }
    },
  );

  // ─── GET /api/billing/entitlements ─────────────────────────────────
  //
  // iOS calls this on app launch to fetch the authoritative entitlement.
  // Returns the current DB state — iOS must NOT trust local StoreKit state.
  fastify.get(
    '/billing/entitlements',
    {
      preHandler: [fastify.authenticate],
    },
    async (request: any, reply: any) => {
      const user = await prisma.user.findUnique({
        where: { id: request.user.id },
        select: { isPremium: true, premiumUntil: true },
      });

      if (!user) {
        return reply.status(404).send({ error: 'User not found' });
      }

      const now = new Date();
      const isActive = user.isPremium && (!user.premiumUntil || user.premiumUntil > now);

      // Determine tier: if premiumUntil is null and isPremium is true → lifetime.
      // Otherwise premium (will expire).
      const tier: 'free' | 'premium' | 'lifetime' = !isActive
        ? 'free'
        : user.premiumUntil === null
          ? 'lifetime'
          : 'premium';

      reply.send({
        entitlement: {
          active: isActive,
          tier,
          expiryDate: user.premiumUntil?.toISOString() ?? null,
        },
      });
    },
  );

  // ─── POST /api/billing/webhooks/apple ──────────────────────────────
  //
  // App Store Server Notifications V2 endpoint.
  // Apple sends signed JWS notifications for lifecycle events:
  //   SUBSCRIPTION_PURCHASED, SUBSCRIPTION_RENEWED, SUBSCRIPTION_EXPIRED,
  //   REFUND, REVOKE, GRACE_PERIOD_EXPIRED.
  //
  // The notification body is a signed JWS — we verify it against Apple's
  // root cert before processing.
  //
  // No authentication — Apple calls this directly. We verify via JWS
  // signature instead.
  fastify.post(
    '/billing/webhooks/apple',
    {
      config: { rateLimit: { max: 100, timeWindow: '1 minute' } },
    },
    async (request: any, reply: any) => {
      const body = request.body;

      // V2 notifications are signed JWS in the body.
      const signedPayload = body?.signedPayload;
      if (!signedPayload || typeof signedPayload !== 'string') {
        return reply.status(400).send({ error: 'signedPayload required' });
      }

      try {
        const notification = await JoseConfig.verifyNotificationV2(signedPayload);
        if (!notification) {
          console.warn('[billing] webhook JWS verification failed');
          return reply.status(400).send({ error: 'JWS verification failed' });
        }

        const { notificationType, notificationUUID, data } = notification;
        const { signedTransactionInfo, signedRenewalInfo } = data || {};

        // Decode transaction info (also JWS-signed).
        let transactionInfo: any = null;
        if (signedTransactionInfo) {
          transactionInfo = await JoseConfig.verifySignedTransaction(signedTransactionInfo);
        }

        if (!transactionInfo) {
          return reply.status(400).send({ error: 'Could not decode transaction info' });
        }

        // Every idempotency key comes ONLY from verified signatures:
        // notificationUUID from the verified notification, originalTransactionId
        // from the verified signedTransactionInfo. Nothing but signedPayload
        // itself is ever read out of the request body.
        const { originalTransactionId, productId, environment } = transactionInfo;

        // Ревью 26.07.2026: verifySignedTransaction отдаёт пустую строку, если в
        // payload нет идентификаторов. Искать по ней подписку нельзя — с @unique
        // строка originalTransactionId='' может принадлежать кому угодно, и
        // эффект уведомления применился бы к чужому аккаунту. 200, чтобы Apple не
        // ретраил вечно заведомо непригодное уведомление.
        if (!originalTransactionId) {
          console.warn(
            '[billing] webhook: transaction info без originalTransactionId',
            notificationType,
          );
          return reply
            .status(200)
            .send({ processed: false, reason: 'missing_original_transaction_id' });
        }

        // Find user by originalTransactionId (stored in Subscription).
        // После миграции 20260726120500_billing_idempotency поле @unique.
        const sub = await prisma.subscription.findUnique({
          where: { originalTransactionId },
          select: { userID: true, id: true },
        });

        if (!sub) {
          console.warn('[billing] webhook: no subscription for', originalTransactionId);
          // Apple may send notifications for transactions we haven't seen yet.
          // Log and return 200 so Apple doesn't retry.
          return reply.status(200).send({ processed: false, reason: 'no_local_subscription' });
        }

        // Порядок событий у Apple — по signedDate уведомления/транзакции.
        const eventAtMs = notification.signedDate ?? transactionInfo.signedDate ?? null;
        const eventDate =
          eventAtMs !== null && Number.isFinite(eventAtMs) ? new Date(eventAtMs) : null;

        // Дедупликация доставок по notificationUUID через
        // таблицу AppleNotification. Apple повторяет уведомление при любом не-2xx
        // и иногда дублирует доставку сама. Заявка пишется ДО обработки, поэтому
        // гонку двух одновременных доставок разрешает первичный ключ (P2002 у
        // проигравшей), а не «проверил-и-сделал». Повтор — короткое замыкание с
        // 200, чтобы Apple не ретраил вечно.
        if (notificationUUID) {
          const claimed = await claimNotification({
            notificationUUID,
            notificationType: String(notificationType ?? 'UNKNOWN'),
            originalTransactionId,
            signedDate: eventDate,
          });
          if (!claimed) {
            return reply.status(200).send({ processed: false, reason: 'duplicate_notification' });
          }
        }

        try {
          switch (notificationType) {
            case 'SUBSCRIPTION_PURCHASED':
            case 'SUBSCRIPTION_RENEWED':
            case 'SUBSCRIPTION_RENEWAL': // legacy alias
            case 'DID_RENEW': // legacy alias
              await handleRenewal(
                sub.userID,
                originalTransactionId,
                transactionInfo,
                eventDate,
                notificationUUID ?? null,
              );
              break;

            case 'SUBSCRIPTION_EXPIRED':
            case 'GRACE_PERIOD_EXPIRED':
              await handleExpiry(
                sub.userID,
                originalTransactionId,
                eventDate,
                notificationUUID ?? null,
              );
              break;

            case 'REFUND':
              await handleRefund(
                sub.userID,
                originalTransactionId,
                transactionInfo,
                eventDate,
                notificationUUID ?? null,
              );
              break;

            case 'REVOKE':
              await handleRevoke(
                sub.userID,
                originalTransactionId,
                transactionInfo,
                eventDate,
                notificationUUID ?? null,
              );
              break;

            default:
              console.log('[billing] webhook: unhandled notificationType', notificationType);
          }

          await logAudit({
            userId: sub.userID,
            action: `billing.webhook.${notificationType}`,
            ip: request.ip,
            metadata: { originalTransactionId, productId, environment },
          });
        } catch (e) {
          // Ревью 26.07.2026: обработка не дошла до конца — снимаем заявку, иначе
          // ретрай Apple был бы отброшен как дубликат и REFUND/REVOKE потерялся
          // бы навсегда. Ответ 5xx (общий catch ниже) заставит Apple повторить.
          if (notificationUUID) await releaseNotification(notificationUUID);
          throw e;
        }

        // Обработка дошла до конца — фиксируем время применения.
        if (notificationUUID) await markNotificationProcessed(notificationUUID);

        reply.status(200).send({ processed: true });
      } catch (e: any) {
        console.error('[billing] webhook error', e);
        // Ревью 26.07.2026: на внутреннюю ошибку отвечаем 5xx, чтобы Apple
        // повторил доставку — прежний 200 навсегда терял REFUND/REVOKE.
        // Отметка «обработано» ставится только после успеха, поэтому ретрай
        // не будет отброшен как дубликат.
        reply.status(500).send({ processed: false, error: e.message });
      }
    },
  );

  // ─── GET /api/billing/status (legacy alias) ────────────────────────
  fastify.get(
    '/billing/status',
    {
      preHandler: [fastify.authenticate],
    },
    async (request: any, reply: any) => {
      const user = await prisma.user.findUnique({
        where: { id: request.user.id },
        select: { isPremium: true, premiumUntil: true },
      });

      if (!user) return reply.status(404).send({ error: 'User not found' });

      const isActive = user.isPremium && (!user.premiumUntil || user.premiumUntil > new Date());

      reply.send({
        isPremium: isActive,
        premiumUntil: user.premiumUntil,
      });
    },
  );

  // ─── POST /api/billing/cancel ──────────────────────────────────────
  fastify.post(
    '/billing/cancel',
    {
      preHandler: [fastify.authenticate],
    },
    async (request: any, reply: any) => {
      await prisma.subscription.updateMany({
        where: {
          userID: request.user.id,
          isActive: true,
        },
        data: { isActive: false },
      });

      await logAudit({
        userId: request.user.id,
        action: 'billing.cancel',
        ip: request.ip,
      });

      reply.send({ success: true });
    },
  );
}

// ─── Дедупликация Server Notifications V2 ────────────────────────────
//
// Обработанные notificationUUID живут в таблице
// AppleNotification (миграция 20260726120500_billing_idempotency), где
// notificationUUID — первичный ключ. Раньше отметка писалась в AuditLog с
// детерминированным id (таблицы не было), и порядок был «обработали → отметили»:
// две одновременные доставки одного уведомления успевали применить эффект
// дважды, потому что обе проходили проверку до записи.
//
// Схема теперь: заявка ДО обработки (P2002 = дубликат, короткое замыкание с
// 200) → обработка → фиксация времени; при ошибке заявка снимается, чтобы
// ретрай Apple не был отброшен как дубликат. Жёсткое падение процесса между
// заявкой и эффектом теряет одно уведомление — это осознанный размен на
// защиту от двойного применения; отзывы (REFUND/REVOKE) дополнительно
// подтверждаются при следующем verify по TransactionRecord.revocationDate.

/// true — заявка наша, можно обрабатывать. false — уведомление уже видели.
async function claimNotification(params: {
  notificationUUID: string;
  notificationType: string;
  originalTransactionId: string | null;
  signedDate: Date | null;
}): Promise<boolean> {
  try {
    await prisma.appleNotification.create({
      data: {
        notificationUUID: params.notificationUUID,
        notificationType: params.notificationType,
        originalTransactionId: params.originalTransactionId,
        signedDate: params.signedDate,
      },
    });
    return true;
  } catch (e: any) {
    // P2002 — параллельная (или повторная) доставка успела первой.
    if (e?.code === 'P2002') return false;
    throw e;
  }
}

/// Обработка завершилась — обновляем время применения (заявка ставилась раньше).
async function markNotificationProcessed(notificationUUID: string): Promise<void> {
  try {
    await prisma.appleNotification.update({
      where: { notificationUUID },
      data: { processedAt: new Date() },
    });
  } catch (e: any) {
    // Эффект уже применён — падать нельзя: 5xx заставил бы Apple прислать
    // уведомление снова и применить его второй раз.
    console.error('[billing] не удалось отметить уведомление обработанным', e?.message);
  }
}

/// Снятие заявки при неудачной обработке — чтобы ретрай Apple прошёл.
///
/// Ревью 26.07.2026: раньше ошибка удаления просто логировалась, а ответ всё
/// равно уходил 5xx. Если DELETE не прошёл по той же причине, что и сама
/// обработка (моргнула БД), заявка оставалась в таблице и ретрай Apple
/// отбивался как duplicate → REFUND/REVOKE терялся навсегда, то есть ровно тот
/// сценарий, ради которого release и добавлен. Повторяем удаление с короткой
/// паузой; если не вышло совсем — пишем отдельный маркер для алерта.
async function releaseNotification(notificationUUID: string, attempts = 3): Promise<void> {
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      await prisma.appleNotification.delete({ where: { notificationUUID } });
      return;
    } catch (e: any) {
      // Строки уже нет — считать это неудачей нельзя.
      if (e?.code === 'P2025') return;
      if (attempt === attempts) {
        console.error(
          '[billing][ALERT] заявка на уведомление не снята — ретрай Apple будет отброшен как дубликат',
          { notificationUUID, error: e?.message },
        );
        return;
      }
      await new Promise((resolve) => setTimeout(resolve, 50 * attempt));
    }
  }
}

// ─── Приоритет по времени между уведомлениями ────────────────────────
//
// Ревью 26.07.2026: Apple не гарантирует порядок доставки, поэтому «кто пришёл
// позже» решается по signedDate, а не по времени приёма. Важно, что сравнивать
// нужно ТОЛЬКО с уведомлениями противоположного смысла:
//   • продление не должно включать премиум, если позже подписан отзыв;
//   • отзыв не должен гасить премиум, если позже подписано продление.
// Раньше проверка в handleRenewal сравнивалась с уведомлениями ЛЮБОГО типа, а
// claimNotification пишет строку для всех доставок — включая необрабатываемые
// (DID_CHANGE_RENEWAL_PREF/STATUS, PRICE_INCREASE, OFFER_REDEEMED и т.д.).
// Любое такое уведомление с более поздним signedDate выключало реактивацию, и
// легитимный DID_RENEW не продлевал User.premiumUntil — премиум гас у
// платящего пользователя.

/// Типы, которые реально ГАСЯТ право (обрабатываются ниже в этом файле).
const ENTITLEMENT_REVOKING_TYPES = [
  'SUBSCRIPTION_EXPIRED',
  'GRACE_PERIOD_EXPIRED',
  'REFUND',
  'REVOKE',
];

/// Типы, которые реально ВЫДАЮТ право.
const ENTITLEMENT_GRANTING_TYPES = [
  'SUBSCRIPTION_PURCHASED',
  'SUBSCRIPTION_RENEWED',
  'SUBSCRIPTION_RENEWAL',
  'DID_RENEW',
];

type NotificationMarker = {
  notificationUUID: string;
  notificationType: string;
  signedDate: Date | null;
};

/// Уведомление указанных типов по этой же подписке, подписанное ПОЗЖЕ текущего.
/// null — текущее уведомление самое свежее (или у него нет signedDate: тогда
/// сравнивать не с чем и проверка не применяется, чтобы не рубить легальные
/// события).
async function findNewerNotification(
  originalTransactionId: string,
  types: string[],
  eventDate: Date | null,
  selfUUID: string | null,
): Promise<NotificationMarker | null> {
  if (!eventDate) return null;
  return prisma.appleNotification.findFirst({
    where: {
      originalTransactionId,
      notificationType: { in: types },
      signedDate: { gt: eventDate },
      ...(selfUUID ? { NOT: { notificationUUID: selfUUID } } : {}),
    },
    select: { notificationUUID: true, notificationType: true, signedDate: true },
    orderBy: { signedDate: 'desc' },
  });
}

function markerToMetadata(marker: NotificationMarker | null) {
  return marker
    ? {
        notificationUUID: marker.notificationUUID,
        notificationType: marker.notificationType,
        signedDate: marker.signedDate?.toISOString() ?? null,
      }
    : null;
}

/// Одна повторная попытка на нарушение уникальности: проигравшая сторона гонки
/// на втором заходе видит уже существующую строку и уходит в ветку update.
async function withUniqueConflictRetry<T>(run: () => Promise<T>, attempts = 2): Promise<T> {
  for (let attempt = 1; ; attempt++) {
    try {
      return await run();
    } catch (e: any) {
      if (attempt >= attempts || e?.code !== 'P2002') throw e;
    }
  }
}

// ─── Webhook handlers ────────────────────────────────────────────────

async function handleRenewal(
  userId: string,
  originalTransactionId: string,
  txInfo: any,
  eventDate: Date | null = null,
  notificationUUID: string | null = null,
) {
  // Раньше читалось несуществующее поле expiresDateMs —
  // verifySignedTransaction возвращает `expiresAt` (мс с эпохи), поэтому
  // вебхук продления был вечным no-op и premiumUntil никогда не продлевался.
  const expiresAt =
    typeof txInfo.expiresAt === 'number' && Number.isFinite(txInfo.expiresAt)
      ? new Date(txInfo.expiresAt)
      : null;
  if (!expiresAt) return;

  // Приоритет по времени. Раньше продление безусловно
  // реактивировало премиум, поэтому устаревший DID_RENEW, доставленный после
  // REFUND/REVOKE, возвращал премиум отозванному пользователю.
  const current = await prisma.subscription.findUnique({
    where: { originalTransactionId },
    select: { revokedAt: true, expiresAt: true },
  });
  // Отзыв мог быть записан и на уровне отдельной транзакции (handleRefund
  // помечает revocationDate только у своей записи TransactionRecord, чтобы не
  // блокировать переверификацию оплаченного периода) — берём самый свежий
  // след отзыва из обоих источников.
  const revokedTx = await prisma.transactionRecord.findFirst({
    where: { originalTransactionId, revocationDate: { not: null } },
    select: { revocationDate: true },
    orderBy: { revocationDate: 'desc' },
  });
  const revokedAt =
    [current?.revokedAt ?? null, revokedTx?.revocationDate ?? null]
      .filter((d): d is Date => d instanceof Date)
      .sort((a, b) => b.getTime() - a.getTime())[0] ?? null;

  // Ревью 26.07.2026: eventDate — это signedDate Apple, а revokedAt раньше
  // сравнивался с ним, будучи временем ПРИЁМА вебхука на сервере (теперь для
  // REFUND берётся revocationDate Apple, см. handleRefund, но серверный
  // fallback остался). Сравнение с '>=' и early-return выбрасывали ЛЕГАЛЬНОЕ
  // продление, подписанное до приёма возврата за старый период, — и ручка
  // отвечала 200, поэтому продление больше не приходило. Теперь в спорном
  // случае срок продлеваем, но отзыв НЕ снимаем и премиум не включаем.
  const staleAfterRevoke = !!revokedAt && (!eventDate || revokedAt > eventDate);

  // Доставка вне очереди. Apple не гарантирует порядок,
  // поэтому если по этой же подписке УЖЕ обработано уведомление, подписанное
  // позже, — текущее устарело и премиум по нему не включаем.
  // Ревью 26.07.2026: только уведомления, которые ГАСЯТ право. Раньше фильтра
  // по типу не было, а заявка пишется на любую доставку — поэтому безобидный
  // DID_CHANGE_RENEWAL_PREF, подписанный на секунду позже, отменял продление
  // премиума платящему пользователю (см. ENTITLEMENT_REVOKING_TYPES выше).
  const supersededBy = await findNewerNotification(
    originalTransactionId,
    ENTITLEMENT_REVOKING_TYPES,
    eventDate,
    notificationUUID,
  );

  const skipReactivation = staleAfterRevoke || supersededBy !== null;

  if (current && current.expiresAt > expiresAt) {
    // В базе уже более свежий срок — уведомление устарело, не укорачиваем.
    return;
  }

  await prisma.subscription.updateMany({
    where: { userID: userId, originalTransactionId },
    data: skipReactivation
      ? { expiresAt, lastVerifiedAt: new Date() }
      : { isActive: true, expiresAt, lastVerifiedAt: new Date(), revokedAt: null },
  });

  if (skipReactivation) {
    // Пропуск реактивации виден в аудите — иначе такие потери незаметны.
    await logAudit({
      userId,
      action: 'billing.webhook.renewal_after_revocation',
      metadata: {
        originalTransactionId,
        reason: staleAfterRevoke ? 'revoked' : 'superseded_by_newer_notification',
        revokedAt: revokedAt?.toISOString() ?? null,
        supersededBy: markerToMetadata(supersededBy),
        eventDate: eventDate?.toISOString() ?? null,
        expiresAt: expiresAt.toISOString(),
      },
    });
    return;
  }

  await prisma.user.update({
    where: { id: userId },
    data: { isPremium: true, premiumUntil: expiresAt },
  });
}

/// Обратная сторона приоритета по времени: устаревшее гашение, доставленное
/// ПОСЛЕ более свежего продления, не должно отбирать оплаченный период.
/// Возвращает «обогнавшее» продление или null.
///
/// Ревью 26.07.2026: раньше проверка стояла только в handleRenewal, а
/// handleExpiry/handleRefund/handleRevoke гасили право безусловно — именно эта
/// гонка и отбирает премиум у платящего (период N возвращён, период N+1 уже
/// оплачен и включён, REFUND за N приходит с задержкой и обнуляет всё).
async function findNewerRenewal(
  originalTransactionId: string,
  eventDate: Date | null,
  notificationUUID: string | null,
): Promise<NotificationMarker | null> {
  return findNewerNotification(
    originalTransactionId,
    ENTITLEMENT_GRANTING_TYPES,
    eventDate,
    notificationUUID,
  );
}

async function logRevocationSkipped(
  userId: string,
  originalTransactionId: string,
  kind: string,
  newerRenewal: NotificationMarker,
  eventDate: Date | null,
) {
  await logAudit({
    userId,
    action: 'billing.webhook.revocation_skipped',
    metadata: {
      originalTransactionId,
      kind,
      supersededBy: markerToMetadata(newerRenewal),
      eventDate: eventDate?.toISOString() ?? null,
    },
  });
}

async function handleExpiry(
  userId: string,
  originalTransactionId: string,
  eventDate: Date | null = null,
  notificationUUID: string | null = null,
) {
  const newerRenewal = await findNewerRenewal(originalTransactionId, eventDate, notificationUUID);
  if (newerRenewal) {
    // Продление подписано позже истечения — подписка уже продлена, гасить нечего.
    await logRevocationSkipped(userId, originalTransactionId, 'expiry', newerRenewal, eventDate);
    return;
  }

  await prisma.subscription.updateMany({
    where: { userID: userId, originalTransactionId },
    data: { isActive: false },
  });

  // Check if user has any other active subscriptions before revoking premium.
  const activeCount = await prisma.subscription.count({
    where: { userID: userId, isActive: true },
  });

  if (activeCount === 0) {
    await prisma.user.update({
      where: { id: userId },
      data: { isPremium: false, premiumUntil: null },
    });
  }
}

async function handleRefund(
  userId: string,
  originalTransactionId: string,
  txInfo: any,
  eventDate: Date | null = null,
  notificationUUID: string | null = null,
) {
  // Ревью 26.07.2026: (1) дату отзыва берём у Apple — она однородна с signedDate
  // продлений, с которым сравнивается в handleRenewal (серверное время — только
  // запасной вариант); (2) возврат касается ОДНОЙ транзакции, поэтому помечаем
  // отозванной только её запись, иначе переверификация текущего (оплаченного)
  // периода получала 400 и премиум было нечем восстановить.
  const revokedAt = txInfo?.revocationDate ? new Date(Number(txInfo.revocationDate)) : new Date();
  const transactionId = txInfo?.transactionId ?? null;

  const newerRenewal = await findNewerRenewal(originalTransactionId, eventDate, notificationUUID);
  if (newerRenewal) {
    // Возврат за СТАРЫЙ период пришёл после того, как новый уже оплачен и
    // включён. Возвращённую транзакцию помечаем (она не должна пройти verify),
    // но право на подписку не гасим — иначе сервер аннулирует оплаченный период.
    // Массовую пометку по originalTransactionId здесь НЕ делаем: она задела бы
    // и новую (оплаченную) транзакцию, после чего её verify получал бы 400.
    if (transactionId) {
      await prisma.transactionRecord.updateMany({
        where: { transactionId: String(transactionId) },
        data: { revocationDate: revokedAt },
      });
    }
    await logRevocationSkipped(userId, originalTransactionId, 'refund', newerRenewal, eventDate);
    return;
  }

  await revokeEntitlement(userId, originalTransactionId, revokedAt, transactionId);
}

async function handleRevoke(
  userId: string,
  originalTransactionId: string,
  txInfo: any,
  eventDate: Date | null = null,
  notificationUUID: string | null = null,
) {
  const revokedAt = txInfo.revocationDate ? new Date(parseInt(txInfo.revocationDate)) : new Date();

  const newerRenewal = await findNewerRenewal(originalTransactionId, eventDate, notificationUUID);
  if (newerRenewal) {
    // Более свежее продление уже применено — отзыв устарел (симметрично
    // skipReactivation в handleRenewal). Право оставляем: оплаченный период не
    // наш, чтобы его отбирать. Транзакции тоже не помечаем — пометка по
    // originalTransactionId задела бы новую (оплаченную) транзакцию, и её
    // verify получал бы 400 «Transaction revoked».
    await logRevocationSkipped(userId, originalTransactionId, 'revoke', newerRenewal, eventDate);
    return;
  }

  // REVOKE — отзыв права на всю подписку (например семейный доступ), поэтому
  // помечаются все транзакции этого originalTransactionId.
  await revokeEntitlement(userId, originalTransactionId, revokedAt);
}

async function revokeEntitlement(
  userId: string,
  originalTransactionId: string,
  revokedAt: Date,
  transactionId: string | null = null,
) {
  await prisma.subscription.updateMany({
    where: { userID: userId, originalTransactionId },
    data: { isActive: false, revokedAt },
  });

  await prisma.transactionRecord.updateMany({
    where: transactionId ? { transactionId } : { originalTransactionId },
    data: { revocationDate: revokedAt },
  });

  // Check if user has any other active subscriptions.
  const activeCount = await prisma.subscription.count({
    where: { userID: userId, isActive: true },
  });

  if (activeCount === 0) {
    await prisma.user.update({
      where: { id: userId },
      data: { isPremium: false, premiumUntil: null },
    });
  }
}
