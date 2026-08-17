// src/services/moderation/moderationEngine.ts — GPT-5.6 §15
import { ModerationDecision, FLOOD_RATE_LIMIT, HARASSMENT_HIDE_TTL, SCAM_URL_PATTERNS, MODERATION_POLICY_VERSION } from './moderationPolicy.js';
import { recordModerationAudit } from './moderationAudit.js';
import crypto from 'crypto';

const userMessageTimestamps = new Map<string, number[]>();

export function evaluateMessage(params: {
  roomId: string; messageId: string; userId: string; text: string;
}): ModerationDecision {
  const { roomId, messageId, userId, text } = params;
  const now = Date.now();
  const timestamps = userMessageTimestamps.get(userId) ?? [];
  const recent = timestamps.filter(t => now - t < FLOOD_RATE_LIMIT.windowMs);
  recent.push(now);
  userMessageTimestamps.set(userId, recent);
  if (recent.length > FLOOD_RATE_LIMIT.max) {
    void recordAudit(roomId, messageId, userId, 'warn', 'flood');
    return { action: 'warn', reasonCode: 'flood' };
  }
  for (const pattern of SCAM_URL_PATTERNS) {
    if (pattern.test(text)) {
      void recordAudit(roomId, messageId, userId, 'quarantine_link', 'scam_url');
      return { action: 'quarantine_link', reasonCode: 'scam_url' };
    }
  }
  const harassmentPatterns = [/kill yourself/i, /go die/i];
  for (const pattern of harassmentPatterns) {
    if (pattern.test(text)) {
      void recordAudit(roomId, messageId, userId, 'hide_pending_review', 'harassment');
      return { action: 'hide_pending_review', reasonCode: 'harassment', ttlSeconds: HARASSMENT_HIDE_TTL };
    }
  }
  const threatPatterns = [/i will find you/i, /i will hurt you/i];
  for (const pattern of threatPatterns) {
    if (pattern.test(text)) {
      void recordAudit(roomId, messageId, userId, 'escalate', 'threat');
      return { action: 'escalate', reasonCode: 'threat', queue: 'safety-critical' };
    }
  }
  return { action: 'allow' };
}

async function recordAudit(roomId: string, messageId: string, userId: string, action: string, reasonCode: string) {
  const evidenceHash = crypto.createHash('sha256').update(`${roomId}:${messageId}:${userId}`).digest('hex');
  await recordModerationAudit({
    roomId, messageId, subjectUserId: userId, action, reasonCode,
    policyVersion: MODERATION_POLICY_VERSION, evidenceHash, reversible: true,
  });
}
