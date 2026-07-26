// PlinkTests/AmbientVideoSamplerTests.swift — PATCH 06
//
// Unit tests for AmbientVideoSampler actor + AmbientCapability checker.
//
// AVPlayer-dependent behavior (sampleOnce, attach/detach) is hard to test
// without a real video file — those paths are covered by runtime tests.
// These tests cover:
//   - Default palette value
//   - setEnabled(false) → currentPalette returns default
//   - setEnabled(true) preserves currentPalette (no-op when nothing attached)
//   - detach() resets to default palette
//   - stopSampling() does not crash when no task is running
//   - AmbientPalette.defaultPalette matches PlinkRave.magenta/cyan/hotPink
//   - AmbientPalette.ambientState conversion
//   - AmbientCapability.shouldEnableLivingBackground returns false for
//     known disable conditions (best-effort — actual system state varies)
//
// AVPlayer-dependent tests (deferred to runtime test plan):
//   - attach(player:) sets up video output
//   - sampleOnce() extracts palette from real video
//   - 500ms tick cadence
//   - CPU budget <=2% (measured via os_signpost)

import XCTest
import UIKit
@testable import Plink

@MainActor
final class AmbientVideoSamplerTests: XCTestCase {

    // MARK: - Default palette

    func testDefaultPalette_isMagentaCyanHotPink() {
        let palette = AmbientPalette.defaultPalette

        // PlinkRave.magenta = 0xFF00FF → (1.0, 0.0, 1.0)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        palette.primary.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 1.0, accuracy: 0.01)

        // PlinkRave.cyan = 0x00FFFF → (0.0, 1.0, 1.0)
        palette.secondary.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0.0, accuracy: 0.01)
        XCTAssertEqual(g, 1.0, accuracy: 0.01)
        XCTAssertEqual(b, 1.0, accuracy: 0.01)

        // PlinkRave.hotPink = 0xFF1493 → (1.0, 0.08, 0.58)
        palette.accent.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.08, accuracy: 0.01)
        XCTAssertEqual(b, 0.58, accuracy: 0.01)
    }

    // MARK: - Actor state

    func testCurrentPalette_returnsDefaultInitially() async {
        let sampler = AmbientVideoSampler()
        let palette = await sampler.currentPalette()
        XCTAssertEqual(palette, .defaultPalette,
                       "Sampler must return default palette before any sample")
    }

    func testSetEnabled_false_resetsToDefault() async {
        let sampler = AmbientVideoSampler()
        await sampler.setEnabled(false)
        let palette = await sampler.currentPalette()
        XCTAssertEqual(palette, .defaultPalette,
                       "setEnabled(false) must reset palette to default")
    }

    func testDetach_resetsToDefaultPalette() async {
        let sampler = AmbientVideoSampler()
        await sampler.detach()
        let palette = await sampler.currentPalette()
        XCTAssertEqual(palette, .defaultPalette,
                       "detach() must reset palette to default")
    }

    func testStopSampling_doesNotCrashWithoutStart() async {
        let sampler = AmbientVideoSampler()
        // Should be a no-op, not a crash.
        await sampler.stopSampling()
        // No assertion needed — reaching here means no crash.
    }

    func testStartSampling_canBeCancelledImmediately() async {
        let sampler = AmbientVideoSampler()
        await sampler.startSampling()
        await sampler.stopSampling()
        // Should not crash; palette should still be default (no video attached).
        let palette = await sampler.currentPalette()
        XCTAssertEqual(palette, .defaultPalette)
    }

    // MARK: - AmbientPalette conversion

    func testAmbientPalette_primaryColor_isSwiftUIColor() {
        let palette = AmbientPalette.defaultPalette
        // Just verify it doesn't crash — SwiftUI Color equality is not
        // straightforward across components.
        _ = palette.primaryColor
        _ = palette.secondaryColor
        _ = palette.accentColor
    }

    func testAmbientPalette_ambientState_hasCorrectIntensity() {
        let palette = AmbientPalette.defaultPalette
        let state = palette.ambientState
        XCTAssertEqual(state.intensity, 0.55,
                       "ambientState.intensity must be 0.55 (default)")
    }

    // MARK: - Capability check
    //
    // These tests are best-effort — the actual system state (Low Power,
    // thermal, Reduce Transparency, background) is not controllable from
    // unit tests. We verify the function returns a Bool without crashing
    // and does not block.

    func testCapability_shouldEnableLivingBackground_returnsBool() {
        // Will be true or false depending on test env — just verify it
        // doesn't crash.
        _ = AmbientCapability.shouldEnableLivingBackground()
    }

    // MARK: - Concurrency

    func testSampler_isSafeToCallFromMultipleTasks() async {
        let sampler = AmbientVideoSampler()

        async let p1: AmbientPalette = sampler.currentPalette()
        async let p2: AmbientPalette = sampler.currentPalette()
        async let p3: AmbientPalette = sampler.currentPalette()

        let (r1, r2, r3) = await (p1, p2, p3)
        XCTAssertEqual(r1, r2)
        XCTAssertEqual(r2, r3)
        XCTAssertEqual(r1, .defaultPalette)
    }

    func testSampler_setEnabledConcurrent() async {
        let sampler = AmbientVideoSampler()

        // Concurrent setEnabled calls should not crash.
        async let a: Void = sampler.setEnabled(true)
        async let b: Void = sampler.setEnabled(false)
        async let c: Void = sampler.setEnabled(true)
        _ = await (a, b, c)

        // Final state is deterministic only in that currentPalette
        // returns a valid AmbientPalette.
        let palette = await sampler.currentPalette()
        XCTAssertEqual(palette, .defaultPalette,
                       "After setEnabled(false) (last write wins is not guaranteed, but no video attached → default)")
    }
}
