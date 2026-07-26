package com.plink.app.data.sync

import android.os.Handler
import android.os.Looper
import kotlin.math.abs

data class RoomPlaybackState(
    val protocolVersion: Int = 2,
    val roomId: String,
    val epoch: Int,
    val seq: Int,
    val mediaId: String?,
    val positionMs: Long,
    val playing: Boolean,
    val rate: Double,
    val effectiveAtServerMs: Long,
    val issuedBy: String,
)

interface PlayerSyncAdapter {
    fun getPositionSec(): Double
    fun getDurationSec(): Double
    fun isPlaying(): Boolean
    fun play()
    fun pause()
    fun seek(sec: Double)

    /**
     * M13 (parity with iOS M12): smooth drift correction via playback rate.
     * Default no-op keeps existing adapters compiling; players that support
     * it (YouTube IFrame API → setPlaybackRate) should override.
     */
    fun setRate(rate: Double) {}
}

class OrderedSyncController(
    private val clock: ClockSynchronizer,
    private val player: PlayerSyncAdapter,
) {
    var lastEpoch = 0
        private set
    var lastSeq = 0
        private set
    var hasAppliedAnyState = false
        private set
    var lastDriftMs = 0.0
        private set

    private val mainHandler = Handler(Looper.getMainLooper())
    private var latestState: RoomPlaybackState? = null
    private var rateCorrectionActive = false
    private var recheckRunnable: Runnable? = null

    companion object {
        /** Above this drift a hard seek is cheaper than a long rate correction. */
        private const val HARD_SEEK_MS = 750.0
        /** Below this drift while paused / above it while playing we act. */
        private const val SOFT_MS = 120.0
        /** Rate correction is released once drift falls inside the dead zone. */
        private const val DEAD_ZONE_MS = 40.0
        /** M13 P-controller: correction proportional to drift (iOS parity). */
        private const val K_P = 0.0002
        /** Never nudge more than ±5% — inaudible / invisible to the viewer. */
        private const val MAX_CORRECTION = 0.05
    }

    fun apply(state: RoomPlaybackState) {
        if (hasAppliedAnyState) {
            if (state.epoch < lastEpoch) return
            if (state.epoch == lastEpoch && state.seq <= lastSeq) return
        }
        lastEpoch = state.epoch
        lastSeq = state.seq
        hasAppliedAnyState = true
        latestState = state

        val serverNow = if (clock.isSynchronized) clock.serverNowMs else System.currentTimeMillis()
        val waitMs = state.effectiveAtServerMs - serverNow
        val run = Runnable { applyTransition(state) }
        if (waitMs > 0) {
            mainHandler.postDelayed(run, waitMs.coerceAtMost(2000))
        } else {
            mainHandler.post(run)
        }
    }

    private fun applyTransition(state: RoomPlaybackState) {
        cancelRecheck()

        val target = targetPosition(state)
        val driftMs = (target - player.getPositionSec()) * 1000.0
        lastDriftMs = driftMs

        val playingMismatch = state.playing != player.isPlaying()
        if (playingMismatch || abs(driftMs) >= HARD_SEEK_MS) {
            releaseRateCorrection(state)
            player.seek(target)
            if (state.playing) player.play() else player.pause()
            return
        }

        if (!state.playing) {
            // Paused: exact position matters, rate does not.
            releaseRateCorrection(state)
            if (abs(driftMs) >= SOFT_MS) player.seek(target)
            return
        }

        when {
            abs(driftMs) >= SOFT_MS -> {
                // M13: P-controller — proportional rate nudge instead of a
                // jarring seek. Adaptive window: re-check sooner when far off.
                val correction = (K_P * driftMs).coerceIn(-MAX_CORRECTION, MAX_CORRECTION)
                player.setRate(state.rate * (1.0 + correction))
                rateCorrectionActive = true
                scheduleRecheck(if (abs(driftMs) >= 250) 1000L else 2000L)
            }
            rateCorrectionActive && abs(driftMs) <= DEAD_ZONE_MS -> {
                releaseRateCorrection(state)
            }
            rateCorrectionActive -> {
                // Inside soft band but not yet converged — keep nudging.
                scheduleRecheck(1000L)
            }
        }
    }

    private fun targetPosition(state: RoomPlaybackState): Double {
        val serverNow = if (clock.isSynchronized) clock.serverNowMs else System.currentTimeMillis()
        val elapsed = if (state.playing) {
            ((serverNow - state.effectiveAtServerMs).coerceAtLeast(0)) / 1000.0
        } else {
            0.0
        }
        return state.positionMs / 1000.0 + elapsed
    }

    private fun scheduleRecheck(delayMs: Long) {
        val run = Runnable { latestState?.let { applyTransition(it) } }
        recheckRunnable = run
        mainHandler.postDelayed(run, delayMs)
    }

    private fun cancelRecheck() {
        recheckRunnable?.let { mainHandler.removeCallbacks(it) }
        recheckRunnable = null
    }

    private fun releaseRateCorrection(state: RoomPlaybackState) {
        if (rateCorrectionActive) {
            player.setRate(state.rate)
            rateCorrectionActive = false
        }
    }
}
