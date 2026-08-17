// src/tests/contract/realtime-v2.contract.test.ts
// Schema-level contract tests (runbook §12)
//
// Verifies the Zod schemas reject malformed payloads and accept valid ones.
// These tests don't need a DB or Redis — pure schema validation.

import { describe, it, expect } from 'vitest';
import {
  SyncCommandSchema,
  StateRequestSchema,
  ChatSendSchema,
  ReactionSendSchema,
  ClockProbeSchema,
  RoomStateSchema,
  ClientMessageSchema,
  ServerMessageSchema,
} from '../../contracts/realtime-v2.js';

const VALID_UUID = '00000000-0000-4000-8000-000000000000';

describe('SyncCommandSchema', () => {
  it('accepts a minimal valid command', () => {
    const cmd = {
      type: 'sync.command',
      protocolVersion: 2,
      roomId: VALID_UUID,
      actionId: VALID_UUID,
      mediaId: 'yt:abc123',
      positionMs: 0,
      playing: true,
    };
    const parsed = SyncCommandSchema.parse(cmd);
    expect(parsed.rate).toBe(1); // default
  });

  it('rejects command with wrong protocolVersion', () => {
    const cmd = {
      type: 'sync.command',
      protocolVersion: 1, // ← wrong
      roomId: VALID_UUID,
      actionId: VALID_UUID,
      mediaId: null,
      positionMs: 0,
      playing: true,
    };
    expect(() => SyncCommandSchema.parse(cmd)).toThrow();
  });

  it('rejects command with roomID instead of roomId (§19 casing rule)', () => {
    const cmd = {
      type: 'sync.command',
      protocolVersion: 2,
      roomID: VALID_UUID, // ← wrong casing
      actionId: VALID_UUID,
      mediaId: null,
      positionMs: 0,
      playing: true,
    };
    expect(() => SyncCommandSchema.parse(cmd)).toThrow();
  });

  it('rejects command with client-supplied seq (server-assigned)', () => {
    const cmd = {
      type: 'sync.command',
      protocolVersion: 2,
      roomId: VALID_UUID,
      actionId: VALID_UUID,
      mediaId: null,
      positionMs: 0,
      playing: true,
      seq: 5, // ← clients cannot set this
    };
    // .strict() rejects unknown keys
    expect(() => SyncCommandSchema.parse(cmd)).toThrow();
  });

  it('rejects positionMs > 86_400_000 (24h)', () => {
    const cmd = {
      type: 'sync.command',
      protocolVersion: 2,
      roomId: VALID_UUID,
      actionId: VALID_UUID,
      mediaId: null,
      positionMs: 100_000_000,
      playing: true,
    };
    expect(() => SyncCommandSchema.parse(cmd)).toThrow();
  });

  it('rejects rate outside [0.5, 2]', () => {
    const baseCmd = {
      type: 'sync.command',
      protocolVersion: 2,
      roomId: VALID_UUID,
      actionId: VALID_UUID,
      mediaId: null,
      positionMs: 0,
      playing: true,
    };
    expect(() => SyncCommandSchema.parse({ ...baseCmd, rate: 0.1 })).toThrow();
    expect(() => SyncCommandSchema.parse({ ...baseCmd, rate: 5 })).toThrow();
  });
});

describe('StateRequestSchema', () => {
  it('accepts request without afterSeq (default 0)', () => {
    const req = {
      type: 'sync.state.request',
      protocolVersion: 2,
      roomId: VALID_UUID,
    };
    const parsed = StateRequestSchema.parse(req);
    expect(parsed.afterSeq).toBe(0);
  });

  it('rejects non-uuid roomId', () => {
    expect(() =>
      StateRequestSchema.parse({
        type: 'sync.state.request',
        protocolVersion: 2,
        roomId: 'not-a-uuid',
      }),
    ).toThrow();
  });
});

describe('ChatSendSchema', () => {
  it('accepts a valid chat send', () => {
    ChatSendSchema.parse({
      type: 'chat.send',
      protocolVersion: 2,
      roomId: VALID_UUID,
      clientMessageId: VALID_UUID,
      text: 'hello',
    });
  });

  it('rejects empty text', () => {
    expect(() =>
      ChatSendSchema.parse({
        type: 'chat.send',
        protocolVersion: 2,
        roomId: VALID_UUID,
        clientMessageId: VALID_UUID,
        text: '',
      }),
    ).toThrow();
  });

  it('rejects text > 2000 chars', () => {
    expect(() =>
      ChatSendSchema.parse({
        type: 'chat.send',
        protocolVersion: 2,
        roomId: VALID_UUID,
        clientMessageId: VALID_UUID,
        text: 'x'.repeat(2001),
      }),
    ).toThrow();
  });

  it('rejects chat.send with senderId in payload (identity must come from JWT)', () => {
    expect(() =>
      ChatSendSchema.parse({
        type: 'chat.send',
        protocolVersion: 2,
        roomId: VALID_UUID,
        clientMessageId: VALID_UUID,
        text: 'hello',
        senderId: VALID_UUID, // ← .strict() rejects this
      }),
    ).toThrow();
  });
});

describe('ReactionSendSchema', () => {
  it('accepts a valid reaction', () => {
    ReactionSendSchema.parse({
      type: 'reaction.send',
      protocolVersion: 2,
      roomId: VALID_UUID,
      emoji: '👍',
    });
  });
});

describe('ClockProbeSchema', () => {
  it('accepts a valid probe', () => {
    ClockProbeSchema.parse({
      type: 'clock.probe',
      protocolVersion: 2,
      clientSentMs: 1700000000000,
    });
  });
});

describe('ClientMessageSchema (discriminated union)', () => {
  it('routes by type correctly', () => {
    const cmd = ClientMessageSchema.parse({
      type: 'sync.command',
      protocolVersion: 2,
      roomId: VALID_UUID,
      actionId: VALID_UUID,
      mediaId: null,
      positionMs: 0,
      playing: true,
    });
    expect(cmd.type).toBe('sync.command');

    const req = ClientMessageSchema.parse({
      type: 'sync.state.request',
      protocolVersion: 2,
      roomId: VALID_UUID,
    });
    expect(req.type).toBe('sync.state.request');
  });

  it('rejects unknown message type', () => {
    expect(() =>
      ClientMessageSchema.parse({
        type: 'totally.fake',
        protocolVersion: 2,
      }),
    ).toThrow();
  });
});

describe('RoomStateSchema', () => {
  it('accepts a valid state', () => {
    RoomStateSchema.parse({
      protocolVersion: 2,
      roomId: VALID_UUID,
      epoch: 1,
      seq: 0,
      mediaId: null,
      positionMs: 0,
      playing: false,
      rate: 1,
      effectiveAtServerMs: 1700000000000,
      issuedBy: VALID_UUID,
    });
  });

  it('rejects epoch = 0 (must be positive)', () => {
    expect(() =>
      RoomStateSchema.parse({
        protocolVersion: 2,
        roomId: VALID_UUID,
        epoch: 0, // ← must be positive
        seq: 0,
        mediaId: null,
        positionMs: 0,
        playing: false,
        rate: 1,
        effectiveAtServerMs: 1700000000000,
        issuedBy: VALID_UUID,
      }),
    ).toThrow();
  });

  it('rejects negative seq', () => {
    expect(() =>
      RoomStateSchema.parse({
        protocolVersion: 2,
        roomId: VALID_UUID,
        epoch: 1,
        seq: -1,
        mediaId: null,
        positionMs: 0,
        playing: false,
        rate: 1,
        effectiveAtServerMs: 1700000000000,
        issuedBy: VALID_UUID,
      }),
    ).toThrow();
  });
});

describe('ServerMessageSchema (discriminated union)', () => {
  it('routes sync.state correctly', () => {
    const msg = ServerMessageSchema.parse({
      type: 'sync.state',
      protocolVersion: 2,
      roomId: VALID_UUID,
      state: {
        protocolVersion: 2,
        roomId: VALID_UUID,
        epoch: 1,
        seq: 1,
        mediaId: null,
        positionMs: 0,
        playing: false,
        rate: 1,
        effectiveAtServerMs: 1700000000000,
        issuedBy: VALID_UUID,
      },
      serverTimeMs: 1700000000000,
    });
    expect(msg.type).toBe('sync.state');
  });

  it('routes session.ready correctly', () => {
    const msg = ServerMessageSchema.parse({
      type: 'session.ready',
      protocolVersion: 2,
      roomId: VALID_UUID,
      role: 'host',
      serverTimeMs: 1700000000000,
    });
    expect(msg.type).toBe('session.ready');
  });
});
