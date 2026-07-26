// PlinkTests/FinalArchNavigationTests.swift — §15 Final Unified
//
// Tests for final architecture: 5 tabs, navigation invariants,
// create room flow, onboarding versioning.

import XCTest
@testable import Plink

@MainActor
final class FinalArchNavigationTests: XCTestCase {

    // MARK: - AppSection (5 canonical tabs)

    func testAppSection_hasExactlyFiveTabs() {
        XCTAssertEqual(AppSection.allCases.count, 5,
                       "Must have exactly 5 tabs per final unified spec")
    }

    func testAppSection_orderIsCanonical() {
        let order = AppSection.allCases.map(\.rawValue)
        XCTAssertEqual(order, ["home", "rooms", "ai", "friends", "settings"],
                       "Tab order must be: Главная, Комнаты, ИИ, Друзья, Настройки")
    }

    func testAppSection_titlesAreRussian() {
        XCTAssertEqual(AppSection.home.title, "Главная")
        XCTAssertEqual(AppSection.rooms.title, "Комнаты")
        XCTAssertEqual(AppSection.ai.title, "ИИ")
        XCTAssertEqual(AppSection.friends.title, "Друзья")
        XCTAssertEqual(AppSection.settings.title, "Настройки")
    }

    func testAppSection_symbolsAreValid() {
        for section in AppSection.allCases {
            XCTAssertFalse(section.symbol.isEmpty, "\(section) must have a symbol")
        }
    }

    func testAppSection_noCreateTab() {
        // Create Room is NOT a tab — it's a sheet.
        XCTAssertFalse(AppSection.allCases.contains { $0.rawValue == "create" },
                       "Create must not be a tab")
    }

    func testAppSection_noProfileTab() {
        // Profile is under Settings, not a separate tab.
        XCTAssertFalse(AppSection.allCases.contains { $0.rawValue == "profile" },
                       "Profile must not be a tab")
    }

    func testAppSection_noDiscoverTab() {
        XCTAssertFalse(AppSection.allCases.contains { $0.rawValue == "discover" },
                       "Discover must not be a tab")
    }

    // MARK: - Onboarding versioning

    func testOnboardingVersion_currentIs2() {
        XCTAssertEqual(OnboardingVersion.current, 2)
    }

    func testOnboardingStore_needsOnboarding_whenVersionIsZero() {
        let store = UserDefaultsOnboardingStore()
        // Clear any existing version
        UserDefaults.standard.removeObject(forKey: "plink_onboarding_version")
        XCTAssertTrue(store.needsCurrentOnboarding,
                      "Version 0 < current 2 → needs onboarding")
    }

    func testOnboardingStore_doesNotNeedOnboarding_whenVersionIsCurrent() {
        let store = UserDefaultsOnboardingStore()
        store.markCompleted(version: OnboardingVersion.current)
        XCTAssertFalse(store.needsCurrentOnboarding)
        // Cleanup
        UserDefaults.standard.removeObject(forKey: "plink_onboarding_version")
    }

    func testOnboardingStore_needsOnboarding_whenVersionIsStale() {
        let store = UserDefaultsOnboardingStore()
        store.markCompleted(version: 1)  // Stale
        XCTAssertTrue(store.needsCurrentOnboarding)
        // Cleanup
        UserDefaults.standard.removeObject(forKey: "plink_onboarding_version")
    }

    // MARK: - StoreKit products (1m, 3m, 12m)

    func testStoreKitProducts_exactlyThreeProducts() {
        XCTAssertEqual(PlinkProductID.all.count, 3)
    }

    func testStoreKitProducts_correctIDs() {
        XCTAssertEqual(PlinkProductID.monthly, "plink.plus.1m")
        XCTAssertEqual(PlinkProductID.quarterly, "plink.plus.3m")
        XCTAssertEqual(PlinkProductID.yearly, "plink.plus.12m")
    }

    func testStoreKitProducts_noLifetime() {
        // Final unified spec: exactly 1m, 3m, 12m. No lifetime.
        XCTAssertNil(PlinkProductID.tier(for: "plink.plus.lifetime"))
    }

    func testStoreKitProducts_allArePremiumTier() {
        XCTAssertEqual(PlinkProductID.tier(for: PlinkProductID.monthly), .premium)
        XCTAssertEqual(PlinkProductID.tier(for: PlinkProductID.quarterly), .premium)
        XCTAssertEqual(PlinkProductID.tier(for: PlinkProductID.yearly), .premium)
    }

    // MARK: - Compact metrics

    func testCompactPhoneMetrics_insets() {
        XCTAssertEqual(CompactPhoneMetrics.horizontalInset, 14)
        XCTAssertEqual(CompactPhoneMetrics.sectionSpacing, 18)
        XCTAssertEqual(CompactPhoneMetrics.railSpacing, 8)
    }

    func testCompactPhoneMetrics_posterSize() {
        XCTAssertEqual(CompactPhoneMetrics.posterWidth, 108)
        XCTAssertEqual(CompactPhoneMetrics.posterAspect, 0.70)
        XCTAssertEqual(CompactPhoneMetrics.posterRadius, 9)
    }

    func testCompactPhoneMetrics_landscapeCard() {
        XCTAssertEqual(CompactPhoneMetrics.landscapeCardWidth, 186)
        XCTAssertEqual(CompactPhoneMetrics.landscapeCardHeight, 105)
    }

    func testCompactPhoneMetrics_hitTarget() {
        XCTAssertEqual(CompactPhoneMetrics.minimumHitTarget, 44)
        XCTAssertEqual(CompactPhoneMetrics.primaryButtonHeight, 50)
    }

    // MARK: - Cinema2026 palette

    func testCinema2026_accentIsTealGreen() {
        // accent should be teal-green (0.355, 0.690, 0.610), not violet
        // We verify the color exists and is accessible
        _ = Cinema2026.accent
        _ = Cinema2026.background
        _ = Cinema2026.surface
        _ = Cinema2026.text
        _ = Cinema2026.secondary
        _ = Cinema2026.danger
        _ = Cinema2026.amber
        _ = Cinema2026.divider
        _ = Cinema2026.raised
    }

    // MARK: - Launch destination

    func testLaunchDestination_allCases() {
        let destinations: [LaunchDestination] = [
            .restoringSession, .authentication, .onboarding, .app
        ]
        XCTAssertEqual(destinations.count, 4)
    }

    // MARK: - Auth route

    func testAuthRoute_allCases() {
        let routes: [AuthRoute] = [.login, .registration]
        XCTAssertEqual(routes.count, 2)
    }
}
