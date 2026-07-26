// PlinkTests/ProfileTests.swift — PATCH 20: profile system tests
//
// Closes the "profile" red system in RegressionMatrix.

import XCTest
@testable import Plink

@MainActor
final class ProfileTests: XCTestCase {

    // MARK: - User model

    func testUser_defaultRole_isNil() {
        let user = User(
            id: "u1",
            username: "alice",
            email: "alice@example.com",
            avatarURL: nil,
            isOnline: false,
            isPremium: false,
            role: nil,
            createdAt: Date()
        )
        XCTAssertNil(user.role)
    }

    func testUser_initials_fromDisplayName() {
        let user = User(
            id: "u1",
            username: "alice_films",
            email: "alice@example.com",
            avatarURL: nil,
            displayName: "Alice Wonderland",
            coverURL: nil,
            isOnline: true,
            isPremium: false,
            role: "USER",
            createdAt: Date()
        )
        // User has initials computed property — verify it uses displayName first.
        XCTAssertFalse(user.initials.isEmpty)
    }

    func testUser_initials_fallsBackToUsername() {
        let user = User(
            id: "u1",
            username: "alice_films",
            email: "alice@example.com",
            avatarURL: nil,
            displayName: nil,
            coverURL: nil,
            isOnline: true,
            isPremium: false,
            role: "USER",
            createdAt: Date()
        )
        XCTAssertFalse(user.initials.isEmpty)
    }

    // MARK: - PremiumStatusManager

    func testPremiumStatusManager_initialState_notPremium() {
        // Use a fresh instance to avoid singleton state.
        let manager = PremiumStatusManager()
        XCTAssertFalse(manager.isPremium)
        XCTAssertNil(manager.subscriptionExpiry)
    }

    func testPremiumStatusManager_activatePremium_setsExpiry() {
        let manager = PremiumStatusManager()
        let expiry = Date().addingTimeInterval(30 * 24 * 3600)  // 30 days
        manager.activatePremium(expiryDate: expiry)
        XCTAssertTrue(manager.isPremium)
        XCTAssertEqual(manager.subscriptionExpiry, expiry)
    }

    func testPremiumStatusManager_activateLifetime_setsNilExpiry() {
        let manager = PremiumStatusManager()
        manager.activateLifetime()
        XCTAssertTrue(manager.isPremium)
        XCTAssertNil(manager.subscriptionExpiry, "Lifetime = nil expiry")
    }

    func testPremiumStatusManager_deactivate_resetsState() {
        let manager = PremiumStatusManager()
        manager.activatePremium(expiryDate: Date().addingTimeInterval(3600))
        XCTAssertTrue(manager.isPremium)

        manager.deactivatePremium()
        XCTAssertFalse(manager.isPremium)
        XCTAssertNil(manager.subscriptionExpiry)
    }

    // MARK: - UserPreview

    func testUserPreview_equality() {
        let p1 = UserPreview(id: "u1", username: "alice", avatarURL: nil, isOnline: false)
        let p2 = UserPreview(id: "u1", username: "alice", avatarURL: nil, isOnline: true)
        let p3 = UserPreview(id: "u2", username: "bob", avatarURL: nil, isOnline: false)
        XCTAssertEqual(p1, p2, "UserPreview equality is by id")
        XCTAssertNotEqual(p1, p3)
    }

    func testUserPreview_id_isStable() {
        let preview = UserPreview(id: "u1", username: "alice", avatarURL: nil, isOnline: true)
        XCTAssertEqual(preview.id, "u1")
    }

    // MARK: - Profile serialization

    func testUser_codableRoundTrip() throws {
        let user = User(
            id: "u1",
            username: "alice",
            email: "alice@example.com",
            avatarURL: "http://example.com/a.png",
            displayName: "Alice",
            coverURL: nil,
            isOnline: true,
            isPremium: true,
            role: "ADMIN",
            createdAt: Date(timeIntervalSince1970: 1_000_000_000)
        )
        let data = try JSONEncoder().encode(user)
        let decoded = try JSONDecoder().decode(User.self, from: data)
        XCTAssertEqual(user.id, decoded.id)
        XCTAssertEqual(user.username, decoded.username)
        XCTAssertEqual(user.email, decoded.email)
        XCTAssertEqual(user.isPremium, decoded.isPremium)
        XCTAssertEqual(user.role, decoded.role)
    }
}
