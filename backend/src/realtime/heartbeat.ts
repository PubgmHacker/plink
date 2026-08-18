// src/realtime/heartbeat.ts — WS ping/pong heartbeat
//
// Heartbeat invariants:
//
// The presence lease is refreshed on pong through a callback — the gateway
//   passes onPong(socket), which calls refreshPresenceLease() with
//   socket.connectionId. Refreshes are coalesced to at most once per 20s so
//   that a pong does not cause a Redis write every time.
//
// On a dead socket the heartbeat only calls socket.terminate(); it never
//   calls registry.disconnect. finalize (registered via socket.once in the
//   gateway) handles ALL cleanup, including the registry disconnect.

import type { WebSocketServer } from 'ws';
import type { PlinkSocket } from './connectionRegistry.js';

const HEARTBEAT_INTERVAL_MS = 20_000;
export const TERMINATE_GRACE_MS = 35_000;

export interface HeartbeatCallbacks {
  /** Called when a pong is received — gateway refreshes presence lease. */
  onPong?: (socket: PlinkSocket) => void;
  /** Called when a socket is detected as dead — gateway does NOT need to
   * disconnect registry here; finalize handles it via the 'close' event. */
  onDead?: (socket: PlinkSocket) => void;
}

export class Heartbeat {
  private readonly interval: NodeJS.Timeout;
  private readonly callbacks: HeartbeatCallbacks;

  constructor(wss: WebSocketServer, callbacks: HeartbeatCallbacks = {}) {
    this.callbacks = callbacks;

    wss.on('connection', (socket: PlinkSocket) => {
      socket.isAlive = true;
      socket.on('pong', () => {
        socket.isAlive = true;
        // Refresh presence lease on pong
        try {
          this.callbacks.onPong?.(socket);
        } catch (err) {
          // Lease refresh failure must not crash heartbeat loop.
          console.warn('[Heartbeat] onPong callback error:', err);
        }
      });
    });

    this.interval = setInterval(() => {
      wss.clients.forEach((sock) => {
        const socket = sock as PlinkSocket;
        if (socket.isAlive === false) {
          // Only terminate — finalize (via 'close') does ALL cleanup.
          // Do NOT call registry.disconnect here — that's finalize's job.
          try {
            socket.terminate();
          } catch {}
          try {
            this.callbacks.onDead?.(socket);
          } catch {}
          return;
        }
        socket.isAlive = false;
        try {
          socket.ping();
        } catch {
          // socket already dead
        }
      });
    }, HEARTBEAT_INTERVAL_MS);
    this.interval.unref();
  }

  close(): void {
    clearInterval(this.interval);
  }
}

export type { PlinkSocket };
