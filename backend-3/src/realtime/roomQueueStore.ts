// src/realtime/roomQueueStore.ts — M17: очередь видео комнаты (Redis — источник истины).
// ИИ-ассистент реально ставит ролики в очередь. Очередь переживает
// редеплой через Redis (TTL 24ч). Без Redis — fail-open в память процесса.
//
// Аудит 26.07.2026 P2: раньше память была ПЕРВИЧНОЙ (`const mem = queues.get(roomId);
// if (mem) return mem;`) и никогда не инвалидировалась — вторая реплика писала
// в Redis, а первая вечно отдавала свой кэш. Плюс enqueue был неатомарным
// read-modify-write: два конкурентных POST теряли элемент. Теперь все мутации
// выполняются одним EVAL на стороне Redis, а Map остаётся только аварийным
// хранилищем на случай, когда Redis не настроен/недоступен.

import { redis } from '../config/redis.js';

export type QueuedMedia = {
  id: string;
  title: string;
  streamURL: string;
  source: string;
  addedBy: string;
  addedAtMs: number;
  /** M18: Plink+ приоритет — элемент встаёт впереди обычных. */
  priority?: boolean;
};

/** Маркер wire-сообщения очереди (едет по чат-протоколу, как poll/mod). */
export const QUEUE_WIRE_MARKER = '\u2063plink.queue\u2063';

const MAX_QUEUE = 50;
const QUEUE_TTL_SECONDS = 60 * 60 * 24; // комнаты эфемерны — суток достаточно
/** Аварийный кэш: используется, только если Redis не настроен или упал. */
const fallbackQueues = new Map<string, QueuedMedia[]>();
/**
 * Ревью P2: элементы, которые не доехали до Redis из-за сбоя. Роут уже ответил
 * 201 и разослал очередь участникам, поэтому просто потерять их при первом
 * успешном чтении (оно перезаписывает fallbackQueues данными из Redis) нельзя —
 * досылаем при первой же удачной операции и подмешиваем в чтение до тех пор.
 */
const pendingEnqueues = new Map<string, QueuedMedia[]>();

const redisKey = (roomId: string) => `roomqueue:${roomId}`;

// ── Lua: атомарные мутации очереди ───────────────────────────────────────────
// Очередь хранится как JSON-массив в одном ключе, поэтому весь
// read-modify-write выполняется внутри одного EVAL — конкурентные POST-ы
// больше не теряют элементы.
//
// ENQUEUE: KEYS[1] = roomqueue:<roomId>
//          ARGV[1] = JSON элемента, ARGV[2] = MAX_QUEUE, ARGV[3] = TTL сек
const ENQUEUE = `
local raw = redis.call('GET', KEYS[1])
local queue = {}
if raw then
  local ok, decoded = pcall(cjson.decode, raw)
  if ok and type(decoded) == 'table' then queue = decoded end
end
local entry = cjson.decode(ARGV[1])
local maxQueue = tonumber(ARGV[2])
while #queue >= maxQueue do
  table.remove(queue, 1)
end
if entry.priority then
  local insertAt = #queue + 1
  for i = 1, #queue do
    if not queue[i].priority then
      insertAt = i
      break
    end
  end
  table.insert(queue, insertAt, entry)
else
  table.insert(queue, entry)
end
local encoded = cjson.encode(queue)
redis.call('SET', KEYS[1], encoded, 'EX', tonumber(ARGV[3]))
return encoded
`;

// MUTATE: удаление или промоут элемента.
//   KEYS[1] = roomqueue:<roomId>
//   ARGV[1] = itemId, ARGV[2] = 'remove' | 'promote', ARGV[3] = TTL сек
const MUTATE = `
local raw = redis.call('GET', KEYS[1])
if not raw then return '[]' end
local ok, queue = pcall(cjson.decode, raw)
if not ok or type(queue) ~= 'table' then
  redis.call('DEL', KEYS[1])
  return '[]'
end
local itemId = ARGV[1]
if ARGV[2] == 'remove' then
  -- Ревью P2: id элемента приходит от клиента, дубликаты создаются тривиально,
  -- поэтому вычищаем ВСЕ совпадения (как делал старый .filter) — иначе после
  -- DELETE чип остаётся в ленте очереди.
  for i = #queue, 1, -1 do
    if queue[i].id == itemId then
      table.remove(queue, i)
    end
  end
else
  local idx = nil
  for i = 1, #queue do
    if queue[i].id == itemId then
      idx = i
      break
    end
  end
  if idx and idx > 1 then
    local item = table.remove(queue, idx)
    table.insert(queue, 1, item)
  end
end
if #queue == 0 then
  redis.call('DEL', KEYS[1])
  return '[]'
end
local encoded = cjson.encode(queue)
redis.call('SET', KEYS[1], encoded, 'EX', tonumber(ARGV[3]))
return encoded
`;

function parseQueue(raw: string | null): QueuedMedia[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as QueuedMedia[]) : [];
  } catch {
    return [];
  }
}

/** Запомнить элемент, не доехавший до Redis, для последующей досылки. */
function rememberPending(roomId: string, entry: QueuedMedia): void {
  const pending = pendingEnqueues.get(roomId) ?? [];
  pending.push(entry);
  while (pending.length > MAX_QUEUE) pending.shift();
  pendingEnqueues.set(roomId, pending);
}

/** Досылка в Redis элементов, записанных во время сбоя. Никогда не бросает. */
async function flushPendingEnqueues(roomId: string): Promise<void> {
  const pending = pendingEnqueues.get(roomId);
  if (!redis || !pending || pending.length === 0) return;
  for (let i = 0; i < pending.length; i++) {
    try {
      await redis.eval(
        ENQUEUE,
        1,
        redisKey(roomId),
        JSON.stringify(pending[i]),
        String(MAX_QUEUE),
        String(QUEUE_TTL_SECONDS),
      );
    } catch (e: any) {
      // Redis всё ещё недоступен — неотправленный хвост ждёт следующего раза.
      pendingEnqueues.set(roomId, pending.slice(i));
      console.warn('[roomQueue] pending flush failed:', e?.message || e);
      return;
    }
  }
  pendingEnqueues.delete(roomId);
}

export async function getRoomQueue(roomId: string): Promise<QueuedMedia[]> {
  if (redis) {
    await flushPendingEnqueues(roomId);
    try {
      const queue = parseQueue(await redis.get(redisKey(roomId)));
      // Досылка не удалась — не теряем элементы, уже подтверждённые клиенту.
      const pending = pendingEnqueues.get(roomId);
      const merged = pending && pending.length > 0 ? [...queue, ...pending] : queue;
      // Держим аварийный кэш тёплым, но читаем всегда из Redis.
      fallbackQueues.set(roomId, merged);
      return merged;
    } catch {
      /* fail-open: Redis недоступен — отвечаем из памяти процесса */
    }
  }
  return fallbackQueues.get(roomId) ?? [];
}

export async function enqueueRoomMedia(
  roomId: string,
  item: Omit<QueuedMedia, 'addedAtMs'>,
): Promise<QueuedMedia[]> {
  const entry: QueuedMedia = { ...item, addedAtMs: Date.now() };
  if (redis) {
    await flushPendingEnqueues(roomId);
    try {
      const encoded = (await redis.eval(
        ENQUEUE,
        1,
        redisKey(roomId),
        JSON.stringify(entry),
        String(MAX_QUEUE),
        String(QUEUE_TTL_SECONDS),
      )) as string;
      const queue = parseQueue(encoded);
      fallbackQueues.set(roomId, queue);
      return queue;
    } catch (e: any) {
      console.warn('[roomQueue] enqueue via Redis failed, using memory:', e?.message || e);
      // Ревью P2: роут ответит 201 и разошлёт очередь, поэтому элемент обязан
      // доехать до Redis позже — иначе первый же getRoomQueue его сотрёт.
      rememberPending(roomId, entry);
    }
  }
  return enqueueInMemory(roomId, entry);
}

export async function dequeueRoomMedia(roomId: string, itemId: string): Promise<QueuedMedia[]> {
  return mutateRoomQueue(roomId, itemId, 'remove');
}

/** M17: переместить элемент в начало очереди («включить сейчас»). */
export async function promoteRoomMedia(roomId: string, itemId: string): Promise<QueuedMedia[]> {
  return mutateRoomQueue(roomId, itemId, 'promote');
}

async function mutateRoomQueue(
  roomId: string,
  itemId: string,
  op: 'remove' | 'promote',
): Promise<QueuedMedia[]> {
  // Удаляемый элемент мог ещё не доехать до Redis — убираем его и из досылки,
  // иначе flush вернёт удалённый элемент обратно в очередь.
  if (op === 'remove') {
    const pending = pendingEnqueues.get(roomId);
    if (pending?.some((p) => p.id === itemId)) {
      const left = pending.filter((p) => p.id !== itemId);
      if (left.length > 0) pendingEnqueues.set(roomId, left);
      else pendingEnqueues.delete(roomId);
    }
  }
  if (redis) {
    await flushPendingEnqueues(roomId);
    try {
      const encoded = (await redis.eval(
        MUTATE,
        1,
        redisKey(roomId),
        itemId,
        op,
        String(QUEUE_TTL_SECONDS),
      )) as string;
      const queue = parseQueue(encoded);
      fallbackQueues.set(roomId, queue);
      return queue;
    } catch (e: any) {
      console.warn(`[roomQueue] ${op} via Redis failed, using memory:`, e?.message || e);
    }
  }
  let queue = [...(fallbackQueues.get(roomId) ?? [])];
  if (op === 'remove') {
    // Та же семантика, что в Lua: вычищаем все элементы с этим id.
    queue = queue.filter((q) => q.id !== itemId);
  } else {
    const idx = queue.findIndex((q) => q.id === itemId);
    if (idx > 0) {
      const [item] = queue.splice(idx, 1);
      queue.unshift(item);
    }
  }
  fallbackQueues.set(roomId, queue);
  return queue;
}

/** Вставка в аварийный кэш с той же семантикой приоритета, что и в Lua. */
function enqueueInMemory(roomId: string, entry: QueuedMedia): QueuedMedia[] {
  const queue = [...(fallbackQueues.get(roomId) ?? [])];
  while (queue.length >= MAX_QUEUE) queue.shift();
  if (entry.priority) {
    // M18: Plink+ приоритет — после других приоритетных, но впереди обычных (FIFO внутри классов)
    let insertAt = queue.length;
    for (let i = 0; i < queue.length; i++) {
      if (!queue[i].priority) {
        insertAt = i;
        break;
      }
    }
    queue.splice(insertAt, 0, entry);
  } else {
    queue.push(entry);
  }
  fallbackQueues.set(roomId, queue);
  return queue;
}

export async function clearRoomQueue(roomId: string): Promise<void> {
  fallbackQueues.delete(roomId);
  pendingEnqueues.delete(roomId);
  if (!redis) return;
  try {
    await redis.del(redisKey(roomId));
  } catch { /* noop */ }
}

/** Wire-пейлоад для broadcast очереди всем участникам комнаты. */
export function buildQueueWirePayload(
  queue: QueuedMedia[],
  nowPlaying: QueuedMedia | null = null,
): string {
  return QUEUE_WIRE_MARKER + JSON.stringify(nowPlaying ? { queue, nowPlaying } : { queue });
}
