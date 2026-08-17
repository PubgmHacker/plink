// M16: AI-модератор — единое ядро автомодерации для чата комнат, лички и создания комнат.
// - маты → временный мут (60с, эскалация до 10 мин при рецидивах)
// - NSFW-фото → мут 10 мин + скрытие сообщения
// - запрещённый контент в названиях/ссылках комнат → блокировка создания
// Аудит пишется в AIModerationAudit (уже есть в схеме).

import { prisma } from '../config/db.js';

export const MOD_POLICY_VERSION = 'm16-automod-1';

// ── Профанация (RU/EN). Корневые формы + обходы через повторы/разделители не ловим — это бета.
const PROFANITY_PATTERNS: RegExp[] = [
  /(?:^|[^а-яёа-яё])(?:ху[йяеиюё]|пизд|[её]ба[нтл]|[её]буч|еблан|бля[дтьс]|бля\b|муда[кц]|гандон|гондон|шлюх|долбо[её]б|залуп|пидор|пидар|херня|сука|сучк)/iu,
  /\b(?:fuck|fucking|motherfucker|shit|bitch|cunt|whore|slut|asshole|dickhead|faggot|nigger|nigga)\b/i,
];

// ── Запрещённый контент (порнография/нелегал) — для названий комнат, ссылок и тайтлов медиа.
const FORBIDDEN_CONTENT_PATTERNS: RegExp[] = [
  /\b(?:porn|porno|pornhub|xvideos|xnxx|xhamster|redtube|youporn|brazzers|onlyfans|rule34|hentai|xxx|18\+)\b/i,
  /порно|порнух|хентай|эротик/iu,
  // CSAM / насилие — жёсткий блок
  /\bcp\b.{0,12}(?:video|видео)|child\s*porn|детское\s*порн|цп\s*видео/iu,
  /\b(?:rape|beastiality|zoofil|zoophil)\b|изнасил|зоофил/iu,
  /\b(?:buy|sell)\s+(?:drugs|cocaine|heroin)\b|купить\s+(?:нарко|меф|героин)/iu,
];

/** Снять транспортные маркеры Plink ([[bs:...]], невидимые разделители) перед анализом. */
export function stripTransportMarkers(raw: string): string {
  let text = String(raw ?? '');
  const bs = text.match(/^\[\[bs:[A-Za-z0-9_-]{1,64}\]\]/);
  if (bs) text = text.slice(bs[0].length);
  return text.replace(/\u2063/g, ' ');
}

export function containsProfanity(raw: string): boolean {
  const text = stripTransportMarkers(raw);
  return PROFANITY_PATTERNS.some((re) => re.test(text));
}

export function violatesContentPolicy(raw: string): boolean {
  const text = stripTransportMarkers(raw);
  return FORBIDDEN_CONTENT_PATTERNS.some((re) => re.test(text));
}

// ── Муты (in-memory; Railway — один инстанс; при рестарте муты сгорают — приемлемо для МВП)

type MuteEntry = { until: number; reason: string; strikes: number };
const mutes = new Map<string, MuteEntry>();
const strikes = new Map<string, { count: number; windowStart: number }>();

const STRIKE_WINDOW_MS = 10 * 60_000;
const PRUNE_INTERVAL_MS = 60_000;
let lastPruneAt = 0;

function muteKey(scope: string, userId: string): string {
  return `${scope}::${userId}`;
}

/**
 * Ленивая чистка in-memory карт: истёкшие муты и страйки за пределами окна.
 * Без страйков ключи вида `group:<uuid>::<userId>` копились до рестарта процесса.
 * Специально без setInterval — таймер держал бы event loop (graceful shutdown/тесты).
 */
function pruneExpired(now: number): void {
  if (now - lastPruneAt < PRUNE_INTERVAL_MS) return;
  lastPruneAt = now;
  for (const [key, entry] of mutes) {
    if (entry.until <= now) mutes.delete(key);
  }
  for (const [key, s] of strikes) {
    if (now - s.windowStart >= STRIKE_WINDOW_MS) strikes.delete(key);
  }
}

/** Замутить. Эскалация: 1-й страйк 60с, 2-й — 3 мин, 3+ — 10 мин (в окне 10 мин). */
export function muteUser(scope: string, userId: string, reason: string, baseSeconds = 60): number {
  const key = muteKey(scope, userId);
  const now = Date.now();
  pruneExpired(now);
  const s = strikes.get(key);
  let count = 1;
  if (s && now - s.windowStart < STRIKE_WINDOW_MS) count = s.count + 1;
  strikes.set(key, { count, windowStart: s && now - s.windowStart < STRIKE_WINDOW_MS ? s.windowStart : now });
  const seconds = count >= 3 ? 600 : count === 2 ? 180 : baseSeconds;
  mutes.set(key, { until: now + seconds * 1000, reason, strikes: count });
  return seconds;
}

/** Остаток мута в секундах (0 — не замучен). */
export function muteRemainingSec(scope: string, userId: string): number {
  const key = muteKey(scope, userId);
  const now = Date.now();
  pruneExpired(now);
  const entry = mutes.get(key);
  if (!entry) return 0;
  const remaining = Math.ceil((entry.until - now) / 1000);
  if (remaining <= 0) {
    mutes.delete(key);
    const s = strikes.get(key);
    if (s && now - s.windowStart >= STRIKE_WINDOW_MS) strikes.delete(key);
    return 0;
  }
  return remaining;
}

/** Только для тестов/диагностики: размер in-memory карт автомодерации. */
export function __automodMapSizes(): { mutes: number; strikes: number } {
  return { mutes: mutes.size, strikes: strikes.size };
}

// ── NSFW-проверка фото через vision-модель OpenRouter (fail-open при отсутствии ключа/таймауте).

const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';
const NSFW_MODEL = process.env.AI_NSFW_MODEL || process.env.AI_MODEL || 'openai/gpt-4o-mini';

export type ImageModerationResult = { nsfw: boolean; checked: boolean };

export async function moderateImage(dataURL: string): Promise<ImageModerationResult> {
  const key = process.env.OPENROUTER_API_KEY;
  if (!key || !dataURL.startsWith('data:image/')) return { nsfw: false, checked: false };
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    const resp = await fetch(OPENROUTER_URL, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${key}`,
        'HTTP-Referer': 'https://plink.app',
        'X-Title': 'Plink AI Moderator',
      },
      body: JSON.stringify({
        model: NSFW_MODEL,
        max_tokens: 8,
        temperature: 0,
        messages: [
          {
            role: 'system',
            content:
              'You are a strict content moderator. Answer with exactly one word: UNSAFE if the image contains nudity, sexual content, pornography, gore, or content illegal to share; otherwise SAFE.',
          },
          {
            role: 'user',
            content: [
              { type: 'text', text: 'Classify this image.' },
              { type: 'image_url', image_url: { url: dataURL } },
            ],
          },
        ],
      }),
    });
    clearTimeout(timer);
    if (!resp.ok) return { nsfw: false, checked: false };
    const data: any = await resp.json();
    const answer = String(data.choices?.[0]?.message?.content ?? '').trim().toUpperCase();
    return { nsfw: answer.includes('UNSAFE'), checked: true };
  } catch {
    return { nsfw: false, checked: false };
  }
}

// ── Аудит

export async function auditModeration(args: {
  roomId: string;
  messageId: string;
  subjectUserId: string;
  action: string;
  reasonCode: string;
  confidence?: number;
}): Promise<void> {
  try {
    const { createHash } = await import('node:crypto');
    await prisma.aIModerationAudit.create({
      data: {
        roomId: args.roomId,
        messageId: args.messageId,
        subjectUserId: args.subjectUserId,
        action: args.action,
        reasonCode: args.reasonCode,
        confidence: args.confidence ?? null,
        policyVersion: MOD_POLICY_VERSION,
        modelVersion: null,
        evidenceHash: createHash('sha256').update(`${args.messageId}:${args.reasonCode}`).digest('hex'),
        reversible: true,
      },
    });
  } catch (e: any) {
    console.warn('[autoMod] audit failed:', e?.message);
  }
}

/** Сервисный маркер для системных сообщений ИИ-модератора в чате комнаты. */
export const MOD_WIRE_MARKER = '\u2063plink.mod\u2063';

export function buildModWirePayload(args: {
  action: 'mute';
  userId: string;
  username: string;
  seconds: number;
  reason: 'profanity' | 'nsfw_image';
}): string {
  return `${MOD_WIRE_MARKER}${JSON.stringify(args)}`;
}
