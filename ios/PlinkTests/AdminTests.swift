// Admin system tests
//
    // Tests the current AdminModule contract (V5/PlinkAdminRoot.swift).

import XCTest
@testable import Plink

@MainActor
final class AdminTests: XCTestCase {

    // MARK: - AdminModule enum

    func testAdminModule_hasCurrentCases() {
        XCTAssertEqual(AdminModule.allCases.count, 9)
    }

    func testAdminModule_cases() {
        let expected: Set<String> = [
            "overview", "users", "rooms", "moderation",
            "analytics", "system", "audit", "broadcasts", "premium"
        ]
        let actual = Set(AdminModule.allCases.map(\.rawValue))
        XCTAssertEqual(actual, expected)
    }

    func testAdminModule_id_equalsRawValue() {
        for module in AdminModule.allCases {
            XCTAssertEqual(module.id, module.rawValue)
        }
    }

    // MARK: - Display names

    func testAdminModule_displayName_nonEmpty() {
        for module in AdminModule.allCases {
            XCTAssertFalse(module.title.isEmpty, "\(module) should have title")
        }
    }

    func testAdminModule_titles() {
        XCTAssertEqual(AdminModule.overview.title, "Сводка")
        XCTAssertEqual(AdminModule.users.title, "Пользователи")
        XCTAssertEqual(AdminModule.rooms.title, "Комнаты")
        XCTAssertEqual(AdminModule.moderation.title, "Жалобы")
        XCTAssertEqual(AdminModule.analytics.title, "Аналитика")
        XCTAssertEqual(AdminModule.system.title, "Система")
        XCTAssertEqual(AdminModule.audit.title, "Журнал")
        XCTAssertEqual(AdminModule.broadcasts.title, "Рассылки")
        XCTAssertEqual(AdminModule.premium.title, "Plink+")
    }

    // MARK: - Icons

    func testAdminModule_icons_nonEmpty() {
        for module in AdminModule.allCases {
            XCTAssertFalse(module.icon.isEmpty, "\(module) should have icon")
        }
    }

    func testAdminModule_icons_unique() {
        let icons = AdminModule.allCases.map(\.icon)
        XCTAssertEqual(icons.count, Set(icons).count, "icons must be unique per module")
    }
}
