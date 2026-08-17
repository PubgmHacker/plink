// src/services/moderation/moderationPolicy.ts — GPT-5.6 §14
export const MODERATION_POLICY_VERSION = '1.0.0';

export type ModerationDecision =
  | { action: 'allow' }
  | { action: 'warn'; reasonCode: string }
  | { action: 'hide_pending_review'; reasonCode: string; ttlSeconds: number }
  | { action: 'quarantine_link'; reasonCode: string }
  | { action: 'escalate'; reasonCode: string; queue: 'safety-critical' }
  | { action: 'suggest_host_action'; suggested: 'mute' | 'remove' | 'slow_mode'; reasonCode: string };

export const FLOOD_RATE_LIMIT = { max: 5, windowMs: 10_000 };
export const HARASSMENT_HIDE_TTL = 15 * 60;
export const SCAM_URL_PATTERNS = [/bit\.ly/i, /tinyurl/i, /t\.me/i, /wa\.me/i];
