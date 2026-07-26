// Plink/Playback/PlaybackControlling.swift
// Player abstraction (runbook §6)
//
// Defines the contract that OrderedSyncController talks to. The
// implementation is NativePlayerController (AVPlayer) — provider adapters
// (HLS, YouTube embedded) are pluggable behind the same protocol.
//
// IMPORTANT: this protocol lives in Plink/Playback/, NOT Plink/Realtime/.
// Realtime never imports a concrete player class — it only knows the
// protocol. This is the §21 architecture rule: 'PlaybackController не
// отправляет WebSocket сообщения' and the inverse.

import Foundation

// P0-27: SeekResult — caller knows whether their seek was applied or
// superseded by a newer seek. OrderedSyncController must NOT call play()
// after a superseded seek — the newer seek's caller owns the next action.
public enum SeekResult: Sendable, Equatable {
    case applied
    case superseded
    case unavailable  // P0-53: proxy has no target — player not ready
}

@MainActor
public protocol PlaybackControlling: AnyObject {
    var position: TimeInterval { get }
    var duration: TimeInterval { get }
    var isPlaying: Bool { get }
    var isBuffering: Bool { get }

    /// Loaded media capability flags. Used by OrderedSyncController to
    /// decide whether rate-based drift correction is allowed — if the
    /// provider doesn't support rate correction, fall back to less frequent
    /// precise seeks (runbook §19: 'Если provider не поддерживает rate
    /// correction, sync policy использует более редкие precise seeks').
    var capabilities: PlaybackCapabilities { get }

    func prepare(_ source: PlaybackSource) async throws
    func play() async
    func pause()
    /// P0-27: seek returns SeekResult. Caller MUST check result before
    /// proceeding with play/pause — superseded means a newer seek owns
    /// the next action.
    func seek(to seconds: TimeInterval, precise: Bool) async -> SeekResult
    func setRate(_ rate: Float)
}

public struct PlaybackCapabilities: Sendable, Equatable {
    public let seekable: Bool
    public let supportsPiP: Bool
    public let supportsAirPlay: Bool
    public let supportsRateCorrection: Bool
    public let supportsDRM: Bool

    public init(
        seekable: Bool,
        supportsPiP: Bool,
        supportsAirPlay: Bool,
        supportsRateCorrection: Bool,
        supportsDRM: Bool
    ) {
        self.seekable = seekable
        self.supportsPiP = supportsPiP
        self.supportsAirPlay = supportsAirPlay
        self.supportsRateCorrection = supportsRateCorrection
        self.supportsDRM = supportsDRM
    }

    /// Conservative defaults for unknown providers.
    public static let unknown = PlaybackCapabilities(
        seekable: false,
        supportsPiP: false,
        supportsAirPlay: false,
        supportsRateCorrection: false,
        supportsDRM: false
    )
}
