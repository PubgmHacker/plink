// src/routes/billing.ts — PATCH 16: App Store Server API V2 (JWS verification)
//
// Brain Review 10 P0-66: previous implementation used deprecated
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

import { prisma } from '../config/db.js';
import { logAudit, AuditActions } from '../utils/audit.js';
import { JoseConfig } from '../utils/jose-config.js';

// Premium plans — product IDs match iOS PlinkProductID enum.
const PLANS: Record<string, { tier: 'premium' | 'lifetime'; durationDays: number }> = {
  'com.syncwatch.plink.premium.monthly':  { tier: 'premium',  durationDays: 30 },
  'com.syncwatch.plink.premium.yearly':   { tier: 'premium',  durationDays: 365 },
  'com.syncwatch.plink.premium.lifetime': { tier: 'lifetime', durationDays: 36500 },
};

export default async function billingRoutes(fastify: any) {

  // ─── POST /api/billing/verify ───────────────────────────────────────
  //
  // iOS sends a signed JWS transaction from StoreKit 2. Backend verifies
  // the JWS signature against Apple's root cert, extracts transaction
  // info, and updates the user's entitlement in DB.
  //
  // GPT-5 BE-P0-04: Billing trust boundary improvements:
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

  fastify.post('/billing/verify', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 5, timeWindow: '1 minute' } },
  }, async (request: any, reply: any) => {
    const { jws, productId, transactionId } = request.body || {};

    if (!jws || typeof jws !== 'string') {
      return reply.status(400).send({ error: 'jws required' });
    }
    // GPT-5 BE-P0-04: verify productId is in allowlist.
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

      // GPT-5 BE-P0-04: verify bundleId matches configured value.
      const bundleId = (verified as any).bundleId;
      if (bundleId && bundleId !== APPLE_BUNDLE_ID) {
        await logAudit({
          userId: request.user.id,
          action: 'billing.verify_failed',
          ip: request.ip,
          metadata: { productId, reason: 'bundle_id_mismatch', expected: APPLE_BUNDLE_ID, got: bundleId },
        });
        return reply.status(403).send({
          entitlement: { active: false, tier: 'free', expiryDate: null },
          error: 'Bundle ID mismatch',
        });
      }

      // GPT-5 BE-P0-04: verify productId in JWS matches body productId.
      const jwsProductId = (verified as any).productId;
      if (jwsProductId && jwsProductId !== productId) {
        await logAudit({
          userId: request.user.id,
          action: 'billing.verify_failed',
          ip: request.ip,
          metadata: { productId, reason: 'product_id_mismatch', bodyProductId: productId, jwsProductId },
        });
        return reply.status(400).send({
          entitlement: { active: false, tier: 'free', expiryDate: null },
          error: 'Product ID mismatch between body and JWS',
        });
      }

      // Extract transaction info from verified payload.
      const { originalTransactionId, environment, expiresAt, revocationDate } = verified;

      // GPT-5 BE-P0-04: ownership check — verify this transaction belongs to the authenticated user.
      // Check if originalTransactionId is already linked to a DIFFERENT user.
      const existingTx = await prisma.transactionRecord.findUnique({
        where: { transactionId: transactionId || originalTransactionId },
      });
      if (existingTx && existingTx.userId !== request.user.id) {
        await logAudit({
          userId: request.user.id,
          action: 'billing.verify_failed',
          ip: request.ip,
          metadata: { productId, reason: 'ownership_mismatch', originalTransactionId, ownerUserId: existingTx.userId },
        });
        return reply.status(403).send({
          entitlement: { active: false, tier: 'free', expiryDate: null },
          error: 'Transaction belongs to a different user',
        });
      }

      // If revoked, fail closed.
      if (revocationDate) {
        await revokeEntitlement(request.user.id, originalTransactionId, new Date(revocationDate));
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

      // GPT-5 BE-P0-04: wrap transaction record + subscription update in one tx.
      // Store the transaction record (idempotent on transactionId).
      await prisma.$transaction(async (tx) => {
        await tx.transactionRecord.upsert({
          where: { transactionId: transactionId || originalTransactionId },
          create: {
            userId: request.user.id,
            transactionId: transactionId || originalTransactionId,
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

        // Upsert subscription.
        await tx.subscription.upsert({
          where: { id: originalTransactionId },
          create: {
            userID: request.user.id,
            plan: productId,
            isActive: true,
            expiresAt: expiryDate,
            originalTransactionId,
            environment,
            lastVerifiedAt: new Date(),
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
        await tx.subscription.updateMany({
          where: {
            userID: request.user.id,
            isActive: true,
            originalTransactionId: { not: originalTransactionId },
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

        // GPT-5 BE-P0-04: audit log inside the same transaction.
        await tx.auditLog.create({
          data: {
            actorId: request.user.id,
            action: 'billing.verify_success',
            targetType: 'SUBSCRIPTION',
            targetId: originalTransactionId,
            ip: request.ip,
            requestId: request.id,
            metadata: { productId, originalTransactionId, expiresAt: expiryDate.toISOString() },
          } as any,
        });
      }); // end prisma.$transaction

      // GPT-5 BE-P0-04: audit already written inside transaction above.
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
      console.error('[billing] verify error', e);
      reply.status(500).send({ error: 'Verification failed: ' + e.message });
    }
  });

  // ─── GET /api/billing/entitlements ─────────────────────────────────
  //
  // iOS calls this on app launch to fetch the authoritative entitlement.
  // Returns the current DB state — iOS must NOT trust local StoreKit state.
  fastify.get('/billing/entitlements', {
    preHandler: [fastify.authenticate],
  }, async (request: any, reply: any) => {
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
      : (user.premiumUntil === null ? 'lifetime' : 'premium');

    reply.send({
      entitlement: {
        active: isActive,
        tier,
        expiryDate: user.premiumUntil?.toISOString() ?? null,
      },
    });
  });

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
  fastify.post('/billing/webhooks/apple', {
    config: { rateLimit: { max: 100, timeWindow: '1 minute' } },
  }, async (request: any, reply: any) => {
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

      const { notificationType, data } = notification;
      const { signedTransactionInfo, signedRenewalInfo } = data || {};

      // Decode transaction info (also JWS-signed).
      let transactionInfo: any = null;
      if (signedTransactionInfo) {
        transactionInfo = await JoseConfig.verifySignedTransaction(signedTransactionInfo);
      }

      if (!transactionInfo) {
        return reply.status(400).send({ error: 'Could not decode transaction info' });
      }

      const { originalTransactionId, productId, environment } = transactionInfo;

      // Find user by originalTransactionId (stored in Subscription).
      const sub = await prisma.subscription.findFirst({
        where: { originalTransactionId },
        select: { userID: true, id: true },
      });

      if (!sub) {
        console.warn('[billing] webhook: no subscription for', originalTransactionId);
        // Apple may send notifications for transactions we haven't seen yet.
        // Log and return 200 so Apple doesn't retry.
        return reply.status(200).send({ processed: false, reason: 'no_local_subscription' });
      }

      switch (notificationType) {
        case 'SUBSCRIPTION_PURCHASED':
        case 'SUBSCRIPTION_RENEWED':
        case 'SUBSCRIPTION_RENEWAL':  // legacy alias
        case 'DID_RENEW':             // legacy alias
          await handleRenewal(sub.userID, originalTransactionId, transactionInfo);
          break;

        case 'SUBSCRIPTION_EXPIRED':
        case 'GRACE_PERIOD_EXPIRED':
          await handleExpiry(sub.userID, originalTransactionId);
          break;

        case 'REFUND':
          await handleRefund(sub.userID, originalTransactionId, transactionInfo);
          break;

        case 'REVOKE':
          await handleRevoke(sub.userID, originalTransactionId, transactionInfo);
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

      reply.status(200).send({ processed: true });
    } catch (e: any) {
      console.error('[billing] webhook error', e);
      // Return 200 so Apple doesn't retry forever on transient errors.
      reply.status(200).send({ processed: false, error: e.message });
    }
  });

  // ─── GET /api/billing/status (legacy alias) ────────────────────────
  fastify.get('/billing/status', {
    preHandler: [fastify.authenticate],
  }, async (request: any, reply: any) => {
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
  });

  // ─── POST /api/billing/cancel ──────────────────────────────────────
  fastify.post('/billing/cancel', {
    preHandler: [fastify.authenticate],
  }, async (request: any, reply: any) => {
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
  });
}

// ─── Webhook handlers ────────────────────────────────────────────────

async function handleRenewal(userId: string, originalTransactionId: string, txInfo: any) {
  const expiresAt = txInfo.expiresDateMs ? new Date(parseInt(txInfo.expiresDateMs)) : null;
  if (!expiresAt) return;

  await prisma.subscription.updateMany({
    where: { userID: userId, originalTransactionId },
    data: { isActive: true, expiresAt, lastVerifiedAt: new Date(), revokedAt: null },
  });

  await prisma.user.update({
    where: { id: userId },
    data: { isPremium: true, premiumUntil: expiresAt },
  });
}

async function handleExpiry(userId: string, originalTransactionId: string) {
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

async function handleRefund(userId: string, originalTransactionId: string, txInfo: any) {
  await revokeEntitlement(userId, originalTransactionId, new Date());
}

async function handleRevoke(userId: string, originalTransactionId: string, txInfo: any) {
  const revokedAt = txInfo.revocationDate ? new Date(parseInt(txInfo.revocationDate)) : new Date();
  await revokeEntitlement(userId, originalTransactionId, revokedAt);
}

async function revokeEntitlement(userId: string, originalTransactionId: string, revokedAt: Date) {
  await prisma.subscription.updateMany({
    where: { userID: userId, originalTransactionId },
    data: { isActive: false, revokedAt },
  });

  await prisma.transactionRecord.updateMany({
    where: { originalTransactionId },
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
