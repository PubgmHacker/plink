// PlinkTests/GDPRTests.swift — PATCH 21: gdpr system tests
//
// Tests GDPR data export + delete account flow.

import XCTest
@testable import Plink

@MainActor
final class GDPRTests: XCTestCase {

    // MARK: - User data

    func testUser_canBeExportedAsJSON() throws {
        let user = User(
            id: "u1",
            username: "alice",
            email: "alice@example.com",
            avatarURL: nil,
            displayName: "Alice",
            coverURL: nil,
            isOnline: true,
            isPremium: false,
            role: "USER",
            createdAt: Date(timeIntervalSince1970: 1_000_000_000)
        )
        let data = try JSONEncoder().encode(user)
        XCTAssertGreaterThan(data.count, 0)

        // Verify JSON contains expected fields.
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["id"])
        XCTAssertNotNil(json?["username"])
        XCTAssertNotNil(json?["email"])
    }

    // MARK: - Account deletion

    func testDeleteAccount_viaFakeAuthService() async throws {
        let auth = FakeAuthService()
        _ = try await auth.signUp(email: "gdpr@example.com", password: "password123", username: "gdpr_user")
        XCTAssertNotNil(auth.currentUser)

        try await auth.deleteAccount()

        XCTAssertNil(auth.currentUser)
        XCTAssertNil(auth.authToken)

        // Verify account is gone — cannot sign in.
        do {
            _ = try await auth.signIn(email: "gdpr@example.com", password: "password123")
            XCTFail("Should not be able to sign in after deletion")
        } catch FakeAuthError.userNotFound {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - Conversation history

    func testDirectMessage_canBeSerialized() throws {
        let dm = DirectMessage(
            id: "msg-1",
            conversationID: "conv-1",
            senderID: "u1",
            recipientID: "u2",
            senderName: "Alice",
            text: "Hello",
            timestamp: Date(),
            isRead: false,
            senderAvatarURL: nil
        )
        let data = try JSONEncoder().encode(dm)
        XCTAssertGreaterThan(data.count, 0)
    }

    // MARK: - Watch history

    func testWatchHistory_serialization() throws {
        // WatchHistoryItem model test — verify Codable.
        let history = WatchHistoryItem(
            id: "h1",
            mediaItemId: "m1",
            title: "Test Video",
            thumbnailURL: nil,
            streamURL: "https://example.com/video",
            mediaType: "movie",
            source: "youtube",
            watchedAt: Date(),
            watchedDuration: 600,
            totalDuration: 1200
        )
        let data = try JSONEncoder().encode(history)
        XCTAssertGreaterThan(data.count, 0)

        let decoded = try JSONDecoder().decode(WatchHistoryItem.self, from: data)
        XCTAssertEqual(history.id, decoded.id)
        XCTAssertEqual(history.title, decoded.title)
    }

    // MARK: - Privacy settings

    func testUser_privacyFieldsAccessible() {
        let user = User(
            id: "u1",
            username: "alice",
            email: "alice@example.com",
            avatarURL: nil,
            isOnline: false,
            isPremium: false,
            role: "USER",
            createdAt: Date()
        )
        // GDPR requires ability to access all user data.
        XCTAssertEqual(user.email, "alice@example.com")
        XCTAssertEqual(user.username, "alice")
        XCTAssertNotNil(user.createdAt)
    }
}
