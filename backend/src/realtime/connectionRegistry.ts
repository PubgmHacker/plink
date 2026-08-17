// src/realtime/connectionRegistry.ts — Local socket registry (runbook §5)
//
// Tracks which WebSocket connections are currently in which room ON THIS REPLICA.
// This is the local fanout target for both:
//   - direct broadcasts (chat, reactions)
//   - RoomPubSub-driven fanout (sync.state from another replica)
//
// NOTE: this is per-process state. Cross-replica fanout happens via Redis
// Pub/Sub (roomPubSub.ts). The registry's only job is to know which sockets
// on THIS process are in which room, and to broadcast to them efficiently.

import type { WebSocket } from 'ws';
import type { ServerMessage } from '../contracts/realtime-v2.js';

export interface PlinkSocket extends WebSocket {
  userId?: string;
  username?: string;
  role?: string;
  activeRoomId?: string;
  isAlive?: boolean;
  // P0-25: presence lease connectionId — set after bumpRoomPresence,
  // used by heartbeat to refresh lease via refreshPresenceLease().
  connectionId?: string;
  _rateBuckets?: Map<string, { count: number; resetAt: number }>;
  // Аудит 26.07.2026 P2: учёт пропущенных из-за backpressure отправок.
  // Пассивный зритель ничего не шлёт, поэтому входящий checkSlowConsumer
  // (messageRouter) его не отсекает — считаем пропуски здесь.
  _dropStreak?: number;
  _dropSince?: number;
  // Ревью P2: время последнего пропуска — нужно, чтобы отличить непрерывный
  // затык от двух пропусков, разделённых минутой тишины в комнате.
  _lastDropAt?: number;
}

export class ConnectionRegistry {
  // roomId → set of sockets on this replica in that room
  private readonly rooms = new Map<string, Set<PlinkSocket>>();
  // userId → set of sockets (one user can have multiple devices)
  private readonly userSockets = new Map<string, Set<PlinkSocket>>();

  join(socket: PlinkSocket, roomId: string): void {
    // Leave any previous room first (§19: leave старой room при switch)
    if (socket.activeRoomId && socket.activeRoomId !== roomId) {
      this.leave(socket, socket.activeRoomId);
    }
    socket.activeRoomId = roomId;
    let set = this.rooms.get(roomId);
    if (!set) {
      set = new Set();
      this.rooms.set(roomId, set);
    }
    set.add(socket);

    if (socket.userId) {
      let userSet = this.userSockets.get(socket.userId);
      if (!userSet) {
        userSet = new Set();
        this.userSockets.set(socket.userId, userSet);
      }
      userSet.add(socket);
    }
  }

  leave(socket: PlinkSocket, roomId: string): void {
    const set = this.rooms.get(roomId);
    if (set) {
      set.delete(socket);
      if (set.size === 0) this.rooms.delete(roomId);
    }
    if (socket.activeRoomId === roomId) {
      socket.activeRoomId = undefined;
    }
  }

  disconnect(socket: PlinkSocket): void {
    if (socket.activeRoomId) {
      this.leave(socket, socket.activeRoomId);
    }
    if (socket.userId) {
      const userSet = this.userSockets.get(socket.userId);
      if (userSet) {
        userSet.delete(socket);
        if (userSet.size === 0) this.userSockets.delete(socket.userId);
      }
    }
  }

  /**
   * Get all sockets in a room on this replica.
   * Optionally exclude a sender (for chat/reaction broadcasts).
   */
  getRoomSockets(roomId: string, exclude?: PlinkSocket): PlinkSocket[] {
    const set = this.rooms.get(roomId);
    if (!set) return [];
    const out: PlinkSocket[] = [];
    for (const s of set) {
      if (s === exclude) continue;
      out.push(s);
    }
    return out;
  }

  /** Check if a user has any other connections on this replica. */
  hasOtherConnections(userId: string, exclude: PlinkSocket): boolean {
    const userSet = this.userSockets.get(userId);
    if (!userSet) return false;
    for (const s of userSet) {
      if (s !== exclude) return true;
    }
    return false;
  }

  /**
   * Register a user-level socket (DM '@me' channel — no room binding).
   * Cleanup happens via disconnect(), which already removes userSockets.
   */
  registerUser(socket: PlinkSocket): void {
    if (!socket.userId) return;
    let userSet = this.userSockets.get(socket.userId);
    if (!userSet) {
      userSet = new Set();
      this.userSockets.set(socket.userId, userSet);
    }
    userSet.add(socket);
  }

  /**
   * Send an arbitrary event to all of a user's sockets on this replica.
   * DM events are intentionally outside the room ServerMessage union.
   */
  sendToUser(userId: string, payload: unknown): number {
    const userSet = this.userSockets.get(userId);
    if (!userSet || userSet.size === 0) return 0;
    const encoded = JSON.stringify(payload);
    let sent = 0;
    for (const s of userSet) {
      if (this.trySend(s, encoded)) sent++;
    }
    return sent;
  }

  /**
   * Broadcast a typed ServerMessage to all sockets in a room on this replica.
   * Excludes the sender if provided.
   */
  broadcastLocal(roomId: string, msg: ServerMessage, exclude?: PlinkSocket): void {
    const sockets = this.getRoomSockets(roomId, exclude);
    if (sockets.length === 0) return;
    const encoded = JSON.stringify(msg);
    for (const s of sockets) {
      this.trySend(s, encoded);
    }
  }

  // ── Аудит 26.07.2026 P2: backpressure с эвикцией ────────────────────────
  // Раньше сокет с bufferedAmount > 256KB просто пропускался (continue) и
  // навсегда оставался в комнате, тихо теряя sync.state и чат: входящий
  // checkSlowConsumer к нему не применялся, потому что зритель ничего не
  // шлёт. Теперь считаем подряд идущие пропуски и длительность непрерывного
  // backpressure — при превышении порога закрываем сокет, клиент
  // переподключится и заберёт снапшот.
  private static readonly BACKPRESSURE_BYTES = 256 * 1024;
  private static readonly MAX_DROP_STREAK = 20;
  private static readonly MAX_BACKPRESSURE_MS = 15_000;
  // Ревью P2: _dropSince сбрасывался только при УСПЕШНОЙ отправке, а попытки
  // происходят лишь при броадкасте. В тихой комнате между двумя пропусками
  // проходили десятки секунд, и второй же пропуск давал stuckMs >= 15s —
  // здоровый клиент вылетал с 1011. Серия считается прерванной, если между
  // пропусками была пауза длиннее этого окна.
  private static readonly DROP_STREAK_GAP_MS = 5_000;

  /** Отправить, если сокет успевает читать. true — сообщение ушло. */
  private trySend(socket: PlinkSocket, encoded: string): boolean {
    if (socket.readyState !== socket.OPEN) return false;
    const buffered = (socket.bufferedAmount ?? 0) as number;
    if (buffered > ConnectionRegistry.BACKPRESSURE_BYTES) {
      const now = Date.now();
      const lastDropAt = socket._lastDropAt;
      if (lastDropAt === undefined || now - lastDropAt > ConnectionRegistry.DROP_STREAK_GAP_MS) {
        // Пропуски шли не подряд — начинаем новую серию.
        socket._dropStreak = 0;
        socket._dropSince = now;
      }
      socket._lastDropAt = now;
      socket._dropStreak = (socket._dropStreak ?? 0) + 1;
      if (socket._dropSince === undefined) socket._dropSince = now;
      const stuckMs = now - socket._dropSince;
      if (
        socket._dropStreak >= ConnectionRegistry.MAX_DROP_STREAK ||
        stuckMs >= ConnectionRegistry.MAX_BACKPRESSURE_MS
      ) {
        console.warn(
          `[ConnectionRegistry] slow consumer evicted: user=${socket.userId} room=${socket.activeRoomId} ` +
            `buffered=${buffered} skipped=${socket._dropStreak} stuckMs=${stuckMs}`,
        );
        socket._dropStreak = 0;
        socket._dropSince = undefined;
        socket._lastDropAt = undefined;
        try {
          socket.close(1011, 'Slow consumer');
        } catch {
          /* сокет уже рвётся — cleanup сделает finalize по 'close' */
        }
      }
      return false;
    }
    // Сокет разгрузился — сбрасываем счётчики.
    socket._dropStreak = 0;
    socket._dropSince = undefined;
    socket._lastDropAt = undefined;
    socket.send(encoded);
    return true;
  }

  /** Total connections on this replica (for metrics). */
  get totalConnections(): number {
    let count = 0;
    for (const set of this.rooms.values()) count += set.size;
    return count;
  }
  /** Number of rooms with at least one local connection. */
  get activeRooms(): number {
    return this.rooms.size;
  }
}
