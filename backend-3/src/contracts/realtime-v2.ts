// src/contracts/realtime-v2.ts — Protocol v2 contracts (runbook §3)
//
// Single source of truth for all realtime payloads between backend and iOS.
// Rules enforced by these schemas:
//   - protocolVersion: literal 2 (no implicit upgrade)
//   - field names: camelCase only (kills the roomID/roomId + userID/userId mix)
//   - server-assigned fields (epoch, seq, effectiveAtServerMs, issuedBy)
//     are NOT accepted from clients — see ServerAssignedRoomStateSchema
//   - actionId: client-generated UUID, provides idempotency at the Redis layer
//   - epoch: increments on host migration or timeline reset
//   - seq: monotonic within (roomId, epoch)
//
// After v2 stabilizes across both clients, lift this into Protobuf per runbook §3.

import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Client → Server
// ─────────────────────────────────────────────────────────────────────────────

/** Host pushes a playback intent. Server assigns epoch/seq/timestamps. */
export const SyncCommandSchema = z
  .object({
    type: z.literal('sync.command'),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    actionId: z.string().uuid(),
    mediaId: z.string().min(1).max(512).nullable(),
    positionMs: z.number().int().nonnegative().max(86_400_000),
    playing: z.boolean(),
    rate: z.number().min(0.5).max(2).default(1),
  })
  .strict();

/** Client (re)requests authoritative snapshot, optionally after a seq watermark. */
export const StateRequestSchema = z
  .object({
    type: z.literal('sync.state.request'),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    afterSeq: z.number().int().nonnegative().default(0),
  })
  .strict();

/** Chat send (v2). Identity always comes from JWT, never from payload. */
export const ChatSendSchema = z
  .object({
    type: z.literal('chat.send'),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    clientMessageId: z.string().uuid(),
    text: z.string().min(1).max(2000),
  })
  .strict();

/** Reaction (v2). */
export const ReactionSendSchema = z
  .object({
    type: z.literal('reaction.send'),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    emoji: z.string().min(1).max(32),
  })
  .strict();

/** Reaction broadcast (server → all room clients). */
export const ReactionBroadcastSchema = z
  .object({
    type: z.literal('reaction.broadcast'),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    userId: z.string().uuid(),
    username: z.string().min(1).max(64),
    emoji: z.string().min(1).max(32),
    serverTimeMs: z.number().int(),
  })
  .strict();

/** Clock probe — client→server→client round-trip for ClockSynchronizer. */
export const ClockProbeSchema = z
  .object({
    type: z.literal('clock.probe'),
    protocolVersion: z.literal(2),
    clientSentMs: z.number().int(),
  })
  .strict();

// ─────────────────────────────────────────────────────────────────────────────
// Server → Client
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Authoritative room state. ALL fields are server-assigned — clients MUST NOT
 * send this schema. We keep a separate schema for "input from Redis Lua" vs
 * "wire format to client" so the wire never accidentally accepts client seq.
 */
export const RoomStateSchema = z
  .object({
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    epoch: z.number().int().positive(),
    seq: z.number().int().nonnegative(),
    mediaId: z.string().nullable(),
    positionMs: z.number().int().nonnegative(),
    playing: z.boolean(),
    rate: z.number(),
    effectiveAtServerMs: z.number().int(),
    issuedBy: z.string().uuid(),
  })
  .strict();

export const SyncStateMessageSchema = z
  .object({
    type: z.literal('sync.state'),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    state: RoomStateSchema,
    serverTimeMs: z.number().int(),
  })
  .strict();

export const SyncStateSnapshotMessageSchema = z
  .object({
    type: z.literal('sync.state.snapshot'),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    state: RoomStateSchema.nullable(),
    serverTimeMs: z.number().int(),
  })
  .strict();

export const ClockProbeReplySchema = z
  .object({
    type: z.literal('clock.probe.reply'),
    protocolVersion: z.literal(2),
    clientSentMs: z.number().int(),
    serverMs: z.number().int(),
  })
  .strict();

export const ChatBroadcastSchema = z
  .object({
    type: z.literal('chat.broadcast'),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    messageId: z.string().uuid(),
    clientMessageId: z.string().uuid().nullable(),
    senderId: z.string().uuid(),
    senderName: z.string().min(1).max(64),
    text: z.string().min(0).max(2000),
    createdAtMs: z.number().int(),
    mediaType: z.enum(['photo']).nullable().optional(),
    hasMedia: z.boolean().optional(),
  })
  .strict();

export const ParticipantEventSchema = z
  .object({
    type: z.enum(['participant.joined', 'participant.left']),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    userId: z.string().uuid(),
    username: z.string().min(1).max(64),
    joinedAtMs: z.number().int().optional(),
    leftAtMs: z.number().int().optional(),
  })
  .strict();

export const ErrorMessageSchema = z
  .object({
    type: z.literal('error'),
    protocolVersion: z.literal(2),
    code: z.string().min(1).max(64),
    message: z.string().min(1).max(512),
  })
  .strict();

export const SessionReadySchema = z
  .object({
    type: z.literal('session.ready'),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    role: z.enum(['host', 'viewer']),
    serverTimeMs: z.number().int(),
  })
  .strict();

/** P1-64: role migration event — host change with epoch bump */
export const RoleChangedSchema = z
  .object({
    type: z.literal('role.changed'),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    newHostId: z.string().uuid(),
    newRole: z.enum(['host', 'viewer']),
    epoch: z.number().int().positive(),
    serverTimeMs: z.number().int(),
  })
  .strict();

/** Server draining — graceful shutdown announcement (P1-20: typed contract). */
export const ServerDrainingSchema = z
  .object({
    type: z.literal('server.draining'),
    protocolVersion: z.literal(2),
    message: z.string().min(1).max(512),
    retryInMs: z.number().int().nonnegative(),
  })
  .strict();

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

export type SyncCommand = z.infer<typeof SyncCommandSchema>;
export type StateRequest = z.infer<typeof StateRequestSchema>;
export type ChatSend = z.infer<typeof ChatSendSchema>;
export type ReactionSend = z.infer<typeof ReactionSendSchema>;
export type ClockProbe = z.infer<typeof ClockProbeSchema>;

export type RoomState = z.infer<typeof RoomStateSchema>;
export type SyncStateMessage = z.infer<typeof SyncStateMessageSchema>;
export type SyncStateSnapshotMessage = z.infer<typeof SyncStateSnapshotMessageSchema>;
export type ClockProbeReply = z.infer<typeof ClockProbeReplySchema>;
export type ChatBroadcast = z.infer<typeof ChatBroadcastSchema>;
export type ReactionBroadcast = z.infer<typeof ReactionBroadcastSchema>;
export type ParticipantEvent = z.infer<typeof ParticipantEventSchema>;
export type ErrorMessage = z.infer<typeof ErrorMessageSchema>;
export type SessionReady = z.infer<typeof SessionReadySchema>;
export type RoleChanged = z.infer<typeof RoleChangedSchema>;
export type ServerDraining = z.infer<typeof ServerDrainingSchema>;

/** Discriminated union of all client→server messages for type-safe routing. */
export const ClientMessageSchema = z.discriminatedUnion('type', [
  SyncCommandSchema,
  StateRequestSchema,
  ChatSendSchema,
  ReactionSendSchema,
  ClockProbeSchema,
]);

export type ClientMessage = z.infer<typeof ClientMessageSchema>;

/** Discriminated union of all server→client messages. */
export const ServerMessageSchema = z.discriminatedUnion('type', [
  SyncStateMessageSchema,
  SyncStateSnapshotMessageSchema,
  ClockProbeReplySchema,
  ChatBroadcastSchema,
  ReactionBroadcastSchema,
  ParticipantEventSchema,
  ErrorMessageSchema,
  SessionReadySchema,
  RoleChangedSchema,  // P1-64
  ServerDrainingSchema,
]);

export type ServerMessage = z.infer<typeof ServerMessageSchema>;

/** Stable list of message type strings — used by messageRouter. */
export const CLIENT_MESSAGE_TYPES = [
  'sync.command',
  'sync.state.request',
  'chat.send',
  'reaction.send',
  'clock.probe',
] as const;

export const SERVER_MESSAGE_TYPES = [
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
] as const;
