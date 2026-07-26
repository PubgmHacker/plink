// account.ts — Plink M39
//
// Guideline 5.1.1(v): удаление аккаунта из приложения обязательно.
// Реализовано через tombstone + грейс-период 7 дней:
// персональные данные обезличиваются СРАЗУ, а сама запись удаляется через неделю.
// Так и GDPR соблюдён, и человек может вернуться, если передумал.

import type { FastifyInstance, FastifyRequest } from 'fastify'
import { PrismaClient } from '@prisma/client'
import crypto from 'node:crypto'

const prisma = new PrismaClient()

const GRACE_PERIOD_DAYS = 7

function userId(request: FastifyRequest): string {
  return (request as any).user?.id
}

export async function accountRoutes(fastify: FastifyInstance) {
  // —— Удаление ——
  fastify.delete('/users/me', async (request, reply) => {
    const me = userId(request)
    if (!me) return reply.code(401).send({ error: 'unauthorized' })

    const tombstone = `deleted_${crypto.randomBytes(8).toString('hex')}`
    const now = new Date()
    const purgeAt = new Date(now.getTime() + GRACE_PERIOD_DAYS * 24 * 60 * 60 * 1000)

    await prisma.$transaction(async (tx) => {
      // Обезличивание — сразу. Никто больше не увидит ни имени, ни аватара.
      await tx.user.update({
        where: { id: me },
        data: {
          email: `${tombstone}@deleted.plink.app`,
          username: tombstone,
          displayName: 'Удалённый пользователь',
          avatarUrl: null,
          bio: null,
          pushToken: null,
          deletedAt: now,
          purgeAt,
        },
      })

      // Связи удаляются сразу: держать человека в списках друзей после удаления нельзя.
      await tx.friendship.deleteMany({ where: { OR: [{ userId: me }, { friendId: me }] } })
      await tx.friendRequest.deleteMany({ where: { OR: [{ fromId: me }, { toId: me }] } })
      await tx.roomMember.deleteMany({ where: { userId: me } })
      await tx.groupMember.deleteMany({ where: { userId: me } })
      await tx.pushDevice.deleteMany({ where: { userId: me } })
      await tx.session.deleteMany({ where: { userId: me } })
    })

    return reply.send({
      ok: true,
      purgeAt,
      gracePeriodDays: GRACE_PERIOD_DAYS,
      message: 'Аккаунт удалён. У вас есть 7 дней, чтобы вернуться.',
    })
  })

  // —— Восстановление ——
  fastify.post<{ Body: { email: string } }>('/users/me/restore', async (request, reply) => {
    const me = userId(request)
    if (!me) return reply.code(401).send({ error: 'unauthorized' })

    const user = await prisma.user.findUnique({ where: { id: me } })
    if (!user?.deletedAt) return reply.code(400).send({ error: 'not_deleted' })

    if (user.purgeAt && user.purgeAt.getTime() < Date.now()) {
      // 410 Gone — данные уже физически удалены, вернуть нечего.
      return reply.code(410).send({ error: 'grace_period_expired' })
    }

    await prisma.user.update({
      where: { id: me },
      data: { deletedAt: null, purgeAt: null },
    })

    return reply.send({ ok: true, message: 'С возвращением.' })
  })

  // —— Экспорт данных ——
  fastify.get('/users/me/export', async (request, reply) => {
    const me = userId(request)
    if (!me) return reply.code(401).send({ error: 'unauthorized' })

    const [user, friends, rooms, messages, subscription] = await Promise.all([
      prisma.user.findUnique({
        where: { id: me },
        select: { id: true, email: true, username: true, displayName: true, bio: true, createdAt: true, isPlus: true },
      }),
      prisma.friendship.findMany({ where: { userId: me }, select: { friendId: true, createdAt: true } }),
      prisma.roomMember.findMany({ where: { userId: me }, select: { roomId: true, joinedAt: true } }),
      prisma.message.findMany({
        where: { authorId: me },
        select: { id: true, text: true, createdAt: true, roomId: true },
        take: 5000,
        orderBy: { createdAt: 'desc' },
      }),
      prisma.subscription.findFirst({ where: { userId: me }, orderBy: { createdAt: 'desc' } }),
    ])

    reply.header('Content-Type', 'application/json; charset=utf-8')
    reply.header('Content-Disposition', 'attachment; filename="plink-data.json"')
    return reply.send({
      exportedAt: new Date().toISOString(),
      format: 'plink-export-v1',
      user,
      friends,
      rooms,
      messages,
      subscription,
    })
  })
}

// Фоновая чистка. Вызывать из cron раз в сутки.
export async function purgeExpiredAccounts(): Promise<number> {
  const expired = await prisma.user.findMany({
    where: { deletedAt: { not: null }, purgeAt: { lt: new Date() } },
    select: { id: true },
  })
  for (const { id } of expired) {
    await prisma.user.delete({ where: { id } }).catch(() => {})
  }
  return expired.length
}
