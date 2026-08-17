// Lightweight chat moderation for closed beta (no external API).
// Blocks obvious slurs / spam; not a full moderation suite.

const BLOCKED = [
  // RU/EN sample blocklist — expand via admin blocklist later
  /\b(пидор|пидар|nigga|nigger|faggot|сука\s*бля)\b/iu,
  /(.)\1{12,}/u, // aaaaaaaaaaaa spam
  /(https?:\/\/|www\.)\S{40,}/iu, // long link spam
];

export type ChatFilterResult =
  | { ok: true; text: string }
  | { ok: false; reason: string };

export function filterChatMessage(raw: string): ChatFilterResult {
  const text = String(raw ?? '').trim();
  if (!text) return { ok: false, reason: 'Empty message' };
  if (text.length > 2000) return { ok: false, reason: 'Message too long' };
  for (const re of BLOCKED) {
    if (re.test(text)) {
      return { ok: false, reason: 'Message blocked by moderation' };
    }
  }
  return { ok: true, text };
}
