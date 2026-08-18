// Settings system tests

import XCTest
@testable import Plink

@MainActor
final class SettingsTests: XCTestCase {

    // MARK: - NickStyle

    func testNickStyle_allCases() {
        XCTAssertEqual(NickStyle.allCases.count, 8)
    }

    func testNickStyle_rawValues() {
        XCTAssertEqual(NickStyle.default.rawValue, "default")
        XCTAssertEqual(NickStyle.neonPurple.rawValue, "neon_purple")
        XCTAssertEqual(NickStyle.gold.rawValue, "gold")
        XCTAssertEqual(NickStyle.ice.rawValue, "ice")
    }

    func testNickStyle_id_equalsRawValue() {
        for style in NickStyle.allCases {
            XCTAssertEqual(style.id, style.rawValue)
        }
    }

    // MARK: - AvatarBorder

    func testAvatarBorder_allCases() {
        XCTAssertEqual(AvatarBorder.allCases.count, 5)
    }

    func testAvatarBorder_defaultIsNone() {
        XCTAssertEqual(AvatarBorder.none.rawValue, "none")
    }

    // MARK: - RoomTheme

    func testRoomTheme_allCases() {
        XCTAssertEqual(RoomTheme.allCases.count, 6)
    }

    func testRoomTheme_defaultIsDefault() {
        XCTAssertEqual(RoomTheme.default.rawValue, "default")
    }

    func testRoomTheme_displayName_nonEmpty() {
        for theme in RoomTheme.allCases {
            XCTAssertFalse(theme.displayName.isEmpty, "\(theme) should have displayName")
        }
    }

    // MARK: - PremiumStatusManager settings

    func testPremiumStatusManager_defaultNickStyle() {
        let manager = PremiumStatusManager()
        XCTAssertEqual(manager.selectedNickStyle, .default)
    }

    func testPremiumStatusManager_defaultAvatarBorder() {
        let manager = PremiumStatusManager()
        XCTAssertEqual(manager.selectedAvatarBorder, .none)
    }

    func testPremiumStatusManager_defaultRoomTheme() {
        let manager = PremiumStatusManager()
        XCTAssertEqual(manager.selectedRoomTheme, .default)
    }

    // MARK: - LocalizationManager

    func testLocalizationManager_defaultLanguage() {
        // LocalizationManager has private init() — use singleton.
        let manager = LocalizationManager.shared
        // Just verify it doesn't crash.
        _ = manager.currentLanguage
    }

    // MARK: - Linked cinema accounts

    func testLinkedAccountsCoverEveryCinemaThatRequiresLogin() {
        let linked = Set(LinkedExternalAccount.allCases.compactMap(\.videoService))
        for svc in VideoService.allCases where svc.requiresAuth {
            XCTAssertTrue(linked.contains(svc), "\(svc.rawValue) must be in profile connections")
        }
        XCTAssertFalse(linked.contains(.smotrim))
        XCTAssertFalse(linked.contains(.youtube))
    }

    func testYandexIDUnlocksKinopoiskWithoutSeparateFlag() {
        ServiceAuthStore.markYandexID(false)
        ServiceAuthStore.logout(.kinopoisk)
        XCTAssertFalse(ServiceAuthStore.hasAccess(to: .kinopoisk))
        ServiceAuthStore.markYandexID(true)
        XCTAssertTrue(ServiceAuthStore.hasAccess(to: .kinopoisk))
        XCTAssertTrue(LinkedExternalAccount.yandex.isConnected)
        ServiceAuthStore.markYandexID(false)
        XCTAssertFalse(ServiceAuthStore.hasAccess(to: .kinopoisk))
    }

    func testYandexLoginURLIsPassport() {
        XCTAssertEqual(LinkedExternalAccount.yandex.loginURL.host, "passport.yandex.ru")
    }
}
