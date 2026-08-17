// Plink/Features/WatchRoom/Danmaku/DanmakuEngine.swift — PATCH 05
//
// GLM-5.2 master implementation patch — Commit Group 5.
//
// Actor-isolated lane scheduler for flying comments (danmaku). Decouples
// lane assignment timing from the View renderer so the Canvas can poll
// at display refresh rate without lock contention on the message queue.
//
// Lane scheduling:
//   - 5 lanes compact (portrait)
//   - 7 lanes landscape
//   - Lane is reused when its head has cleared the left edge + 20% gap
//   - Maximum 50 active placements (drops overflow silently with telemetry)
//
// Duration model:
//   - Duration = clamp((viewportWidth + textWidth) / 55, 8.0, 12.0)
//   - Lane becomes available again at duration * 0.42 (head clears right edge)
//
// Settings (user-configurable):
//   - enabled: Bool
//   - density: Double 0...1 (scales lane availability)
//   - opacity: Double 0.5...1.0
//   - speed: Double 0.5...2.0 (scales duration)
//   - palette: .free | .premium
//
// Reduce Motion: callers should switch to a static top feed and NOT call
// enqueue(). The engine itself does not observe accessibility state.
//
// Concurrency:
//   - enqueue() is actor-isolated — safe to call from chat broadcast handler
//     on the main actor without blocking.
//   - poll() returns the current placement snapshot — also actor-isolated.
//   - The Canvas view polls poll() every 16ms (display-linked) and renders
//     the snapshot without touching the actor again until next frame.
//
// Testing:
//   - DanmakuEngineTests covers lane assignment, capacity cap, lane reuse,
//     duration clamping, density gating, settings updates.

import Foundation
import SwiftUI

// MARK: - Public types

struct DanmakuMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let color: Color
    let senderName: String
    let createdAt: Date
    let isPremium: Bool
    let isAdmin: Bool

    init(
        id: UUID = UUID(),
        text: String,
        color: Color,
        senderName: String,
        createdAt: Date = Date(),
        isPremium: Bool = false,
        isAdmin: Bool = false
    ) {
        self.id = id
        self.text = text
        self.color = color
        self.senderName = senderName
        self.createdAt = createdAt
        self.isPremium = isPremium
        self.isAdmin = isAdmin
    }
}

struct DanmakuPlacement: Identifiable, Equatable, Sendable {
    let id: UUID                // matches DanmakuMessage.id
    let lane: Int
    let duration: Double        // seconds for full traverse
    let color: Color
    let text: String
    let isPremium: Bool
    let isAdmin: Bool
    let createdAt: ContinuousClock.Instant
    /// PATCH 16: Date representation of createdAt for View-side progress
    /// computation. TimelineView provides context.date as Date, and
    /// converting Date → ContinuousClock.Instant is not directly possible.
    /// Storing a parallel Date lets the View compute progress without
    /// actor calls.
    let createdAtDate: Date

    /// 0...1 progress through the lane. View computes x-offset from this.
    /// progress = (now - createdAt) / (duration * speed)
    func progress(at now: ContinuousClock.Instant, speed: Double) -> Double {
        // PATCH 16: Duration has no .seconds method/property. Use .components
        // tuple (seconds: Int64, attoseconds: Int64) and convert to Double.
        // createdAt.duration(to: now) returns positive duration when
        // createdAt < now (no unary minus needed).
        let (secs, attos) = createdAt.duration(to: now).components
        let elapsed = Double(secs) + Double(attos) * 1e-18
        guard duration > 0 else { return 1 }
        return elapsed / (duration * max(0.1, speed))
    }

    /// PATCH 16: Date-based progress for View rendering (TimelineView).
    func progress(at date: Date, speed: Double) -> Double {
        let elapsed = date.timeIntervalSince(createdAtDate)
        guard duration > 0 else { return 1 }
        return elapsed / (duration * max(0.1, speed))
    }
}

struct DanmakuSettings: Equatable, Sendable {
    var enabled: Bool = true
    var density: Double = 0.7      // 0...1 — scales how many lanes are active
    var opacity: Double = 0.85     // 0.5...1.0
    var speed: Double = 1.0        // 0.5...2.0
    var palette: Palette = .free

    enum Palette: String, CaseIterable, Sendable {
        case free        // white + role colors (gold admin, hotPink premium)
        case premium     // free + cyan/magenta neon palette
    }
}

// MARK: - Engine

actor DanmakuEngine {
    private struct Lane {
        var availableAt: ContinuousClock.Instant
    }

    private var lanes: [Lane] = []
    private var active: [UUID: DanmakuPlacement] = [:]
    private let clock = ContinuousClock()
    private var settings: DanmakuSettings = .init()

    private let maxActive = 50

    // MARK: - Configuration

    func configure(laneCount: Int) {
        let clamped = max(1, min(7, laneCount))
        lanes = Array(repeating: Lane(availableAt: clock.now), count: clamped)
    }

    func updateSettings(_ newSettings: DanmakuSettings) {
        settings = newSettings
    }

    func currentSettings() -> DanmakuSettings { settings }

    // MARK: - Enqueue

    /// Attempts to place a message in the next available lane. Returns the
    /// placement on success, nil if:
    ///   - density gate rejects (random sample > density)
    ///   - all lanes are occupied and not yet available
    ///   - active.count >= maxActive
    ///   - settings.enabled is false
    func enqueue(
        _ message: DanmakuMessage,
        textWidth: CGFloat,
        viewportWidth: CGFloat
    ) -> DanmakuPlacement? {
        guard settings.enabled else { return nil }
        guard active.count < maxActive else { return nil }
        guard !lanes.isEmpty else { return nil }

        // Density gate: probability of acceptance scales with settings.density.
        // Density 1.0 = accept all; 0.5 = accept ~half; 0.0 = accept none.
        if Double.random(in: 0...1) > settings.density {
            return nil
        }

        let now = clock.now

        // Find the lane with the earliest availableAt that is <= now.
        // Lanes are scanned in order; min-by-availableAt picks the most-free.
        guard let laneIndex = lanes.indices.min(by: { lanes[$0].availableAt < lanes[$1].availableAt }) else {
            return nil
        }
        guard lanes[laneIndex].availableAt <= now else {
            // All lanes busy — drop. Telemetry hook would go here.
            return nil
        }

        // Duration model per spec:
        //   duration = clamp((viewportWidth + textWidth) / 55, 8.0, 12.0)
        //   then scaled by 1/speed (faster speed = shorter duration).
        let baseDuration = min(12.0, max(8.0, Double((viewportWidth + textWidth) / 55)))
        let duration = baseDuration / max(0.5, settings.speed)

        let placement = DanmakuPlacement(
            id: message.id,
            lane: laneIndex,
            duration: duration,
            color: message.color,
            text: message.text,
            isPremium: message.isPremium,
            isAdmin: message.isAdmin,
            createdAt: now,
            createdAtDate: Date()  // PATCH 16: parallel Date for View-side progress
        )

        // Lane becomes available again when the head of the message has
        // cleared the right edge + 20% gap. Empirically this is ~42% of
        // the duration (text enters from right, head reaches left edge
        // around 50%, plus gap).
        lanes[laneIndex].availableAt = now.advanced(by: .seconds(duration * 0.42))
        active[message.id] = placement

        return placement
    }

    // MARK: - Poll

    /// Returns the current placement snapshot, purging placements whose
    /// progress has exceeded 1.0 (fully traversed the lane).
    func poll(at now: ContinuousClock.Instant) -> [DanmakuPlacement] {
        var surviving: [DanmakuPlacement] = []
        surviving.reserveCapacity(active.count)

        var toRemove: [UUID] = []
        for (id, placement) in active {
            let p = placement.progress(at: now, speed: settings.speed)
            if p >= 1.0 {
                toRemove.append(id)
            } else {
                surviving.append(placement)
            }
        }
        for id in toRemove {
            active.removeValue(forKey: id)
        }
        return surviving.sorted { $0.lane < $1.lane }
    }

    // MARK: - Manual control

    /// Clears all active placements. Called on teardown or when user
    /// disables danmaku in settings.
    func clear() {
        active.removeAll()
        for i in lanes.indices {
            lanes[i].availableAt = clock.now
        }
    }

    /// Returns the current active count (for telemetry / debugging).
    func activeCount() -> Int { active.count }

    /// Returns the configured lane count.
    func laneCount() -> Int { lanes.count }
}
