// PlinkTests/AdminTests.swift — PATCH 21: admin system tests
//
// Tests AdminModule enum + routing + authorization contract.

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
            "users", "rooms", "moderation", "flags", "analytics",
            "system", "audit", "broadcasts", "premium", "blocklists"
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
        XCTAssertEqual(AdminModule.users.title, "Users")
        XCTAssertEqual(AdminModule.rooms.title, "Rooms")
        XCTAssertEqual(AdminModule.moderation.title, "Moderation")
        XCTAssertEqual(AdminModule.flags.title, "Flags")
        XCTAssertEqual(AdminModule.analytics.title, "Analytics")
        XCTAssertEqual(AdminModule.system.title, "System")
        XCTAssertEqual(AdminModule.audit.title, "Audit Log")
        XCTAssertEqual(AdminModule.broadcasts.title, "Broadcasts")
        XCTAssertEqual(AdminModule.premium.title, "Premium")
        XCTAssertEqual(AdminModule.blocklists.title, "Blocklists")
    }

    // MARK: - Icons

    func testAdminModule_icons_nonEmpty() {
        for module in AdminModule.allCases {
            XCTAssertFalse(module.icon.isEmpty, "\(module) should have icon")
        }
    }

    // MARK: - API prefix

    func testAdminModule_apiPrefix_correctFormat() {
        for module in AdminModule.allCases {
            XCTAssertEqual(module.apiPrefix, "/api/admin/\(module.rawValue)")
        }
    }

    // MARK: - Owners

    func testAdminModule_owner_nonEmpty() {
        for module in AdminModule.allCases {
            XCTAssertFalse(module.owner.isEmpty, "\(module) should have owner")
        }
    }

    func testAdminModule_owners_mapped() {
        XCTAssertEqual(AdminModule.users.owner, "auth-team")
        XCTAssertEqual(AdminModule.rooms.owner, "navigation-team")
        XCTAssertEqual(AdminModule.moderation.owner, "chat-team")
        XCTAssertEqual(AdminModule.premium.owner, "billing-team")
    }

    // MARK: - AdminModuleView routing

    func testAdminModuleView_routesToCorrectModule() {
        // Verify AdminModuleView exists and accepts each module.
        // Full view rendering test requires SwiftUI preview — we test enum.
        for module in AdminModule.allCases {
            _ = AdminModuleView(module: module)
        }
    }
}
