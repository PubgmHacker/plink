//  M39Tests.swift
//  PlinkTests — M39
//
//  Тесты на три вещи, где ошибка стоит дорого: распознавание источников
//  (юридика и безопасность), арифметика синхронизации и экономика подписок.

import XCTest
@testable import Plink

final class MediaSourceResolverTests: XCTestCase {

    func testRecognizesRussianServices() {
        XCTAssertEqual(MediaSourceResolver.resolve("https://rutube.ru/video/0f1a2b3c4d5e6f7a8b9c/")?.kind, .rutube)
        XCTAssertEqual(MediaSourceResolver.resolve("https://vk.com/video-111_222")?.kind, .vk)
        XCTAssertEqual(MediaSourceResolver.resolve("https://vkvideo.ru/video-111_222")?.kind, .vk)
        XCTAssertEqual(MediaSourceResolver.resolve("https://ok.ru/video/123456789")?.kind, .ok)
        XCTAssertEqual(MediaSourceResolver.resolve("https://dzen.ru/video/watch/64f0abc123")?.kind, .dzen)
    }

    /// Главный тест безопасности: старый `host.contains("vk.com")` ловил фишинг.
    func testRejectsLookalikeDomains() {
        XCTAssertNil(MediaSourceResolver.resolve("https://evil-vk.com.ru/video-1_1"))
        XCTAssertNil(MediaSourceResolver.resolve("https://vk.com.attacker.net/video-1_1"))
        XCTAssertNil(MediaSourceResolver.resolve("https://notrutube.ru/video/abc/"))
    }

    func testAcceptsLinksWithoutScheme() {
        XCTAssertEqual(MediaSourceResolver.resolve("rutube.ru/video/0f1a2b3c4d5e6f7a8b9c/")?.kind, .rutube)
    }

    func testDirectFilesUseNativePlayer() {
        let resolved = MediaSourceResolver.resolve("https://cdn.site.com/movie.mp4")
        XCTAssertEqual(resolved?.kind, .nativePlayer)
        XCTAssertTrue(resolved?.supportsPreciseSync ?? false)
    }

    /// Embed-плееры не дают кадровой точности — нельзя обещать еᄅ в UI.
    func testEmbedsDoNotClaimPreciseSync() {
        XCTAssertFalse(MediaSourceResolver.resolve("https://youtu.be/dQw4w9WgXcQ")?.supportsPreciseSync ?? true)
        XCTAssertFalse(MediaSourceResolver.resolve("https://rutube.ru/video/0f1a2b3c4d5e6f7a8b9c/")?.supportsPreciseSync ?? true)
    }

    func testUnsupportedReturnsNilNotFallback() {
        XCTAssertNil(MediaSourceResolver.resolve("https://example.com/some-page"))
        XCTAssertNil(MediaSourceResolver.resolve("не ссылка вообще"))
    }
}

final class PlaybackSyncEngineTests: XCTestCase {

    func testNoCorrectionInsideDeadZone() {
        let engine = PlaybackSyncEngine()
        let decision = engine.decideCorrection(drift: 0.03)
        XCTAssertEqual(decision, .none)
    }

    func testSoftCorrectionForSmallDrift() {
        let engine = PlaybackSyncEngine()
        guard case .rate(let rate) = engine.decideCorrection(drift: 0.18) else {
            return XCTFail("Ожидалась мягкая коррекция скоростью")
        }
        XCTAssertLessThanOrEqual(abs(rate - 1.0), 0.05, "Коррекция скорости не должна быть слышимой")
    }

    func testHardSeekForLargeDrift() {
        let engine = PlaybackSyncEngine()
        guard case .seek = engine.decideCorrection(drift: 2.5) else {
            return XCTFail("При большом рассинхроне нужен жᄅсткий seek")
        }
    }

    func testCorrectionIsSymmetric() {
        let engine = PlaybackSyncEngine()
        if case .rate(let ahead) = engine.decideCorrection(drift: 0.2),
           case .rate(let behind) = engine.decideCorrection(drift: -0.2) {
            XCTAssertEqual(ahead - 1.0, -(behind - 1.0), accuracy: 0.0001)
        } else {
            XCTFail("Оба направления должны давать мягкую коррекцию")
        }
    }
}

final class ClockSyncTests: XCTestCase {

    func testMedianOfBestSamplesIgnoresOutlier() {
        let samples: [(offset: Double, rtt: Double)] = [
            (0.010, 0.04), (0.012, 0.05), (0.011, 0.045), (0.900, 3.80),
        ]
        let offset = ClockSync.medianOffset(from: samples, bestCount: 3)
        XCTAssertEqual(offset, 0.011, accuracy: 0.002, "Выброс с огромным RTT не должен влиять")
    }

    func testQualityThresholds() {
        XCTAssertEqual(ClockSync.Quality(rtt: 0.05), .excellent)
        XCTAssertEqual(ClockSync.Quality(rtt: 0.15), .good)
        XCTAssertEqual(ClockSync.Quality(rtt: 0.90), .poor)
    }
}

final class StoreKitPricingTests: XCTestCase {

    /// Годовой тариф — основной. Если выгода окажется ниже 30 %,
    /// пейволл перестанет работать как воронка — это надо ловить тестом.
    func testYearlySavingsStayAttractive() {
        let savings = StoreKitManager.yearlySavingsPercent(monthly: 199, yearly: 1490)
        XCTAssertGreaterThanOrEqual(savings, 30)
    }

    func testMonthlyEquivalentRounding() {
        XCTAssertEqual(StoreKitManager.monthlyEquivalent(yearly: 1490), 124, accuracy: 1)
    }

    func testProductIdentifiersMatchAppStoreConnect() {
        XCTAssertEqual(StoreKitManager.ProductID.monthly.rawValue, "com.plink.app.plus.monthly")
        XCTAssertEqual(StoreKitManager.ProductID.yearly.rawValue, "com.plink.app.plus.yearly")
        XCTAssertEqual(StoreKitManager.ProductID.lifetime.rawValue, "com.plink.app.plus.lifetime")
    }
}

final class ModerationTests: XCTestCase {

    func testBlockingHidesUserImmediately() async {
        let service = ModerationService.shared
        await service.block(userID: "user-test-1")
        XCTAssertTrue(service.isBlocked("user-test-1"))
        await service.unblock(userID: "user-test-1")
        XCTAssertFalse(service.isBlocked("user-test-1"))
    }

    func testEveryReasonHasTitleAndIcon() {
        for reason in ModerationService.Reason.allCases {
            XCTAssertFalse(reason.title.isEmpty)
            XCTAssertFalse(reason.icon.isEmpty)
        }
    }
}
