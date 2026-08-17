// PlinkTests/FakeAuthService.swift — PATCH 17: testable auth service
//
// In-memory implementation of AuthServiceProtocol for unit tests.
// No network, no Keychain, no UserDefaults — pure state machine.

import Foundation
@testable import Plink

@MainActor
final class FakeAuthService: AuthServiceProtocol {
    private var users: [String: FakeUser] = [:]  // email → user
    private var usersById: [String: FakeUser] = [:]
    private var passwords: [String: String] = [:]

    private(set) var currentUser: User?
    private(set) var authToken: String?

    var currentUserValue: User? { currentUser }

    struct FakeUser {
        let id: String
        let email: String
        var username: String
        var isPremium: Bool
        var role: String
    }

    init() {}

    private func makeUser(from fake: FakeUser) -> User {
        User(
            id: fake.id,
            username: fake.username,
            email: fake.email,
            avatarURL: nil,
            displayName: nil,
            coverURL: nil,
            isOnline: true,
            isPremium: fake.isPremium,
            role: fake.role,
            createdAt: Date()
        )
    }

    // MARK: - AuthServiceProtocol

    func signIn(email: String, password: String) async throws -> User {
        guard let fake = users[email.lowercased()] else {
            throw FakeAuthError.userNotFound
        }
        guard passwords[email.lowercased()] == password else {
            throw FakeAuthError.invalidPassword
        }
        let user = makeUser(from: fake)
        currentUser = user
        authToken = "fake-token-\(fake.id)"
        return user
    }

    func signUp(email: String, password: String, username: String) async throws -> User {
        let key = email.lowercased()
        guard users[key] == nil else {
            throw FakeAuthError.emailAlreadyExists
        }
        guard password.count >= 6 else {
            throw FakeAuthError.passwordTooShort
        }
        guard username.count >= 3 else {
            throw FakeAuthError.usernameTooShort
        }
        let id = UUID().uuidString
        let fake = FakeUser(id: id, email: key, username: username, isPremium: false, role: "USER")
        users[key] = fake
        usersById[id] = fake
        passwords[key] = password
        let user = makeUser(from: fake)
        currentUser = user
        authToken = "fake-token-\(id)"
        return user
    }

    func signOut() async throws {
        currentUser = nil
        authToken = nil
    }

    func currentUser() async -> User? {
        currentUser
    }

    func verifyAdminCode(email: String, code: String) async throws -> User {
        guard code == "ADMIN-VALID-CODE" else {
            throw FakeAuthError.invalidAdminCode
        }
        guard let fake = users[email.lowercased()] else {
            throw FakeAuthError.userNotFound
        }
        var updated = fake
        updated.role = "ADMIN"
        users[fake.email] = updated
        usersById[fake.id] = updated
        let user = makeUser(from: updated)
        currentUser = user
        return user
    }

    func deleteAccount() async throws {
        guard let user = currentUser else {
            throw FakeAuthError.notAuthenticated
        }
        if let fake = usersById[user.id] {
            users.removeValue(forKey: fake.email)
            passwords.removeValue(forKey: fake.email)
        }
        usersById.removeValue(forKey: user.id)
        currentUser = nil
        authToken = nil
    }

    func fetchCurrentUser() async throws -> User {
        guard let user = currentUser else {
            throw FakeAuthError.notAuthenticated
        }
        return user
    }

    func updateCachedUser(_ user: User) {
        currentUser = user
    }

    func updateProfile(username: String?, avatarURL: String?, displayName: String?, coverURL: String?) async throws -> User {
        guard let user = currentUser else {
            throw FakeAuthError.notAuthenticated
        }
        let updated = User(
            id: user.id,
            username: username ?? user.username,
            email: user.email,
            avatarURL: avatarURL ?? user.avatarURL,
            displayName: displayName ?? user.displayName,
            coverURL: coverURL ?? user.coverURL,
            isOnline: user.isOnline,
            isPremium: user.isPremium,
            role: user.role,
            createdAt: user.createdAt
        )
        currentUser = updated
        return updated
    }

    // MARK: - Test helpers

    @discardableResult
    func seedUser(email: String, password: String, username: String, id: String? = nil, isPremium: Bool = false, role: String = "USER") -> User {
        let key = email.lowercased()
        let userId = id ?? UUID().uuidString
        let fake = FakeUser(id: userId, email: key, username: username, isPremium: isPremium, role: role)
        users[key] = fake
        usersById[userId] = fake
        passwords[key] = password
        return makeUser(from: fake)
    }

    func reset() {
        users.removeAll()
        usersById.removeAll()
        passwords.removeAll()
        currentUser = nil
        authToken = nil
    }
}

enum FakeAuthError: Error, Equatable {
    case userNotFound
    case invalidPassword
    case emailAlreadyExists
    case passwordTooShort
    case usernameTooShort
    case invalidAdminCode
    case notAuthenticated
}
