// src/middleware/auth.ts — обновлённый с access token (коротким)
import { FastifyRequest, FastifyReply } from 'fastify';

export async function authenticate(request: FastifyRequest, reply: FastifyReply) {
  try {
    const authHeader = request.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
      return reply.status(401).send({ error: 'No token' });
    }
    const token = authHeader.substring(7);
    
    // Access tokens теперь короткие (15 min)
    const payload = request.server.jwt.verify(token) as any;
    
    request.user = {
      id: payload.id,
      username: payload.username,
      email: payload.email,
      role: payload.role,
    };
  } catch (err: any) {
    if (err.message === 'Unauthorized' || err.code?.includes('JWT') || err.name === 'TokenExpiredError') {
      return reply.status(401).send({ 
        error: 'Сессия истекла. Войдите заново.',
        code: 'TOKEN_EXPIRED',
      });
    }
    return reply.status(500).send({ error: 'Auth error' });
  }
}

// Optional auth — не падает если нет токена
export async function optionalAuth(request: FastifyRequest, reply: FastifyReply) {
  try {
    const authHeader = request.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) return;
    const token = authHeader.substring(7);
    const payload = request.server.jwt.verify(token) as any;
    request.user = {
      id: payload.id,
      username: payload.username,
      email: payload.email,
      role: payload.role,
    };
  } catch {
    // ignore — optional
  }
}
