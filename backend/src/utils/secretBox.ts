// src/utils/secretBox.ts — шифрование 2FA-секретов в БД (аудит 26.07.2026, P1 5.6)
//
// twofaSecret и twofaBackupCodes хранились открытым текстом. Теперь значения
// шифруются AES-256-GCM ключом из окружения TWOFA_ENC_KEY (32 байта, base64
// или hex). Формат хранения: "enc:v1:<iv>:<ciphertext>:<tag>" (base64).
//
// Легаси-значения без префикса читаются как есть — decryptSecret() их
// пропускает насквозь, чтобы ничего не сломать до перешифровки
// (scripts/encrypt-2fa-secrets.js).

import crypto from 'node:crypto';

const PREFIX = 'enc:v1:';

function loadKey(): Buffer | null {
  const raw = process.env.TWOFA_ENC_KEY;
  if (!raw) return null;
  try {
    const buf = /^[0-9a-fA-F]{64}$/.test(raw)
      ? Buffer.from(raw, 'hex')
      : Buffer.from(raw, 'base64');
    return buf.length === 32 ? buf : null;
  } catch {
    return null;
  }
}

export function isEncryptedSecret(value: string): boolean {
  return value.startsWith(PREFIX);
}

/** Есть ли рабочий ключ шифрования в окружении. */
export function secretBoxReady(): boolean {
  return loadKey() !== null;
}

export function encryptSecret(plain: string): string {
  const key = loadKey();
  if (!key) {
    throw new Error('TWOFA_ENC_KEY не задан или не 32 байта (base64/hex) — шифрование 2FA невозможно');
  }
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ct = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return PREFIX + [iv, ct, tag].map((b) => b.toString('base64')).join(':');
}

/**
 * Расшифровка. Значение без префикса enc:v1: считается легаси-плейнтекстом
 * и возвращается как есть. null — если ключа нет или данные повреждены.
 */
export function decryptSecret(stored: string): string | null {
  if (!isEncryptedSecret(stored)) return stored;
  const key = loadKey();
  if (!key) return null;
  try {
    const [ivB64, ctB64, tagB64] = stored.slice(PREFIX.length).split(':');
    const iv = Buffer.from(ivB64, 'base64');
    const ct = Buffer.from(ctB64, 'base64');
    const tag = Buffer.from(tagB64, 'base64');
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(ct), decipher.final()]).toString('utf8');
  } catch {
    return null;
  }
}
