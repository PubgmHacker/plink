// Plink/Realtime/RealtimeConnectionState.swift
// Explicit connection states
//
// Replaces the legacy 'fake connected via socket existence after 250ms'.
// The client MUST NOT report .connected until the server has sent
// session.ready with room membership and protocol version.

import Foundation

public enum RealtimeConnectionState: Sendable, Equatable {
    case idle
    case connecting
    case authenticating
    case joining
    case synchronizing
    case connected
    case reconnecting(attempt: Int)
    case failed(reason: String)

    public var isOnline: Bool {
        switch self {
        case .connected: return true
        default: return false
        }
    }

    public var isTransient: Bool {
        switch self {
        case .connecting, .authenticating, .joining, .synchronizing, .reconnecting:
            return true
        default: return false
        }
    }
}
