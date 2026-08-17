// src/services/moderation/moderationAudit.ts — GPT-5.6 §14
import { prisma } from '../../config/db.js';

export async function recordModerationAudit(params: {
  roomId: string; messageId: string; subjectUserId: string;
  action: string; reasonCode: string; confidence?: number;
  policyVersion: string; modelVersion?: string; evidenceHash: string;
  reversible?: boolean;
}) {
  try {
    await (prisma as any).aIModerationAudit.create({
      data: {
        roomId: params.roomId, messageId: params.messageId,
        subjectUserId: params.subjectUserId, action: params.action,
        reasonCode: params.reasonCode, confidence: params.confidence ?? null,
        policyVersion: params.policyVersion, modelVersion: params.modelVersion ?? null,
        evidenceHash: params.evidenceHash, reversible: params.reversible ?? true,
      },
    });
  } catch (e: any) {
    console.error('[moderation] audit failed:', e.message);
  }
}
