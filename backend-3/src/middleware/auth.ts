// src/middleware/auth.ts — обновлённый с access token (коротким)
//
// ⚠️ АУДИТ 26.07.2026 (P0): раньше здесь БЕЗОГОВОРОЧНО доверяли claim'ам JWT.
//
// Что это означало на практике:
//   • бан пользователя не действовал до истечения токена — забаненный
//     спокойно продолжал писать в чат и создавать комнаты;
//   • разжалование администратора не отбирало права;
//   • удалённый аккаунт продолжал работать по старому токену;
//   • роль бралась из токена, а не из БД, поэтому когда-то выданное
//     повышение прав переживало свой отзыв.
//
// В связке со сломанным сроком жизни токена (см. utils/tokens.ts, где exp
// фактически не выставлялся) окно «до истечения» было бесконечным — то есть
// бан не срабатывал вообще никогда. Websocket-шлюз при этом всё делал
// правильно и сверялся с БД; расходился именно HTTP-слой.
//
// Теперь на каждый запрос сверяемся с БД, но с коротким кэшем (30 с), чтобы
// не превращать каждый вызов API в лишний запрос к Postgres. Бан вступает
// в силу максимум через 30 секунд, а при явном сбросе кэша — мгновенно.

import { FastifyRequest, FastifyReply } from 'fastify';
import { prisma } from '../config/db.js';

interface UserSnapshot {
  role: string;
  bannedUntil: Date | null;
  deletedAt: Date | null;
  username: string;
  email: string;
  checkedAt: number;
}

const SNAPSHOT_TTL_MS = 30_000;
/// Ограничиваем размер кэша, чтобы он не рос бесконечно на большом трафике.
const MAX_SNAPSHOTS = 10_000;

const snapshots = new Map<string, UserSnapshot>();

function cached(userId: string): UserSnapshot | null {
  const hit = snapshots.get(userId);
  if (!hit) return null;
  if (Date.now() - hit.checkedAt > SNAPSHOT_TTL_MS) {
    snapshots.delete(userId);
    return null;
  }
  return hit;
}

async function loadSnapshot(userId: string): Promise<UserSnapshot | null> {
  const fresh = cached(userId);
  if (fresh) return fresh;

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { role: true, bannedUntil: true, deletedAt: true, username: true, email: true },
  });
  if (!user) return null;

  if (snapshots.size >= MAX_SNAPSHOTS) snapshots.clear();

  const snapshot: UserSnapshot = {
    role: user.role as unknown as string,
    bannedUntil: user.bannedUntil,
    deletedAt: user.deletedAt,
    username: user.username,
    email: user.email,
    checkedAt: Date.now(),
  };
  snapshots.set(userId, snapshot);
  return snapshot;
}

/// Сбросить кэш для пользователя — вызывать после бана, смены роли и удаления,
/// чтобы решение вступало в силу мгновенно, а не через TTL.
export function invalidateUserSnapshot(userId: string): void {
  snapshots.delete(userId);
}

export async function authenticate(request: FastifyRequest, reply: FastifyReply) {
  let payload: any;
  try {
    const authHeader = request.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
      return reply.status(401).send({ error: 'No token' });
    }
    const token = authHeader.substring(7);

    // Access tokens теперь действительно короткие: exp выставляется явно
    // в utils/tokens.ts (раньше claim не проставлялся вовсе).
    payload = request.server.jwt.verify(token) as any;
  } catch (err: any) {
    if (err.message === 'Unauthorized' || err.code?.includes('JWT') || err.name === 'TokenExpiredError') {
      return reply.status(401).send({
        error: 'Сессия истекла. Войдите заново.',
        code: 'TOKEN_EXPIRED',
      });
    }
    return reply.status(500).send({ error: 'Auth error' });
  }

  if (!payload?.id) {
    return reply.status(401).send({ error: 'No token' });
  }

  // ── Сверка с текущим состоянием в БД ─────────────────────────────────
  let snapshot: UserSnapshot | null;
  try {
    snapshot = await loadSnapshot(payload.id);
  } catch (err) {
    // БД недоступна: не пускаем по одному лишь токену, но и не отдаём 401,
    // иначе клиент разлогинит пользователя из-за проблем инфраструктуры.
    request.log.error({ err }, '[auth] не удалось проверить пользователя в БД');
    return reply.status(503).send({ error: 'Сервис временно недоступен', code: 'AUTH_BACKEND_DOWN' });
  }

  if (!snapshot || snapshot.deletedAt) {
    return reply.status(401).send({ error: 'Аккаунт недоступен', code: 'ACCOUNT_GONE' });
  }

  if (snapshot.bannedUntil && snapshot.bannedUntil.getTime() > Date.now()) {
    return reply.status(403).send({
      error: 'Аккаунт заблокирован',
      code: 'ACCOUNT_BANNED',
      until: snapshot.bannedUntil.toISOString(),
    });
  }

  request.user = {
    id: payload.id,
    username: snapshot.username,
    email: snapshot.email,
    // Роль — ТОЛЬКО из БД. Значение из токена намеренно игнорируется:
    // иначе отозванные права продолжали бы действовать.
    role: snapshot.role,
    // Аудит 26.07.2026 P1: mfa/auth_time — из ПОДПИСАННОГО токена (в БД их
    // нет и быть не должно: это свойства сессии). Раньше claims терялись,
    // и step-up 2FA в админке (requireAdmin) не проходил никогда.
    mfa: payload.mfa === true,
    auth_time: typeof payload.auth_time === 'number' ? payload.auth_time : undefined,
  };
}

// Optional auth — не падает если нет токена
export async function optionalAuth(request: FastifyRequest, reply: FastifyReply) {
  try {
    const authHeader = request.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) return;
    const token = authHeader.substring(7);
    const payload = request.server.jwt.verify(token) as any;
    if (!payload?.id) return;

    // Здесь тоже сверяемся с БД, но молча: авторизация необязательная,
    // и забаненный либо удалённый пользователь просто считается гостем.
    const snapshot = await loadSnapshot(payload.id);
    if (!snapshot || snapshot.deletedAt) return;
    if (snapshot.bannedUntil && snapshot.bannedUntil.getTime() > Date.now()) return;

    request.user = {
      id: payload.id,
      username: snapshot.username,
      email: snapshot.email,
      role: snapshot.role,
      // Аудит 26.07.2026 P1: те же session-claims, что и в authenticate.
      mfa: payload.mfa === true,
      auth_time: typeof payload.auth_time === 'number' ? payload.auth_time : undefined,
    };
  } catch {
    // ignore — optional
  }
}
