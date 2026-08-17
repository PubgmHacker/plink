// PlinkTests/AdminTests.swift — PATCH 21: admin system tests
//
// Tests AdminModule enum contract (V5/PlinkAdminRoot.swift).
// Аудит 26.07.2026: тест был написан под мёртвую версию AdminModule
// (blocklists/apiPrefix/owner/AdminModuleView) и не компилировался.
// Переписан под живой enum.

import XCTest
@testable import Plink

@MainActor
final class AdminTests: XCTestCase {

    // MARK: - AdminModule enum

    func testAdminModule_allTenCases() {
        XCTAssertEqual(AdminModule.allCases.count, 10)
    }

    func testAdminModule_cases() {
        let expected: Set<String> = [
            "overview", "users", "rooms", "moderation", "flags",
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
        XCTAssertEqual(AdminModule.overview.title, "Overview")
        XCTAssertEqual(AdminModule.users.title, "Users")
        XCTAssertEqual(AdminModule.rooms.title, "Rooms")
        XCTAssertEqual(AdminModule.moderation.title, "Moderation")
        XCTAssertEqual(AdminModule.flags.title, "Feature Flags")
        XCTAssertEqual(AdminModule.analytics.title, "Analytics")
        XCTAssertEqual(AdminModule.system.title, "System")
        XCTAssertEqual(AdminModule.audit.title, "Audit Log")
        XCTAssertEqual(AdminModule.broadcasts.title, "Broadcasts")
        XCTAssertEqual(AdminModule.premium.title, "Premium")
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
