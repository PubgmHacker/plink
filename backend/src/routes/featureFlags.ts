// src/routes/featureFlags.ts — Pack 5: Feature flag endpoints + admin controls
import { getFeatureFlags, isFeatureEnabled, updateFeatureFlag, getUserFlags } from '../services/featureFlags.js';
import { prisma } from '../config/db.js';

export default async function featureFlagRoutes(fastify) {
  
  // GET /api/feature-flags — флаги для текущего юзера
  fastify.get('/feature-flags', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    const user = await prisma.user.findUnique({
      where: { id: request.user.id },
      select: { isPremium: true }
    });
    
    const flags = await getUserFlags(request.user.id, user?.isPremium || false);
    reply.send({ flags });
  });
  
  // GET /api/admin/feature-flags — все флаги (admin only)
  fastify.get('/admin/feature-flags', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    if (request.user.role !== 'ADMIN' && request.user.role !== 'FOUNDER') {
      return reply.status(403).send({ error: 'Admin only' });
    }
    
    const flags = await getFeatureFlags();
    reply.send({ flags });
  });
  
  // PATCH /api/admin/feature-flags/:key — обновить флаг (admin only)
  fastify.patch('/admin/feature-flags/:key', {
    preHandler: [fastify.authenticate]
  }, async (request, reply) => {
    if (request.user.role !== 'ADMIN' && request.user.role !== 'FOUNDER') {
      return reply.status(403).send({ error: 'Admin only' });
    }
    
    const { key } = request.params;
    const updates = request.body;
    
    try {
      await updateFeatureFlag(key, updates);
      reply.send({ success: true, key, updates });
    } catch (e: any) {
      reply.status(400).send({ error: e.message });
    }
  });
}
