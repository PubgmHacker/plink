// src/utils/tokens.ts — Pack 1.1: настраиваемый TTL через env
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { prisma } from '../config/db.js';
import { redis } from '../config/redis.js';
import { config } from '../config/index.js';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  accessExpiresAt: number;
  refreshExpiresAt: number;
}

/**
 * Issue access token with role + mfa + auth_time claims.
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
  options?: { mfaVerified?: boolean; role?: string },
): Promise<TokenPair> {
  const now = Math.floor(Date.now() / 1000);
  const accessTtlMs = parseTtlToMs(config.ACCESS_TOKEN_TTL);

  const payload: any = {
    id: userId,
    sub: userId, // Standard JWT subject claim
    iat: now, // issued at (seconds)
    auth_time: now, // Authentication timestamp
    mfa: options?.mfaVerified ?? false, // 2FA completed
    // ⚠️ АУДИТ 26.07.2026 (P0): срок жизни задаётся ЯВНО.
    //
    // Было: `sign(payload, { expiresIn: config.ACCESS_TOKEN_TTL as any })`,
    // то есть строка '1h'. Библиотека fast-jwt (под @fastify/jwt) ожидает
    // в `expiresIn` ЧИСЛО МИЛЛИСЕКУНД, а не строку формата `ms`. Строка
    // давала `exp = iat + Math.floor('1h'/1000)` → NaN, и claim `exp`
    // фактически не выставлялся. Access-токен не истекал НИКОГДА.
    //
    // Последствия: утёкший токен оставался валидным вечно, а бан и
    // разжалование не срабатывали до ручного отзыва. Приведение `as any`
    // как раз и скрывало несоответствие типов.
    //
    // Теперь считаем `exp` сами в секундах Unix — это стандарт JWT и
    // не зависит от того, в каких единицах конкретная библиотека ждёт TTL.
    exp: now + Math.floor(accessTtlMs / 1000),
  };
  if (username) payload.username = username;
  if (options?.role) payload.role = options.role;

  const accessToken = fastify.jwt.sign(payload);

  // Refresh token (по умолчанию 90 дней)
  const refreshPayload = crypto.randomBytes(48).toString('hex');
  const refreshHash = await bcrypt.hash(refreshPayload, 10);
  const refreshExpiresAt = new Date(Date.now() + config.REFRESH_TOKEN_TTL_DAYS * 24 * 3600 * 1000);

  await prisma.refreshToken.create({
    data: {
      userId,
      tokenHash: refreshHash,
      expiresAt: refreshExpiresAt,
    },
  });

  const refreshToken = `${userId}.${refreshPayload}`;

  return {
    accessToken,
    refreshToken,
    accessExpiresAt: Date.now() + accessTtlMs,
    refreshExpiresAt: refreshExpiresAt.getTime(),
  };
}

function parseTtlToMs(ttl: string): number {
  const match = ttl.match(/^(\d+)([smhd])$/);
  if (!match) return 7 * 24 * 3600 * 1000; // default 7 days
  const num = parseInt(match[1]);
  const unit = match[2];
  switch (unit) {
    case 's':
      return num * 1000;
    case 'm':
      return num * 60 * 1000;
    case 'h':
      return num * 3600 * 1000;
    case 'd':
      return num * 24 * 3600 * 1000;
    default:
      return 7 * 24 * 3600 * 1000;
  }
}

/// Верхняя граница сканирования отозванных токенов bcrypt-ом (fallback-путь).
/// bcryptjs — чистый JS, одна проверка ~100–300 мс, поэтому лимит держим
/// низким; полноту детекта обеспечивает индекс в Redis (см. ниже).
const REUSE_SCAN_LIMIT = 20;

/// Ключ индекса отозванных refresh-токенов. Значение payload'а хешируется
/// sha256 (быстро и детерминированно), поэтому поиск — O(1) вместо
/// bcrypt-скана всей истории ротаций.
function reuseIndexKey(userId: string, payload: string): string {
  const digest = crypto.createHash('sha256').update(payload).digest('hex');
  return `plink:rt:revoked:${userId}:${digest}`;
}

/// Окно детекта повторного использования. Ревью 26.07.2026: TTL «до
/// expiresAt» при REFRESH_TOKEN_TTL_DAYS=90 давал ~2000+ ключей на активного
/// пользователя, живущих 90 дней, и ничем не чистился — Redis здесь общий с
/// состоянием комнат, nonce-ами WS-тикетов и rate limit, поэтому при
/// maxmemory вытеснялись бы именно рабочие ключи. Реюз старше двух недель на
/// практике не встречается, а глубже подстрахует bcrypt-скан ниже.
const REUSE_INDEX_MAX_TTL_SEC = 14 * 24 * 3600;

/// Запомнить отозванный токен в индексе. TTL = остаток его жизни, но не
/// больше окна детекта: после expiresAt предъявлять токен бессмысленно,
/// активная ветка его не примет.
async function rememberRevokedToken(
  userId: string,
  payload: string,
  expiresAt: Date,
  tokenId: string,
): Promise<void> {
  if (!redis) return;
  const remainingSec = Math.ceil((expiresAt.getTime() - Date.now()) / 1000);
  const ttlSec = Math.min(remainingSec, REUSE_INDEX_MAX_TTL_SEC);
  if (ttlSec <= 0) return;
  try {
    await redis.set(reuseIndexKey(userId, payload), tokenId, 'EX', ttlSec);
  } catch {
    /* индекс — ускоритель, а не источник истины: остаётся bcrypt-скан */
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
      // Кладём отозванный токен в индекс, чтобы его
      // повторное предъявление ловилось за один GET, а не bcrypt-сканом
      // последних N ротаций (см. ниже).
      await rememberRevokedToken(userId, payload, stored.expiresAt, stored.id);
      return { userId, tokenId: stored.id };
    }
  }

  // ── обнаружение повторного использования ───────────
  // Раньше предъявление уже отозванного refresh-токена просто давало 401.
  // Но это классический признак кражи: пользователь обновил сессию, а
  // злоумышленник предъявляет старый токен из перехваченной копии
  // (или наоборот). Жертва получала 401 и заново входила, а цепочка
  // злоумышленника продолжала жить.
  //
  // Теперь при попадании в отозванный токен отзывается ВСЁ семейство
  // токенов пользователя: активная сессия обрывается у обеих сторон,
  // и владелец аккаунта возвращает контроль повторным входом.
  //
  // Детект был ограничен `take: 20` — сканировались
  // только 20 последних отозванных токенов. Украденный токен, ротированный
  // больше 20 генераций назад, не матчился ни с одной строкой, и вместо
  // инвалидации семьи возвращался обычный 401. Поднять лимит «в лоб» нельзя:
  // каждая строка — это bcryptjs.compare (чистый JS, ~100–300 мс), то есть
  // 401-путь превратился бы в CPU-усилитель.
  //
  // Поэтому основной детект теперь идёт через индекс в Redis: при ротации мы
  // запоминаем sha256 отозванного payload'а с TTL до его expiresAt, и здесь
  // проверяем его одним GET — глубина истории больше не ограничена.
  if (redis) {
    let hit: string | null = null;
    try {
      hit = await redis.get(reuseIndexKey(userId, payload));
    } catch {
      hit = null; // Redis недоступен — ниже отработает bcrypt-скан
    }
    if (hit) {
      await revokeAllUserTokens(userId);
      try {
        fastify?.log?.warn(
          { userId, tokenId: hit },
          '[auth] повторное использование refresh-токена — отозваны все сессии пользователя',
        );
      } catch {
        /* логгер недоступен — отзыв уже выполнен, это главное */
      }
      return null;
    }
  }

  // Fallback: токены, отозванные до появления индекса (или пока Redis лежал,
  // а также отозванные не через ротацию — logout / signout-others / tombstone,
  // где plaintext payload недоступен и индекс не наполняется).
  // Здесь лимит осознанно низкий из-за стоимости bcrypt.
  //
  // Ревью 26.07.2026: фильтр `expiresAt > now` убран — он СУЖАЛ детект
  // относительно исходного поведения. Предъявление уже истёкшего, но
  // отозванного токена — такой же признак кражи и обязано отзывать семейство.
  const reused = await prisma.refreshToken.findMany({
    where: { userId, revokedAt: { not: null } },
    select: { id: true, tokenHash: true },
    orderBy: { createdAt: 'desc' },
    take: REUSE_SCAN_LIMIT,
  });

  for (const stored of reused) {
    if (await bcrypt.compare(payload, stored.tokenHash)) {
      await revokeAllUserTokens(userId);
      try {
        fastify?.log?.warn(
          { userId, tokenId: stored.id },
          '[auth] повторное использование refresh-токена — отозваны все сессии пользователя',
        );
      } catch {
        /* логгер недоступен — отзыв уже выполнен, это главное */
      }
      return null;
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
