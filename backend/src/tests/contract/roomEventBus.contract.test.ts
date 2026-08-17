// src/tests/contract/roomEventBus.contract.test.ts
// Brain Review 2 P1-10 regression tests
//
// Verifies the Zod schema on RoomEventBus rejects malformed events.
// No Redis needed — pure schema validation.

import { describe, it, expect } from 'vitest';
import { z } from 'zod';

// Mirror of the RoomEventSchema in roomEventBus.ts (kept private there,
// so we re-declare here for contract testing).
const RoomEventSchema = z.discriminatedUnion('kind', [
  z.object({
    kind: z.literal('chat.broadcast'),
    roomId: z.string().uuid(),
    messageId: z.string().min(1),
    clientMessageId: z.string().uuid().nullable(),
    senderId: z.string().uuid(),
    senderName: z.string().min(1).max(64),
    text: z.string().min(1).max(2000),
    createdAtMs: z.number().int(),
  }),
  z.object({
    kind: z.literal('reaction.broadcast'),
    roomId: z.string().uuid(),
    userId: z.string().uuid(),
    username: z.string().min(1).max(64),
    emoji: z.string().min(1).max(32),
    serverTimeMs: z.number().int(),
  }),
  z.object({
    kind: z.literal('participant.joined'),
    roomId: z.string().uuid(),
    userId: z.string().uuid(),
    username: z.string().min(1).max(64),
    timestampMs: z.number().int(),
  }),
  z.object({
    kind: z.literal('participant.left'),
    roomId: z.string().uuid(),
    userId: z.string().uuid(),
    username: z.string().min(1).max(64),
    timestampMs: z.number().int(),
  }),
]);

const VALID_UUID = '00000000-0000-4000-8000-000000000000';

describe('RoomEventSchema (P1-10 regression)', () => {
  it('accepts valid chat.broadcast', () => {
    RoomEventSchema.parse({
      kind: 'chat.broadcast',
      roomId: VALID_UUID,
      messageId: 'msg-1',
      clientMessageId: VALID_UUID,
      senderId: VALID_UUID,
      senderName: 'alice',
      text: 'hello',
      createdAtMs: 1700000000000,
    });
  });

  it('accepts valid reaction.broadcast', () => {
    RoomEventSchema.parse({
      kind: 'reaction.broadcast',
      roomId: VALID_UUID,
      userId: VALID_UUID,
      username: 'alice',
      emoji: '👍',
      serverTimeMs: 1700000000000,
    });
  });

  it('accepts valid participant.joined', () => {
    RoomEventSchema.parse({
      kind: 'participant.joined',
      roomId: VALID_UUID,
      userId: VALID_UUID,
      username: 'alice',
      timestampMs: 1700000000000,
    });
  });

  it('accepts valid participant.left', () => {
    RoomEventSchema.parse({
      kind: 'participant.left',
      roomId: VALID_UUID,
      userId: VALID_UUID,
      username: 'alice',
      timestampMs: 1700000000000,
    });
  });

  it('rejects unknown event kind', () => {
    expect(() =>
      RoomEventSchema.parse({
        kind: 'totally.fake',
        roomId: VALID_UUID,
      }),
    ).toThrow();
  });

  it('rejects chat.broadcast with missing senderId', () => {
    expect(() =>
      RoomEventSchema.parse({
        kind: 'chat.broadcast',
        roomId: VALID_UUID,
        messageId: 'msg-1',
        clientMessageId: null,
        // senderId missing
        senderName: 'alice',
        text: 'hello',
        createdAtMs: 1700000000000,
      }),
    ).toThrow();
  });

  it('rejects chat.broadcast with non-uuid roomId', () => {
    expect(() =>
      RoomEventSchema.parse({
        kind: 'chat.broadcast',
        roomId: 'not-a-uuid',
        messageId: 'msg-1',
        clientMessageId: null,
        senderId: VALID_UUID,
        senderName: 'alice',
        text: 'hello',
        createdAtMs: 1700000000000,
      }),
    ).toThrow();
  });

  it('rejects chat.broadcast with text > 2000 chars', () => {
    expect(() =>
      RoomEventSchema.parse({
        kind: 'chat.broadcast',
        roomId: VALID_UUID,
        messageId: 'msg-1',
        clientMessageId: null,
        senderId: VALID_UUID,
        senderName: 'alice',
        text: 'x'.repeat(2001),
        createdAtMs: 1700000000000,
      }),
    ).toThrow();
  });

  it('rejects reaction.broadcast with emoji > 32 chars', () => {
    expect(() =>
      RoomEventSchema.parse({
        kind: 'reaction.broadcast',
        roomId: VALID_UUID,
        userId: VALID_UUID,
        username: 'alice',
        emoji: 'x'.repeat(33),
        serverTimeMs: 1700000000000,
      }),
    ).toThrow();
  });

  it('rejects participant.joined with empty username', () => {
    expect(() =>
      RoomEventSchema.parse({
        kind: 'participant.joined',
        roomId: VALID_UUID,
        userId: VALID_UUID,
        username: '',
        timestampMs: 1700000000000,
      }),
    ).toThrow();
  });
});
