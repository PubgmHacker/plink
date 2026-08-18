// Plink/Playback/NativePlayerController.swift
// AVPlayer-backed PlaybackControlling
//
// Seeks carry a generation token: each seek bumps the generation and only the
// latest seek's completion is honored. teardown() cancels a pending seek, and
// cancelPendingPrerolls() runs before a new seek.
//
// A .youtube source is an impossible state here — prepare() throws
// immediately. Use EmbeddedPlaybackController for YouTube.
//
// Preroll runs only after prepare() or a route change, never on every play()
// call; isPrerolled carries that state.

import Foundation
import AVFoundation
import AVKit
import UIKit
import Observation

@MainActor
@Observable
public final class NativePlayerController: PlaybackControlling {
    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying: Bool = false
    public private(set) var isBuffering: Bool = false
    public private(set) var capabilities: PlaybackCapabilities = .unknown

    // P0 FIX (infinite spinner): AVPlayerItem .failed was never handled, so
    // the controller reported "buffering" forever. Expose failure state so
    // the UI stops the spinner and callers can fall back to embedded.
    public private(set) var loadFailed: Bool = false
    public private(set) var lastErrorMessage: String?

    public private(set) var player: AVPlayer?
    public private(set) var pipController: AVPlayerViewController?

    private var provider: ProviderAdapter?
    private var timeControlObservation: NSKeyValueObservation?
    private var reasonObservation: NSKeyValueObservation?
    private var timeObserverToken: Any?
    private var statusObservation: NSKeyValueObservation?
    private var likelyKeepUpObservation: NSKeyValueObservation?
    private var isPlaybackBufferEmptyObservation: NSKeyValueObservation?

    // Serial latest-target seek coordinator with SeekResult.
    // activeSeek is the seek currently being executed by AVPlayer — its
    // continuation resumes EXACTLY ONCE on completion.
    // queuedSeek is the latest pending seek — superseded by a newer seek.
    // Double-resume crash fixed: active and queued are separate, never
    // overlap.
    private var seekGeneration = 0
    private var pendingSeekTask: Task<Void, Never>?
    private var activeSeek: SeekWaiter?
    private var queuedSeek: SeekWaiter?

    // Preroll state — only preroll after prepare, not every play()
    // Seek invalidates isPrerolled only for precise transition seeks
    private var isPrerolled: Bool = false

    public init() {}

    public func prepare(_ source: PlaybackSource) async throws {
        // Reject .youtube — use EmbeddedPlaybackController instead
        if case .youtube = source {
            throw ProviderError.unsupportedSource
        }

        teardown()

        let provider: ProviderAdapter
        switch source {
        case .hls, .mp4, .external:
            provider = NativeHLSProvider()
        case .youtube, .rutube, .vk, .embed:
            throw ProviderError.unsupportedSource  // unreachable
        }
        self.provider = provider
        self.capabilities = provider.capabilities
        self.isPrerolled = false  //

        try await provider.prepare(source: source)

        if let item = provider.playerItem {
            let p = AVPlayer(playerItem: item)
            p.automaticallyWaitsToMinimizeStalling = false
            p.usesExternalPlaybackWhileExternalScreenIsActive = true
            p.allowsExternalPlayback = true
            item.preferredForwardBufferDuration = 16
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            self.player = p
            observe(p, item)
        }
    }

    public func play() async {
        guard let p = player else { return }
        // TTFF — do not block first visible playback on preroll.
        // AVPlayer starts immediately; a later precise seek can invalidate
        // isPrerolled as before.
        if capabilities.supportsRateCorrection && !isPrerolled {
            p.playImmediately(atRate: 1.0)
            isPrerolled = true
        } else {
            p.play()
        }
        isPlaying = true
    }

    public func pause() {
        player?.pause()
        isPlaying = false
    }

    // Serial latest-target seek with SeekResult.
    // activeSeek: currently executing — resumed EXACTLY ONCE on completion.
    // queuedSeek: latest pending — superseded by newer seek (resumed once).
    // Double-resume crash fixed: active and queued are SEPARATE.
    private struct SeekWaiter {
        let id: UUID
        let target: (seconds: TimeInterval, precise: Bool)
        let continuation: CheckedContinuation<SeekResult, Never>
    }

    public func seek(to seconds: TimeInterval, precise: Bool) async -> SeekResult {
        guard let p = player else { return .applied }
        let clamped: Double
        if seconds.isNaN || seconds.isInfinite || seconds < 0 {
            clamped = 0
        } else if duration > 0 && seconds > duration {
            clamped = duration
        } else {
            clamped = seconds
        }

        // If there's a queuedSeek (not yet started), resume it as superseded
        if let queued = queuedSeek {
            queuedSeek = nil
            queued.continuation.resume(returning: .superseded)
        }

        // This seek becomes the new queuedSeek
        return await withCheckedContinuation { (continuation: CheckedContinuation<SeekResult, Never>) in
            let waiter = SeekWaiter(id: UUID(), target: (clamped, precise), continuation: continuation)
            self.queuedSeek = waiter

            // If no active seek, start executing immediately
            if self.activeSeek == nil {
                Task { await self.executeNextSeek(p) }
            }
        }
    }

    private func executeNextSeek(_ p: AVPlayer) async {
        // Loop while there's a queued seek to execute
        while let queued = queuedSeek {
            // Promote queued → active (remove from queued FIRST)
            queuedSeek = nil
            activeSeek = queued

            seekGeneration += 1
            let generation = seekGeneration
            p.cancelPendingPrerolls()

            let cmTarget = CMTime(seconds: queued.target.seconds, preferredTimescale: 600)
            let tolerance: CMTime = queued.target.precise
                ? .zero
                : CMTime(seconds: 0.15, preferredTimescale: 600)

            pendingSeekTask = Task { [weak p, weak self] in
                guard let p else { return }
                if Task.isCancelled { return }
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    p.seek(
                        to: cmTarget,
                        toleranceBefore: tolerance,
                        toleranceAfter: tolerance
                    ) { _ in cont.resume() }
                }
                guard !Task.isCancelled,
                      let self else { return }
                guard generation == self.seekGeneration else { return }
                // Only invalidate isPrerolled for precise transition seeks
                if queued.target.precise {
                    self.isPrerolled = false
                }
            }
            await pendingSeekTask?.value
            if generation == seekGeneration {
                pendingSeekTask = nil
            }

            // Resume activeSeek EXACTLY ONCE as .applied
            // Clear activeSeek BEFORE resume to prevent double-resume
            let completed = activeSeek
            activeSeek = nil
            completed?.continuation.resume(returning: .applied)
        }
    }

    public func setRate(_ rate: Float) {
        guard capabilities.supportsRateCorrection else { return }
        player?.rate = rate
    }

    public func teardown() {
        // Cancel pending seek + resume active/queued exactly once
        seekGeneration += 1
        pendingSeekTask?.cancel()
        pendingSeekTask = nil
        // Resume activeSeek and queuedSeek exactly once as .superseded
        if let active = activeSeek {
            activeSeek = nil
            active.continuation.resume(returning: .superseded)
        }
        if let queued = queuedSeek {
            queuedSeek = nil
            queued.continuation.resume(returning: .superseded)
        }
        player?.cancelPendingPrerolls()

        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        for obs in [timeControlObservation, reasonObservation, statusObservation, likelyKeepUpObservation, isPlaybackBufferEmptyObservation] {
            obs?.invalidate()
        }
        timeControlObservation = nil
        reasonObservation = nil
        statusObservation = nil
        likelyKeepUpObservation = nil
        isPlaybackBufferEmptyObservation = nil
        player?.pause()
        player = nil
        pipController = nil
        provider?.teardown()
        provider = nil
        position = 0
        duration = 0
        isPlaying = false
        isBuffering = false
        isPrerolled = false
        loadFailed = false
        lastErrorMessage = nil
    }

    // ── KVO / periodic time observer wiring ────────────────────────────────
    private func observe(_ player: AVPlayer, _ item: AVPlayerItem) {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor in
                guard let self else { return }
                self.recomputeBuffering(player: p, item: item)
                switch p.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                case .paused:
                    self.isPlaying = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = false
                @unknown default:
                    break
                }
            }
        }

        reasonObservation = player.observe(\.reasonForWaitingToPlay, options: [.new]) { [weak self] p, _ in
            Task { @MainActor in
                guard let self else { return }
                self.recomputeBuffering(player: p, item: item)
            }
        }

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            Task { @MainActor in
                guard let self else { return }
                switch it.status {
                case .readyToPlay:
                    self.duration = it.duration.seconds.isFinite ? it.duration.seconds : 0
                case .failed:
                    // P0 FIX: surface the failure — previously unhandled,
                    // which left isBuffering == true forever (infinite spinner).
                    self.loadFailed = true
                    self.lastErrorMessage = it.error?.localizedDescription ?? "Playback failed"
                    self.isPlaying = false
                default:
                    break
                }
                self.recomputeBuffering(player: player, item: it)
            }
        }

        likelyKeepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] it, _ in
            Task { @MainActor in
                guard let self else { return }
                self.recomputeBuffering(player: player, item: it)
            }
        }
        isPlaybackBufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] it, _ in
            Task { @MainActor in
                guard let self else { return }
                self.recomputeBuffering(player: player, item: it)
            }
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.position = time.seconds
            }
        }
    }

    private func recomputeBuffering(player: AVPlayer, item: AVPlayerItem) {
        let controlStatus = player.timeControlStatus
        let bufferEmpty = item.isPlaybackBufferEmpty
        let likelyKeepUp = item.isPlaybackLikelyToKeepUp
        let ready = item.status == .readyToPlay

        let buffering: Bool
        if item.status == .failed {
            // P0 FIX: a dead item is not "buffering" — stop the spinner.
            buffering = false
        } else if controlStatus == .waitingToPlayAtSpecifiedRate {
            buffering = true
        } else if !ready {
            buffering = true
        } else if bufferEmpty {
            buffering = true
        } else if !likelyKeepUp && controlStatus == .playing {
            buffering = true
        } else {
            buffering = false
        }
        isBuffering = buffering
    }
}
