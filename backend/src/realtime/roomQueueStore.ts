// Очередь видео комнаты (Redis — источник истины).
// ИИ-ассистент реально ставит ролики в очередь. Очередь переживает
// редеплой через Redis (TTL 24ч). Без Redis — fail-open в память процесса.
//
// Раньше память была ПЕРВИЧНОЙ (`const mem = queues.get(roomId);
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
  /* * Plink+ приоритет — элемент встаёт впереди обычных. */
  priority?: boolean;
};

/** Маркер wire-сообщения очереди (едет по чат-протоколу, как poll/mod). */
export const QUEUE_WIRE_MARKER = '\u2063plink.queue\u2063';

const MAX_QUEUE = 50;
const QUEUE_TTL_SECONDS = 60 * 60 * 24; // комнаты эфемерны — суток достаточно
/** Emergency cache, used only when Redis is unconfigured or down. */
const fallbackQueues = new Map<string, QueuedMedia[]>();
/**
 * Items that never reached Redis because a write failed. The route has already
 * answered 201 and broadcast the queue to participants, so they cannot simply be
 * dropped by the first successful read (which overwrites fallbackQueues with
 * whatever Redis holds). They are replayed on the next successful operation and
 * merged into reads until then.
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

// REORDER: хост присылает желаемый порядок id.
//   KEYS[1] = roomqueue:<roomId>
//   ARGV[1] = JSON-массив id, ARGV[2] = TTL сек
//
// Порядок применяется как ПЕРЕСТАНОВКА существующих элементов, а не как замена
// очереди целиком: пока хост тянул строку, кто-то мог добавить или удалить
// ролик. Элементы из присланного списка встают в заданном порядке, всё, чего в
// списке нет, дописывается в конец в исходном порядке — так гонка не приводит к
// потере чужого добавления и не воскрешает удалённое.
const REORDER = `
local raw = redis.call('GET', KEYS[1])
if not raw then return '[]' end
local ok, queue = pcall(cjson.decode, raw)
if not ok or type(queue) ~= 'table' then
  redis.call('DEL', KEYS[1])
  return '[]'
end
local okIds, ids = pcall(cjson.decode, ARGV[1])
if not okIds or type(ids) ~= 'table' then return cjson.encode(queue) end

local byId = {}
for i = 1, #queue do
  byId[queue[i].id] = queue[i]
end

local result = {}
local taken = {}
for i = 1, #ids do
  local id = ids[i]
  local item = byId[id]
  if item and not taken[id] then
    taken[id] = true
    table.insert(result, item)
  end
end
-- Хвост: то, что появилось в очереди уже после снимка на клиенте.
for i = 1, #queue do
  if not taken[queue[i].id] then
    table.insert(result, queue[i])
  end
end

if #result == 0 then
  redis.call('DEL', KEYS[1])
  return '[]'
end
local encoded = cjson.encode(result)
redis.call('SET', KEYS[1], encoded, 'EX', tonumber(ARGV[2]))
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

// Обе Map жили без эвикции: ключ на каждую когда-либо жившую комнату, до
// 50 элементов с URL в каждом — за месяцы аптайма это утечка. Пустая очередь
// теперь удаляет ключ (обычный финал комнаты), а на потолке вытесняется
// самая давняя по записи комната (delete→set держит Map в порядке свежести).
const FALLBACK_MAX_ROOMS = 500;

function setFallback(roomId: string, queue: QueuedMedia[]): void {
  fallbackQueues.delete(roomId);
  if (queue.length === 0) return;
  if (fallbackQueues.size >= FALLBACK_MAX_ROOMS) {
    const oldest = fallbackQueues.keys().next().value;
    if (oldest !== undefined) fallbackQueues.delete(oldest);
  }
  setFallback(roomId, queue);
}

function setPending(roomId: string, items: QueuedMedia[]): void {
  pendingEnqueues.delete(roomId);
  if (items.length === 0) return;
  if (pendingEnqueues.size >= FALLBACK_MAX_ROOMS) {
    const oldest = pendingEnqueues.keys().next().value;
    if (oldest !== undefined) {
      // Здесь теряются подтверждённые клиенту элементы — это плата за потолок
      // памяти при многочасовом отказе Redis. Громко, чтобы было видно в логах.
      console.warn('[roomQueue] pending overflow, dropping room', oldest);
      pendingEnqueues.delete(oldest);
    }
  }
  pendingEnqueues.set(roomId, items);
}

/** Запомнить элемент, не доехавший до Redis, для последующей досылки. */
function rememberPending(roomId: string, entry: QueuedMedia): void {
  const pending = pendingEnqueues.get(roomId) ?? [];
  pending.push(entry);
  while (pending.length > MAX_QUEUE) pending.shift();
  setPending(roomId, pending);
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
      setPending(roomId, pending.slice(i));
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
      setFallback(roomId, merged);
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
      setFallback(roomId, queue);
      return queue;
    } catch (e: any) {
      console.warn('[roomQueue] enqueue via Redis failed, using memory:', e?.message || e);
      // The route answers 201 and broadcasts the queue, so this entry has to
      // reach Redis eventually or the next getRoomQueue erases it.
      rememberPending(roomId, entry);
    }
  }
  return enqueueInMemory(roomId, entry);
}

export async function dequeueRoomMedia(roomId: string, itemId: string): Promise<QueuedMedia[]> {
  return mutateRoomQueue(roomId, itemId, 'remove');
}

/* * переместить элемент в начало очереди («включить сейчас»). */
export async function promoteRoomMedia(roomId: string, itemId: string): Promise<QueuedMedia[]> {
  return mutateRoomQueue(roomId, itemId, 'promote');
}

/**
 * Переставить элементы очереди в порядке `orderedIds`.
 *
 * Присланный список — не замена очереди, а перестановка: неизвестные id
 * игнорируются, а элементы, которых нет в списке (кто-то добавил, пока хост
 * тянул строку), дописываются в конец. Так одновременное добавление не
 * теряется, а удалённое не воскресает.
 */
export async function reorderRoomQueue(
  roomId: string,
  orderedIds: string[],
): Promise<QueuedMedia[]> {
  if (redis) {
    await flushPendingEnqueues(roomId);
    try {
      const encoded = (await redis.eval(
        REORDER,
        1,
        redisKey(roomId),
        JSON.stringify(orderedIds),
        String(QUEUE_TTL_SECONDS),
      )) as string;
      const queue = parseQueue(encoded);
      setFallback(roomId, queue);
      return queue;
    } catch (e: any) {
      console.warn('[roomQueue] reorder via Redis failed, using memory:', e?.message || e);
    }
  }
  // Аварийный путь повторяет ту же семантику, что и Lua выше.
  const current = fallbackQueues.get(roomId) ?? [];
  const byId = new Map(current.map((i) => [i.id, i]));
  const taken = new Set<string>();
  const result: QueuedMedia[] = [];
  for (const id of orderedIds) {
    const item = byId.get(id);
    if (item && !taken.has(id)) {
      taken.add(id);
      result.push(item);
    }
  }
  for (const item of current) {
    if (!taken.has(item.id)) result.push(item);
  }
  setFallback(roomId, result);
  return result;
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
      setPending(
        roomId,
        pending.filter((p) => p.id !== itemId),
      );
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
      setFallback(roomId, queue);
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
  setFallback(roomId, queue);
  return queue;
}

/** Вставка в аварийный кэш с той же семантикой приоритета, что и в Lua. */
function enqueueInMemory(roomId: string, entry: QueuedMedia): QueuedMedia[] {
  const queue = [...(fallbackQueues.get(roomId) ?? [])];
  while (queue.length >= MAX_QUEUE) queue.shift();
  if (entry.priority) {
    // Plink+ приоритет — после других приоритетных, но впереди обычных (FIFO внутри классов)
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
  setFallback(roomId, queue);
  return queue;
}

export async function clearRoomQueue(roomId: string): Promise<void> {
  fallbackQueues.delete(roomId);
  pendingEnqueues.delete(roomId);
  if (!redis) return;
  try {
    await redis.del(redisKey(roomId));
  } catch {
    /* noop */
  }
}

/** Wire-пейлоад для broadcast очереди всем участникам комнаты. */
export function buildQueueWirePayload(
  queue: QueuedMedia[],
  nowPlaying: QueuedMedia | null = null,
): string {
  return QUEUE_WIRE_MARKER + JSON.stringify(nowPlaying ? { queue, nowPlaying } : { queue });
}
