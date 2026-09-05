// PlinkURLs tests — the two origins and the difference between them.
//
// What is worth pinning here:
//   1. Legal and support links follow the API origin. That is the whole reason
//      they resolve: the backend serves /terms, /privacy and /support, and
//      App Review 3.1.2 rejects a subscription app whose links are dead.
//   2. Share links do NOT follow the API origin. An invite that lands in
//      someone else's chat must not start leaking the Railway-generated host
//      because somebody pointed the app at a staging backend.
//   3. A room link the app produces is a link the app can parse back. Nothing
//      else checks that the share format and DeepLinkRouter agree.

import XCTest
@testable import Plink

@MainActor
final class PlinkURLsTests: XCTestCase {

    private let backendKey = "plink.backend_base_url"
    private let shareKey = PlinkURLs.shareOriginOverrideKey

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: backendKey)
        UserDefaults.standard.removeObject(forKey: shareKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: backendKey)
        UserDefaults.standard.removeObject(forKey: shareKey)
        super.tearDown()
    }

    // MARK: - Legal follows the origin that serves the pages

    func testLegalLinksDeriveFromTheAPIOrigin() {
        UserDefaults.standard.set("https://api.example.test", forKey: backendKey)

        XCTAssertEqual(PlinkURLs.terms?.absoluteString, "https://api.example.test/terms")
        XCTAssertEqual(PlinkURLs.privacy?.absoluteString, "https://api.example.test/privacy")
        XCTAssertEqual(PlinkURLs.support?.absoluteString, "https://api.example.test/support")
    }

    func testLegalLinksExistWithoutAnyOverride() {
        // The shipped default has to produce usable links on its own — a paywall
        // that draws no Terms link is a rejected build.
        XCTAssertNotNil(PlinkURLs.terms)
        XCTAssertNotNil(PlinkURLs.privacy)
        XCTAssertNotNil(PlinkURLs.support)
        XCTAssertEqual(PlinkURLs.terms?.host, URL(string: PlinkConfig.baseURLString)?.host)
    }

    // MARK: - Share links stay on a trusted, working origin

    func testShareLinksIgnoreTheAPIOrigin() {
        UserDefaults.standard.set("https://api.example.test", forKey: backendKey)

        XCTAssertEqual(PlinkURLs.roomLink(code: "ABCDEF")?.host,
                       URL(string: PlinkURLs.shareOrigin)?.host)
        XCTAssertEqual(PlinkURLs.profileLink("someone")?.host,
                       URL(string: PlinkURLs.shareOrigin)?.host)
    }

    func testShareOriginOverrideAppliesAndDropsTrailingSlash() {
        UserDefaults.standard.set("https://plink.app/", forKey: shareKey)

        XCTAssertEqual(PlinkURLs.shareOrigin, "https://plink.app")
        XCTAssertEqual(PlinkURLs.roomLink(code: "ABCDEF")?.absoluteString,
                       "https://plink.app/r/ABCDEF")
    }

    func testEmptyOverrideFallsBackToTheWorkingWebOrigin() {
        UserDefaults.standard.set("", forKey: shareKey)
        XCTAssertEqual(PlinkURLs.shareOrigin, PlinkURLs.webOrigin)
    }

    func testUntrustedShareOriginIsRejected() {
        UserDefaults.standard.set("https://evil.example/phish", forKey: shareKey)
        XCTAssertEqual(PlinkURLs.shareOrigin, PlinkURLs.webOrigin)
    }

    func testBlankRoomCodeProducesNoLink() {
        XCTAssertNil(PlinkURLs.roomLink(code: ""))
        XCTAssertNil(PlinkURLs.roomLink(code: "   "))
        XCTAssertNil(PlinkURLs.profileLink(""))
    }

    // MARK: - Round trip

    func testRoomLinkParsesBackToTheSameCode() {
        let router = DeepLinkRouter()
        let link = PlinkURLs.roomLink(code: "ABCDEF")

        XCTAssertNotNil(link)
        XCTAssertEqual(router.parse(link!), .room(code: "ABCDEF"))
    }

    func testShareManagerUsesTheSameOrigin() {
        XCTAssertEqual(ShareManager.shareBaseURL, PlinkURLs.shareOrigin)
        XCTAssertEqual(ShareManager.shareURL(for: "room-id", code: "ABCDEF").absoluteString,
                       "\(PlinkURLs.shareOrigin)/r/ABCDEF")
        XCTAssertEqual(ShareManager.shareURL(for: "room-id").absoluteString,
                       "\(PlinkURLs.shareOrigin)/r/room-id")
    }
}
