// Contract parity between the backend ServerMessage union and the message types the
// iOS client can decode.
//
// This test reads Plink/Realtime/RealtimeEnvelope.swift and extracts the wire-type
// strings from RealtimeServerMessage's decoder switch. It used to compare against a
// hand-written SWIFT_HANDLED_TYPES set with a comment saying "must match
// RealtimeEnvelope.swift" — which meant the check was only as good as someone
// remembering to edit two files, and could not see a case being removed from Swift
// at all. Parsing the source makes the assertion about the client that ships.
//
// If this test cannot find or parse the Swift file it FAILS. It does not skip. A
// contract test that quietly stops testing is the failure mode this repository has
// already been bitten by once (see src/tests/redisSkipReporter.ts).

import { describe, expect, it } from 'vitest';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { SERVER_MESSAGE_TYPES } from '../../contracts/realtime-v2.js';

// Resolved from this file's own location rather than process.cwd(), so the test behaves
// the same under `vitest run` from the backend directory and from the repo root.
const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../../..');
const ENVELOPE_CANDIDATES = ['ios/Plink/Realtime/RealtimeEnvelope.swift'];

function readSwiftEnvelope(): { path: string; source: string } {
  for (const rel of ENVELOPE_CANDIDATES) {
    const path = resolve(REPO_ROOT, rel);
    if (existsSync(path)) return { path, source: readFileSync(path, 'utf8') };
  }
  throw new Error(
    `Cannot find RealtimeEnvelope.swift. Looked for:\n` +
      ENVELOPE_CANDIDATES.map((c) => `  ${resolve(REPO_ROOT, c)}`).join('\n') +
      `\nIf the iOS client moved, add its path to ENVELOPE_CANDIDATES in this file.`,
  );
}

/**
 * Wire-type strings the Swift decoder handles, read out of the `switch type` in
 * RealtimeServerMessage.init(from:).
 *
 * Anchored on `switch type {` … `default:` so a `case "…"` string appearing
 * elsewhere in the file — in the client-message encoder, or in a comment — cannot
 * inflate the result.
 */
function swiftHandledTypes(source: string): Set<string> {
  const init = source.indexOf('public init(from decoder: Decoder) throws');
  if (init === -1) {
    throw new Error('RealtimeServerMessage.init(from:) not found in RealtimeEnvelope.swift');
  }
  const switchStart = source.indexOf('switch type {', init);
  if (switchStart === -1) {
    throw new Error('`switch type {` not found in RealtimeServerMessage.init(from:)');
  }
  const switchEnd = source.indexOf('default:', switchStart);
  if (switchEnd === -1) {
    throw new Error('`default:` not found — cannot bound the decoder switch');
  }

  const body = source.slice(switchStart, switchEnd);
  const types = new Set<string>();
  for (const m of body.matchAll(/^\s*case\s+"([^"]+)"\s*:/gm)) {
    types.add(m[1]);
  }
  return types;
}

// Types the backend already sends that the iOS decoder does not parse yet.
//
// Sending one is safe: RealtimeClient.handleIncoming catches the DecodingError and
// records lastError without tearing down the socket. Adding an entry here is how you
// ship a server message ahead of the client that reads it; remove the entry once
// RealtimeEnvelope.swift has the matching case.
//
// The <string> annotation is required. An empty `new Set([])` infers Set<never>, and
// `.has(t)` stops type-checking the moment the list empties.
const PENDING_IOS_DECODER_TYPES = new Set<string>([
  // Empty: every type the backend sends has a matching case in the Swift decoder.
]);

const { path: envelopePath, source: envelopeSource } = readSwiftEnvelope();
const swiftTypes = swiftHandledTypes(envelopeSource);
const backendTypes = new Set<string>(SERVER_MESSAGE_TYPES);

describe('Backend ↔ iOS contract parity', () => {
  it('parsed the Swift decoder rather than silently finding nothing', () => {
    // Guards the parser itself. Without this, a refactor that renames the switch
    // discriminator yields an empty set, every parity assertion below passes
    // vacuously, and the suite reports the contract as verified.
    expect(swiftTypes.size, `no case "…" literals parsed out of ${envelopePath}`).toBeGreaterThan(
      5,
    );
  });

  it('every backend ServerMessage type is decoded by the Swift client', () => {
    const missingInSwift = [...backendTypes].filter(
      (t) => !swiftTypes.has(t) && !PENDING_IOS_DECODER_TYPES.has(t),
    );
    expect(
      missingInSwift,
      'the backend sends these and RealtimeEnvelope.swift has no case for them — ' +
        'add the case, or list the type in PENDING_IOS_DECODER_TYPES',
    ).toEqual([]);
  });

  it('the Swift client decodes no type the backend does not produce', () => {
    const extraInSwift = [...swiftTypes].filter((t) => !backendTypes.has(t));
    expect(
      extraInSwift,
      'RealtimeEnvelope.swift decodes these and no backend code sends them — ' +
        'either the server dropped a message type or the case is dead',
    ).toEqual([]);
  });

  it('pending-iOS types are real backend types, so the list cannot rot', () => {
    for (const t of PENDING_IOS_DECODER_TYPES) {
      expect(backendTypes.has(t), `${t} is not a backend ServerMessage type`).toBe(true);
      expect(swiftTypes.has(t), `${t} is already decoded by Swift — remove it from the list`).toBe(
        false,
      );
    }
  });

  // Two types called out individually because each was added to fix an incident and
  // each is easy to drop in a refactor of the other side.
  it.each(['server.draining', 'reaction.broadcast'])('%s is on both sides', (type) => {
    expect(SERVER_MESSAGE_TYPES).toContain(type);
    expect(swiftTypes.has(type)).toBe(true);
  });
});
