// src/realtime/userEventBus.ts — Cross-replica user-level fanout
//
// DM pushes, friend events and typing indicators are delivered to a USER, not
// a room: gateway.notifyUser(userId, payload). Before this bus existed that
// call reached only the sockets on the replica that happened to handle the
// HTTP request — with N replicas, delivery was ~1/N.
//
// Design differs from RoomEventBus on purpose:
//   - The publisher DOES deliver locally first (registry.sendToUser) and the
//     envelope carries the publishing instance's id so the subscriber skips
//     its own messages. RoomEventBus does the opposite (deliver only via
//     subscription) because room broadcasts must be exactly-once per socket
//     across many senders; here the priority is that DM pushes keep working
//     when Redis pub/sub is degraded — local delivery must not depend on a
//     Redis round-trip.
//   - Channels are per-user (`user:<id>`), subscribed while this replica has
//     at least one socket for that user (registry fires onFirst/onLast hooks).
//     NOT psubscribe('user:*') — that would route every DM event on the
//     platform to every replica.
//
// The payload is opaque to this bus (DM events are outside the room
// ServerMessage union), but a minimal shape check — object with a string
// `type` — is enforced before anything is written to a client socket, so a
// malformed publish cannot inject arbitrary frames.

import Redis from 'ioredis';
import type { Redis as RedisType } from 'ioredis';
import { randomUUID } from 'node:crypto';

type Envelope = { src: string; payload: { type: string } & Record<string, unknown> };

export type UserEventDeliver = (userId: string, payload: unknown) => void;

function isValidPayload(p: unknown): p is Envelope['payload'] {
  return typeof p === 'object' && p !== null && typeof (p as { type?: unknown }).type === 'string';
}

export class UserEventBus {
  private readonly subscriber: RedisType;
  private readonly publisher: RedisType;
  private readonly subscribed = new Set<string>();
  private readonly instanceId = randomUUID();

  constructor(
    redisUrl: string,
    private readonly deliver: UserEventDeliver,
  ) {
    // Subscriber must be a dedicated connection — ioredis refuses regular
    // commands on a connection in subscribe mode. It re-subscribes to the
    // current channel set automatically after a reconnect.
    this.subscriber = new Redis(redisUrl, {
      maxRetriesPerRequest: null,
      lazyConnect: false,
    });
    this.publisher = new Redis(redisUrl, {
      maxRetriesPerRequest: 3,
      lazyConnect: false,
    });

    this.subscriber.on('message', (channel, raw) => {
      if (!channel.startsWith('user:')) return;
      const userId = channel.substring('user:'.length);
      let envelope: Partial<Envelope>;
      try {
        envelope = JSON.parse(raw) as Partial<Envelope>;
      } catch {
        return;
      }
      // Own publish — the local sockets were already served directly.
      if (envelope.src === this.instanceId) return;
      if (typeof envelope.src !== 'string' || !isValidPayload(envelope.payload)) {
        console.warn('[UserEventBus] dropped malformed user event');
        return;
      }
      try {
        this.deliver(userId, envelope.payload);
      } catch (err) {
        // Delivery failure must not break the subscriber loop.
        console.error('[UserEventBus] deliver threw:', err);
      }
    });

    this.subscriber.on('error', (err) => {
      console.warn('[UserEventBus] subscriber error:', err.message);
    });
    this.publisher.on('error', (err) => {
      console.warn('[UserEventBus] publisher error:', err.message);
    });
  }

  /**
   * Start receiving events for a user on this replica. Idempotent.
   * The flag is set BEFORE the await and rolled back on failure — otherwise a
   * concurrent call in the await window would see the channel as pending and
   * both/neither would SUBSCRIBE depending on timing.
   */
  async subscribe(userId: string): Promise<void> {
    if (this.subscribed.has(userId)) return;
    this.subscribed.add(userId);
    try {
      await this.subscriber.subscribe(`user:${userId}`);
    } catch (err) {
      this.subscribed.delete(userId);
      throw err;
    }
  }

  /** Stop receiving events for a user (last local socket gone). Idempotent. */
  async unsubscribe(userId: string): Promise<void> {
    if (!this.subscribed.has(userId)) return;
    this.subscribed.delete(userId);
    try {
      await this.subscriber.unsubscribe(`user:${userId}`);
    } catch (err) {
      this.subscribed.add(userId);
      throw err;
    }
  }

  /**
   * Fan a user event out to OTHER replicas. The caller is responsible for
   * local delivery (gateway.notifyUser does registry.sendToUser first).
   * Throws on invalid payload — a payload that cannot cross the wire safely
   * should fail at the sender, not be dropped silently at the subscriber.
   */
  async publish(userId: string, payload: unknown): Promise<void> {
    if (!isValidPayload(payload)) {
      throw new Error('[UserEventBus] payload must be an object with a string `type`');
    }
    const envelope: Envelope = { src: this.instanceId, payload };
    await this.publisher.publish(`user:${userId}`, JSON.stringify(envelope));
  }

  async close(): Promise<void> {
    await Promise.allSettled([this.subscriber.quit(), this.publisher.quit()]);
  }
}
