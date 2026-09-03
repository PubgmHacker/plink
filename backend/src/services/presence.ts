// src/services/presence.ts — realtime presence + DB lastSeen for friends list
import type { WebSocket } from 'ws';
import { prisma } from '../config/db.js';
import { redis } from '../config/redis.js';

interface UserPresence {
  userId: string;
  username: string;
  lastSeen: number;
  rooms: Set<string>;
  typing: Map<string, number>;
}

/** Consider online if activity within this window (REST heartbeat / WS).
 *  ~10 min matches Telegram-ish “still around” feel; heartbeat is 30–60s. */
export const ONLINE_THRESHOLD_MS = 10 * 60 * 1000;

// DB writes are debounced: same-state refreshes (online → online) hit Postgres
// at most once per window. Every profile poll used to run an UPDATE — at 10k
// clients polling /users/me that alone is a constant write stream, and each
// deploy's reconnect storm doubled it. State CHANGES still write immediately.
const TOUCH_DEBOUNCE_MS = 60_000;
// Cross-replica online marker. Refreshed by connects/heartbeats/pongs,
// checked before writing isOnline=false: a disconnect on replica A must not
// mark a user offline while replica B still holds their live socket.
const MARKER_TTL_MS = 90_000;
const MARKER_DEBOUNCE_MS = 30_000;

async function touchUserDb(userId: string, online: boolean) {
  try {
    await prisma.user.update({
      where: { id: userId },
      data: {
        isOnline: online,
        lastSeenAt: new Date(),
      },
    });
  } catch (e: any) {
    // Schema drift: lastSeenAt may not exist until migrate — try isOnline only
    try {
      await prisma.user.update({
        where: { id: userId },
        data: { isOnline: online },
      });
    } catch {
      /* ignore */
    }
  }
}

class PresenceService {
  private users = new Map<string, UserPresence>();
  private sockets = new Map<WebSocket, string>();
  // userId → last DB touch (what + when); userId → last Redis marker refresh.
  private lastTouch = new Map<string, { at: number; online: boolean }>();
  private lastMarker = new Map<string, number>();

  private async touchDebounced(userId: string, online: boolean): Promise<void> {
    const now = Date.now();
    const prev = this.lastTouch.get(userId);
    if (prev && prev.online === online && now - prev.at < TOUCH_DEBOUNCE_MS) return;
    this.lastTouch.set(userId, { at: now, online });
    await touchUserDb(userId, online);
  }

  /** Fire-and-forget refresh of the cross-replica online marker. */
  private markOnline(userId: string): void {
    if (!redis) return;
    const now = Date.now();
    if (now - (this.lastMarker.get(userId) ?? 0) < MARKER_DEBOUNCE_MS) return;
    this.lastMarker.set(userId, now);
    void redis
      .set(`presence:online:${userId}`, String(now), 'PX', MARKER_TTL_MS)
      .catch(() => this.lastMarker.delete(userId));
  }

  /** A fresh marker written by ANOTHER replica's heartbeat means "still online". */
  private async isOnlineElsewhere(userId: string): Promise<boolean> {
    if (!redis) return false;
    try {
      return (await redis.exists(`presence:online:${userId}`)) === 1;
    } catch {
      // Redis down — can't tell; assume offline (same as pre-marker behavior).
      return false;
    }
  }

  connect(socket: WebSocket, userId: string, username: string) {
    let p = this.users.get(userId);
    if (!p) {
      p = {
        userId,
        username,
        lastSeen: Date.now(),
        rooms: new Set(),
        typing: new Map(),
      };
      this.users.set(userId, p);
    }
    p.lastSeen = Date.now();
    p.username = username || p.username;
    this.sockets.set(socket, userId);
    this.markOnline(userId);
    void this.touchDebounced(userId, true);
  }

  joinRoom(socket: WebSocket, roomId: string) {
    const userId = this.sockets.get(socket);
    if (!userId) return;
    this.users.get(userId)?.rooms.add(roomId);
  }

  leaveRoom(socket: WebSocket, roomId: string) {
    const userId = this.sockets.get(socket);
    if (!userId) return;
    const p = this.users.get(userId);
    if (!p) return;
    p.rooms.delete(roomId);
    p.typing.delete(roomId);
  }

  setTyping(socket: WebSocket, roomId: string) {
    const userId = this.sockets.get(socket);
    if (!userId) return;
    this.users.get(userId)?.typing.set(roomId, Date.now());
  }

  getTypingUsers(roomId: string): { userId: string; username: string }[] {
    const result: { userId: string; username: string }[] = [];
    const now = Date.now();
    for (const p of this.users.values()) {
      const t = p.typing.get(roomId);
      if (t && now - t < 3000) {
        result.push({ userId: p.userId, username: p.username });
      } else if (t) {
        p.typing.delete(roomId);
      }
    }
    return result;
  }

  getRoomUsers(roomId: string): { userId: string; username: string }[] {
    const result: { userId: string; username: string }[] = [];
    for (const p of this.users.values()) {
      if (p.rooms.has(roomId)) {
        result.push({ userId: p.userId, username: p.username });
      }
    }
    return result;
  }

  getOnlineUsers(): { userId: string; username: string }[] {
    return Array.from(this.users.values()).map((p) => ({
      userId: p.userId,
      username: p.username,
    }));
  }

  /** Live WS session for this user */
  isConnected(userId: string): boolean {
    return Array.from(this.sockets.values()).some((id) => id === userId);
  }

  getMemoryLastSeen(userId: string): number | null {
    return this.users.get(userId)?.lastSeen ?? null;
  }

  /**
   * REST/app heartbeat — marks user online in memory + DB without WS.
   */
  async restHeartbeat(userId: string, username?: string) {
    let p = this.users.get(userId);
    if (!p) {
      p = {
        userId,
        username: username || 'user',
        lastSeen: Date.now(),
        rooms: new Set(),
        typing: new Map(),
      };
      this.users.set(userId, p);
    }
    p.lastSeen = Date.now();
    if (username) p.username = username;
    this.markOnline(userId);
    await this.touchDebounced(userId, true);
  }

  disconnect(socket: WebSocket) {
    const userId = this.sockets.get(socket);
    if (!userId) return;
    const p = this.users.get(userId);
    if (p) p.lastSeen = Date.now();
    this.sockets.delete(socket);

    setTimeout(() => {
      const still = Array.from(this.sockets.values()).some((id) => id === userId);
      if (still) return;
      this.users.delete(userId);
      this.lastMarker.delete(userId);
      // Offline write only when no OTHER replica has refreshed the user's
      // marker — otherwise a rebalanced client flaps isOnline in the DB.
      void this.isOnlineElsewhere(userId).then((elsewhere) => {
        if (!elsewhere) void this.touchDebounced(userId, false);
      });
    }, 30_000);
  }

  heartbeat(socket: WebSocket) {
    const userId = this.sockets.get(socket);
    if (!userId) return;
    const p = this.users.get(userId);
    if (p) p.lastSeen = Date.now();
    // Long-lived WS (a 2h movie) sends no REST heartbeats — pongs are the only
    // thing keeping the cross-replica marker alive for these clients.
    this.markOnline(userId);
  }

  /** Deliver a JSON/string payload to all live sockets of a user (friend events). */
  sendToUser(userId: string, payload: string | object): number {
    const data = typeof payload === 'string' ? payload : JSON.stringify(payload);
    let n = 0;
    for (const [sock, uid] of this.sockets) {
      if (uid !== userId) continue;
      try {
        if (sock.readyState === 1 /* OPEN */) {
          sock.send(data);
          n += 1;
        }
      } catch {
        /* ignore dead socket */
      }
    }
    return n;
  }

  cleanup() {
    const now = Date.now();
    const TIMEOUT = 5 * 60 * 1000;
    for (const [userId, p] of this.users) {
      const still = Array.from(this.sockets.values()).some((id) => id === userId);
      if (!still && now - p.lastSeen > TIMEOUT) {
        this.users.delete(userId);
        this.lastMarker.delete(userId);
        void this.isOnlineElsewhere(userId).then((elsewhere) => {
          if (!elsewhere) void this.touchDebounced(userId, false);
        });
      }
    }
    // Debounce bookkeeping must not outlive the users it tracks.
    for (const [userId, t] of this.lastTouch) {
      if (now - t.at > ONLINE_THRESHOLD_MS) this.lastTouch.delete(userId);
    }
    for (const [userId, at] of this.lastMarker) {
      if (now - at > ONLINE_THRESHOLD_MS) this.lastMarker.delete(userId);
    }
  }
}

export const presence = new PresenceService();

setInterval(() => presence.cleanup(), 60_000).unref();

/** Resolve isOnline + lastSeenAt for a user row from DB + memory presence. */
export function resolvePresence(user: {
  id: string;
  isOnline?: boolean | null;
  lastSeenAt?: Date | string | null;
  updatedAt?: Date | string | null;
}): { isOnline: boolean; lastSeenAt: string | null } {
  const mem = presence.getMemoryLastSeen(user.id);
  const connected = presence.isConnected(user.id);
  const dbLast = user.lastSeenAt ? new Date(user.lastSeenAt).getTime() : 0;
  // Do NOT fall back to updatedAt — avatar uploads / profile edits inflate it
  // and also heartbeat-less rows looked "online" forever or wildly stale.
  const lastMs = Math.max(mem ?? 0, Number.isFinite(dbLast) ? dbLast : 0);
  const age = lastMs > 0 ? Date.now() - lastMs : Number.POSITIVE_INFINITY;
  const recent = age >= 0 && age < ONLINE_THRESHOLD_MS;
  // Live WS or recent heartbeat only — ignore sticky DB isOnline without fresh lastSeen
  const isOnline = connected || recent;
  const lastSeenAt = lastMs > 0 ? new Date(lastMs).toISOString() : null;
  return { isOnline, lastSeenAt };
}
