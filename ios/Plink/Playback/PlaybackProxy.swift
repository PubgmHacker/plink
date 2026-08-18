// Plink/Playback/PlaybackProxy.swift
// Stable proxy for OrderedSyncController
//
// The proxy never silently reports success while no target is attached:
// prepare() throws and seek() returns .unavailable. play()/pause() are
// no-ops because their signatures cannot throw. The latest pending seek is
// stored and replayed once a target is attached.

import Foundation
import Observation

@MainActor
@Observable
public final class PlaybackProxy: PlaybackControlling {
    public weak var target: PlaybackControlling?

    // Pending state replay — store latest target after attach
    private var pendingSeek: (seconds: TimeInterval, precise: Bool)?

    public init(target: PlaybackControlling? = nil) {
        self.target = target
    }

    // Attach target and replay pending seek
    public func attachTarget(_ newTarget: PlaybackControlling?) {
        self.target = newTarget
        // Replay pending seek if any
        if let pending = pendingSeek, let target = newTarget {
            pendingSeek = nil
            Task { _ = await target.seek(to: pending.seconds, precise: pending.precise) }
        }
    }

    // Clear target on teardown
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
        // no-op if no target — but don't throw (play is not throwing)
        await target?.play()
    }

    public func pause() {
        target?.pause()
    }

    public func seek(to seconds: TimeInterval, precise: Bool) async -> SeekResult {
        guard let target else {
            // Store pending seek for replay after target attachment
            pendingSeek = (seconds, precise)
            return .unavailable
        }
        return await target.seek(to: seconds, precise: precise)
    }

    public func setRate(_ rate: Float) {
        target?.setRate(rate)
    }
}
