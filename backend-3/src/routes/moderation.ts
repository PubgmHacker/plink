// moderation.ts — Plink M39
//
// Формальные механизмы модерации, которые требует App Review для любого UGC:
// жалоба → реакция за 24 часа → возможность заблокировать обидчика.
// ИИ-модерация из M16 остаётся и работает параллельно — она не заменяет эти механизмы.

import type { FastifyInstance, FastifyRequest } from 'fastify'
import { PrismaClient } from '@prisma/client'

const prisma = new PrismaClient()

const SLA_HOURS = 24
const AUTO_HIDE_THRESHOLD = 3

const REASONS = ['spam', 'harassment', 'hate', 'sexual', 'violence', 'illegal', 'copyright', 'other'] as const
const TARGET_TYPES = ['user', 'message', 'room'] as const

type Reason = (typeof REASONS)[number]
type TargetType = (typeof TARGET_TYPES)[number]

function userId(request: FastifyRequest): string {
  return (request as any).user?.id
}

/// Когда на объект поступает три независимые жалобы, мы скрываем его до разбора.
/// Лучше ошибочно скрыть на пару часов, чем оставить травлю в эфире.
async function autoHide(targetType: TargetType, targetId: string) {
  const count = await prisma.report.count({
    where: { targetType, targetId, resolvedAt: null },
  })
  if (count < AUTO_HIDE_THRESHOLD) return

  if (targetType === 'message') {
    await prisma.message.update({ where: { id: targetId }, data: { hidden: true } }).catch(() => {})
  } else if (targetType === 'room') {
    await prisma.room.update({ where: { id: targetId }, data: { hidden: true } }).catch(() => {})
  } else {
    await prisma.user.update({ where: { id: targetId }, data: { shadowbanned: true } }).catch(() => {})
  }
}

export async function moderationRoutes(fastify: FastifyInstance) {
  // —— Жалоба ——
  fastify.post<{ Body: { targetType: TargetType; targetId: string; reason: Reason; comment?: string } }>(
    '/moderation/report',
    { config: { rateLimit: { max: 20, timeWindow: '1 hour', keyGenerator: (r: FastifyRequest) => userId(r) ?? r.ip } } },
    async (request, reply) => {
      const me = userId(request)
      if (!me) return reply.code(401).send({ error: 'unauthorized' })

      const { targetType, targetId, reason, comment } = request.body ?? ({} as any)

      if (!TARGET_TYPES.includes(targetType)) return reply.code(400).send({ error: 'invalid_target_type' })
      if (!REASONS.includes(reason)) return reply.code(400).send({ error: 'invalid_reason' })
      if (typeof targetId !== 'string' || targetId.length === 0 || targetId.length > 64) {
        return reply.code(400).send({ error: 'invalid_target_id' })
      }
      if (targetType === 'user' && targetId === me) {
        return reply.code(400).send({ error: 'cannot_report_self' })
      }

      const dueAt = new Date(Date.now() + SLA_HOURS * 60 * 60 * 1000)

      const report = await prisma.report.create({
        data: {
          reporterId: me,
          targetType,
          targetId,
          reason,
          comment: typeof comment === 'string' ? comment.slice(0, 1000) : null,
          dueAt,
        },
      })

      await autoHide(targetType, targetId)

      return reply.code(201).send({ id: report.id, dueAt, slaHours: SLA_HOURS })
    },
  )

  // —— Блокировка ——
  fastify.post<{ Body: { userId: string } }>('/moderation/block', async (request, reply) => {
    const me = userId(request)
    if (!me) return reply.code(401).send({ error: 'unauthorized' })

    const target = request.body?.userId
    if (typeof target !== 'string' || target === me) {
      return reply.code(400).send({ error: 'invalid_user' })
    }

    await prisma.block.upsert({
      where: { blockerId_blockedId: { blockerId: me, blockedId: target } },
      create: { blockerId: me, blockedId: target },
      update: {},
    })

    // Блокировка разрывает дружбу в обе стороны — иначе человек остаётся в списке друзей.
    await prisma.friendship.deleteMany({
      where: {
        OR: [
          { userId: me, friendId: target },
          { userId: target, friendId: me },
        ],
      },
    }).catch(() => {})

    return reply.send({ ok: true })
  })

  fastify.delete<{ Params: { userId: string } }>('/moderation/block/:userId', async (request, reply) => {
    const me = userId(request)
    if (!me) return reply.code(401).send({ error: 'unauthorized' })

    await prisma.block.deleteMany({
      where: { blockerId: me, blockedId: request.params.userId },
    })
    return reply.send({ ok: true })
  })

  fastify.get('/moderation/blocked', async (request, reply) => {
    const me = userId(request)
    if (!me) return reply.code(401).send({ error: 'unauthorized' })

    const rows = await prisma.block.findMany({
      where: { blockerId: me },
      select: { blockedId: true },
    })
    return reply.send({ blockedUserIds: rows.map((r) => r.blockedId) })
  })

  // —— Очередь для модераторов ——
  fastify.get('/moderation/queue', async (request, reply) => {
    const me = userId(request)
    if (!me) return reply.code(401).send({ error: 'unauthorized' })

    const actor = await prisma.user.findUnique({ where: { id: me }, select: { isModerator: true } })
    if (!actor?.isModerator) return reply.code(403).send({ error: 'forbidden' })

    const reports = await prisma.report.findMany({
      where: { resolvedAt: null },
      orderBy: { dueAt: 'asc' },
      take: 100,
    })

    const now = Date.now()
    return reply.send({
      total: reports.length,
      overdue: reports.filter((r) => r.dueAt.getTime() < now).length,
      reports,
    })
  })

  fastify.post<{ Params: { id: string }; Body: { action: 'dismiss' | 'hide' | 'ban' } }>(
    '/moderation/queue/:id/resolve',
    async (request, reply) => {
      const me = userId(request)
      if (!me) return reply.code(401).send({ error: 'unauthorized' })

      const actor = await prisma.user.findUnique({ where: { id: me }, select: { isModerator: true } })
      if (!actor?.isModerator) return reply.code(403).send({ error: 'forbidden' })

      const report = await prisma.report.findUnique({ where: { id: request.params.id } })
      if (!report) return reply.code(404).send({ error: 'not_found' })

      const action = request.body?.action ?? 'dismiss'

      if (action === 'ban' && report.targetType === 'user') {
        await prisma.user.update({ where: { id: report.targetId }, data: { shadowbanned: true } }).catch(() => {})
      }
      if (action === 'dismiss') {
        // Отменяем автоскрытие, если жалобы оказались ложными.
        if (report.targetType === 'message') {
          await prisma.message.update({ where: { id: report.targetId }, data: { hidden: false } }).catch(() => {})
        } else if (report.targetType === 'room') {
          await prisma.room.update({ where: { id: report.targetId }, data: { hidden: false } }).catch(() => {})
        } else {
          await prisma.user.update({ where: { id: report.targetId }, data: { shadowbanned: false } }).catch(() => {})
        }
      }

      await prisma.report.updateMany({
        where: { targetType: report.targetType, targetId: report.targetId, resolvedAt: null },
        data: { resolvedAt: new Date(), resolvedById: me, resolution: action },
      })

      return reply.send({ ok: true })
    },
  )
}
