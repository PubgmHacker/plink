import { prisma } from '../config/db.js';
import { config } from '../config/index.js';

export default async function devRoutes(fastify) {
  // DEV ONLY — emergency database wipe for multi-device test resets.
  // P0 audit: never crash on missing body; hard-deny in production unless
  // ENABLE_DEV_WIPE=true AND correct secret (secret always required).
  fastify.post('/dev/wipe-db', async (request, reply) => {
    if (config.isProduction && !config.ENABLE_DEV_WIPE) {
      return reply.code(403).send({ error: 'Forbidden in production' });
    }

    const body = (request.body ?? {}) as { secret?: string };
    const secret = typeof body.secret === 'string' ? body.secret : '';
    if (!config.DEV_WIPE_SECRET || secret !== config.DEV_WIPE_SECRET) {
      return reply.code(401).send({ error: 'Invalid secret' });
    }

    await prisma.chatMessage.deleteMany();
    await prisma.roomParticipant.deleteMany();
    await prisma.room.deleteMany();
    await prisma.user.updateMany({ data: { avatarData: null, avatarURL: null } });

    return { ok: true, wiped: true };
  });
}