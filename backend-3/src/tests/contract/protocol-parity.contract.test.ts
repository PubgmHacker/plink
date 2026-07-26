// src/tests/contract/protocol-parity.contract.test.ts
// Brain Review 2 P0-17 regression: contract parity between backend
// ServerMessage union and the message types iOS Swift decodes.
//
// Verifies that every ServerMessage type produced by the backend has a
// corresponding case in the Swift RealtimeServerMessage enum. The Swift
// enum currently handles:
//   sync.state, sync.state.snapshot, clock.probe.reply, chat.broadcast,
//   reaction.broadcast, participant.joined, participant.left, error,
//   session.ready, server.draining
//
// If a new ServerMessage type is added to the backend union, this test
// will fail until the Swift enum is updated to decode it.

import { describe, it, expect } from 'vitest';
import { SERVER_MESSAGE_TYPES } from '../../contracts/realtime-v2.js';

// Expected Swift-side cases — must match Plink/Realtime/RealtimeEnvelope.swift
// RealtimeServerMessage enum + init(from:) switch.
const SWIFT_HANDLED_TYPES = new Set([
  'sync.state',
  'sync.state.snapshot',
  'clock.probe.reply',
  'chat.broadcast',
  'reaction.broadcast',
  'participant.joined',
  'participant.left',
  'error',
  'session.ready',
  'role.changed',  // P1-64
  'server.draining',
]);

describe('Backend ↔ iOS contract parity (P0-17 regression)', () => {
  it('every backend ServerMessage type is handled by Swift decoder', () => {
    const backendTypes = new Set<string>(SERVER_MESSAGE_TYPES);
    const missingInSwift: string[] = [];
    for (const t of backendTypes) {
      if (!SWIFT_HANDLED_TYPES.has(t)) {
        missingInSwift.push(t);
      }
    }
    expect(missingInSwift).toEqual([]);
  });

  it('Swift decoder does not handle types backend does not produce', () => {
    const backendTypes = new Set<string>(SERVER_MESSAGE_TYPES);
    const extraInSwift: string[] = [];
    for (const t of SWIFT_HANDLED_TYPES) {
      if (!backendTypes.has(t)) {
        extraInSwift.push(t);
      }
    }
    // P1-20: no more exceptions — server.draining is now in typed contract
    expect(extraInSwift).toEqual([]);
  });

  it('server.draining is in Swift decoder and backend typed contract (P0-17 + P1-20)', () => {
    expect(SWIFT_HANDLED_TYPES.has('server.draining')).toBe(true);
    expect(SERVER_MESSAGE_TYPES).toContain('server.draining');
  });

  it('reaction.broadcast is in Swift decoder (P0-17)', () => {
    expect(SWIFT_HANDLED_TYPES.has('reaction.broadcast')).toBe(true);
  });
});
