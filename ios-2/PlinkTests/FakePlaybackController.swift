// PlinkTests/FakePlaybackController.swift
// Fake player for deterministic seek testing (Brain Review 7 P0-55)
//
// Simulates AVPlayer seek behavior without actual media playback.
// Tracks all seek calls, their completion, and allows controlling
// when seek completions fire.

import Foundation
@testable import Plink

@MainActor
final class FakePlaybackController: PlaybackControlling {
    // Recorded state
    var position: TimeInterval = 0
    var duration: TimeInterval = 100
    var isPlaying: Bool = false
    var isBuffering: Bool = false
    var capabilities: PlaybackCapabilities = .init(
        seekable: true, supportsPiP: true, supportsAirPlay: true,
        supportsRateCorrection: true, supportsDRM: false
    )

    // Seek tracking
    private var seekCompletions: [(SeekResult) -> Void] = []
    private(set) var seekCallCount = 0
    private(set) var seekTargets: [TimeInterval] = []

    // Rate tracking
    private(set) var lastRate: Float = 1.0

    func prepare(_ source: PlaybackSource) async throws {}

    func play() async {
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    func seek(to seconds: TimeInterval, precise: Bool) async -> SeekResult {
        seekCallCount += 1
        seekTargets.append(seconds)
        position = seconds
        return .applied
    }

    func setRate(_ rate: Float) {
        lastRate = rate
    }

    // Test helpers
    func reset() {
        position = 0
        isPlaying = false
        isBuffering = false
        seekCallCount = 0
        seekTargets.removeAll()
        lastRate = 1.0
    }
}
