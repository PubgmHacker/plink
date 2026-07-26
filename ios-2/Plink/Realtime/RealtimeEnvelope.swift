// Plink/Realtime/RealtimeEnvelope.swift
// Protocol v2 wire types (runbook §3, §5)
//
// Single source of truth for all realtime payloads between iOS and backend.
// Mirror of src/contracts/realtime-v2.ts. Field names are camelCase on both
// sides — CodingKeys are explicit so a backend rename cannot silently break
// decoding.
//
// Rules:
//   - protocolVersion: literal 2 (no implicit upgrade)
//   - epoch, seq, effectiveAtServerMs, issuedBy are SERVER-ASSIGNED.
//     RealtimeRoomState is Decodable-only on the client; clients never
//     construct or send it.
//   - actionId: client-generated UUID for idempotency at the Redis layer.
//   - epoch: increments on host migration or timeline reset.
//   - seq: monotonic within (roomId, epoch).
//   - Ordering watermark: (epoch, seq) compared lexicographically.

import Foundation

// MARK: - Authoritative room state (server → client only)

/// Mirror of RoomStateSchema on the backend.
/// Decodable-only on the client — clients MUST NOT construct or send this.
public struct RealtimeRoomState: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let roomId: String
    public let epoch: Int64
    public let seq: Int64
    public let mediaId: String?
    public let positionMs: Int64
    public let playing: Bool
    public let rate: Double
    public let effectiveAtServerMs: Int64
    public let issuedBy: String

    public init(
        protocolVersion: Int,
        roomId: String,
        epoch: Int64,
        seq: Int64,
        mediaId: String?,
        positionMs: Int64,
        playing: Bool,
        rate: Double,
        effectiveAtServerMs: Int64,
        issuedBy: String
    ) {
        self.protocolVersion = protocolVersion
        self.roomId = roomId
        self.epoch = epoch
        self.seq = seq
        self.mediaId = mediaId
        self.positionMs = positionMs
        self.playing = playing
        self.rate = rate
        self.effectiveAtServerMs = effectiveAtServerMs
        self.issuedBy = issuedBy
    }

    /// Lexicographic (epoch, seq) ordering — used by OrderedSyncController.
    public func isNewerThan(_ other: RealtimeRoomState) -> Bool {
        if epoch != other.epoch { return epoch > other.epoch }
        return seq > other.seq
    }
}

// MARK: - Client → Server

public enum RealtimeClientMessage: Encodable, Sendable {
    case syncCommand(SyncCommand)
    case stateRequest(StateRequest)
    case chatSend(ChatSend)
    case reactionSend(ReactionSend)
    case clockProbe(ClockProbe)

    public struct SyncCommand: Encodable, Sendable {
        public let type = "sync.command"
        public let protocolVersion = 2
        public let roomId: String
        public let actionId: String
        public let mediaId: String?
        public let positionMs: Int64
        public let playing: Bool
        public let rate: Double

        public init(
            roomId: String,
            actionId: String,
            mediaId: String?,
            positionMs: Int64,
            playing: Bool,
            rate: Double = 1
        ) {
            self.roomId = roomId
            self.actionId = actionId
            self.mediaId = mediaId
            self.positionMs = positionMs
            self.playing = playing
            self.rate = rate
        }
    }

    public struct StateRequest: Encodable, Sendable {
        public let type = "sync.state.request"
        public let protocolVersion = 2
        public let roomId: String
        public let afterSeq: Int64

        public init(roomId: String, afterSeq: Int64 = 0) {
            self.roomId = roomId
            self.afterSeq = afterSeq
        }
    }

    public struct ChatSend: Encodable, Sendable {
        public let type = "chat.send"
        public let protocolVersion = 2
        public let roomId: String
        public let clientMessageId: String
        public let text: String

        public init(roomId: String, clientMessageId: String, text: String) {
            self.roomId = roomId
            self.clientMessageId = clientMessageId
            self.text = text
        }
    }

    public struct ReactionSend: Encodable, Sendable {
        public let type = "reaction.send"
        public let protocolVersion = 2
        public let roomId: String
        public let emoji: String

        public init(roomId: String, emoji: String) {
            self.roomId = roomId
            self.emoji = emoji
        }
    }

    public struct ClockProbe: Encodable, Sendable {
        public let type = "clock.probe"
        public let protocolVersion = 2
        public let clientSentMs: Double

        public init(clientSentMs: Double) {
            self.clientSentMs = clientSentMs
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .syncCommand(let m): try container.encode(m)
        case .stateRequest(let m): try container.encode(m)
        case .chatSend(let m): try container.encode(m)
        case .reactionSend(let m): try container.encode(m)
        case .clockProbe(let m): try container.encode(m)
        }
    }
}

// MARK: - Server → Client

public enum RealtimeServerMessage: Decodable, Sendable, Equatable {
    case syncState(SyncStateMessage)
    case syncStateSnapshot(SyncStateSnapshotMessage)
    case clockProbeReply(ClockProbeReply)
    case chatBroadcast(ChatBroadcast)
    case reactionBroadcast(ReactionBroadcast)
    case participantJoined(ParticipantEvent)
    case participantLeft(ParticipantEvent)
    case error(ErrorMessage)
    case sessionReady(SessionReady)
    case serverDraining(ServerDraining)

    public struct SyncStateMessage: Decodable, Sendable, Equatable {
        public let type: String  // "sync.state"
        public let protocolVersion: Int
        public let roomId: String
        public let state: RealtimeRoomState
        public let serverTimeMs: Int64
    }

    public struct SyncStateSnapshotMessage: Decodable, Sendable, Equatable {
        public let type: String  // "sync.state.snapshot"
        public let protocolVersion: Int
        public let roomId: String
        public let state: RealtimeRoomState?
        public let serverTimeMs: Int64
    }

    public struct ClockProbeReply: Decodable, Sendable, Equatable {
        public let type: String  // "clock.probe.reply"
        public let protocolVersion: Int
        public let clientSentMs: Double
        public let serverMs: Double
    }

    public struct ChatBroadcast: Decodable, Sendable, Equatable {
        public let type: String  // "chat.broadcast"
        public let protocolVersion: Int
        public let roomId: String
        public let messageId: String
        public let clientMessageId: String?
        public let senderId: String
        public let senderName: String
        public let text: String
        public let createdAtMs: Int64
        public let mediaType: String?
        public let hasMedia: Bool?
    }

    public struct ParticipantEvent: Decodable, Sendable, Equatable {
        public let type: String  // "participant.joined" | "participant.left"
        public let protocolVersion: Int
        public let roomId: String
        public let userId: String
        public let username: String
        public let joinedAtMs: Int64?
        public let leftAtMs: Int64?
    }

    public struct ErrorMessage: Decodable, Sendable, Equatable {
        public let type: String  // "error"
        public let protocolVersion: Int
        public let code: String
        public let message: String
    }

    public struct SessionReady: Decodable, Sendable, Equatable {
        public let type: String  // "session.ready"
        public let protocolVersion: Int
        public let roomId: String
        public let role: String  // "host" | "viewer"
        public let serverTimeMs: Int64
    }

    // P0-17: reaction.broadcast — was missing, decode would fail
    public struct ReactionBroadcast: Decodable, Sendable, Equatable {
        public let type: String  // "reaction.broadcast"
        public let protocolVersion: Int
        public let roomId: String
        public let userId: String
        public let username: String
        public let emoji: String
        public let serverTimeMs: Int64
    }

    // P0-17: server.draining — sent on graceful shutdown
    public struct ServerDraining: Decodable, Sendable, Equatable {
        public let type: String  // "server.draining"
        public let protocolVersion: Int
        public let message: String
        public let retryInMs: Int64
    }

    private enum DiscriminatorKey: String, CodingKey { case type, protocolVersion }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKey.self)
        let type = try container.decode(String.self, forKey: .type)
        // P1-21: validate protocolVersion == 2 — reject v1/unknown envelopes
        // instead of silently decoding with mismatched assumptions.
        if let pv = try? container.decode(Int.self, forKey: .protocolVersion), pv != 2 {
            throw DecodingError.dataCorruptedError(
                forKey: .protocolVersion,
                in: container,
                debugDescription: "Unsupported protocolVersion: \(pv). Expected 2."
            )
        }
        let single = try decoder.singleValueContainer()
        switch type {
        case "sync.state":
            self = .syncState(try single.decode(SyncStateMessage.self))
        case "sync.state.snapshot":
            self = .syncStateSnapshot(try single.decode(SyncStateSnapshotMessage.self))
        case "clock.probe.reply":
            self = .clockProbeReply(try single.decode(ClockProbeReply.self))
        case "chat.broadcast":
            self = .chatBroadcast(try single.decode(ChatBroadcast.self))
        case "participant.joined":
            self = .participantJoined(try single.decode(ParticipantEvent.self))
        case "participant.left":
            self = .participantLeft(try single.decode(ParticipantEvent.self))
        case "error":
            self = .error(try single.decode(ErrorMessage.self))
        case "session.ready":
            self = .sessionReady(try single.decode(SessionReady.self))
        case "reaction.broadcast":
            self = .reactionBroadcast(try single.decode(ReactionBroadcast.self))
        case "server.draining":
            self = .serverDraining(try single.decode(ServerDraining.self))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown RealtimeServerMessage type: \(type)"
            )
        }
    }
}
