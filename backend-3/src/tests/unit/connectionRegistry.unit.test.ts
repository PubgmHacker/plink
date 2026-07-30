// src/tests/unit/connectionRegistry.unit.test.ts
// Аудит 26.07.2026 P2: broadcastLocal раньше молча пропускал сокеты с
// bufferedAmount > 256KB и никогда их не закрывал — пассивный зритель навсегда
// оставался в комнате, теряя sync.state и чат (входящий checkSlowConsumer к нему
// не применялся, потому что он ничего не отправляет). Здесь проверяем эвикцию.

import { describe, it, expect } from 'vitest';
import { ConnectionRegistry, type PlinkSocket } from '../../realtime/connectionRegistry.js';
import type { ServerMessage } from '../../contracts/realtime-v2.js';

const ROOM_ID = '00000000-0000-4000-8000-0000000000aa';

const MSG: ServerMessage = {
  type: 'error',
  protocolVersion: 2,
  code: 'TEST',
  message: 'test',
};

type FakeSocket = PlinkSocket & {
  sent: string[];
  closes: Array<{ code: number; reason: string }>;
};

function makeSocket(bufferedAmount = 0): FakeSocket {
  const socket = {
    OPEN: 1,
    readyState: 1,
    bufferedAmount,
    userId: 'user-1',
    sent: [] as string[],
    closes: [] as Array<{ code: number; reason: string }>,
    send(data: string) {
      this.sent.push(data);
    },
    close(code: number, reason: string) {
      this.closes.push({ code, reason });
    },
  };
  return socket as unknown as FakeSocket;
}

describe('ConnectionRegistry.broadcastLocal — slow consumer', () => {
  it('delivers to a socket that keeps up', () => {
    const registry = new ConnectionRegistry();
    const socket = makeSocket(0);
    registry.join(socket, ROOM_ID);

    registry.broadcastLocal(ROOM_ID, MSG);

    expect(socket.sent.length).toBe(1);
    expect(socket.closes.length).toBe(0);
  });

  it('closes a backpressured socket after N consecutive skips', () => {
    const registry = new ConnectionRegistry();
    const socket = makeSocket(300 * 1024); // > 256KB — не успевает читать
    registry.join(socket, ROOM_ID);

    for (let i = 0; i < 20; i++) {
      registry.broadcastLocal(ROOM_ID, MSG);
    }

    expect(socket.sent.length).toBe(0);
    expect(socket.closes).toEqual([{ code: 1011, reason: 'Slow consumer' }]);
  });

  it('does not close while backpressure is short-lived', () => {
    const registry = new ConnectionRegistry();
    const socket = makeSocket(300 * 1024);
    registry.join(socket, ROOM_ID);

    for (let i = 0; i < 5; i++) {
      registry.broadcastLocal(ROOM_ID, MSG);
    }
    expect(socket.closes.length).toBe(0);

    // Сокет разгрузился — счётчик пропусков должен обнулиться.
    (socket as any).bufferedAmount = 0;
    registry.broadcastLocal(ROOM_ID, MSG);
    expect(socket.sent.length).toBe(1);
    expect(socket._dropStreak).toBe(0);

    (socket as any).bufferedAmount = 300 * 1024;
    for (let i = 0; i < 5; i++) {
      registry.broadcastLocal(ROOM_ID, MSG);
    }
    expect(socket.closes.length).toBe(0);
  });

  it('closes a socket stuck in backpressure longer than the time budget', () => {
    const registry = new ConnectionRegistry();
    const socket = makeSocket(300 * 1024);
    registry.join(socket, ROOM_ID);

    registry.broadcastLocal(ROOM_ID, MSG);
    expect(socket.closes.length).toBe(0);
    // Имитируем непрерывный backpressure на 20 секунд.
    socket._dropSince = Date.now() - 20_000;

    registry.broadcastLocal(ROOM_ID, MSG);

    expect(socket.closes).toEqual([{ code: 1011, reason: 'Slow consumer' }]);
  });

  // Ревью P2: в тихой комнате пропуски могут стоять в десятках секунд друг от
  // друга — это не «непрерывный затык», выкидывать клиента нельзя.
  it('does not evict when skips are separated by long silence', () => {
    const registry = new ConnectionRegistry();
    const socket = makeSocket(300 * 1024);
    registry.join(socket, ROOM_ID);

    registry.broadcastLocal(ROOM_ID, MSG);
    expect(socket.closes.length).toBe(0);
    // 20 секунд тишины между броадкастами: серия прервана.
    socket._dropSince = Date.now() - 20_000;
    socket._lastDropAt = Date.now() - 20_000;

    registry.broadcastLocal(ROOM_ID, MSG);

    expect(socket.closes.length).toBe(0);
    expect(socket._dropStreak).toBe(1);
  });
});
