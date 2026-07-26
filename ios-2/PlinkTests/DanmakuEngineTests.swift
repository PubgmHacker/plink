// PlinkTests/DanmakuEngineTests.swift — PATCH 05
//
// Unit tests for DanmakuEngine actor — lane scheduling, capacity cap,
// lane reuse, duration clamping, density gating, settings updates.
//
// These tests are async (actor isolation) but synchronous-friendly —
// they run in <1s total and require no UI, no device, no network.
// Safe for CI.

import XCTest
import SwiftUI
@testable import Plink

@MainActor
final class DanmakuEngineTests: XCTestCase {

    // MARK: - Configuration

    func testConfigure_clampsLaneCountToOne() async {
        let engine = DanmakuEngine()
        await engine.configure(laneCount: 0)
        let count = await engine.laneCount()
        XCTAssertEqual(count, 1, "laneCount 0 must clamp to 1")
    }

    func testConfigure_clampsLaneCountToSeven() async {
        let engine = DanmakuEngine()
        await engine.configure(laneCount: 99)
        let count = await engine.laneCount()
        XCTAssertEqual(count, 7, "laneCount 99 must clamp to 7 (landscape max)")
    }

    func testConfigure_acceptsExactLaneCounts() async {
        for n in [1, 2, 3, 4, 5, 6, 7] {
            let engine = DanmakuEngine()
            await engine.configure(laneCount: n)
            let count = await engine.laneCount()
            XCTAssertEqual(count, n, "laneCount \(n) must be accepted as-is")
        }
    }

    // MARK: - Enqueue (basic)

    func testEnqueue_returnsPlacementWhenLanesAvailable() async {
        let engine = DanmakuEngine()
        await engine.configure(laneCount: 5)
        await engine.updateSettings(DanmakuSettings(enabled: true, density: 1.0))

        let message = DanmakuMessage(text: "hello", color: .white, senderName: "user")
        let placement = await engine.enqueue(message, textWidth: 50, viewportWidth: 400)

        XCTAssertNotNil(placement, "Enqueue with available lanes must return a placement")
        XCTAssertEqual(placement?.lane, 0, "First placement must go to lane 0")
        XCTAssertEqual(placement?.text, "hello")
    }

    func testEnqueue_returnsNilWhenDisabled() async {
        let engine = DanmakuEngine()
        await engine.configure(laneCount: 5)
        await engine.updateSettings(DanmakuSettings(enabled: false, density: 1.0))

        let message = DanmakuMessage(text: "hello", color: .white, senderName: "user")
        let placement = await engine.enqueue(message, textWidth: 50, viewportWidth: 400)

        XCTAssertNil(placement, "Enqueue when disabled must return nil")
    }

    func testEnqueue_returnsNilWhenDensityIsZero() async {
        let engine = DanmakuEngine()
        await engine.configure(laneCount: 5)
        await engine.updateSettings(DanmakuSettings(enabled: true, density: 0.0))

        let message = DanmakuMessage(text: "hello", color: .white, senderName: "user")
        let placement = await engine.enqueue(message, textWidth: 50, viewportWidth: 400)

        XCTAssertNil(placement, "Enqueue with density 0 must always return nil")
    }

    // MARK: - Lane assignment

    func testEnqueue_assignsLanesRoundRobinWhenAllFree() async {
        let engine = DanmakuEngine()
        await engine.configure(laneCount: 3)
        await engine.updateSettings(DanmakuSettings(enabled: true, density: 1.0))

        // All three lanes are free; min-by-availableAt picks lane 0 first,
        // then lane 1 (same availability but min picks lowest index on tie),
        // then lane 2.
        // Actually: min(by:) on equal elements returns the FIRST minimum.
        // After enqueue, lane 0's availableAt is advanced. So next min is
        // lane 1, then lane 2.
        let m1 = DanmakuMessage(text: "1", color: .white, senderName: "u")
        let m2 = DanmakuMessage(text: "2", color: .white, senderName: "u")
        let m3 = DanmakuMessage(text: "3", color: .white, senderName: "u")

        let p1 = await engine.enqueue(m1, textWidth: 50, viewportWidth: 400)
        let p2 = await engine.enqueue(m2, textWidth: 50, viewportWidth: 400)
        let p3 = await engine.enqueue(m3, textWidth: 50, viewportWidth: 400)

        XCTAssertEqual(p1?.lane, 0)
        XCTAssertEqual(p2?.lane, 1)
        XCTAssertEqual(p3?.lane, 2)
    }

    // MARK: - Capacity cap

    func testEnqueue_returnsNilAtMaxActiveCapacity() async {
        let engine = DanmakuEngine()
        await engine.configure(laneCount: 50)  // need 50 lanes to fit 50 active
        await engine.updateSettings(DanmakuSettings(enabled: true, density: 1.0))

        // Enqueue 50 messages — all should fit (one per lane).
        for i in 0..<50 {
            let m = DanmakuMessage(text: "msg\(i)", color: .white, senderName: "u")
            let p = await engine.enqueue(m, textWidth: 50, viewportWidth: 400)
            XCTAssertNotNil(p, "Message \(i) should fit within 50-lane capacity")
        }

        // 51st must be rejected.
        let overflow = DanmakuMessage(text: "overflow", color: .white, senderName: "u")
        let p = await engine.enqueue(overflow, textWidth: 50, viewportWidth: 400)
        XCTAssertNil(p, "51st message must be rejected at maxActive=50")
    }

    // MARK: - Duration clamping

    func testEnqueue_durationClampsToMinimum() async {
        let engine = DanmakuEngine()
        await engine.configure(laneCount: 5)
        await engine.updateSettings(DanmakuSettings(enabled: true, density: 1.0, speed: 1.0))

        // Tiny text + tiny viewport → would compute < 8 → must clamp to 8.
        let m = DanmakuMessage(text: "x", color: .white, senderName: "u")
        let p = await engine.enqueue(m, textWidth: 10, viewportWidth: 50)
        XCTAssertGreaterThanOrEqual(p?.duration ?? 0, 8.0,
                                    "Duration must clamp to 8s minimum")
    }

    func testEnqueue_durationClampsToMaximum() async {
        let engine = DanmakuEngine()
        await engine.configure(laneCount: 5)
        await engine.updateSettings(DanmakuSettings(enabled: true, density: 1.0, speed: 1.0))

        // Huge text + huge viewport → would compute > 12 → must clamp to 12.
        let m = DanmakuMessage(text: String(repeating: "x", count: 500), color: .white, senderName: "u")
        let p = await engine.enqueue(m, textWidth: 2000, viewportWidth: 2000)
        XCTAssertLessThanOrEqual(p?.duration ?? 100, 12.0,
                                 "Duration must clamp to 12s maximum")
    }

    func testEnqueue_speedScalesDurationDown() async {
        let engine = DanmakuEngine()
        await engine.configure(laneCount: 5)
        await engine.updateSettings(DanmakuSettings(enabled: true, density: 1.0, speed: 2.0))

        // Speed 2.0 → duration = baseDuration / 2.0.
        // baseDuration for textWidth=50, viewportWidth=400 → (400+50)/55 ≈ 8.18 → clamps to 8.18
        // With speed 2.0 → 8.18 / 2.0 ≈ 4.09
        let m = DanmakuMessage(text: "hello", color: .white, senderName: "u")
        let p = await engine.enqueue(m, textWidth: 50, viewportWidth: 400)
        let duration = p?.duration ?? 0
        XCTAssertEqual(duration, 4.09, accuracy: 0.1,
                       "Speed 2.0 must halve the duration")
    }

    // MARK: - Poll

    func testPoll_returnsActivePlacements() async {
        let engine = DanmakuEngine()
        await engine.configure(laneCount: 5)
        await engine.updateSettings(DanmakuSettings(enabled: true, density: 1.0))

        let m1 = DanmakuMessage(text: "1", color: .white, senderName: "u")
        let m2 = DanmakuMessage(text: "2", color: .white, senderName: "u")
        _ = await engine.enqueue(m1, textWidth: 50, viewportWidth: 400)
        _ = await engine.enqueue(m2, textWidth: 50, viewportWidth: 400)

        let now = ContinuousClock.now
        let placements = await engine.poll(at: now)
        XCTAssertEqual(placements.count, 2, "Poll immediately after enqueue must return both placements")
    }

    func testPoll_purgesExpiredPlacements() async {
        let engine = DanmakuEngine()
        await engine.configure(laneCount: 5)
        await engine.updateSettings(DanmakuSettings(enabled: true, density: 1.0, speed: 1.0))

        // Use minimum duration (8s) by tiny text+viewport.
        let m = DanmakuMessage(text: "x", color: .white, senderName: "u")
        _ = await engine.enqueue(m, textWidth: 10, viewportWidth: 50)

        // Poll at now+10s — placement should have expired (progress > 1.0).
        let future = ContinuousClock.now.advanced(by: .seconds(10))
        let placements = await engine.poll(at: future)
        XCTAssertEqual(placements.count, 0, "Placement must be purged after duration expires")

        let active = await engine.activeCount()
        XCTAssertEqual(active, 0, "activeCount must be 0 after purge")
    }

    func testPoll_sortsByLane() async {
        let engine = DanmakuEngine()
        await engine.configure(laneCount: 5)
        await engine.updateSettings(DanmakuSettings(enabled: true, density: 1.0))

        // Enqueue 3 — they go to lanes 0, 1, 2 (in order).
        _ = await engine.enqueue(DanmakuMessage(text: "1", color: .white, senderName: "u"), textWidth: 50, viewportWidth: 400)
        _ = await engine.enqueue(DanmakuMessage(text: "2", color: .white, senderName: "u"), textWidth: 50, viewportWidth: 400)
        _ = await engine.enqueue(DanmakuMessage(text: "3", color: .white, senderName: "u"), textWidth: 50, viewportWidth: 400)

        let placements = await engine.poll(at: ContinuousClock.now)
        XCTAssertEqual(placements.map(\.lane), [0, 1, 2],
                       "Poll must return placements sorted by lane")
    }

    // MARK: - Clear

    func testClear_removesAllPlacements() async {
        let engine = DanmakuEngine()
        await engine.configure(laneCount: 5)
        await engine.updateSettings(DanmakuSettings(enabled: true, density: 1.0))

        _ = await engine.enqueue(DanmakuMessage(text: "1", color: .white, senderName: "u"), textWidth: 50, viewportWidth: 400)
        _ = await engine.enqueue(DanmakuMessage(text: "2", color: .white, senderName: "u"), textWidth: 50, viewportWidth: 400)
        let beforeClear = await engine.activeCount()
        XCTAssertEqual(beforeClear, 2)

        await engine.clear()
        let afterClear = await engine.activeCount()
        XCTAssertEqual(afterClear, 0, "clear() must remove all active placements")
    }

    // MARK: - Settings

    func testUpdateSettings_persists() async {
        let engine = DanmakuEngine()
        let new = DanmakuSettings(enabled: false, density: 0.3, opacity: 0.6, speed: 1.5, palette: .premium)
        await engine.updateSettings(new)

        let retrieved = await engine.currentSettings()
        XCTAssertEqual(retrieved, new)
    }

    func testEnqueue_respectsUpdatedDensity() async {
        let engine = DanmakuEngine()
        await engine.configure(laneCount: 5)
        await engine.updateSettings(DanmakuSettings(enabled: true, density: 1.0))

        // First enqueue succeeds.
        let m1 = DanmakuMessage(text: "1", color: .white, senderName: "u")
        let p1 = await engine.enqueue(m1, textWidth: 50, viewportWidth: 400)
        XCTAssertNotNil(p1)

        // Drop density to 0 — all subsequent enqueues must fail.
        await engine.updateSettings(DanmakuSettings(enabled: true, density: 0.0))
        let m2 = DanmakuMessage(text: "2", color: .white, senderName: "u")
        let p2 = await engine.enqueue(m2, textWidth: 50, viewportWidth: 400)
        XCTAssertNil(p2, "After density update to 0, enqueue must return nil")
    }

    // MARK: - Placement progress

    func testPlacementProgress_isZeroAtCreatedAt() {
        let now = ContinuousClock.now
        let placement = DanmakuPlacement(
            id: UUID(), lane: 0, duration: 10, color: .white,
            text: "x", isPremium: false, isAdmin: false, createdAt: now,
            createdAtDate: Date()
        )
        let progress = placement.progress(at: now, speed: 1.0)
        XCTAssertEqual(progress, 0.0, accuracy: 0.001,
                       "Progress at createdAt must be 0")
    }

    func testPlacementProgress_isOneAtDuration() {
        let now = ContinuousClock.now
        let placement = DanmakuPlacement(
            id: UUID(), lane: 0, duration: 10, color: .white,
            text: "x", isPremium: false, isAdmin: false, createdAt: now,
            createdAtDate: Date()
        )
        let atEnd = now.advanced(by: .seconds(10))
        let progress = placement.progress(at: atEnd, speed: 1.0)
        XCTAssertEqual(progress, 1.0, accuracy: 0.01,
                       "Progress at duration must be ~1.0")
    }

    func testPlacementProgress_speedScalesProgress() {
        let now = ContinuousClock.now
        let placement = DanmakuPlacement(
            id: UUID(), lane: 0, duration: 10, color: .white,
            text: "x", isPremium: false, isAdmin: false, createdAt: now,
            createdAtDate: Date()
        )
        // At 5s elapsed with speed 2.0, progress should be 5 / (10 * 2.0) = 0.25
        let atFiveSeconds = now.advanced(by: .seconds(5))
        let progress = placement.progress(at: atFiveSeconds, speed: 2.0)
        XCTAssertEqual(progress, 0.25, accuracy: 0.01,
                       "Speed 2.0 must halve the progress at the same elapsed time")
    }

    // MARK: - Settings struct

    func testDanmakuSettings_defaultValues() {
        let s = DanmakuSettings()
        XCTAssertTrue(s.enabled)
        XCTAssertEqual(s.density, 0.7)
        XCTAssertEqual(s.opacity, 0.85)
        XCTAssertEqual(s.speed, 1.0)
        XCTAssertEqual(s.palette, .free)
    }

    func testDanmakuSettings_palateEnumCases() {
        XCTAssertEqual(DanmakuSettings.Palette.free.rawValue, "free")
        XCTAssertEqual(DanmakuSettings.Palette.premium.rawValue, "premium")
        XCTAssertEqual(DanmakuSettings.Palette.allCases.count, 2)
    }
}
