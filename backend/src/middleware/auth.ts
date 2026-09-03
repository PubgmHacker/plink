// HTTP authentication: verify the bearer token, then verify the user against the
// database on every request.
//
// The second half is the point. This middleware used to trust the JWT claims
// unconditionally, which meant every authorization decision was frozen at the moment
// the token was issued:
//
//   - A ban did not take effect until the token expired. A banned user kept posting
//     in chat and creating rooms.
//   - Demoting an administrator did not remove their privileges.
//   - A deleted account kept working on its old token.
//   - `role` came from the token rather than from the database, so a privilege grant
//     outlived its own revocation.
//
// Combined with a separate defect in token lifetime — `utils/tokens.ts` was not
// setting `exp` at all — the "until it expires" window was unbounded, so a ban never
// took effect at any point. The websocket gateway was doing this correctly and
// checking the database; only the HTTP layer had drifted.
//
// Every request now reconciles against the database, behind a 30-second cache so that
// an API call does not become an extra Postgres round trip. A ban therefore lands
// within 30 seconds, or immediately when the cache is invalidated explicitly
// (`invalidateUserSnapshot`, called from the ban, role-change and delete paths).

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
/// Bound the cache so it cannot grow without limit under heavy traffic.
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

/// Drop one user's cached snapshot. Call this after a ban, a role change or a
/// delete, so the decision takes effect immediately instead of after the TTL.
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

    // Access tokens really are short-lived now: `exp` is set explicitly in
    // utils/tokens.ts. It used to not be set at all, which made them permanent.
    payload = request.server.jwt.verify(token) as any;
  } catch (err: any) {
    if (
      err.message === 'Unauthorized' ||
      err.code?.includes('JWT') ||
      err.name === 'TokenExpiredError'
    ) {
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

  // ── Reconcile against current database state ─────────────────────────
  let snapshot: UserSnapshot | null;
  try {
    snapshot = await loadSnapshot(payload.id);
  } catch (err) {
    // Database unreachable. Do not fall back to trusting the token alone — but do
    // not answer 401 either, or the client signs the user out over an infrastructure
    // problem. 503 tells it to retry.
    request.log.error({ err }, '[auth] could not verify user against the database');
    return reply
      .status(503)
      .send({ error: 'Сервис временно недоступен', code: 'AUTH_BACKEND_DOWN' });
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
    // Role comes from the database ONLY. The value in the token is deliberately
    // ignored; honouring it is what let revoked privileges keep working.
    role: snapshot.role,
    // mfa/auth_time come from the SIGNED token, not the database — they are
    // properties of the session, not of the user, and have no business being stored.
    // These claims used to be dropped here, which meant the step-up 2FA check in the
    // admin panel (`requireAdmin`) could never pass.
    mfa: payload.mfa === true,
    auth_time: typeof payload.auth_time === 'number' ? payload.auth_time : undefined,
  };
}

// Optional auth: populates request.user when a valid token is present, and does
// nothing at all when it is absent or unusable. Never rejects the request.
export async function optionalAuth(request: FastifyRequest, reply: FastifyReply) {
  try {
    const authHeader = request.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) return;
    const token = authHeader.substring(7);
    const payload = request.server.jwt.verify(token) as any;
    if (!payload?.id) return;

    // Reconciled against the database here too, but silently: authentication is
    // optional on these routes, so a banned or deleted user is simply a guest.
    const snapshot = await loadSnapshot(payload.id);
    if (!snapshot || snapshot.deletedAt) return;
    if (snapshot.bannedUntil && snapshot.bannedUntil.getTime() > Date.now()) return;

    request.user = {
      id: payload.id,
      username: snapshot.username,
      email: snapshot.email,
      role: snapshot.role,
      // The same session claims as in authenticate() above.
      mfa: payload.mfa === true,
      auth_time: typeof payload.auth_time === 'number' ? payload.auth_time : undefined,
    };
  } catch {
    // ignore — optional
  }
}
