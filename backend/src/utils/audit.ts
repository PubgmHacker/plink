// src/utils/audit.ts — Audit Log helper
import { prisma } from '../config/db.js';

export async function logAudit(params: {
  userId?: string;
  action: string;
  ip?: string;
  userAgent?: string;
  metadata?: any;
}) {
  try {
    await prisma.auditLog.create({
      data: {
        userId: params.userId || null,
        action: params.action,
        ip: params.ip || null,
        userAgent: params.userAgent || null,
        metadata: params.metadata || undefined,
      },
    });
  } catch (e: any) {
    console.error('[AuditLog] failed to write:', e.message);
  }
}

// Convenience helpers
export const AuditActions = {
  LOGIN: 'login',
  LOGIN_FAILED: 'login.failed',
  LOGOUT: 'logout',
  SIGNUP: 'signup',
  TOKEN_REFRESH: 'token.refresh',
  ROOM_CREATE: 'room.create',
  ROOM_JOIN: 'room.join',
  ROOM_LEAVE: 'room.leave',
  ROOM_DELETE: 'room.delete',
  PLAYBACK_CONTROL: 'playback.control',
  MESSAGE_SENT: 'message.sent',
  USER_BANNED: 'user.banned',
  USER_PREMIUM_GRANTED: 'user.premium.granted',
  // V5 (Phase 4)
  ROOM_APPEARANCE_UPDATE: 'room.appearance.update',
  PROFILE_APPEARANCE_UPDATE: 'profile.appearance.update',
  ACCOUNT_DELETION_REQUESTED: 'account.deletion.requested',
  ACCOUNT_DELETION_CANCELLED: 'account.deletion.cancelled',
  SIGNOUT_OTHERS: 'auth.signout.others',
} as const;
