// Регрессия: setFallback вызывал сам себя вместо fallbackQueues.set — любая
// непустая очередь уходила в бесконечную рекурсию, и POST /rooms/:id/queue
// отвечал 500 «Maximum call stack size exceeded». Проверяем оба пути,
// которые трогают аварийный кэш: запись элемента и чтение очереди.
import { describe, it, expect } from 'vitest';

// roomQueueStore тянет config/redis.js, а config требует DATABASE_URL на
// импорте (та же причина, что в контрактных тестах). Ни к БД, ни к Redis
// эти проверки не ходят: без REDIS_URL стор работает по in-memory ветке —
// ровно по той, где и жила рекурсия.
process.env.DATABASE_URL ||= 'postgresql://test:test@localhost:5432/plink_test';
delete process.env.REDIS_URL;
const { enqueueRoomMedia, getRoomQueue, dequeueRoomMedia, promoteRoomMedia } = await import(
  '../../realtime/roomQueueStore.js'
);

const item = (id: string, priority = false) => ({
  id,
  title: `clip ${id}`,
  streamURL: `https://example.com/${id}.mp4`,
  source: 'direct',
  addedBy: 'testdev',
  ...(priority ? { priority: true } : {}),
});

describe('roomQueueStore fallback cache', () => {
  it('ставит элемент в очередь без переполнения стека', async () => {
    const room = `room-${Math.random().toString(36).slice(2)}`;
    const queue = await enqueueRoomMedia(room, item('a'));
    expect(queue).toHaveLength(1);
    expect(queue[0].id).toBe('a');
    expect(queue[0].addedAtMs).toBeTypeOf('number');
  });

  it('копит очередь и отдаёт её обратно из кэша', async () => {
    const room = `room-${Math.random().toString(36).slice(2)}`;
    await enqueueRoomMedia(room, item('a'));
    await enqueueRoomMedia(room, item('b'));
    const read = await getRoomQueue(room);
    expect(read.map((i) => i.id)).toEqual(['a', 'b']);
  });

  it('приоритетный элемент встаёт впереди обычных', async () => {
    const room = `room-${Math.random().toString(36).slice(2)}`;
    await enqueueRoomMedia(room, item('a'));
    await enqueueRoomMedia(room, item('plus', true));
    expect((await getRoomQueue(room)).map((i) => i.id)).toEqual(['plus', 'a']);
  });

  it('удаление и промоут не роняют кэш', async () => {
    const room = `room-${Math.random().toString(36).slice(2)}`;
    await enqueueRoomMedia(room, item('a'));
    await enqueueRoomMedia(room, item('b'));
    expect((await promoteRoomMedia(room, 'b')).map((i) => i.id)).toEqual(['b', 'a']);
    expect((await dequeueRoomMedia(room, 'b')).map((i) => i.id)).toEqual(['a']);
    expect(await dequeueRoomMedia(room, 'a')).toEqual([]);
  });
});
