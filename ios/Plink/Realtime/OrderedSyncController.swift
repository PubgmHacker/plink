// Plink/Realtime/OrderedSyncController.swift
// Authoritative state → player bridge
//
// Rate correction — playback rate returns to the authoritative rate reliably:
//   - The LAST applied authoritative state is stored; drift is recomputed from
//     current player position vs projected target on each re-evaluation.
//   - state.rate is the base rate for corrections, never a hardcoded 1.0.
//   - After the correction window (2s), if drift < 80ms → setRate(state.rate).
//   - If drift is still > 80ms after the window → keep nudging but increment
//     a counter; after 3 windows, fall back to a precise seek.
//
// effectiveAt transition:
//   - Server sets effectiveAtServerMs = now + 80ms (slightly in the future).
//   - Client computes elapsed = max(0, serverNow - effectiveAt). If
//     effectiveAt is in the future, elapsed is 0 — but the client must NOT
//     apply play/pause/seek until the effectiveAt deadline arrives.
//   - A Task sleeps until effectiveAtServerMs (converted to local time via
//     clock.offsetMs) before the transition is applied.
//   - For non-transition states (drift correction only) there is no wait —
//     it applies immediately because the player is already playing.
//
// All player interactions are async — the player is the single source of
// truth for current position.

import Foundation
import Observation

// ContinuousClock for monotonic waits (immune to system clock changes).
// ClockSynchronizer still uses wall clock for server epoch mapping, but local
// duration waits use ContinuousClock.

@MainActor
@Observable
public final class OrderedSyncController {
    // Watermark — drops out-of-order / duplicate messages.
    public private(set) var lastEpoch: Int64 = 0
    public private(set) var lastSeq: Int64 = 0
    public private(set) var hasAppliedAnyState: Bool = false

    public private(set) var lastDriftMs: Double = 0
    public private(set) var hardCorrectionCount: Int = 0

    private let clock: ClockSynchronizer
    private let player: PlaybackControlling

    // Store last applied state for re-evaluation
    private var lastAppliedState: RealtimeRoomState?
    private var rateCorrectionTask: Task<Void, Never>?
    private var effectiveAtWaitTask: Task<Void, Never>?
    private var correctionWindowCount = 0

    // EMA of measured precise-seek latency (ms). Used to "lead" the
    // target position on hard seeks while playing so the player lands
    // closer to the authoritative position after the seek completes.
    public private(set) var seekLatencyEmaMs: Double = 0

    public init(clock: ClockSynchronizer, player: PlaybackControlling) {
        self.clock = clock
        self.player = player
    }

    public func apply(_ state: RealtimeRoomState) async {
        // ── 1. Ordering watermark ───────────────────────────────────────
        if hasAppliedAnyState {
            if state.epoch < lastEpoch { return }
            if state.epoch == lastEpoch && state.seq <= lastSeq { return }
        }
        lastEpoch = state.epoch
        lastSeq = state.seq
        hasAppliedAnyState = true
        lastAppliedState = state

        // ── 2. Wait for the effectiveAt deadline if it's in the future ──
        // The server sets effectiveAtServerMs = now + 80ms so all clients
        // apply the transition at the same wall-clock moment. We must NOT
        // apply play/pause/seek before that moment.
        // Use ContinuousClock for monotonic wait (immune to system clock changes).
        let serverNow = clock.serverNowMs
        let waitMs = Double(state.effectiveAtServerMs) - serverNow
        if waitMs > 0 {
            effectiveAtWaitTask?.cancel()
            effectiveAtWaitTask = Task { [weak self] in
                let clock = ContinuousClock()
                let duration = Duration.milliseconds(Int64(waitMs))
                try? await clock.sleep(for: duration)
                if !Task.isCancelled {
                    await self?.applyTransition(state)
                }
            }
            await effectiveAtWaitTask?.value
            effectiveAtWaitTask = nil
        } else {
            await applyTransition(state)
        }
    }

    /// Re-issues the last authoritative transition to the player. Called right
    /// after PlaybackProxy attaches its real target: authoritative states that
    /// arrived during the (seconds-long) controller `prepare` were applied while
    /// the proxy had no target, so their seek was queued as `pendingSeek` but
    /// `play()`/`pause()` was skipped (`seekResult == .unavailable` → early
    /// return). Without this a late-joiner seeks to the right spot yet never
    /// starts playing. Deliberately bypasses the ordering watermark — it replays
    /// the SAME stored state (same epoch/seq), it does not accept a new one.
    /// No-op until at least one state has been applied, so the host who has not
    /// received any state yet is unaffected.
    public func reapplyLastState() async {
        guard hasAppliedAnyState, let state = lastAppliedState else { return }
        await applyTransition(state)
    }

    private func applyTransition(_ state: RealtimeRoomState) async {
        // ── 3. Compute target position ──────────────────────────────────
        let elapsed: Double
        if state.playing {
            elapsed = max(0, clock.serverNowMs - Double(state.effectiveAtServerMs)) / 1000.0
        } else {
            elapsed = 0  // Pause does NOT extrapolate
        }
        let target = Double(state.positionMs) / 1000.0 + elapsed
        let driftMs = (target - player.position) * 1000
        lastDriftMs = driftMs

        // ── 4. Decide correction strategy ───────────────────────────────
        let playingMismatch = state.playing != player.isPlaying
        let absDrift = abs(driftMs)

        if playingMismatch || absDrift >= 750 {
            cancelRateCorrection()
            // Lead the target by measured seek latency while playing —
            // remote playback keeps advancing while our precise seek runs.
            let compensatedTarget = state.playing ? target + seekLatencyEmaMs / 1000.0 : target
            let seekStart = ContinuousClock.now
            // Only proceed with play/pause if our seek was APPLIED.
            // If superseded by a newer seek, that seek's caller owns the
            // next action — we must NOT call play() on stale target.
            let seekResult = await player.seek(to: compensatedTarget, precise: true)
            recordSeekLatency(from: seekStart)
            if seekResult == .superseded {
                return
            }
            if seekResult == .unavailable {
                // Proxy has no target — skip transition, state will replay
                return
            }
            if state.playing {
                await player.play()
            } else {
                player.pause()
            }
            // Return to state.rate (not always 1.0)
            player.setRate(Float(state.rate))
            if absDrift >= 750 { hardCorrectionCount += 1 }
            correctionWindowCount = 0
            return
        }

        if !state.playing {
            if absDrift >= 80 {
                cancelRateCorrection()
                let seekResult = await player.seek(to: target, precise: true)
                if seekResult == .superseded || seekResult == .unavailable { return }  //
                player.setRate(Float(state.rate))
            }
            return
        }

        // ── 5. Drift correction via rate nudge ──────────────────────────
        if absDrift < 80 {
            if rateCorrectionTask != nil {
                cancelRateCorrection()
                player.setRate(Float(state.rate))
            }
            return
        }

        // Base rate is state.rate, not always 1.0
        // Proportional (P) controller — correction scales with drift,
        // clamped to ±5% so it stays imperceptible to viewers.
        let baseRate = Float(state.rate)
        player.setRate(correctionRate(baseRate: baseRate, driftMs: driftMs))

        cancelRateCorrection()
        correctionWindowCount += 1
        let windowNs = correctionWindowNs(absDrift: absDrift)
        rateCorrectionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: windowNs)
            await self?.reEvaluateRate()
        }
    }

    // Recompute drift from CURRENT player position vs projected
    // target. If drift < 80ms → reset to state.rate. If 3 correction
    // windows have passed without convergence → fall back to precise seek.
    private func reEvaluateRate() async {
        guard let state = lastAppliedState, hasAppliedAnyState else { return }
        let elapsed: Double
        if state.playing {
            elapsed = max(0, clock.serverNowMs - Double(state.effectiveAtServerMs)) / 1000.0
        } else {
            elapsed = 0
        }
        let target = Double(state.positionMs) / 1000.0 + elapsed
        let driftMs = (target - player.position) * 1000
        lastDriftMs = driftMs
        let absDrift = abs(driftMs)
        let baseRate = Float(state.rate)

        if absDrift < 80 {
            player.setRate(baseRate)
            cancelRateCorrection()
            correctionWindowCount = 0
            return
        }
        if correctionWindowCount >= 3 {
            cancelRateCorrection()
            // Lead the fallback seek by measured seek latency
            let compensatedTarget = state.playing ? target + seekLatencyEmaMs / 1000.0 : target
            let seekStart = ContinuousClock.now
            let seekResult = await player.seek(to: compensatedTarget, precise: true)
            recordSeekLatency(from: seekStart)
            if seekResult == .superseded || seekResult == .unavailable { return }  //
            player.setRate(baseRate)
            hardCorrectionCount += 1
            correctionWindowCount = 0
            return
        }
        // Continue nudging with recomputed proportional rate
        player.setRate(correctionRate(baseRate: baseRate, driftMs: driftMs))
        let windowNs = correctionWindowNs(absDrift: absDrift)
        rateCorrectionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: windowNs)
            await self?.reEvaluateRate()
        }
    }

    // MARK: - M12 sync upgrades

    /// Proportional (P) controller: correction gain scales with drift and is
    /// clamped to ±5%. 100 ms drift → 2% speed change; ≥250 ms → 5%.
    /// Callers handle the <80 ms deadband (base rate, no correction).
    private func correctionRate(baseRate: Float, driftMs: Double) -> Float {
        let kP = 0.0002
        let gain = max(-0.05, min(0.05, driftMs * kP))
        return baseRate * Float(1.0 + gain)
    }

    /// Adaptive re-evaluation window: re-check sooner when drift is large.
    private func correctionWindowNs(absDrift: Double) -> UInt64 {
        absDrift >= 250 ? 1_000_000_000 : 2_000_000_000
    }

    /// EMA of measured precise-seek latency, clamped so a single network
    /// stall cannot poison the estimate.
    private func recordSeekLatency(from start: ContinuousClock.Instant) {
        let elapsed = start.duration(to: .now)
        let ms = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1e15
        let clamped = min(max(ms, 0), 1_500)
        seekLatencyEmaMs = seekLatencyEmaMs == 0
            ? clamped
            : seekLatencyEmaMs * 0.7 + clamped * 0.3
    }

    private func cancelRateCorrection() {
        rateCorrectionTask?.cancel()
        rateCorrectionTask = nil
    }

    public func resetForReconnect() {
        cancelRateCorrection()
        effectiveAtWaitTask?.cancel()
        effectiveAtWaitTask = nil
        if let state = lastAppliedState {
            player.setRate(Float(state.rate))
        } else {
            player.setRate(1.0)
        }
        // Preserve watermark — used as afterSeq in snapshot request.
        // Do NOT reset lastEpoch/lastSeq.
    }

    public func resetCompletely() {
        cancelRateCorrection()
        effectiveAtWaitTask?.cancel()
        effectiveAtWaitTask = nil
        lastEpoch = 0
        lastSeq = 0
        hasAppliedAnyState = false
        lastAppliedState = nil
        lastDriftMs = 0
        hardCorrectionCount = 0
        correctionWindowCount = 0
        seekLatencyEmaMs = 0
    }
}
