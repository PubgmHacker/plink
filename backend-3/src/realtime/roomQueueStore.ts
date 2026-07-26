// src/realtime/roomQueueStore.ts — M17: очередь видео комнаты (Redis write-through + память).
// ИИ-ассистент реально ставит ролики в очередь. M17: очередь переживает
// редеплой через Redis (TTL 24ч), память — горячий кэш. Без Redis — fail-open в память.

import { cacheGet, cacheSet, cacheDel } from '../config/redis.js';

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
const queues = new Map<string, QueuedMedia[]>();

const redisKey = (roomId: string) => `roomqueue:${roomId}`;

export async function getRoomQueue(roomId: string): Promise<QueuedMedia[]> {
  const mem = queues.get(roomId);
  if (mem) return mem;
  try {
    const cached = await cacheGet<QueuedMedia[]>(redisKey(roomId));
    if (Array.isArray(cached)) {
      queues.set(roomId, cached);
      return cached;
    }
  } catch { /* fail-open: без Redis работаем из памяти */ }
  return [];
}

async function persist(roomId: string, queue: QueuedMedia[]): Promise<QueuedMedia[]> {
  queues.set(roomId, queue);
  try {
    await cacheSet(redisKey(roomId), queue, QUEUE_TTL_SECONDS);
  } catch { /* fail-open */ }
  return queue;
}

export async function enqueueRoomMedia(
  roomId: string,
  item: Omit<QueuedMedia, 'addedAtMs'>,
): Promise<QueuedMedia[]> {
  const queue = [...(await getRoomQueue(roomId))];
  if (queue.length >= MAX_QUEUE) queue.shift();
  const entry: QueuedMedia = { ...item, addedAtMs: Date.now() };
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
  return persist(roomId, queue);
}

export async function dequeueRoomMedia(roomId: string, itemId: string): Promise<QueuedMedia[]> {
  const queue = (await getRoomQueue(roomId)).filter((q) => q.id !== itemId);
  return persist(roomId, queue);
}

/** M17: переместить элемент в начало очереди («включить сейчас»). */
export async function promoteRoomMedia(roomId: string, itemId: string): Promise<QueuedMedia[]> {
  const queue = [...(await getRoomQueue(roomId))];
  const idx = queue.findIndex((q) => q.id === itemId);
  if (idx > 0) {
    const [item] = queue.splice(idx, 1);
    queue.unshift(item);
  }
  return persist(roomId, queue);
}

export async function clearRoomQueue(roomId: string): Promise<void> {
  queues.delete(roomId);
  try {
    await cacheDel(redisKey(roomId));
  } catch { /* noop */ }
}

/** Wire-пейлоад для broadcast очереди всем участникам комнаты. */
export function buildQueueWirePayload(
  queue: QueuedMedia[],
  nowPlaying: QueuedMedia | null = null,
): string {
  return QUEUE_WIRE_MARKER + JSON.stringify(nowPlaying ? { queue, nowPlaying } : { queue });
}
