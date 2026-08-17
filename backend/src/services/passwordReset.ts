// passwordReset.ts — код восстановления пароля.
// Хранилище: Redis, если есть; иначе память процесса (один инстанс Railway).
// Код 6 цифр, TTL 15 мин, 5 попыток. Существование почты наружу не светим.

import crypto from 'node:crypto';
import { redis } from '../config/redis.js';

const TTL_SEC = 15 * 60;
const MAX_ATTEMPTS = 5;
const KEY_PREFIX = 'pwdreset:';

export type ConsumeResult = 'ok' | 'invalid' | 'expired' | 'locked';

type Slot = { hash: string; attempts: number };

const memory = new Map<string, { slot: Slot; expiresAt: number }>();

function normalizeEmail(email: string): string {
  return String(email ?? '').trim().toLowerCase();
}

function keyFor(email: string): string {
  return `${KEY_PREFIX}${normalizeEmail(email)}`;
}

export function hashResetCode(email: string, code: string, pepper: string): string {
  return crypto
    .createHash('sha256')
    .update(`${pepper}:${normalizeEmail(email)}:${String(code).trim()}`)
    .digest('hex');
}

export function generateResetCode(): string {
  return String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
}

function pepper(): string {
  return process.env.JWT_SECRET || 'dev-secret-change-me';
}

export async function storeResetCode(email: string, code: string): Promise<void> {
  const slot: Slot = { hash: hashResetCode(email, code, pepper()), attempts: 0 };
  const k = keyFor(email);
  if (redis) {
    await redis.setex(k, TTL_SEC, JSON.stringify(slot));
    return;
  }
  memory.set(k, { slot, expiresAt: Date.now() + TTL_SEC * 1000 });
}

async function readSlot(email: string): Promise<Slot | null> {
  const k = keyFor(email);
  if (redis) {
    const raw = await redis.get(k);
    if (!raw) return null;
    try {
      return JSON.parse(raw) as Slot;
    } catch {
      return null;
    }
  }
  const row = memory.get(k);
  if (!row) return null;
  if (row.expiresAt <= Date.now()) {
    memory.delete(k);
    return null;
  }
  return row.slot;
}

async function writeSlot(email: string, slot: Slot, ttlSec: number): Promise<void> {
  const k = keyFor(email);
  if (redis) {
    await redis.setex(k, ttlSec, JSON.stringify(slot));
    return;
  }
  const row = memory.get(k);
  const expiresAt = row?.expiresAt ?? Date.now() + ttlSec * 1000;
  memory.set(k, { slot, expiresAt });
}

export async function deleteResetCode(email: string): Promise<void> {
  const k = keyFor(email);
  if (redis) {
    await redis.del(k);
    return;
  }
  memory.delete(k);
}

export async function consumeResetCode(email: string, code: string): Promise<ConsumeResult> {
  const slot = await readSlot(email);
  if (!slot) return 'expired';
  if (slot.attempts >= MAX_ATTEMPTS) {
    await deleteResetCode(email);
    return 'locked';
  }
  const expected = Buffer.from(slot.hash);
  const got = Buffer.from(hashResetCode(email, code, pepper()));
  const match = expected.length === got.length && crypto.timingSafeEqual(expected, got);
  if (!match) {
    slot.attempts += 1;
    if (slot.attempts >= MAX_ATTEMPTS) {
      await deleteResetCode(email);
      return 'locked';
    }
    await writeSlot(email, slot, TTL_SEC);
    return 'invalid';
  }
  await deleteResetCode(email);
  return 'ok';
}

export async function sendPasswordResetEmail(to: string, code: string): Promise<'sent' | 'logged'> {
  const key = process.env.RESEND_API_KEY;
  const from = process.env.MAIL_FROM || 'Plink <noreply@plink.app>';
  if (key) {
    const resp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from,
        to: [to],
        subject: 'Код для нового пароля Plink',
        text: `Код: ${code}\nДействует 15 минут. Если вы не просили сброс — просто удалите письмо.`,
      }),
    });
    if (!resp.ok) {
      const body = await resp.text().catch(() => '');
      throw new Error(`mailer ${resp.status}: ${body.slice(0, 200)}`);
    }
    return 'sent';
  }
  console.info(`[mailer] password reset code for ${to}: ${code}`);
  return 'logged';
}

/** Только тесты. */
export function __clearPasswordResetMemory(): void {
  memory.clear();
}
