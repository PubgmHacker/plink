// push.ts — Plink M39
//
// APNs по HTTP/2 с token-based авторизацией (p8-ключ), без сторонних SDK.
// Главный сценарий возврата в продукт: «друг начал смотреть» — это time-sensitive
// уведомление: оно пробивается сквозь режим фокусировки и теряет смысл через час.

import type { FastifyInstance, FastifyRequest } from 'fastify'
import { PrismaClient } from '@prisma/client'
import http2 from 'node:http2'
import crypto from 'node:crypto'

const prisma = new PrismaClient()

const TEAM_ID = process.env.APPLE_TEAM_ID ?? ''
const KEY_ID = process.env.APNS_KEY_ID ?? ''
const PRIVATE_KEY = (process.env.APNS_PRIVATE_KEY ?? '').replace(/\\n/g, '\n')
const BUNDLE_ID = process.env.APPLE_BUNDLE_ID ?? 'com.plink.app'
const APNS_HOST = process.env.APNS_ENV === 'production'
  ? 'https://api.push.apple.com'
  : 'https://api.sandbox.push.apple.com'

const TOKEN_RE = /^[a-fA-F0-9]{64,200}$/

let cachedToken: { value: string; createdAt: number } | null = null

/// APNs требует перевыпуск токена не чаще раза в 20 минут и не реже раза в час.
/// 1500 секунд — безопасная середина.
function apnsToken(): string {
  if (cachedToken && Date.now() - cachedToken.createdAt < 1500 * 1000) return cachedToken.value

  const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: KEY_ID })).toString('base64url')
  const claims = Buffer.from(JSON.stringify({ iss: TEAM_ID, iat: Math.floor(Date.now() / 1000) })).toString('base64url')
  const signature = crypto.sign('sha256', Buffer.from(`${header}.${claims}`), {
    key: PRIVATE_KEY,
    dsaEncoding: 'ieee-p1363',
  }).toString('base64url')

  const value = `${header}.${claims}.${signature}`
  cachedToken = { value, createdAt: Date.now() }
  return value
}

export type PushPayload = {
  title: string
  body: string
  type?: 'ROOM_STARTED' | 'FRIEND_REQUEST' | 'MESSAGE'
  deeplink?: string
  badge?: number
}

export async function sendPush(deviceToken: string, payload: PushPayload): Promise<boolean> {
  if (!TEAM_ID || !KEY_ID || !PRIVATE_KEY) return false

  return new Promise((resolve) => {
    const client = http2.connect(APNS_HOST)
    const timer = setTimeout(() => {
      client.close()
      resolve(false)
    }, 10_000)

    const isUrgent = payload.type === 'ROOM_STARTED'

    const request = client.request({
      ':method': 'POST',
      ':path': `/3/device/${deviceToken}`,
      authorization: `bearer ${apnsToken()}`,
      'apns-topic': BUNDLE_ID,
      'apns-push-type': 'alert',
      'apns-priority': isUrgent ? '10' : '5',
      'apns-expiration': isUrgent ? String(Math.floor(Date.now() / 1000) + 900) : '0',
    })

    request.setEncoding('utf8')
    request.write(JSON.stringify({
      aps: {
        alert: { title: payload.title, body: payload.body },
        sound: 'default',
        badge: payload.badge,
        'interruption-level': isUrgent ? 'time-sensitive' : 'active',
      },
      deeplink: payload.deeplink,
      type: payload.type,
    }))

    let status = 0
    request.on('response', (headers) => { status = Number(headers[':status'] ?? 0) })
    request.on('end', () => {
      clearTimeout(timer)
      client.close()
      resolve(status >= 200 && status < 300)
    })
    request.on('error', () => {
      clearTimeout(timer)
      client.close()
      resolve(false)
    })
    request.end()
  })
}

function userId(request: FastifyRequest): string {
  return (request as any).user?.id
}

export async function pushRoutes(fastify: FastifyInstance) {
  fastify.post<{ Body: { token: string; platform?: string; appVersion?: string } }>(
    '/push/register',
    async (request, reply) => {
      const uid = userId(request)
      if (!uid) return reply.code(401).send({ error: 'unauthorized' })

      const token = request.body?.token
      if (typeof token !== 'string' || !TOKEN_RE.test(token)) {
        return reply.code(400).send({ error: 'invalid_token' })
      }

      await prisma.pushDevice.upsert({
        where: { token },
        create: { token, userId: uid, platform: request.body?.platform ?? 'ios', appVersion: request.body?.appVersion ?? null },
        update: { userId: uid, appVersion: request.body?.appVersion ?? null, updatedAt: new Date() },
      })

      return reply.send({ ok: true })
    },
  )

  fastify.delete<{ Params: { token: string } }>('/push/register/:token', async (request, reply) => {
    const uid = userId(request)
    if (!uid) return reply.code(401).send({ error: 'unauthorized' })
    await prisma.pushDevice.deleteMany({ where: { token: request.params.token, userId: uid } })
    return reply.send({ ok: true })
  })

  fastify.patch<{ Body: { roomStarted?: boolean; friendRequests?: boolean; messages?: boolean } }>(
    '/push/preferences',
    async (request, reply) => {
      const uid = userId(request)
      if (!uid) return reply.code(401).send({ error: 'unauthorized' })

      const data = {
        roomStarted: request.body?.roomStarted ?? true,
        friendRequests: request.body?.friendRequests ?? true,
        messages: request.body?.messages ?? true,
      }

      await prisma.pushPreferences.upsert({
        where: { userId: uid },
        create: { userId: uid, ...data },
        update: data,
      })

      return reply.send({ ok: true, ...data })
    },
  )

  fastify.post('/push/test', async (request, reply) => {
    const uid = userId(request)
    if (!uid) return reply.code(401).send({ error: 'unauthorized' })

    const devices = await prisma.pushDevice.findMany({ where: { userId: uid }, select: { token: true } })
    if (devices.length === 0) return reply.code(404).send({ error: 'no_devices' })

    const results = await Promise.all(devices.map((device) =>
      sendPush(device.token, {
        title: 'Plink',
        body: 'Уведомления работают.',
        type: 'MESSAGE',
      })))

    return reply.send({ sent: results.filter(Boolean).length, total: results.length })
  })
}
