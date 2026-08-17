// PlinkTests/RegressionMatrixTests.swift — PATCH 11
//
// Unit tests for RegressionMatrix — verifies the matrix is complete,
// every system has owner/test/telemetry/status, and the markdown table
// renders correctly.
//
// These are META-tests — they test the test matrix itself, not the app.
// They ensure the matrix stays in sync with the spec (18 systems) and
// that no field is empty.

import XCTest
@testable import Plink

final class RegressionMatrixTests: XCTestCase {

    // MARK: - Completeness

    func testMatrix_hasExactly18Systems() {
        XCTAssertEqual(RegressionSystem.allCases.count, 18,
                       "PATCH 11 spec requires exactly 18 systems in the regression matrix")
    }

    func testMatrix_containsAllSpecSystems() {
        let expected: Set<String> = [
            "auth", "rooms", "lifecycle", "websockets", "playback", "chat",
            "reactions", "presence", "sync", "profile", "friends", "dms",
            "deeplinks", "notifications", "settings", "gdpr", "billing", "admin"
        ]
        let actual = Set(RegressionSystem.allCases.map(\.rawValue))
        XCTAssertEqual(actual, expected,
                       "Matrix must contain exactly the 18 systems specified in PATCH 11")
    }

    // MARK: - Every system has all fields

    func testEverySystem_hasNonEmptyDisplayName() {
        for system in RegressionSystem.allCases {
            XCTAssertFalse(system.displayName.isEmpty,
                           "System \(system.rawValue) must have a non-empty display name")
        }
    }

    func testEverySystem_hasNonEmptyOwner() {
        for system in RegressionSystem.allCases {
            XCTAssertFalse(system.owner.isEmpty,
                           "System \(system.rawValue) must have a non-empty owner")
        }
    }

    func testEverySystem_hasNonEmptyTestFile() {
        for system in RegressionSystem.allCases {
            XCTAssertFalse(system.testFile.isEmpty,
                           "System \(system.rawValue) must have a non-empty test file reference")
        }
    }

    func testEverySystem_hasNonEmptyTelemetry() {
        for system in RegressionSystem.allCases {
            XCTAssertFalse(system.telemetry.isEmpty,
                           "System \(system.rawValue) must have non-empty telemetry")
        }
    }

    // MARK: - Status distribution

    func testStatusCounts_sumTo18() {
        let (green, yellow, red) = RegressionSystem.statusCounts
        XCTAssertEqual(green + yellow + red, 18,
                       "Green + yellow + red must equal 18")
    }

    func testAllEighteenSystemsAreGreen() {
        // After PATCH 21, ALL 18 systems have tests:
        //   playback, chat, reactions, auth, sync, rooms, presence,
        //   profile, friends, dms, deeplinks, settings, gdpr, billing,
        //   admin, notifications, lifecycle, websockets
        let (green, yellow, red) = RegressionSystem.statusCounts
        XCTAssertEqual(green, 18, "All 18 systems should be green after PATCH 21")
        XCTAssertEqual(yellow, 0, "No yellow systems should remain")
        XCTAssertEqual(red, 0, "No red systems should remain")
    }

    // MARK: - Markdown table

    func testMarkdownTable_hasHeaderRow() {
        let table = RegressionSystem.markdownTable
        XCTAssertTrue(table.contains("| System | Owner | Test File | Telemetry | Status |"),
                      "Markdown table must have the spec'd header row")
    }

    func testMarkdownTable_has18DataRows() {
        let table = RegressionSystem.markdownTable
        let lines = table.components(separatedBy: "\n")
        // Header + separator + 18 data rows = 20 lines
        XCTAssertEqual(lines.count, 20,
                       "Markdown table must have 20 lines (header + separator + 18 data rows)")
    }

    func testMarkdownTable_containsAllDisplayNames() {
        let table = RegressionSystem.markdownTable
        for system in RegressionSystem.allCases {
            XCTAssertTrue(table.contains(system.displayName),
                          "Markdown table must contain \(system.displayName)")
        }
    }

    // MARK: - Status values

    func testStatusRawValues() {
        XCTAssertEqual(RegressionStatus.green.rawValue, "green")
        XCTAssertEqual(RegressionStatus.yellow.rawValue, "yellow")
        XCTAssertEqual(RegressionStatus.red.rawValue, "red")
    }
}
