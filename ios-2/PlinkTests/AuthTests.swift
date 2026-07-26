// PlinkTests/AuthTests.swift — PATCH 17: auth system tests
//
// Closes the "auth" red system in RegressionMatrix (was red, now green).
// Tests cover: signUp, signIn, signOut, account deletion, profile update,
// admin verification, error cases.

import XCTest
@testable import Plink

@MainActor
final class AuthTests: XCTestCase {

    private var auth: FakeAuthService!

    override func setUp() async throws {
        try await super.setUp()
        auth = FakeAuthService()
    }

    override func tearDown() async throws {
        auth.reset()
        auth = nil
        try await super.tearDown()
    }

    // MARK: - signUp

    func testSignUp_createsUserAndSetsSession() async throws {
        let user = try await auth.signUp(email: "alice@example.com", password: "password123", username: "alice")

        XCTAssertEqual(user.username, "alice")
        XCTAssertEqual(user.email, "alice@example.com")
        XCTAssertFalse(user.isPremium)
        XCTAssertEqual(user.role, "USER")
        XCTAssertEqual(auth.currentUser?.id, user.id)
        XCTAssertNotNil(auth.authToken)
    }

    func testSignUp_rejectsShortPassword() async {
        do {
            _ = try await auth.signUp(email: "bob@example.com", password: "12345", username: "bob")
            XCTFail("Should have thrown passwordTooShort")
        } catch FakeAuthError.passwordTooShort {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testSignUp_rejectsShortUsername() async {
        do {
            _ = try await auth.signUp(email: "carol@example.com", password: "password123", username: "ab")
            XCTFail("Should have thrown usernameTooShort")
        } catch FakeAuthError.usernameTooShort {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testSignUp_rejectsDuplicateEmail() async throws {
        _ = try await auth.signUp(email: "dup@example.com", password: "password123", username: "first")
        do {
            _ = try await auth.signUp(email: "dup@example.com", password: "password123", username: "second")
            XCTFail("Should have thrown emailAlreadyExists")
        } catch FakeAuthError.emailAlreadyExists {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - signIn

    func testSignIn_withValidCredentials_setsSession() async throws {
        _ = try await auth.signUp(email: "dave@example.com", password: "password123", username: "dave")
        try await auth.signOut()

        let user = try await auth.signIn(email: "dave@example.com", password: "password123")

        XCTAssertEqual(user.username, "dave")
        XCTAssertEqual(auth.currentUser?.id, user.id)
        XCTAssertNotNil(auth.authToken)
    }

    func testSignIn_withWrongPassword_throwsInvalidPassword() async throws {
        _ = try await auth.signUp(email: "eve@example.com", password: "password123", username: "eve")
        try await auth.signOut()

        do {
            _ = try await auth.signIn(email: "eve@example.com", password: "wrong")
            XCTFail("Should have thrown invalidPassword")
        } catch FakeAuthError.invalidPassword {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testSignIn_withUnknownEmail_throwsUserNotFound() async {
        do {
            _ = try await auth.signIn(email: "nobody@example.com", password: "password123")
            XCTFail("Should have thrown userNotFound")
        } catch FakeAuthError.userNotFound {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - signOut

    func testSignOut_clearsSession() async throws {
        _ = try await auth.signUp(email: "frank@example.com", password: "password123", username: "frank")
        XCTAssertNotNil(auth.currentUser)

        try await auth.signOut()

        XCTAssertNil(auth.currentUser)
        XCTAssertNil(auth.authToken)
    }

    // MARK: - deleteAccount

    func testDeleteAccount_removesUserAndClearsSession() async throws {
        _ = try await auth.signUp(email: "grace@example.com", password: "password123", username: "grace")

        try await auth.deleteAccount()

        XCTAssertNil(auth.currentUser)
        XCTAssertNil(auth.authToken)

        // Verify user is gone — signIn should fail.
        do {
            _ = try await auth.signIn(email: "grace@example.com", password: "password123")
            XCTFail("Should have thrown userNotFound")
        } catch FakeAuthError.userNotFound {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testDeleteAccount_whenNotAuthenticated_throws() async {
        do {
            try await auth.deleteAccount()
            XCTFail("Should have thrown notAuthenticated")
        } catch FakeAuthError.notAuthenticated {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - fetchCurrentUser

    func testFetchCurrentUser_whenAuthenticated_returnsUser() async throws {
        let signedUp = try await auth.signUp(email: "henry@example.com", password: "password123", username: "henry")
        let fetched = try await auth.fetchCurrentUser()
        XCTAssertEqual(fetched.id, signedUp.id)
    }

    func testFetchCurrentUser_whenNotAuthenticated_throws() async {
        do {
            _ = try await auth.fetchCurrentUser()
            XCTFail("Should have thrown notAuthenticated")
        } catch FakeAuthError.notAuthenticated {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - updateProfile

    func testUpdateProfile_updatesUsername() async throws {
        _ = try await auth.signUp(email: "ivy@example.com", password: "password123", username: "ivy")
        let updated = try await auth.updateProfile(username: "ivy_new", avatarURL: nil, displayName: "Ivy", coverURL: nil)

        XCTAssertEqual(updated.username, "ivy_new")
        XCTAssertEqual(updated.displayName, "Ivy")
        XCTAssertEqual(auth.currentUser?.username, "ivy_new")
    }

    func testUpdateProfile_whenNotAuthenticated_throws() async {
        do {
            _ = try await auth.updateProfile(username: "x", avatarURL: nil, displayName: nil, coverURL: nil)
            XCTFail("Should have thrown notAuthenticated")
        } catch FakeAuthError.notAuthenticated {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - verifyAdminCode

    func testVerifyAdminCode_withValidCode_promotesToAdmin() async throws {
        _ = auth.seedUser(email: "admin@example.com", password: "pw", username: "admin")
        try await auth.signIn(email: "admin@example.com", password: "pw")

        let user = try await auth.verifyAdminCode(email: "admin@example.com", code: "ADMIN-VALID-CODE")

        XCTAssertEqual(user.role, "ADMIN")
        XCTAssertEqual(auth.currentUser?.role, "ADMIN")
    }

    func testVerifyAdminCode_withInvalidCode_throws() async throws {
        _ = auth.seedUser(email: "admin2@example.com", password: "pw", username: "admin2")
        try await auth.signIn(email: "admin2@example.com", password: "pw")

        do {
            _ = try await auth.verifyAdminCode(email: "admin2@example.com", code: "WRONG")
            XCTFail("Should have thrown invalidAdminCode")
        } catch FakeAuthError.invalidAdminCode {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - updateCachedUser

    func testUpdateCachedUser_overridesCurrentUser() async throws {
        _ = try await auth.signUp(email: "jack@example.com", password: "password123", username: "jack")
        let cached = User(
            id: "different-id",
            username: "override",
            email: "jack@example.com",
            avatarURL: nil,
            isOnline: true,
            isPremium: true,
            role: "ADMIN",
            createdAt: Date()
        )
        auth.updateCachedUser(cached)
        XCTAssertEqual(auth.currentUser?.id, "different-id")
        XCTAssertEqual(auth.currentUser?.isPremium, true)
    }

    // MARK: - seedUser helper

    func testSeedUser_createsUserWithoutActivatingSession() {
        let user = auth.seedUser(email: "seeded@example.com", password: "pw", username: "seeded", isPremium: true, role: "ADMIN")

        XCTAssertEqual(user.username, "seeded")
        XCTAssertTrue(user.isPremium)
        XCTAssertEqual(user.role, "ADMIN")
        XCTAssertNil(auth.currentUser, "seedUser should not activate session")
        XCTAssertNil(auth.authToken)
    }
}
