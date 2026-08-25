// src/routes/ai.ts — Pack 6: AI Assistant endpoint + P0.4 action confirmation
import crypto from 'node:crypto';
import { prisma } from '../config/db.js';
import { logAudit, AuditActions } from '../utils/audit.js';
import { redis } from '../config/redis.js';
// Реальная очередь комнаты — ИИ ставит видео по-настоящему, а не шаблоном
import { enqueueRoomMedia, buildQueueWirePayload } from '../realtime/roomQueueStore.js';

const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;
const AI_MODEL = process.env.AI_MODEL ?? 'openai/gpt-4o-mini';
const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';

// Feature flag for AI structured actions.
// Set AI_ACTIONS_ENABLED=true to enable proposedAction creation.
// Until function/tool calling is implemented, this stays false for external beta.
const AI_ACTIONS_ENABLED = process.env.AI_ACTIONS_ENABLED !== 'false'; // enabled by default when OPENROUTER_API_KEY is set

// Pending AI actions в Redis с TTL.
// Fallback на in-memory Map если Redis не настроен (dev only).
interface PendingAction {
  confirmationId: string;
  userId: string;
  type: string;  // 'create_room' | 'build_queue' | 'get_friend_activity'
  payload: any;
  createdAt: number;
  expiresAt: number;
}

const ACTION_TTL_SECONDS = 5 * 60;  // 5 minutes
const ACTION_KEY_PREFIX = 'plink:ai_action:';

// In-memory fallback (dev only)
const pendingActionsFallback = new Map<string, PendingAction>();

async function savePendingAction(action: PendingAction): Promise<void> {
  if (redis) {
    await redis.set(
      ACTION_KEY_PREFIX + action.confirmationId,
      JSON.stringify(action),
      'EX',
      ACTION_TTL_SECONDS
    );
  } else {
    pendingActionsFallback.set(action.confirmationId, action);
    // Schedule cleanup
    setTimeout(() => {
      pendingActionsFallback.delete(action.confirmationId);
    }, ACTION_TTL_SECONDS * 1000).unref?.();
  }
}

async function getPendingAction(confirmationId: string): Promise<PendingAction | null> {
  if (redis) {
    const data = await redis.get(ACTION_KEY_PREFIX + confirmationId);
    if (!data) return null;
    return JSON.parse(data);
  } else {
    const action = pendingActionsFallback.get(confirmationId);
    if (!action) return null;
    if (action.expiresAt < Date.now()) {
      pendingActionsFallback.delete(confirmationId);
      return null;
    }
    return action;
  }
}

async function deletePendingAction(confirmationId: string): Promise<void> {
  if (redis) {
    // Atomic consume: use GETDEL if available (Redis 6.2+), else GET + DEL
    await redis.del(ACTION_KEY_PREFIX + confirmationId);
  } else {
    pendingActionsFallback.delete(confirmationId);
  }
}

// Atomic consume — returns the action if it exists and belongs to user,
// then deletes it. Prevents race conditions on concurrent confirm.
async function consumePendingAction(confirmationId: string, userId: string): Promise<PendingAction | null> {
  if (redis) {
    // Use Lua script for atomic get-check-delete
    const script = `
      local data = redis.call('GET', KEYS[1])
      if not data then return nil end
      local action = cjson.decode(data)
      if action.userId ~= ARGV[1] then return false end
      redis.call('DEL', KEYS[1])
      return data
    `;
    const result = await redis.eval(script, 1, ACTION_KEY_PREFIX + confirmationId, userId);
    if (result === null) return null;
    if (result === false) return false as any;  // wrong user
    return JSON.parse(result as string);
  } else {
    const action = pendingActionsFallback.get(confirmationId);
    if (!action) return null;
    if (action.userId !== userId) return false as any;
    pendingActionsFallback.delete(confirmationId);
    return action;
  }
}

// P1 5.11: дневной лимит ИИ для бесплатного тарифа. Plink+ — без дневного
// лимита (остаётся только общий 30/мин). Счётчик в памяти — как rlMap в
// security.ts: сбрасывается при рестарте, для MVP этого достаточно.
const AI_FREE_DAILY_LIMIT = 20;
const aiDailyUsage = new Map<string, { count: number; day: string }>();

function aiFreeQuotaExceeded(userId: string): boolean {
  const day = new Date().toISOString().slice(0, 10);
  const entry = aiDailyUsage.get(userId);
  if (!entry || entry.day !== day) {
    aiDailyUsage.set(userId, { count: 1, day });
    return false;
  }
  if (entry.count >= AI_FREE_DAILY_LIMIT) return true;
  entry.count++;
  return false;
}

setInterval(() => {
  const day = new Date().toISOString().slice(0, 10);
  for (const [k, v] of aiDailyUsage) if (v.day !== day) aiDailyUsage.delete(k);
}, 3600_000).unref?.();

export default async function aiRoutes(fastify) {

  // POST /api/ai/chat — universal AI assistant
  fastify.post('/ai/chat', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 30, timeWindow: '1 minute' } }
  }, async (request, reply) => {
    // P1 5.11: бесплатный тариф — AI_FREE_DAILY_LIMIT запросов в сутки.
    {
      const requester = await prisma.user.findUnique({
        where: { id: request.user.id },
        select: { isPremium: true, premiumUntil: true },
      });
      const now = new Date();
      const premiumActive = !!requester?.isPremium
        && (!requester.premiumUntil || requester.premiumUntil > now);
      if (!premiumActive && aiFreeQuotaExceeded(request.user.id)) {
        return reply.status(429).send({
          error: 'Дневной лимит ИИ на бесплатном тарифе исчерпан. Plink+ снимает лимит.',
          code: 'AI_DAILY_LIMIT',
          limit: AI_FREE_DAILY_LIMIT,
        });
      }
    }
    const body = (request.body ?? {}) as {
      messages?: Array<{ role?: string; content?: string }>;
      message?: string;
      context?: {
        mediaItem?: unknown;
        title?: string;
        url?: string;
        roomName?: string;
        [key: string]: unknown;
      };
      mode?: string;
    };
    // Compat: desktop/Android may send { message: "..." } instead of messages[]
    let messages = body.messages;
    if ((!messages || !Array.isArray(messages) || messages.length === 0) && typeof body.message === 'string' && body.message.trim()) {
      messages = [{ role: 'user', content: body.message.trim() }];
    }
    const context = body.context ?? {};
    const mode = body.mode ?? 'default';
    
    if (!OPENROUTER_API_KEY) {
      return reply.status(503).send({ 
        error: 'AI not configured. Set OPENROUTER_API_KEY env var.' 
      });
    }
    
    if (!messages || !Array.isArray(messages) || messages.length === 0) {
      return reply.status(400).send({ error: 'Messages array required' });
    }
    
    // System prompt depends on mode
    const systemPrompt = buildSystemPrompt(mode, context, request.user);
    
    try {
      const response = await fetch(OPENROUTER_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${OPENROUTER_API_KEY}`,
          'HTTP-Referer': 'https://plink.app',
          'X-Title': 'Plink AI Assistant',
        },
        // LLM может думать долго, но не бесконечно: зависший OpenRouter не
        // должен держать HTTP-хендлер (и слот rate-limit клиента) вечно.
        signal: AbortSignal.timeout(30_000),
        body: JSON.stringify({
          model: AI_MODEL,
          messages: [
            { role: 'system', content: systemPrompt },
            ...messages,
          ],
          temperature: 0.7,
          max_tokens: 1000,
        }),
      });
      
      if (!response.ok) {
        const errText = await response.text();
        console.error('OpenRouter error', response.status, errText);
        return reply.status(response.status).send({ 
          error: 'AI request failed',
          details: errText,
        });
      }
      
      const data: any = await response.json();
      const aiMessage = data.choices?.[0]?.message?.content || '';

      // Detect an action intent in the model's reply — asking it to create a
      // room makes it mention "create_room" — and turn that into a pending
      // action the user has to confirm.
      //
      // Gated behind AI_ACTIONS_ENABLED, which defaults to off: this is a
      // keyword match on model output, so it must not act on its own.
      let proposedAction: any = null;
      const lowerMsg = aiMessage.toLowerCase();

      if (AI_ACTIONS_ENABLED && lowerMsg.includes('созда') && (lowerMsg.includes('комнат') || lowerMsg.includes('room'))) {
        // AI wants to create a room — create pending action
        const confirmationId = crypto.randomUUID();
        const mediaItem: { id: string; title: string; streamURL: string; source: string } =
          (context.mediaItem as { id?: string; title?: string; streamURL?: string; source?: string } | undefined) &&
          typeof context.mediaItem === 'object'
            ? {
                id: String((context.mediaItem as any).id ?? 'youtube_search'),
                title: String((context.mediaItem as any).title ?? context.title ?? 'AI suggested content'),
                streamURL: String((context.mediaItem as any).streamURL ?? context.url ?? ''),
                source: String((context.mediaItem as any).source ?? 'youtube'),
              }
            : {
                id: 'youtube_search',
                title: context.title || 'AI suggested content',
                streamURL: context.url || '',
                source: 'youtube',
              };
        const action: PendingAction = {
          confirmationId,
          userId: request.user.id,
          type: 'create_room',
          payload: {
            name: context.roomName || `${request.user.username}'s room`,
            mediaItem,
            privacy: 'public',
            maxParticipants: 10,
          },
          createdAt: Date.now(),
          expiresAt: Date.now() + ACTION_TTL_SECONDS * 1000,
        };
        await savePendingAction(action);
        proposedAction = {
          type: 'create_room',
          confirmationId,
          expiresAt: new Date(action.expiresAt).toISOString(),
          payloadPreview: {
            title: action.payload.name,
            privacy: 'public',
            maxParticipants: 10,
            mediaTitle: mediaItem.title,
          }
        };
      }

      // Реальная постановка видео в очередь комнаты (не шаблонный ответ!)
      const lastUserText = String(
        [...(messages ?? [])].reverse().find((m: any) => m?.role === 'user')?.content ?? ''
      ).toLowerCase();
      const wantsQueue = /очеред|поставь|добавь|queue/.test(lastUserText) || lowerMsg.includes('очеред');
      if (AI_ACTIONS_ENABLED && !proposedAction && context?.roomId && wantsQueue) {
        const confirmationId = crypto.randomUUID();
        const rawItem: any =
          context.mediaItem && typeof context.mediaItem === 'object' ? context.mediaItem : {};
        const queueItem = {
          id: String(rawItem.id ?? crypto.randomUUID()),
          title: String(rawItem.title ?? context.title ?? 'Видео от Plink AI'),
          streamURL: String(rawItem.streamURL ?? context.url ?? ''),
          source: String(rawItem.source ?? 'youtube'),
        };
        const action: PendingAction = {
          confirmationId,
          userId: request.user.id,
          type: 'queue_video',
          payload: { roomId: String(context.roomId), mediaItem: queueItem },
          createdAt: Date.now(),
          expiresAt: Date.now() + ACTION_TTL_SECONDS * 1000,
        };
        await savePendingAction(action);
        proposedAction = {
          type: 'queue_video',
          confirmationId,
          expiresAt: new Date(action.expiresAt).toISOString(),
          payloadPreview: {
            roomId: String(context.roomId),
            mediaTitle: queueItem.title,
          },
        };
      }

      reply.send({
        message: aiMessage,
        model: data.model,
        usage: data.usage,
        proposedAction,
      });
    } catch (e: any) {
      console.error('AI chat error', e);
      reply.status(500).send({ error: 'AI request failed: ' + e.message });
    }
  });
  
  // ─────────────────────────────────────────────────────────────────────
  // POST /api/ai/room-recap — «что я пропустил» для опоздавшего.
  // ─────────────────────────────────────────────────────────────────────
  // Пересказывает пропущенный кусок ЧАТА комнаты. Ответ ПРИВАТНЫЙ (в HTTP),
  // в чат комнаты ничего не публикуется: рекап нужен одному опоздавшему,
  // остальные ничего не пропускали, и спамить им «краткое содержание
  // предыдущих серий» — способ отучить людей от фичи.
  //
  // Источник — только реальная переписка из БД: сервисные wire-сообщения
  // (очередь, отсчёт — маркер \u2063plink.*) отфильтровываются, скрытые
  // модерацией (hidden) не выбираются вовсе. ИИ прямо запрещено выдумывать
  // события вне переданной переписки.
  fastify.post('/ai/room-recap', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 6, timeWindow: '1 minute' } }
  }, async (request, reply) => {
    // Та же тарифная логика, что у /ai/chat: Plink+ без дневного лимита.
    {
      const requester = await prisma.user.findUnique({
        where: { id: request.user.id },
        select: { isPremium: true, premiumUntil: true },
      });
      const now = new Date();
      const premiumActive = !!requester?.isPremium
        && (!requester.premiumUntil || requester.premiumUntil > now);
      if (!premiumActive && aiFreeQuotaExceeded(request.user.id)) {
        return reply.status(429).send({
          error: 'Дневной лимит ИИ на бесплатном тарифе исчерпан. Plink+ снимает лимит.',
          code: 'AI_DAILY_LIMIT',
          limit: AI_FREE_DAILY_LIMIT,
        });
      }
    }

    const body = (request.body ?? {}) as { roomId?: string; sinceMs?: number };
    const roomId = typeof body.roomId === 'string' ? body.roomId : '';
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(roomId)) {
      return reply.status(400).send({ error: 'roomId (uuid) обязателен' });
    }

    // Членство — рекап чужой комнаты равен чтению её переписки.
    const isMember = await prisma.roomParticipant.findFirst({
      where: { roomID: roomId, userID: request.user.id },
    });
    if (!isMember) {
      return reply.status(403).send({ error: 'Вы не участник комнаты' });
    }

    if (!OPENROUTER_API_KEY) {
      return reply.status(503).send({ error: 'AI not configured. Set OPENROUTER_API_KEY env var.' });
    }

    // Окно: не старше 4 часов (дальше это не «догнать», а «пересмотреть»),
    // не свежее 30 секунд (там нечего пересказывать).
    const nowMs = Date.now();
    const rawSince = typeof body.sinceMs === 'number' && Number.isFinite(body.sinceMs)
      ? body.sinceMs
      : nowMs - 30 * 60_000;
    const sinceMs = Math.min(Math.max(rawSince, nowMs - 4 * 3600_000), nowMs - 30_000);
    const windowMinutes = Math.max(1, Math.round((nowMs - sinceMs) / 60_000));

    const rows = await prisma.chatMessage.findMany({
      where: { roomID: roomId, hidden: false, createdAt: { gt: new Date(sinceMs) } },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
      take: 200,
      select: { senderID: true, text: true, createdAt: true },
    });

    // Wire-пейлоады (очередь, отсчёт) — служебный JSON с маркером
    // "\u2063plink.": человеку в пересказе они не нужны.
    const humanRows = rows.filter((r) => !r.text.includes('\u2063plink.'));

    if (humanRows.length === 0) {
      return reply.send({ recap: null, messageCount: 0, windowMinutes });
    }

    const senderIds = [...new Set(humanRows.map((r) => r.senderID))];
    const senders = await prisma.user.findMany({
      where: { id: { in: senderIds } },
      select: { id: true, username: true },
    });
    const nameById = new Map(senders.map((s) => [s.id, s.username]));

    // Свежие сообщения важнее старых: если переписка не влезает в бюджет,
    // режем с НАЧАЛА окна, а не с конца.
    const lines: string[] = [];
    let budget = 2800;
    for (let i = humanRows.length - 1; i >= 0; i--) {
      const row = humanRows[i];
      const line = `${nameById.get(row.senderID) ?? 'участник'}: ${row.text.slice(0, 280)}`;
      if (budget - line.length < 0) break;
      budget -= line.length + 1;
      lines.unshift(line);
    }

    const room = await prisma.room.findUnique({
      where: { id: roomId },
      select: { name: true, mediaItem: true },
    });
    let mediaTitle = '';
    try {
      const media = room?.mediaItem ? JSON.parse(room.mediaItem) : null;
      if (media?.title) mediaTitle = String(media.title).slice(0, 120);
    } catch { /* mediaItem бывает строкой не-JSON — тогда без названия */ }

    const systemPrompt =
      'Ты — ИИ-компаньон Plink в комнате совместного просмотра. Участник отсутствовал ' +
      `${windowMinutes} мин и просит краткий пересказ пропущенной переписки. ` +
      'Перескажи в 2–5 предложениях: о чём говорили, о чём договорились, что решили смотреть. ' +
      'Опирайся ТОЛЬКО на переданные сообщения — не выдумывай событий и не пересказывай сюжет фильма. ' +
      'Отвечай на языке, на котором ведётся переписка.';
    const userPrompt =
      (room?.name ? `Комната: «${room.name}». ` : '') +
      (mediaTitle ? `Сейчас смотрят: «${mediaTitle}». ` : '') +
      `Пропущенная переписка (${humanRows.length} сообщений):\n${lines.join('\n')}`;

    try {
      const response = await fetch(OPENROUTER_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${OPENROUTER_API_KEY}`,
          'HTTP-Referer': 'https://plink.app',
          'X-Title': 'Plink AI Recap',
        },
        signal: AbortSignal.timeout(30_000),
        body: JSON.stringify({
          model: AI_MODEL,
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: userPrompt },
          ],
          temperature: 0.4,
          max_tokens: 350,
        }),
      });

      if (!response.ok) {
        const errText = await response.text();
        console.error('OpenRouter recap error', response.status, errText);
        return reply.status(502).send({ error: 'AI request failed' });
      }

      const data: any = await response.json();
      const recap = String(data.choices?.[0]?.message?.content ?? '').trim();
      return reply.send({
        recap: recap || null,
        messageCount: humanRows.length,
        windowMinutes,
      });
    } catch (e: any) {
      console.error('AI recap error', e);
      return reply.status(500).send({ error: 'AI request failed: ' + e.message });
    }
  });

  // POST /api/ai/recommend — recommend movies/shows based on mood
  fastify.post('/ai/recommend', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } }
  }, async (request, reply) => {
    const { mood, genre, service } = request.body;
    
    if (!OPENROUTER_API_KEY) {
      return reply.status(503).send({ error: 'AI not configured' });
    }
    
    const prompt = buildRecommendationPrompt(mood, genre, service);
    
    try {
      const response = await fetch(OPENROUTER_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${OPENROUTER_API_KEY}`,
          'HTTP-Referer': 'https://plink.app',
          'X-Title': 'Plink AI',
        },
        signal: AbortSignal.timeout(30_000),
        body: JSON.stringify({
          model: AI_MODEL,
          messages: [
            { role: 'system', content: 'You are a movie/TV recommendation expert. Return JSON only.' },
            { role: 'user', content: prompt },
          ],
          temperature: 0.8,
          max_tokens: 800,
          response_format: { type: 'json_object' },
        }),
      });
      
      if (!response.ok) {
        return reply.status(response.status).send({ error: 'AI request failed' });
      }
      
      const data: any = await response.json();
      const content = data.choices?.[0]?.message?.content || '{}';
      
      try {
        const parsed = JSON.parse(content);
        reply.send(parsed);
      } catch {
        reply.send({ recommendations: [], raw: content });
      }
    } catch (e: any) {
      reply.status(500).send({ error: 'AI request failed: ' + e.message });
    }
  });

  // ─────────────────────────────────────────────────────────────────────
  // P0.4: POST /api/ai/confirm-action
  // ─────────────────────────────────────────────────────────────────────
  // Confirms a pending AI action by confirmationId. Executes the action
  // server-side (create room, build queue, etc.). Idempotent — each
  // confirmationId can only be executed once. Audit-logged.
  fastify.post('/ai/confirm-action', {
    preHandler: [fastify.authenticate],
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } }
  }, async (request, reply) => {
    const { confirmationId, idempotencyKey } = request.body;

    if (!confirmationId) {
      return reply.status(400).send({ error: 'confirmationId required' });
    }

    // Get, verify ownership, and delete in one Redis operation. Split into
    // separate calls, two concurrent confirmations both pass the ownership
    // check and the action runs twice.
    const action = await consumePendingAction(confirmationId, request.user.id);

    if (action === null) {
      return reply.status(404).send({ error: 'Action not found or expired' });
    }

    if (action === false as any) {
      return reply.status(403).send({ error: 'Action belongs to another user' });
    }

    // Verify not expired (Redis TTL handles this, but double-check)
    if (action.expiresAt < Date.now()) {
      return reply.status(410).send({ error: 'Action expired' });
    }

    try {
      switch (action.type) {
        case 'create_room': {
          const { name, mediaItem, privacy, maxParticipants } = action.payload;
          const room = await prisma.room.create({
            data: {
              name: name || 'AI Room',
              hostID: request.user.id,
              hostName: request.user.username,
              code: generateRoomCode(),
              mediaItem: mediaItem ? JSON.stringify(mediaItem) : null,
              maxParticipants: maxParticipants || 10,
              privacy: privacy || 'public',
            }
          });

          await prisma.roomParticipant.create({
            data: { roomID: room.id, userID: request.user.id }
          });

          await logAudit({
            userId: request.user.id,
            action: 'room.create',
            ip: request.ip,
            metadata: { roomId: room.id, source: 'ai_confirm', confirmationId }
          });

          return reply.send({ success: true, room });
        }

        case 'get_friend_activity': {
          // Return friend activity data (already fetched in payload)
          return reply.send({ success: true, activity: action.payload.activity });
        }

        // Реальная постановка в очередь комнаты + broadcast всем участникам
        case 'queue_video': {
          const { roomId, mediaItem } = action.payload;
          const isMember = await prisma.roomParticipant.findFirst({
            where: { roomID: roomId, userID: request.user.id },
          });
          if (!isMember) {
            return reply.status(403).send({ error: 'Вы не участник комнаты' });
          }
          // Plink+ — приоритет в очереди ИИ (функциональная фича подписки)
          const requester = await prisma.user.findUnique({
            where: { id: request.user.id },
            select: { isPremium: true },
          });
          const queue = await enqueueRoomMedia(roomId, {
            id: String(mediaItem?.id ?? crypto.randomUUID()),
            title: String(mediaItem?.title ?? 'Видео'),
            streamURL: String(mediaItem?.streamURL ?? ''),
            source: String(mediaItem?.source ?? 'youtube'),
            addedBy: request.user.username ?? 'Plink AI',
            priority: Boolean(requester?.isPremium),
          });
          try {
            await (fastify as any).gateway?.publishChatMessage?.({
              kind: 'chat.broadcast' as const,
              roomId,
              messageId: crypto.randomUUID(),
              clientMessageId: crypto.randomUUID(),
              senderId: 'plink-ai',
              senderName: 'Plink AI',
              text: buildQueueWirePayload(queue),
              createdAtMs: Date.now(),
            });
          } catch { /* noop */ }
          await logAudit({
            userId: request.user.id,
            action: 'room.queue.add',
            ip: request.ip,
            metadata: { roomId, source: 'ai_confirm', confirmationId },
          });
          return reply.send({ success: true, queue });
        }

        case 'build_queue': {
          // Queue built from payload
          return reply.send({ success: true, queue: action.payload.queue });
        }

        default:
          return reply.status(400).send({ error: `Unknown action type: ${action.type}` });
      }
    } catch (e: any) {
      console.error('[ai/confirm-action] Execution failed:', e);
      return reply.status(500).send({ error: 'Action execution failed: ' + e.message });
    }
  });
}

// У ai.ts был собственный генератор с полным алфавитом —
// комната, созданная через ИИ, могла получить код с I/O/0/1, которые главный
// генератор (rooms.ts) сознательно исключает, чтобы код диктовался голосом
// без ошибок. Плюс Math.random() вместо crypto. Приведено к rooms.ts.
function generateRoomCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = crypto.randomBytes(6);
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars[bytes[i] % chars.length];
  }
  return code;
}

function buildSystemPrompt(mode: string, context: any, user: any): string {
  const base = `You are Plink AI Assistant — a friendly helper inside Plink, an app for watching movies and shows together with friends in real-time.

User context:
- Username: ${user.username}
- Language: detect from user message and respond in same language
- Be concise but warm. Use emojis occasionally. Don't be overly formal.

`;
  
  switch (mode) {
    case 'room_host':
      return base + `The user is hosting a watch party. Help them with:
- Setting up the room
- Choosing what to watch
- Solving sync issues
- Inviting friends
Context: ${JSON.stringify(context || {})}`;
      
    case 'movie_search':
      return base + `The user is looking for something to watch. Help them:
- Suggest movies/shows based on their mood
- Find content available on streaming services
- Give brief descriptions without spoilers
Context: ${JSON.stringify(context || {})}`;
      
    case 'general':
    default:
      return base + `Help the user with any question about Plink, movies, or general chat. Be helpful and friendly.`;
  }
}

function buildRecommendationPrompt(mood: string, genre: string, service: string): string {
  return `Suggest 5 movies or shows to watch with friends.

Criteria:
- Mood: ${mood || 'any'}
- Genre: ${genre || 'any'}
- Available on: ${service || 'any streaming service'}
- Good for group watching

Return JSON in this exact format:
{
  "recommendations": [
    {
      "title": "Movie Name",
      "year": 2024,
      "genre": "Comedy",
      "service": "Netflix",
      "reason": "Why it's good for groups (1 sentence)",
      "rating": 8.5
    }
  ]
}`;
}
