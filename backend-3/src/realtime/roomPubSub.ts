// src/realtime/roomPubSub.ts — Cross-replica fanout via Redis Pub/Sub (runbook §4)
//
// Each backend replica runs ONE subscriber per room-channel it has local
// connections in. When a sync.command is applied on replica A, the Lua script
// PUBLISHes the new state to room:<roomId>. Replica B's subscriber receives it
// and rebroadcasts to its local connections — same as if the command had been
// issued on B.
//
// CRITICAL (runbook §4): the connection that SUBSCRIBEs MUST be a separate
// ioredis instance from the one used for commands. ioredis enters
// subscribe-mode on a connection and refuses non-subscribe commands on it.

import Redis from 'ioredis';
import type { RoomState } from '../contracts/realtime-v2.js';

export type RoomStateListener = (state: RoomState) => void;

export class RoomPubSub {
  private readonly subscriber: Redis;
  private readonly listeners = new Map<string, Set<RoomStateListener>>();
  private readonly subscribedChannels = new Set<string>();

  constructor(redisUrl: string) {
    this.subscriber = new Redis(redisUrl, {
      maxRetriesPerRequest: null, // required for subscriber connections
      lazyConnect: false,
    });

    this.subscriber.on('message', (channel, raw) => {
      if (!channel.startsWith('room:')) return;
      const roomId = channel.substring('room:'.length);
      const listeners = this.listeners.get(roomId);
      if (!listeners || listeners.size === 0) return;

      let state: RoomState;
      try {
        state = JSON.parse(raw) as RoomState;
      } catch {
        return;
      }
      for (const fn of listeners) {
        try {
          fn(state);
        } catch (err) {
          // Listener failure must not break the subscriber loop.
          console.error('[RoomPubSub] listener threw:', err);
        }
      }
    });

    this.subscriber.on('error', (err) => {
      console.warn('[RoomPubSub] subscriber error:', err.message);
    });
  }

  /**
   * Subscribe to a room's state channel. Idempotent — calling twice with the
   * same listener is a no-op. Calling with different listeners adds both.
   */
  async subscribe(roomId: string, listener: RoomStateListener): Promise<void> {
    let set = this.listeners.get(roomId);
    if (!set) {
      set = new Set();
      this.listeners.set(roomId, set);
    }
    set.add(listener);

    if (!this.subscribedChannels.has(roomId)) {
      await this.subscriber.subscribe(`room:${roomId}`);
      this.subscribedChannels.add(roomId);
    }
  }

  /**
   * Unsubscribe a specific listener. If no listeners remain, unsubscribe from
   * the Redis channel to avoid leaking subscriptions.
   */
  async unsubscribe(roomId: string, listener: RoomStateListener): Promise<void> {
    const set = this.listeners.get(roomId);
    if (!set) return;
    set.delete(listener);
    if (set.size === 0) {
      this.listeners.delete(roomId);
      if (this.subscribedChannels.has(roomId)) {
        await this.subscriber.unsubscribe(`room:${roomId}`);
        this.subscribedChannels.delete(roomId);
      }
    }
  }

  /** Disconnect — called on graceful shutdown. */
  async close(): Promise<void> {
    try {
      await this.subscriber.quit();
    } catch {
      // ignore — shutting down
    }
  }
}
