// timeSync.ts — Plink M39
//
// Фикс ℗ 7: раньше эндпоинт отдавал только serverTime, и клиент не мог
// отделить смещение часов от сетевой задержки. Теперь возвращаются точки t1 и t2
// (момент приёма и момент ответа), как в NTP — без них RTT посчитать нельзя.

import type { FastifyInstance, FastifyRequest } from 'fastify'

export async function timeSyncRoutes(fastify: FastifyInstance) {
  fastify.get('/realtime/time', {
    config: {
      rateLimit: {
        max: 120,
        timeWindow: '1 minute',
        keyGenerator: (req: FastifyRequest) => (req as any).user?.id ?? req.ip,
      },
    },
  }, async (request, reply) => {
    const t1 = Date.now()
    // Полезной работы здесь нет, но t2 обязателен по протоколу: он учитывает
    // время, проведённое запросом внутри сервера.
    const t2 = Date.now()

    reply.header('Cache-Control', 'no-store')
    return {
      serverTime: new Date(t2).toISOString(),
      t0: null,
      t1,
      t2,
    }
  })
}
