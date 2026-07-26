// PlinkTests/DeepLinkTests.swift — PATCH 20: deeplinks system tests
//
// Closes the "deeplinks" red system in RegressionMatrix.

import XCTest
@testable import Plink

@MainActor
final class DeepLinkTests: XCTestCase {

    private var router: DeepLinkRouter!

    override func setUp() async throws {
        try await super.setUp()
        router = DeepLinkRouter()
    }

    // MARK: - Room links

    func testParse_universalLinkRoom_returnsRoomCode() {
        let url = URL(string: "https://plink.app/r/ABCDEF")!
        let result = router.parse(url)
        XCTAssertEqual(result, .room(code: "ABCDEF"))
    }

    func testParse_universalLinkRoom_wwwSubdomain() {
        let url = URL(string: "https://www.plink.app/r/XYZ123")!
        let result = router.parse(url)
        XCTAssertEqual(result, .room(code: "XYZ123"))
    }

    func testParse_customSchemeRoom() {
        let url = URL(string: "raveclone://r/ABCDEF")!
        let result = router.parse(url)
        XCTAssertEqual(result, .room(code: "ABCDEF"))
    }

    func testParse_roomWithQueryParameter() {
        let url = URL(string: "https://plink.app/r?code=QUERY1")!
        let result = router.parse(url)
        XCTAssertEqual(result, .room(code: "QUERY1"))
    }

    // MARK: - Friend invite links

    func testParse_universalLinkFriendInvite() {
        let url = URL(string: "https://plink.app/u/user-123")!
        let result = router.parse(url)
        XCTAssertEqual(result, .friendInvite(userId: "user-123"))
    }

    func testParse_customSchemeFriendInvite() {
        let url = URL(string: "raveclone://u/user-456")!
        let result = router.parse(url)
        XCTAssertEqual(result, .friendInvite(userId: "user-456"))
    }

    func testParse_friendInviteWithQueryParameter() {
        let url = URL(string: "https://plink.app/u?userId=user-789")!
        let result = router.parse(url)
        XCTAssertEqual(result, .friendInvite(userId: "user-789"))
    }

    // MARK: - Legacy 6-char code

    func testParse_legacyBareCode_treatedAsRoom() {
        let url = URL(string: "https://plink.app/ABCDEF")!
        let result = router.parse(url)
        XCTAssertEqual(result, .room(code: "ABCDEF"))
    }

    // MARK: - Invalid links

    func testParse_unknownHost_returnsNone() {
        let url = URL(string: "https://evil.com/r/ABCDEF")!
        let result = router.parse(url)
        XCTAssertEqual(result, .none)
    }

    func testParse_unknownScheme_returnsNone() {
        let url = URL(string: "ftp://r/ABCDEF")!
        let result = router.parse(url)
        XCTAssertEqual(result, .none)
    }

    func testParse_emptyPath_returnsNone() {
        let url = URL(string: "https://plink.app/")!
        let result = router.parse(url)
        XCTAssertEqual(result, .none)
    }

    func testParse_unknownPathSegment_returnsNone() {
        let url = URL(string: "https://plink.app/unknown/segment")!
        let result = router.parse(url)
        XCTAssertEqual(result, .none)
    }

    // MARK: - handle

    func testHandle_validRoomLink_setsPendingLink() {
        let url = URL(string: "https://plink.app/r/ABCDEF")!
        router.handle(url)
        XCTAssertEqual(router.pendingLink, .room(code: "ABCDEF"))
    }

    func testHandle_invalidLink_doesNotSetPendingLink() {
        let url = URL(string: "https://evil.com/r/ABCDEF")!
        router.handle(url)
        XCTAssertNil(router.pendingLink)
    }

    func testClear_resetsPendingLink() {
        let url = URL(string: "https://plink.app/r/ABCDEF")!
        router.handle(url)
        XCTAssertNotNil(router.pendingLink)

        router.clear()
        XCTAssertNil(router.pendingLink)
    }

    // MARK: - URL builders

    func testRoomURL_buildsCorrectURL() {
        let url = DeepLinkRouter.roomURL(code: "ABCDEF")
        XCTAssertTrue(url.absoluteString.contains("ABCDEF"))
        XCTAssertTrue(url.absoluteString.contains("/r/"))
    }

    func testFriendInviteURL_buildsCorrectURL() {
        let url = DeepLinkRouter.friendInviteURL(userId: "user-123")
        XCTAssertTrue(url.absoluteString.contains("user-123"))
        XCTAssertTrue(url.absoluteString.contains("/u/"))
    }
}
