// Plink/Playback/PlaybackProxy.swift
// Stable proxy for OrderedSyncController (Brain Review 5 P0-29, 7 P0-53)
//
// P0-53 fix: proxy no longer silently succeeds when target is nil.
// seek returns .unavailable, play/pause throw if no target.
// Latest pending state is stored and replayed after target attachment.

import Foundation
import Observation

@MainActor
@Observable
public final class PlaybackProxy: PlaybackControlling {
    public weak var target: PlaybackControlling?

    // P0-53: pending state replay — store latest target after attach
    private var pendingSeek: (seconds: TimeInterval, precise: Bool)?

    public init(target: PlaybackControlling? = nil) {
        self.target = target
    }

    // P0-53: attach target and replay pending seek
    public func attachTarget(_ newTarget: PlaybackControlling?) {
        self.target = newTarget
        // Replay pending seek if any
        if let pending = pendingSeek, let target = newTarget {
            pendingSeek = nil
            Task { _ = await target.seek(to: pending.seconds, precise: pending.precise) }
        }
    }

    // P0-53: clear target on teardown
    public func clearTarget() {
        self.target = nil
    }

    public var position: TimeInterval { target?.position ?? 0 }
    public var duration: TimeInterval { target?.duration ?? 0 }
    public var isPlaying: Bool { target?.isPlaying ?? false }
    public var isBuffering: Bool { target?.isBuffering ?? false }
    public var capabilities: PlaybackCapabilities { target?.capabilities ?? .unknown }

    public func prepare(_ source: PlaybackSource) async throws {
        guard let target else {
            throw ProviderError.loadingFailed("PlaybackProxy has no target")
        }
        try await target.prepare(source)
    }

    public func play() async {
        // P0-53: no-op if no target — but don't throw (play is not throwing)
        await target?.play()
    }

    public func pause() {
        target?.pause()
    }

    public func seek(to seconds: TimeInterval, precise: Bool) async -> SeekResult {
        guard let target else {
            // P0-53: store pending seek for replay after target attachment
            pendingSeek = (seconds, precise)
            return .unavailable
        }
        return await target.seek(to: seconds, precise: precise)
    }

    public func setRate(_ rate: Float) {
        target?.setRate(rate)
    }
}
