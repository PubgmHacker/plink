// Plink/Realtime/ClockSynchronizer.swift
// Server clock estimator (runbook §5)
//
// Replaces the legacy single-EMA sample taken every 25s. The new design:
//   - 7 probes at 120ms intervals on connect (rapid convergence)
//   - 1 probe every 10s while connected (drift correction)
//
// Algorithm:
//   - For each probe, compute (rtt, offset) where
//       rtt = clientReceivedMs - clientSentMs
//       offset = serverMs - (clientSentMs + rtt/2)
//   - Keep the 20 most recent samples.
//   - For the estimate, take the 5 samples with the smallest RTT (they have
//     the tightest midpoint assumption), then median their offsets.
//   - Median (not mean) is robust to occasional large-RTT outliers
//     (e.g. probe that arrived during a brief network stall).
//
// IMPORTANT (runbook §19):
//   'currentServerTime нельзя хранить как единственный снимок времени:
//    хранить offset к текущим часам.' — This class never stores a snapshot.
//   It stores an OFFSET that's added to Date() at read time.
//
// All mutations are on @MainActor — the WS delegate callback path.

import Foundation
import Observation

@MainActor
@Observable
public final class ClockSynchronizer {
    public struct Sample: Sendable, Equatable {
        public let rttMs: Double
        public let offsetMs: Double
    }

    /// Current best estimate of (serverClock - localClock) in ms.
    /// Positive: server is ahead of local. Negative: server is behind.
    public private(set) var offsetMs: Double = 0

    /// Current best estimate of round-trip time in ms.
    public private(set) var rttMs: Double = 0

    /// Number of probes received since connect. Used to drive the initial
    /// burst→steady-state transition.
    public private(set) var probeCount: Int = 0

    /// True once at least 3 samples have been ingested — the estimate is
    /// considered trustworthy. Below this, callers should treat offsetMs as
    /// 0 (i.e. fall back to local clock).
    public var isSynchronized: Bool { probeCount >= 3 }

    private var samples: [Sample] = []
    private static let maxSamples = 20
    private static let topNByRtt = 5

    public init() {}

    /// Process one clock.probe.reply.
    public func ingest(clientSentMs: Double, serverMs: Double, clientReceivedMs: Double) {
        let rtt = max(0, clientReceivedMs - clientSentMs)
        let midpoint = clientSentMs + rtt / 2
        let offset = serverMs - midpoint

        samples.append(Sample(rttMs: rtt, offsetMs: offset))
        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }
        probeCount += 1

        // Take the N samples with smallest RTT, median their offsets.
        let best = samples.sorted { $0.rttMs < $1.rttMs }.prefix(Self.topNByRtt)
        let offsets = best.map(\.offsetMs).sorted()
        guard !offsets.isEmpty else { return }
        offsetMs = offsets[offsets.count / 2]
        rttMs = best.map(\.rttMs).reduce(0, +) / Double(best.count)
    }

    /// Reset state — called on full reconnect after a long disconnection
    /// (samples are likely stale due to clock drift while offline).
    public func reset() {
        samples.removeAll()
        offsetMs = 0
        rttMs = 0
        probeCount = 0
    }

    /// Current server time in ms, computed on demand from local clock + offset.
    /// NEVER cached as a snapshot (runbook §19).
    public var serverNowMs: Double {
        Date().timeIntervalSince1970 * 1000 + offsetMs
    }
}
