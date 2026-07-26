#!/usr/bin/env node
// scripts/bootstrap-admin.js
//
// B1 (GPT-5.6 ADR-002): idempotent bootstrap script для назначения admin ролей.
// Заменяет удалённый POST /api/auth/promote-self endpoint.
//
// Usage:
//   DATABASE_URL="postgresql://..." node scripts/bootstrap-admin.js --email=koslakandrej@gmail.com --role=FOUNDER
//
// Features:
//   - Allowlist: только email из ALLOWED_BOOTSTRAP_ADMINS env var может быть повышен
//   - Idempotent: повторный запуск не создаёт дубликаты, только обновляет роль
//   - Audit log: пишет запись в AuditLog
//   - Requires production secrets access (DATABASE_URL)
//
// Allowlist format (env var):
//   ALLOWED_BOOTSTRAP_ADMINS=koslakandrej@gmail.com,admin@plink.app

import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const ALLOWED_ROLES = ['ADMIN', 'FOUNDER'];

async function main() {
  const args = process.argv.slice(2);
  const emailArg = args.find(a => a.startsWith('--email='));
  const roleArg = args.find(a => a.startsWith('--role='));

  if (!emailArg || !roleArg) {
    console.error('Usage: node scripts/bootstrap-admin.js --email=<email> --role=<ADMIN|FOUNDER>');
    process.exit(1);
  }

  const email = emailArg.split('=')[1].toLowerCase().trim();
  const role = roleArg.split('=')[1].toUpperCase().trim();

  if (!ALLOWED_ROLES.includes(role)) {
    console.error(`Invalid role: ${role}. Must be one of: ${ALLOWED_ROLES.join(', ')}`);
    process.exit(1);
  }

  // Allowlist check
  const allowlist = (process.env.ALLOWED_BOOTSTRAP_ADMINS || '')
    .split(',')
    .map(e => e.toLowerCase().trim())
    .filter(Boolean);

  if (allowlist.length === 0) {
    console.error('ALLOWED_BOOTSTRAP_ADMINS env var not set or empty. Set it to comma-separated list of allowed emails.');
    process.exit(1);
  }

  if (!allowlist.includes(email)) {
    console.error(`Email ${email} is not in allowlist. Allowed: ${allowlist.join(', ')}`);
    process.exit(1);
  }

  // Find user
  const user = await prisma.user.findUnique({
    where: { email },
    select: { id: true, username: true, email: true, role: true }
  });

  if (!user) {
    console.error(`User with email ${email} not found. User must sign up first.`);
    process.exit(1);
  }

  console.log(`Current role: ${user.role}`);
  console.log(`Target role: ${role}`);

  if (user.role === role) {
    console.log('User already has this role. No change needed (idempotent).');
    return;
  }

  // Update role
  const updated = await prisma.user.update({
    where: { id: user.id },
    data: { role },
    select: { id: true, username: true, email: true, role: true }
  });

  // Audit log
  await prisma.auditLog.create({
    data: {
      userId: user.id,
      action: 'admin.bootstrap_promoted',
      ip: '127.0.0.1',
      userAgent: 'bootstrap-admin.js',
      metadata: {
        email: updated.email,
        previousRole: user.role,
        newRole: role,
        source: 'bootstrap_script',
        timestamp: new Date().toISOString()
      }
    }
  });

  console.log(`✅ Success: ${updated.email} promoted to ${updated.role}`);
  console.log(`Audit log entry created.`);
}

main()
  .catch(e => {
    console.error('Bootstrap failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
