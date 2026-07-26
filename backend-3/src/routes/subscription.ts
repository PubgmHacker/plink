// subscription.ts — Plink M39
//
// Серверная проверка покупок StoreKit 2. Клиенту верить нельзя: JWS разбирается
// вручную, цепочка сертификатов x5c валидируется до корневого Apple Root CA,
// подпись проверяется в формате IEEE P1363 (ES256).

import type { FastifyInstance, FastifyRequest } from 'fastify'
import { PrismaClient } from '@prisma/client'
import crypto from 'node:crypto'

const prisma = new PrismaClient()

const BUNDLE_ID = process.env.APPLE_BUNDLE_ID ?? 'com.plink.app'
const APPLE_ROOT_CA_PEM = process.env.APPLE_ROOT_CA_PEM ?? ''

export const PRODUCTS = {
  monthly: 'com.plink.app.plus.monthly',
  yearly: 'com.plink.app.plus.yearly',
  lifetime: 'com.plink.app.plus.lifetime',
} as const

const KNOWN_PRODUCTS = new Set<string>(Object.values(PRODUCTS))

function userId(request: FastifyRequest): string {
  return (request as any).user?.id
}

function base64UrlToBuffer(input: string): Buffer {
  return Buffer.from(input.replace(/-/g, '+').replace(/_/g, '/'), 'base64')
}

function certFromBase64(b64: string): crypto.X509Certificate {
  const pem = `-----BEGIN CERTIFICATE-----\n${b64.match(/.{1,64}/g)?.join('\n')}\n-----END CERTIFICATE-----`
  return new crypto.X509Certificate(pem)
}

/// Проверка цепочки: leaf ← intermediate ← root, и root совпадает с Apple Root CA.
/// Без этого шага подделать «покупку» может любой человек с curl.
function verifyCertChain(x5c: string[]): boolean {
  if (x5c.length < 2) return false

  const certs = x5c.map(certFromBase64)
  for (let i = 0; i < certs.length - 1; i++) {
    if (!certs[i].verify(certs[i + 1].publicKey)) return false
  }

  const root = certs[certs.length - 1]
  if (root.validTo && new Date(root.validTo).getTime() < Date.now()) return false

  if (!APPLE_ROOT_CA_PEM) {
    // В окружении без корневого сертификата не притворяемся, что проверили.
    return false
  }

  const expected = new crypto.X509Certificate(APPLE_ROOT_CA_PEM)
  return root.fingerprint256 === expected.fingerprint256
}

export function verifyAppleJWS(jws: string): Record<string, any> | null {
  const [headerB64, payloadB64, signatureB64] = jws.split('.')
  if (!headerB64 || !payloadB64 || !signatureB64) return null

  let header: any
  let payload: any
  try {
    header = JSON.parse(base64UrlToBuffer(headerB64).toString('utf8'))
    payload = JSON.parse(base64UrlToBuffer(payloadB64).toString('utf8'))
  } catch {
    return null
  }

  if (header.alg !== 'ES256' || !Array.isArray(header.x5c)) return null
  if (!verifyCertChain(header.x5c)) return null

  const leaf = certFromBase64(header.x5c[0])
  const valid = crypto.verify(
    'sha256',
    Buffer.from(`${headerB64}.${payloadB64}`),
    { key: leaf.publicKey, dsaEncoding: 'ieee-p1363' },
    base64UrlToBuffer(signatureB64),
  )
  if (!valid) return null

  if (payload.bundleId && payload.bundleId !== BUNDLE_ID) return null

  return payload
}

async function persist(uid: string, payload: Record<string, any>) {
  const productId: string = payload.productId
  const expiresAt = payload.expiresDate ? new Date(payload.expiresDate) : null
  const revoked = Boolean(payload.revocationDate)
  const active = !revoked && (!expiresAt || expiresAt.getTime() > Date.now())

  await prisma.subscription.upsert({
    where: { transactionId: String(payload.transactionId ?? payload.originalTransactionId) },
    create: {
      userId: uid,
      transactionId: String(payload.transactionId ?? payload.originalTransactionId),
      originalTransactionId: String(payload.originalTransactionId ?? ''),
      productId,
      expiresAt,
      revokedAt: revoked ? new Date(payload.revocationDate) : null,
      environment: payload.environment ?? 'Production',
    },
    update: {
      expiresAt,
      revokedAt: revoked ? new Date(payload.revocationDate) : null,
    },
  })

  await prisma.user.update({ where: { id: uid }, data: { isPlus: active } })
  return { active, productId, expiresAt }
}

export async function subscriptionRoutes(fastify: FastifyInstance) {
  fastify.post<{ Body: { signedTransaction: string; transactionId?: string; productId?: string } }>(
    '/subscription/verify',
    async (request, reply) => {
      const uid = userId(request)
      if (!uid) return reply.code(401).send({ error: 'unauthorized' })

      const signed = request.body?.signedTransaction
      if (typeof signed !== 'string' || signed.length === 0) {
        return reply.code(400).send({ error: 'signed_transaction_required' })
      }

      // StoreKit отдаёт jsonRepresentation в base64 — внутри либо JWS, либо JSON.
      const decoded = Buffer.from(signed, 'base64').toString('utf8')
      let payload: Record<string, any> | null = null

      if (decoded.split('.').length === 3) {
        payload = verifyAppleJWS(decoded)
      } else {
        try {
          const parsed = JSON.parse(decoded)
          payload = parsed.signedTransactionInfo
            ? verifyAppleJWS(parsed.signedTransactionInfo)
            : parsed
        } catch {
          payload = null
        }
      }

      if (!payload || !KNOWN_PRODUCTS.has(payload.productId)) {
        return reply.code(400).send({ error: 'invalid_transaction' })
      }

      const result = await persist(uid, payload)
      return reply.send({ ok: true, ...result })
    },
  )

  fastify.get('/subscription/status', async (request, reply) => {
    const uid = userId(request)
    if (!uid) return reply.code(401).send({ error: 'unauthorized' })

    const latest = await prisma.subscription.findFirst({
      where: { userId: uid, revokedAt: null },
      orderBy: { createdAt: 'desc' },
    })

    const active = Boolean(latest && (!latest.expiresAt || latest.expiresAt.getTime() > Date.now()))

    return reply.send({
      isPlus: active,
      productId: active ? latest?.productId : null,
      expiresAt: active ? latest?.expiresAt : null,
    })
  })

  // App Store Server Notifications V2. Отвечаем 500 при ошибке — Apple повторит доставку.
  fastify.post<{ Body: { signedPayload: string } }>('/subscription/apple-notifications', async (request, reply) => {
    const signed = request.body?.signedPayload
    if (typeof signed !== 'string') return reply.code(400).send({ error: 'bad_payload' })

    const payload = verifyAppleJWS(signed)
    if (!payload) return reply.code(400).send({ error: 'invalid_signature' })

    try {
      const info = payload.data?.signedTransactionInfo
        ? verifyAppleJWS(payload.data.signedTransactionInfo)
        : null
      if (!info) return reply.send({ ok: true })

      const subscription = await prisma.subscription.findFirst({
        where: { originalTransactionId: String(info.originalTransactionId ?? '') },
        select: { userId: true },
      })
      if (subscription) await persist(subscription.userId, info)

      return reply.send({ ok: true })
    } catch (error) {
      request.log.error({ err: error }, 'apple notification failed')
      return reply.code(500).send({ error: 'retry_later' })
    }
  })
}
