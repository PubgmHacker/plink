import { prisma } from '../config/db.js';

/**
 * Emails that always receive ADMIN (or FOUNDER) role on sign-in /users/me.
 * Override with env PRIVILEGED_ADMIN_EMAILS=a@x.com,b@y.com
 * FOUNDER list: PRIVILEGED_FOUNDER_EMAILS
 */
function parseList(raw: string | undefined): string[] {
  if (!raw) return [];
  return raw
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
}

const DEFAULT_ADMINS = ['koslakandrej@gmail.com'];

export function privilegedAdminEmails(): string[] {
  const fromEnv = parseList(process.env.PRIVILEGED_ADMIN_EMAILS);
  return fromEnv.length > 0 ? fromEnv : DEFAULT_ADMINS;
}

export function privilegedFounderEmails(): string[] {
  return parseList(process.env.PRIVILEGED_FOUNDER_EMAILS);
}

/**
 * Ensure DB role matches privileged email lists.
 * Returns the (possibly updated) user row fields needed by auth/profile.
 */
export async function ensurePrivilegedRole<T extends { id: string; email: string; role: string }>(
  user: T,
): Promise<T> {
  const email = (user.email || '').toLowerCase().trim();
  if (!email) return user;

  const founders = privilegedFounderEmails();
  const admins = privilegedAdminEmails();

  let desired: 'FOUNDER' | 'ADMIN' | null = null;
  if (founders.includes(email)) desired = 'FOUNDER';
  else if (admins.includes(email)) desired = 'ADMIN';

  if (!desired) return user;
  if (user.role === desired || (desired === 'ADMIN' && user.role === 'FOUNDER')) {
    return user;
  }

  try {
    const updated = await prisma.user.update({
      where: { id: user.id },
      data: { role: desired },
    });
    console.log(`[privileged] ${email} → role ${desired}`);
    return { ...user, role: updated.role } as T;
  } catch (e: any) {
    console.warn('[privileged] role update failed:', e?.message || e);
    return user;
  }
}
