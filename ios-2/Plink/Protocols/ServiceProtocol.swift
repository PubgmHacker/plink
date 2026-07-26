// Plink/Protocols/ServiceProtocol.swift — protocols matching actual implementations

import Foundation

@MainActor
protocol AuthServiceProtocol: AnyObject {
    var currentUser: User? { get }
    var currentUserValue: User? { get }
    var authToken: String? { get }
    func signIn(email: String, password: String) async throws -> User
    func signUp(email: String, password: String, username: String) async throws -> User
    func signOut() async throws
    func currentUser() async -> User?
    func verifyAdminCode(email: String, code: String) async throws -> User
    func deleteAccount() async throws
    func fetchCurrentUser() async throws -> User
    func updateCachedUser(_ user: User)
    func updateProfile(username: String?, avatarURL: String?, displayName: String?, coverURL: String?) async throws -> User
}

@MainActor
protocol RoomServiceProtocol: AnyObject {
    func fetchActiveRooms() async throws -> [Room]
    func fetchMyRooms() async throws -> [Room]
    func fetchPublicRooms() async throws -> [Room]
    func createRoom(_ request: CreateRoomRequest) async throws -> Room
    func joinRoom(code: String, password: String?) async throws -> Room
    func leaveRoom(roomID: String) async throws
    func deleteRoom(roomID: String) async throws
    func fetchRoom(id: String) async throws -> Room
}
