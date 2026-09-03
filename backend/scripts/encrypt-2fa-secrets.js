#!/usr/bin/env node
// scripts/encrypt-2fa-secrets.js — разовая перешифровка 2FA-секретов (P1 5.6).
//
// Шифрует все НЕзашифрованные twofaSecret / twofaBackupCodes в таблице User
// ключом TWOFA_ENC_KEY (AES-256-GCM, см. src/utils/secretBox.ts).
// Уже зашифрованные значения (префикс enc:v1:) пропускаются — скрипт идемпотентен.
//
// Запуск:
//   1) снять бэкап:  pg_dump "$DATABASE_URL" -Fc -f backup-before-2fa-enc.dump
//   2) DATABASE_URL=... TWOFA_ENC_KEY=... node scripts/encrypt-2fa-secrets.js
//   3) добавить --dry-run чтобы посмотреть без записи.
//
// На 26.07.2026 в проде 0 строк с секретами — скрипт нужен на будущее,
// если появятся плейнтекст-значения до включения шифрования.

import { PrismaClient } from '@prisma/client';
import crypto from 'node:crypto';

const PREFIX = 'enc:v1:';
const DRY = process.argv.includes('--dry-run');

function loadKey() {
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

function encryptSecret(key, plain) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ct = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return PREFIX + [iv, ct, tag].map((b) => b.toString('base64')).join(':');
}

const key = loadKey();
if (!key) {
  console.error('TWOFA_ENC_KEY не задан или не 32 байта (base64/hex). Прерываю.');
  process.exit(1);
}

const prisma = new PrismaClient();

const users = await prisma.user.findMany({
  where: {
    OR: [{ twofaSecret: { not: null } }, { twofaBackupCodes: { not: null } }],
  },
  select: { id: true, twofaSecret: true, twofaBackupCodes: true },
});

let updated = 0;
for (const u of users) {
  const data = {};
  if (u.twofaSecret && !u.twofaSecret.startsWith(PREFIX)) {
    data.twofaSecret = encryptSecret(key, u.twofaSecret);
  }
  if (u.twofaBackupCodes && !u.twofaBackupCodes.startsWith(PREFIX)) {
    data.twofaBackupCodes = encryptSecret(key, u.twofaBackupCodes);
  }
  if (Object.keys(data).length === 0) continue;
  if (DRY) {
    console.log(`[dry-run] user ${u.id}: зашифровал бы ${Object.keys(data).join(', ')}`);
  } else {
    await prisma.user.update({ where: { id: u.id }, data });
  }
  updated++;
}

console.log(
  `${DRY ? '[dry-run] ' : ''}Готово: строк с секретами ${users.length}, перешифровано ${updated}.`,
);
await prisma.$disconnect();
