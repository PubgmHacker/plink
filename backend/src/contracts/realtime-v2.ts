// Realtime protocol v2 — the single source of truth for every payload exchanged
// between the backend and the clients. Both the iOS decoders and the web guest
// player are written against these schemas, and the contract tests in
// src/tests/contract/ fail when one side drifts from the other.
//
// Invariants these schemas enforce:
//   - protocolVersion is the literal 2. There is no implicit upgrade path; a
//     client speaking another version is rejected at the door rather than
//     partially understood.
//   - Field names are camelCase, without exception. The earlier mix of roomID
//     and roomId cost more debugging time than the convention ever will.
//   - Server-assigned fields (epoch, seq, effectiveAtServerMs, issuedBy) are
//     absent from every client→server schema, so a client cannot claim a
//     sequence number or forge authorship by sending one.
//   - actionId is a client-generated UUID that makes commands idempotent at the
//     Redis layer, so a retry after a dropped ack cannot apply twice.
//   - epoch increments on host migration and on timeline reset; seq is monotonic
//     within a single (roomId, epoch) pair.
//
// See docs/architecture/realtime-protocol.md for how these fit together, and
// ADR-0002 for why the host owns the timeline.

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

/**
 * A pause request, delivered to everyone in the room.
 *
 * Deliberately broadcast rather than sent to the host alone: the other viewers
 * need to see that a pause has already been asked for, otherwise three people
 * press the button for the same reason. The client distinguishes the two
 * readings by its own role — the host sees a prompt to answer, viewers see a
 * notice that someone asked.
 */
export const PauseRequestedSchema = z
  .object({
    type: z.literal('pause.requested'),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    userId: z.string().uuid(),
    username: z.string().min(1).max(64),
    reason: z.string().min(1).max(120).nullable(),
    serverTimeMs: z.number().int(),
  })
  .strict();

/**
 * The host's answer to a pause request, delivered to everyone in the room.
 *
 * This closes the feedback loop. A declined request used to vanish silently, so
 * the viewer could not tell whether anyone had seen it and asked again as soon
 * as the cooldown expired.
 *
 * Note what this event is not: even when accepted is true, the pause itself
 * still travels separately as the host's own sync.command. This is a social
 * signal, not a player command — keeping the two apart means the player has
 * exactly one authority.
 *
 * requestUserId identifies whose request was answered. It is nullable because
 * the server keeps no queue of pending requests: the host's client supplies the
 * attribution, and recipients match it against the last request they saw.
 */
export const PauseResolvedSchema = z
  .object({
    type: z.literal('pause.resolved'),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    hostId: z.string().uuid(),
    hostName: z.string().min(1).max(64),
    accepted: z.boolean(),
    requestUserId: z.string().uuid().nullable(),
    serverTimeMs: z.number().int(),
  })
  .strict();

/**
 * The host answers a pause request.
 *
 * Restricted to the host in messageRouter; without that check any viewer could
 * decline someone else's request on the room's behalf. Accepting does not touch
 * the player — the pause follows as an ordinary sync.command, which already
 * verifies the sender's role.
 */
export const PauseResolveSchema = z
  .object({
    type: z.literal('pause.resolve'),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    accepted: z.boolean(),
    requestUserId: z.string().uuid().optional(),
  })
  .strict();

/** Clock probe — client→server→client round trip that feeds ClockSynchronizer. */
export const ClockProbeSchema = z
  .object({
    type: z.literal('clock.probe'),
    protocolVersion: z.literal(2),
    // Fractional, not .int(): the Swift client sends sub-millisecond timestamps,
    // and an integer constraint rejected every probe it sent.
    clientSentMs: z.number().finite(),
  })
  .strict();

/**
 * A viewer asks the host to pause.
 *
 * The player belongs to the host — sync.command checks the sender's role — so
 * before this existed a viewer's only option was the chat ("wait, I'll be right
 * back"), which drowns in the reaction stream. This is not a player command:
 * the server pauses nothing. It delivers the request and the decision stays
 * with the host, because a stop button over someone else's session is not a
 * thing a viewer should hold.
 *
 * reason is an optional short note ("back in a minute", "still buffering") so
 * the host knows whether to wait a second or a while.
 */
export const PauseRequestSchema = z
  .object({
    type: z.literal('pause.request'),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    reason: z.string().min(1).max(120).optional(),
  })
  .strict();

// ─────────────────────────────────────────────────────────────────────────────
// Server → Client
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Authoritative room state. Every field here is server-assigned, which is why no
 * client→server schema in this file contains epoch, seq, effectiveAtServerMs, or
 * issuedBy: a client has no way to express them, so it has no way to claim a
 * position in the sequence or forge authorship of a command.
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
    // Echoed back unchanged, fractional for the same reason as on the way in.
    clientSentMs: z.number().finite(),
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

/**
 * Host migration. The epoch bump is the point of this event: it invalidates
 * in-flight commands from the previous host rather than racing them.
 */
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

/**
 * Live delivery of a room's appearance. The host saves it through
 * PATCH /rooms/:id/appearance, the route publishes to RoomEventBus, and every
 * replica forwards it to the sockets it holds for that room.
 *
 * Only the fields a client needs in order to render are on the wire:
 * updatedAt and updatedBy stay in the database as audit metadata.
 *
 * intensity is capped at the same 0.44 the route enforces, so a mismatch
 * between the two fails at publish time instead of quietly reaching a client
 * that would then render something the route would have rejected.
 */
export const RoomAppearanceUpdatedSchema = z
  .object({
    type: z.literal('room.appearance.updated'),
    protocolVersion: z.literal(2),
    roomId: z.string().uuid(),
    appearance: z
      .object({
        themeId: z.string().min(1).max(64),
        themeRevision: z.number().int().nonnegative(),
        intensity: z.number().min(0).max(0.44),
        motionEnabled: z.boolean(),
      })
      .strict(),
    serverTimeMs: z.number().int(),
  })
  .strict();

/**
 * Graceful shutdown announcement. Typed rather than an ad-hoc error so clients
 * can distinguish "come back in retryInMs" from a genuine failure and reconnect
 * without showing the user an error.
 */
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
export type RoomAppearanceUpdated = z.infer<typeof RoomAppearanceUpdatedSchema>;
export type ServerDraining = z.infer<typeof ServerDrainingSchema>;
export type PauseRequest = z.infer<typeof PauseRequestSchema>;
export type PauseRequested = z.infer<typeof PauseRequestedSchema>;
export type PauseResolve = z.infer<typeof PauseResolveSchema>;
export type PauseResolved = z.infer<typeof PauseResolvedSchema>;

/** Discriminated union of all client→server messages for type-safe routing. */
export const ClientMessageSchema = z.discriminatedUnion('type', [
  SyncCommandSchema,
  StateRequestSchema,
  ChatSendSchema,
  ReactionSendSchema,
  ClockProbeSchema,
  PauseRequestSchema,
  PauseResolveSchema,
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
  RoleChangedSchema,
  RoomAppearanceUpdatedSchema,
  ServerDrainingSchema,
  PauseRequestedSchema,
  PauseResolvedSchema,
]);

export type ServerMessage = z.infer<typeof ServerMessageSchema>;

/** Stable list of message type strings — used by messageRouter. */
export const CLIENT_MESSAGE_TYPES = [
  'sync.command',
  'sync.state.request',
  'chat.send',
  'reaction.send',
  'clock.probe',
  'pause.request',
  'pause.resolve',
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
  'role.changed',
  'room.appearance.updated',
  'server.draining',
  'pause.requested',
  'pause.resolved',
] as const;
