// PlinkTests/FakeRoomService.swift — PATCH 19: testable room service
//
// In-memory implementation of RoomServiceProtocol for unit tests.
// No network — pure state machine.

import Foundation
@testable import Plink

@MainActor
final class FakeRoomService: RoomServiceProtocol {
    private var rooms: [String: Room] = [:]  // id → room
    private var roomsByCode: [String: String] = [:]  // code → roomID
    private var myRoomIds: Set<String> = []

    init() {}

    // MARK: - RoomServiceProtocol

    func fetchActiveRooms() async throws -> [Room] {
        rooms.values.filter { $0.isActive }.sorted { $0.createdAt > $1.createdAt }
    }

    func fetchMyRooms() async throws -> [Room] {
        rooms.values.filter { myRoomIds.contains($0.id) }.sorted { $0.createdAt > $1.createdAt }
    }

    func fetchPublicRooms() async throws -> [Room] {
        rooms.values.filter { $0.isActive && $0.privacy == .publicRoom }.sorted { $0.createdAt > $1.createdAt }
    }

    func createRoom(_ request: CreateRoomRequest) async throws -> Room {
        let id = UUID().uuidString
        let code = generateRoomCode()
        let room = Room(
            id: id,
            name: request.name,
            hostID: "fake-host-id",
            hostName: request.hostName ?? "Host",
            code: code,
            participants: [],
            mediaItem: request.mediaItem,
            isActive: true,
            maxParticipants: request.maxParticipants,
            hostIsPremium: false,
            createdAt: Date(),
            privacy: request.privacy,
            password: request.password
        )
        rooms[id] = room
        roomsByCode[code] = id
        myRoomIds.insert(id)
        return room
    }

    func joinRoom(code: String, password: String?) async throws -> Room {
        guard let roomId = roomsByCode[code.uppercased()] ?? roomsByCode[code] else {
            throw FakeRoomError.roomNotFound
        }
        guard var room = rooms[roomId] else {
            throw FakeRoomError.roomNotFound
        }
        if room.isLocked {
            guard let password = password, password == room.password else {
                throw FakeRoomError.invalidPassword
            }
        }
        if room.participants.count >= room.maxParticipants {
            throw FakeRoomError.roomFull
        }
        // Add fake participant.
        let participant = UserPreview(id: UUID().uuidString, username: "Joiner", avatarURL: nil, isOnline: true)
        room.participants.append(participant)
        rooms[roomId] = room
        myRoomIds.insert(roomId)
        return room
    }

    func leaveRoom(roomID: String) async throws {
        myRoomIds.remove(roomID)
    }

    func deleteRoom(roomID: String) async throws {
        guard let room = rooms.removeValue(forKey: roomID) else {
            throw FakeRoomError.roomNotFound
        }
        roomsByCode.removeValue(forKey: room.code)
        myRoomIds.remove(roomID)
    }

    func fetchRoom(id: String) async throws -> Room {
        guard let room = rooms[id] else {
            throw FakeRoomError.roomNotFound
        }
        return room
    }

    // MARK: - Test helpers

    @discardableResult
    func seedRoom(
        id: String = UUID().uuidString,
        name: String = "Test Room",
        hostName: String = "Host",
        code: String? = nil,
        maxParticipants: Int = 10,
        isActive: Bool = true,
        privacy: RoomPrivacy = .publicRoom,
        password: String? = nil
    ) -> Room {
        let roomCode = code ?? generateRoomCode()
        let room = Room(
            id: id,
            name: name,
            hostID: "host-\(id)",
            hostName: hostName,
            code: roomCode,
            participants: [],
            mediaItem: nil,
            isActive: isActive,
            maxParticipants: maxParticipants,
            hostIsPremium: false,
            createdAt: Date(),
            privacy: privacy,
            password: password
        )
        rooms[id] = room
        roomsByCode[roomCode] = id
        return room
    }

    func reset() {
        rooms.removeAll()
        roomsByCode.removeAll()
        myRoomIds.removeAll()
    }

    private func generateRoomCode() -> String {
        String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })
    }
}

enum FakeRoomError: Error, Equatable {
    case roomNotFound
    case invalidPassword
    case roomFull
}
