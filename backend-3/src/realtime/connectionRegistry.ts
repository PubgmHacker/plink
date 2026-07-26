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
      if (s.readyState !== s.OPEN) continue;
      if ((s.bufferedAmount ?? 0) > 256 * 1024) continue;
      s.send(encoded);
      sent++;
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
      if (s.readyState !== s.OPEN) continue;
      // Slow consumer guard — don't add to a backpressured socket
      if ((s.bufferedAmount ?? 0) > 256 * 1024) continue;
      s.send(encoded);
    }
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
