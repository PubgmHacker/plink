// src/utils/tokens.ts — Pack 1.1: настраиваемый TTL через env
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { prisma } from '../config/db.js';
import { config } from '../config/index.js';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  accessExpiresAt: number;
  refreshExpiresAt: number;
}

/**
 * GPT-5 BE-P0-01: issue access token with role + mfa + auth_time claims.
 * - `role`: USER | MODERATOR | ADMIN | FOUNDER (from DB)
 * - `mfa`: true if user completed 2FA verification in this session
 * - `auth_time`: Unix timestamp (seconds) of when the user authenticated
 *
 * Admin routes check `mfa === true` and `now - auth_time <= 600` (10 min)
 * before allowing any admin action.
 */
export async function issueTokenPair(
  fastify: any,
  userId: string,
  username?: string,
  options?: { mfaVerified?: boolean; role?: string }
): Promise<TokenPair> {
  const now = Math.floor(Date.now() / 1000);
  const payload: any = {
    id: userId,
    sub: userId,       // GPT-5: standard JWT subject claim
    iat: now,          // issued at (seconds)
    auth_time: now,    // GPT-5 BE-P0-01: authentication timestamp
    mfa: options?.mfaVerified ?? false,  // GPT-5 BE-P0-01: 2FA completed
  };
  if (username) payload.username = username;
  if (options?.role) payload.role = options.role;

  const accessToken = fastify.jwt.sign(
    payload,
    { expiresIn: config.ACCESS_TOKEN_TTL as any }
  );

  // Refresh token (по умолчанию 90 дней)
  const refreshPayload = crypto.randomBytes(48).toString('hex');
  const refreshHash = await bcrypt.hash(refreshPayload, 10);
  const refreshExpiresAt = new Date(
    Date.now() + config.REFRESH_TOKEN_TTL_DAYS * 24 * 3600 * 1000
  );

  await prisma.refreshToken.create({
    data: {
      userId,
      tokenHash: refreshHash,
      expiresAt: refreshExpiresAt,
    },
  });

  const refreshToken = `${userId}.${refreshPayload}`;

  // Вычисляем accessExpiresAt из TTL строки ('7d' → 7 * 24 * 3600 * 1000)
  const accessExpiresAt = parseTtlToMs(config.ACCESS_TOKEN_TTL);

  return {
    accessToken,
    refreshToken,
    accessExpiresAt: Date.now() + accessExpiresAt,
    refreshExpiresAt: refreshExpiresAt.getTime(),
  };
}

function parseTtlToMs(ttl: string): number {
  const match = ttl.match(/^(\d+)([smhd])$/);
  if (!match) return 7 * 24 * 3600 * 1000; // default 7 days
  const num = parseInt(match[1]);
  const unit = match[2];
  switch (unit) {
    case 's': return num * 1000;
    case 'm': return num * 60 * 1000;
    case 'h': return num * 3600 * 1000;
    case 'd': return num * 24 * 3600 * 1000;
    default: return 7 * 24 * 3600 * 1000;
  }
}

export async function verifyRefreshToken(fastify: any, refreshToken: string) {
  const [userId, payload] = refreshToken.split('.');
  if (!userId || !payload) return null;
  
  const tokens = await prisma.refreshToken.findMany({
    where: { userId, revokedAt: null, expiresAt: { gt: new Date() } },
  });
  
  for (const stored of tokens) {
    const match = await bcrypt.compare(payload, stored.tokenHash);
    if (match) {
      // Rotation: revoke this token
      await prisma.refreshToken.update({
        where: { id: stored.id },
        data: { revokedAt: new Date() },
      });
      return { userId, tokenId: stored.id };
    }
  }
  return null;
}

export async function revokeAllUserTokens(userId: string) {
  await prisma.refreshToken.updateMany({
    where: { userId, revokedAt: null },
    data: { revokedAt: new Date() },
  });
}
