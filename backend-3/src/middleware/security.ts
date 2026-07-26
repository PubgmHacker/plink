// src/middleware/security.ts — Pack 4: helmet-style security headers + 2FA
import bcrypt from 'bcryptjs';
import { prisma } from '../config/db.js';

// ═══════════════════════════════════════════════════════════════════════
// SECURITY HEADERS (helmet-equivalent)
// ═══════════════════════════════════════════════════════════════════════

export async function securityHeaders(request: any, reply: any) {
  const url = String(request.url ?? '');
  const isApi = url.startsWith('/api') || url.startsWith('/ws') || url.startsWith('/health');
  // Hosted YouTube player pages must be iframe-able from desktop/Tauri clients.
  // Without this, browsers honor global X-Frame-Options: DENY and the player
  // never loads — surface symptom is empty stage / YouTube 153 workarounds fail.
  const isEmbeddablePlayer =
    url.includes('/api/media/youtube-player') ||
    url.includes('/api/media/youtube-embed');

  reply.header('X-Content-Type-Options', 'nosniff');
  if (isEmbeddablePlayer) {
    // Allow framing from any app origin (desktop tauri://, vite localhost, iOS WKWebView).
    reply.removeHeader?.('X-Frame-Options');
    reply.header('Content-Security-Policy',
      "default-src * 'unsafe-inline' 'unsafe-eval' data: blob:; " +
      "script-src * 'unsafe-inline' 'unsafe-eval'; " +
      "style-src * 'unsafe-inline'; " +
      "img-src * data: blob:; media-src *; connect-src * wss:; frame-src *; child-src *;");
  } else {
    reply.header('X-Frame-Options', 'DENY');
    reply.header('Content-Security-Policy',
      "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; " +
      "img-src 'self' data: https:; media-src 'self' https:; " +
      "connect-src 'self' wss: https:;");
  }
  reply.header('X-XSS-Protection', '1; mode=block');
  reply.header('Referrer-Policy', 'strict-origin-when-cross-origin');
  reply.header('Permissions-Policy',
    'geolocation=(), microphone=(), camera=(), payment=(), usb=()');
  reply.header('Strict-Transport-Security',
    'max-age=31536000; includeSubDomains; preload');

  // API + WebSocket: allow Tauri/Vite/desktop clients to read JSON responses.
  // Global same-origin CORP breaks fetch() from tauri://localhost even when CORS passes.
  if (isApi || isEmbeddablePlayer) {
    reply.header('Cross-Origin-Resource-Policy', 'cross-origin');
    reply.header('Cross-Origin-Embedder-Policy', 'unsafe-none');
    if (isEmbeddablePlayer) {
      // Do not set COOP same-origin — it can block cross-origin iframe embed.
      reply.removeHeader?.('Cross-Origin-Opener-Policy');
    }
  } else {
    reply.header('Cross-Origin-Opener-Policy', 'same-origin');
    reply.header('Cross-Origin-Embedder-Policy', 'require-corp');
    reply.header('Cross-Origin-Resource-Policy', 'same-origin');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 2FA — TOTP (Time-based One-Time Password)
// ═══════════════════════════════════════════════════════════════════════

import crypto from 'crypto';

const BASE32_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function base32Encode(buffer: Buffer): string {
  let result = '';
  let bits = 0;
  let value = 0;
  for (const byte of buffer) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      result += BASE32_CHARS[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) {
    result += BASE32_CHARS[(value << (5 - bits)) & 31];
  }
  return result;
}

function base32Decode(str: string): Buffer {
  str = str.toUpperCase().replace(/[^A-Z2-7]/g, '');
  const bytes: number[] = [];
  let buffer = 0;
  let bitsLeft = 0;
  for (const c of str) {
    const val = BASE32_CHARS.indexOf(c);
    if (val < 0) continue;
    buffer = (buffer << 5) | val;
    bitsLeft += 5;
    if (bitsLeft >= 8) {
      bytes.push((buffer >> (bitsLeft - 8)) & 0xff);
      bitsLeft -= 8;
    }
  }
  return Buffer.from(bytes);
}

/** Генерация нового TOTP секрета для пользователя */
export function generateTOTPSecret(): string {
  const buffer = crypto.randomBytes(20);
  return base32Encode(buffer);
}

/** Генерация otpauth URL для QR-кода */
export function generateOTPAuthURL(secret: string, email: string, issuer = 'Plink'): string {
  const label = encodeURIComponent(`${issuer}:${email}`);
  const params = new URLSearchParams({
    secret,
    issuer,
    algorithm: 'SHA1',
    digits: '6',
    period: '30',
  });
  return `otpauth://totp/${label}?${params.toString()}`;
}

/** Генерация текущего TOTP кода */
export function generateTOTPCode(secret: string, timestamp = Date.now()): string {
  const buffer = base32Decode(secret);
  const counter = Math.floor(timestamp / 1000 / 30);
  const counterBuffer = Buffer.alloc(8);
  counterBuffer.writeBigInt64BE(BigInt(counter));
  
  const hmac = crypto.createHmac('sha1', buffer).update(counterBuffer).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const code = ((hmac[offset] & 0x7f) << 24 |
                (hmac[offset + 1] & 0xff) << 16 |
                (hmac[offset + 2] & 0xff) << 8 |
                (hmac[offset + 3] & 0xff)) % 1000000;
  return code.toString().padStart(6, '0');
}

/** Проверка TOTP кода (с окном ±1 step для рассинхрона часов) */
export function verifyTOTP(secret: string, code: string): boolean {
  const now = Date.now();
  for (const offset of [-30000, 0, 30000]) {
    const expected = generateTOTPCode(secret, now + offset);
    if (crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(code))) {
      return true;
    }
  }
  return false;
}

/** Backup codes (8 штук, по 8 символов) */
export function generateBackupCodes(): string[] {
  return Array.from({ length: 8 }, () => 
    crypto.randomBytes(4).toString('hex').toUpperCase()
  );
}

// ═══════════════════════════════════════════════════════════════════════
// Утилиты безопасности
// ═══════════════════════════════════════════════════════════════════════

/** Проверка пароля на сложность */
export function validatePasswordStrength(password: string): {
  valid: boolean;
  score: number;
  feedback: string[];
} {
  const feedback: string[] = [];
  let score = 0;
  
  if (password.length >= 8) score++;
  else feedback.push('Минимум 8 символов');
  
  if (password.length >= 12) score++;
  
  if (/[a-z]/.test(password) && /[A-Z]/.test(password)) score++;
  else feedback.push('Нужны заглавные и строчные буквы');
  
  if (/\d/.test(password)) score++;
  else feedback.push('Нужны цифры');
  
  if (/[^a-zA-Z\d]/.test(password)) score++;
  else feedback.push('Нужны спецсимволы');
  
  // Проверка на часто используемые пароли
  const common = ['password', '123456', 'qwerty', 'admin', 'letmein'];
  if (common.some(p => password.toLowerCase().includes(p))) {
    score = 0;
    feedback.push('Слишком простой пароль');
  }
  
  return { valid: score >= 3, score, feedback };
}

// ═══════════════════════════════════════════════════════════════════════
// Сохранённые функции (из Pack 1)
// ═══════════════════════════════════════════════════════════════════════

export async function isRoomHost(prisma, roomId: string, userId: string): Promise<boolean> {
  const room = await prisma.room.findUnique({
    where: { id: roomId },
    select: { hostID: true }
  });
  return room?.hostID === userId;
}

export function requireHost(prisma) {
  return async (request: any, reply: any) => {
    const { id: roomId } = request.params;
    const userId = request.user.id;
    const room = await prisma.room.findUnique({
      where: { id: roomId },
      select: { hostID: true }
    });
    if (!room) return reply.status(404).send({ error: 'Room not found' });
    if (room.hostID !== userId) {
      return reply.status(403).send({ error: 'Only host can control playback' });
    }
  };
}

export async function sanitizeChatMessage(clientMsg: any, user: { id: string; username: string; role: string }, prisma?: any) {
  // 🔧 FIX: fetch avatarURL + isPremium + displayName so chat bubbles can show
  // avatars, names, AND we can validate bubble style permissions server-side.
  let avatarURL: string | null = null;
  let displayName: string | null = null;
  let isPremium = false;
  if (prisma) {
    try {
      const userData = await prisma.user.findUnique({
        where: { id: user.id },
        select: { avatarURL: true, isPremium: true, premiumUntil: true, displayName: true }
      });
      avatarURL = userData?.avatarURL || null;
      displayName = userData?.displayName || null;
      // 🔧 v10 (bubble styles): premium is active only if isPremium=true AND
      // premiumUntil is in the future (or null = lifetime).
      const now = new Date();
      isPremium = !!userData?.isPremium && (
        !userData.premiumUntil || userData.premiumUntil > now
      );
    } catch {}
  }

  // 🔧 v10 (bubble styles): validate requested bubble style against user's
  // permissions. processMessageStyle() returns a guaranteed-safe style id
  // that the client is allowed to use. NEVER trust the client's style id
  // directly — always re-derive it here.
  const confirmedStyleId = await processMessageStyle(
    user.id,
    clientMsg.bubbleStyle || clientMsg.bubble_style || 'default',
    { role: user.role, isPremium },
    prisma
  );

  return {
    type: 'chat',
    roomID: clientMsg.roomID,
    id: clientMsg.id || crypto.randomUUID(),
    senderID: user.id,
    senderName: user.username,  // 🔧 v11: keep @username for compatibility
    senderDisplayName: displayName,  // 🔧 v11: Telegram-style display name (nil on old clients)
    senderRole: user.role,
    senderAvatarURL: avatarURL,
    text: sanitizeText(clientMsg.text),
    timestamp: Date.now(),
    // 🔧 v10: confirmed bubble style — client uses this for rendering.
    bubbleStyle: confirmedStyleId,
  };
}

// ═══════════════════════════════════════════════════════════════════════
// 🔧 v10 (July 2026): Chat Bubble Styles — server-side validation
// ═══════════════════════════════════════════════════════════════════════
//
// Permission matrix:
//   ┌──────────────────┬──────────┬───────────────┬───────────────────┐
//   │ Style ID         │ Default  │ Плинк+ (paid) │ Admin/Founder     │
//   ├──────────────────┼──────────┼───────────────┼───────────────────┤
//   │ default          │    ✅    │      ✅       │        ✅          │
//   │ cute_duck        │    ❌    │      ✅       │        ✅*         │
//   │ neon_cyber       │    ❌    │      ✅       │        ✅*         │
//   │ admin_bubble     │    ❌    │      ❌       │        ✅          │
//   └──────────────────┴──────────┴───────────────┴───────────────────┘
//   * Admins get Плинк+ features implicitly, but their messages use the
//     admin_bubble style automatically (override), not the Плинк+ style.
//
// Anti-tampering: clients can send ANY string as bubbleStyle. This function
// is the ONLY authority that decides which style is actually used. Unknown
// or unauthorized styles are downgraded to 'default'. Admin style attempts
// from non-admins are HARD-BLOCKED (also downgraded to 'default', not
// silently kept) — we log this as a security event for monitoring.

const ALLOWED_STYLES = new Set([
  'default',
  'cute_duck',
  'neon_cyber',
  'admin_bubble',
]);

const PREMIUM_STYLES = new Set([
  'cute_duck',
  'neon_cyber',
]);

const ADMIN_STYLES = new Set([
  'admin_bubble',
]);

/**
 * Validates a requested bubble style against the user's permissions.
 *
 * @param userId       - The sender's user ID (for DB lookup if needed)
 * @param requestedStyleId - The style the client requested (UNTRUSTED)
 * @param user         - Cached user context: { role, isPremium }
 * @param prisma       - Optional DB handle (used only if user.isPremium is
 *                       undefined and we need to refresh from DB)
 * @returns confirmed_style_id — guaranteed to be one of ALLOWED_STYLES,
 *          safe to broadcast to other clients.
 */
export async function processMessageStyle(
  userId: string,
  requestedStyleId: string,
  user: { role: string; isPremium?: boolean },
  prisma?: any
): Promise<string> {
  // ── 1. Normalize input ──────────────────────────────────────────────
  // Reject anything that's not a non-empty string. Default to 'default'.
  if (typeof requestedStyleId !== 'string' || !requestedStyleId.trim()) {
    return 'default';
  }
  const requested = requestedStyleId.trim().toLowerCase();

  // Unknown style id (client tampering or outdated client) → default.
  if (!ALLOWED_STYLES.has(requested)) {
    console.warn(
      `[security] Unknown bubble style '${requested}' from user ${userId}. ` +
      `Downgrading to 'default'.`
    );
    return 'default';
  }

  // ── 2. Resolve user context (refresh from DB if isPremium is unknown) ──
  let isPremium = user.isPremium;
  const role = (user.role || '').toUpperCase();
  const isAdmin = role === 'ADMIN' || role === 'FOUNDER';

  if (isPremium === undefined && prisma) {
    try {
      const userData = await prisma.user.findUnique({
        where: { id: userId },
        select: { isPremium: true, premiumUntil: true }
      });
      const now = new Date();
      isPremium = !!userData?.isPremium && (
        !userData.premiumUntil || userData.premiumUntil > now
      );
    } catch {
      isPremium = false;
    }
  }
  isPremium = !!isPremium;

  // ── 3. Admin override — admins ALWAYS get admin_bubble style ──────────
  // This is by design: admin messages should be visually distinct in the
  // chat, so we apply the admin style automatically, regardless of what
  // the client requested. The client's requestedStyleId is ignored.
  if (isAdmin) {
    return 'admin_bubble';
  }

  // ── 4. Hard-block admin_bubble attempts from non-admins ──────────────
  // This is a security event — log it for monitoring. Non-admins trying to
  // use admin_bubble are either tampering with the client or using an
  // outdated version that doesn't know about the permission system.
  if (ADMIN_STYLES.has(requested)) {
    console.warn(
      `[security] Non-admin user ${userId} (role=${role}) attempted to use ` +
      `admin bubble style '${requested}'. HARD-BLOCKED, downgrading to 'default'.`
    );
    return 'default';
  }

  // ── 5. Premium styles — requires active Плинк+ subscription ──────────
  if (PREMIUM_STYLES.has(requested)) {
    if (!isPremium) {
      console.warn(
        `[security] Non-premium user ${userId} attempted to use premium ` +
        `bubble style '${requested}'. Downgrading to 'default'.`
      );
      return 'default';
    }
    return requested;  // User is premium, style is allowed
  }

  // ── 6. 'default' is always allowed for everyone ──────────────────────
  return 'default';
}

function sanitizeText(text: string): string {
  if (!text || typeof text !== 'string') return '';
  let cleaned = text
    .replace(/<[^>]*>/g, '')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&').replace(/&quot;/g, '"')
    .replace(/&#x27;/g, "'").replace(/&#x2F;/g, '/');
  if (cleaned.length > 150) cleaned = cleaned.substring(0, 150);
  cleaned = cleaned.replace(/[\x00-\x1F\x7F]/g, '');
  return cleaned.trim();
}

export async function hashRoomPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, 10);
}

export async function verifyRoomPassword(plain: string, hashed: string): Promise<boolean> {
  try { return await bcrypt.compare(plain, hashed); } catch { return false; }
}

const rlMap = new Map<string, { count: number; resetAt: number }>();

export function checkRateLimit(userId: string): boolean {
  const now = Date.now();
  const e = rlMap.get(userId);
  if (!e || now > e.resetAt) {
    rlMap.set(userId, { count: 1, resetAt: now + 1000 });
    return true;
  }
  if (e.count >= 10) return false;
  e.count++;
  return true;
}

setInterval(() => {
  const now = Date.now();
  for (const [k, v] of rlMap) if (now > v.resetAt) rlMap.delete(k);
}, 60_000);
