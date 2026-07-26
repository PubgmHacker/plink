// Telegram-style account tombstone: keep the User row so chats/friends
// still resolve a peer as «Удалённый аккаунт» with a generic avatar, but
// strip PII and block further login / messaging.

import bcrypt from 'bcryptjs';
import { prisma } from '../config/db.js';
import { revokeAllUserTokens } from '../utils/tokens.js';

export const DELETED_DISPLAY_NAME = 'Удалённый аккаунт';

export function isDeletedUsername(username: string | null | undefined): boolean {
  if (!username) return false;
  return username.startsWith('deleted_') || username === 'deleted';
}

export function isDeletedUser(user: {
  deletedAt?: Date | string | null;
  username?: string | null;
}): boolean {
  if (user.deletedAt) return true;
  return isDeletedUsername(user.username);
}

/** Public-safe projection for friends / DMs / profiles. */
export function publicDeletedProjection(userId: string) {
  return {
    id: userId,
    username: `deleted_${userId.replace(/-/g, '').slice(0, 12)}`,
    displayName: DELETED_DISPLAY_NAME,
    avatarURL: null as string | null,
    avatarData: null as string | null,
    coverURL: null as string | null,
    isOnline: false,
    lastSeenAt: null as string | null,
    isPremium: false,
    isDeleted: true as const,
  };
}

/**
 * Soft-delete: anonymize PII, revoke sessions, keep id for FK integrity.
 * Idempotent if already deleted.
 */
export async function tombstoneAccount(userId: string): Promise<{ alreadyDeleted: boolean }> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      id: true,
      username: true,
      email: true,
      deletedAt: true,
    },
  });
  if (!user) {
    throw Object.assign(new Error('User not found'), { statusCode: 404 });
  }
  if (user.deletedAt) {
    return { alreadyDeleted: true };
  }

  const short = userId.replace(/-/g, '').slice(0, 12);
  const tombUsername = `deleted_${short}`;
  const tombEmail = `deleted_${short}@deleted.plink.invalid`;
  // Unusable password — login always fails
  const randomPass = await bcrypt.hash(`tombstone-${userId}-${Date.now()}-${Math.random()}`, 12);

  try {
    await prisma.user.update({
      where: { id: userId },
      data: {
        username: tombUsername,
        email: tombEmail,
        password: randomPass,
        displayName: DELETED_DISPLAY_NAME,
        avatarURL: null,
        avatarData: null,
        coverURL: null,
        fcmToken: null,
        isOnline: false,
        isPremium: false,
        premiumUntil: null,
        twofaSecret: null,
        twofaEnabled: false,
        twofaBackupCodes: null,
        appearancePrefs: null,
        scheduledForDeletionAt: null,
        deletedAt: new Date(),
      } as any,
    });
  } catch (e: any) {
    // If deletedAt column missing mid-migrate — still anonymize classic fields
    await prisma.user.update({
      where: { id: userId },
      data: {
        username: tombUsername,
        email: tombEmail,
        password: randomPass,
        displayName: DELETED_DISPLAY_NAME,
        avatarURL: null,
        avatarData: null,
        coverURL: null,
        fcmToken: null,
        isOnline: false,
        isPremium: false,
      } as any,
    });
  }

  // Optional: blank personal DM content they authored (privacy)
  try {
    await prisma.directMessage.updateMany({
      where: { senderID: userId },
      data: { content: 'Сообщение удалено' },
    });
  } catch {
    /* ignore */
  }
  try {
    await prisma.chatMessage.updateMany({
      where: { senderID: userId },
      data: { text: 'Сообщение удалено' },
    });
  } catch {
    /* ignore */
  }

  // Drop watch history / FCM etc. already cleared on user row
  try {
    await prisma.watchHistory.deleteMany({ where: { userID: userId } });
  } catch {
    /* ignore */
  }

  await revokeAllUserTokens(userId).catch(() => {});

  return { alreadyDeleted: false };
}
