//
// PlinkTests/VideoThemeMotionPolicyTests.swift
//
// Тесты энергодисциплины видео-тем. VideoThemeMotionPolicy — чистая функция
// (без UIKit), поэтому проверяется без симулятора. На эти тесты ссылается
// шапка Plink/Design/Cinematic/VideoThemeMotionPolicy.swift.
//

import XCTest
@testable import Plink

final class VideoThemeMotionPolicyTests: XCTestCase {

    private func inputs(
        reduceMotion: Bool = false,
        lowPowerMode: Bool = false,
        thermalThrottled: Bool = false,
        sceneActive: Bool = true,
        motionPreferenceEnabled: Bool = true
    ) -> VideoThemeMotionInputs {
        VideoThemeMotionInputs(
            reduceMotion: reduceMotion,
            lowPowerMode: lowPowerMode,
            thermalThrottled: thermalThrottled,
            sceneActive: sceneActive,
            motionPreferenceEnabled: motionPreferenceEnabled
        )
    }

    func testAnimatesInNormalConditions() {
        XCTAssertTrue(VideoThemeMotionPolicy.shouldAnimate(inputs()))
    }

    func testReduceMotionFreezes() {
        XCTAssertFalse(VideoThemeMotionPolicy.shouldAnimate(inputs(reduceMotion: true)))
    }

    func testLowPowerModeFreezes() {
        XCTAssertFalse(VideoThemeMotionPolicy.shouldAnimate(inputs(lowPowerMode: true)))
    }

    func testThermalThrottlingFreezes() {
        XCTAssertFalse(VideoThemeMotionPolicy.shouldAnimate(inputs(thermalThrottled: true)))
    }

    func testBackgroundSceneFreezes() {
        XCTAssertFalse(VideoThemeMotionPolicy.shouldAnimate(inputs(sceneActive: false)))
    }

    func testUserMotionToggleFreezes() {
        XCTAssertFalse(VideoThemeMotionPolicy.shouldAnimate(inputs(motionPreferenceEnabled: false)))
    }

    func testAllBadConditionsFreeze() {
        XCTAssertFalse(VideoThemeMotionPolicy.shouldAnimate(inputs(
            reduceMotion: true, lowPowerMode: true,
            thermalThrottled: true, sceneActive: false,
            motionPreferenceEnabled: false
        )))
    }

    // MARK: - effectiveVideoOpacity

    func testOpacityPassthroughWithoutReduceTransparency() {
        XCTAssertEqual(VideoThemeMotionPolicy.effectiveVideoOpacity(base: 0.8, reduceTransparency: false), 0.8)
    }

    func testOpacityCappedAtQuarterWithReduceTransparency() {
        XCTAssertEqual(VideoThemeMotionPolicy.effectiveVideoOpacity(base: 0.8, reduceTransparency: true), 0.25)
    }

    func testOpacityBelowCapUnchangedWithReduceTransparency() {
        XCTAssertEqual(VideoThemeMotionPolicy.effectiveVideoOpacity(base: 0.1, reduceTransparency: true), 0.1)
    }

    func testOpacityClampsOutOfRangeInput() {
        XCTAssertEqual(VideoThemeMotionPolicy.effectiveVideoOpacity(base: 1.7, reduceTransparency: false), 1.0)
        XCTAssertEqual(VideoThemeMotionPolicy.effectiveVideoOpacity(base: -0.3, reduceTransparency: false), 0.0)
    }
}
