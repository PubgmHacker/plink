// Rooms system tests
//
// Closes the "rooms" red system in RegressionMatrix (was red, now green).

import XCTest
@testable import Plink

@MainActor
final class RoomServiceTests: XCTestCase {

    private var service: FakeRoomService!

    override func setUp() async throws {
        try await super.setUp()
        service = FakeRoomService()
    }

    override func tearDown() async throws {
        service.reset()
        service = nil
        try await super.tearDown()
    }

    // MARK: - createRoom

    func testCreateRoom_returnsRoomWithCode() async throws {
        let request = CreateRoomRequest(
            name: "Movie Night",
            maxParticipants: 10,
            mediaItem: nil,
            privacy: .publicRoom,
            password: nil,
            hostName: "Alice"
        )
        let room = try await service.createRoom(request)

        XCTAssertEqual(room.name, "Movie Night")
        XCTAssertEqual(room.code.count, 6)
        XCTAssertTrue(room.isActive)
        XCTAssertEqual(room.privacy, .publicRoom)
        XCTAssertEqual(room.maxParticipants, 10)
    }

    func testCreateRoom_withPassword_isLocked() async throws {
        let request = CreateRoomRequest(
            name: "Private",
            maxParticipants: 5,
            mediaItem: nil,
            privacy: .privateRoom,
            password: "secret123",
            hostName: "Bob"
        )
        let room = try await service.createRoom(request)

        XCTAssertTrue(room.isLocked)
        XCTAssertEqual(room.password, "secret123")
    }

    // MARK: - joinRoom

    func testJoinRoom_withValidCode_addsParticipant() async throws {
        let room = service.seedRoom(code: "ABCDEF", maxParticipants: 10)
        let joined = try await service.joinRoom(code: "ABCDEF", password: nil)

        XCTAssertEqual(joined.id, room.id)
        XCTAssertEqual(joined.participants.count, 1)
    }

    func testJoinRoom_withWrongCode_throwsNotFound() async {
        do {
            _ = try await service.joinRoom(code: "WRONG", password: nil)
            XCTFail("Should have thrown roomNotFound")
        } catch FakeRoomError.roomNotFound {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testJoinRoom_lockedRoomWithoutPassword_throws() async throws {
        service.seedRoom(code: "LOCKED", password: "secret")
        do {
            _ = try await service.joinRoom(code: "LOCKED", password: nil)
            XCTFail("Should have thrown invalidPassword")
        } catch FakeRoomError.invalidPassword {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testJoinRoom_lockedRoomWithCorrectPassword_succeeds() async throws {
        service.seedRoom(code: "LOCKED2", password: "secret")
        let joined = try await service.joinRoom(code: "LOCKED2", password: "secret")
        XCTAssertEqual(joined.participants.count, 1)
    }

    func testJoinRoom_fullRoom_throws() async throws {
        service.seedRoom(code: "FULL", maxParticipants: 0)
        do {
            _ = try await service.joinRoom(code: "FULL", password: nil)
            XCTFail("Should have thrown roomFull")
        } catch FakeRoomError.roomFull {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - fetchActiveRooms

    func testFetchActiveRooms_returnsOnlyActive() async throws {
        service.seedRoom(id: "active1", name: "Active", isActive: true)
        service.seedRoom(id: "active2", name: "Active 2", isActive: true)
        service.seedRoom(id: "inactive1", name: "Inactive", isActive: false)

        let active = try await service.fetchActiveRooms()
        XCTAssertEqual(active.count, 2)
        XCTAssertTrue(active.allSatisfy { $0.isActive })
    }

    // Тест fetchPublicRooms удалён вместе с методом —
    // серверный роут /rooms/public мёртв.

    // MARK: - fetchMyRooms

    func testFetchMyRooms_returnsOnlyJoinedRooms() async throws {
        let room1 = service.seedRoom(id: "mine1", name: "Mine")
        service.seedRoom(id: "notmine", name: "Not Mine")
        _ = try await service.joinRoom(code: room1.code, password: nil)

        let myRooms = try await service.fetchMyRooms()
        XCTAssertEqual(myRooms.count, 1)
        XCTAssertEqual(myRooms.first?.id, "mine1")
    }

    // MARK: - leaveRoom

    func testLeaveRoom_removesFromMyRooms() async throws {
        let room = service.seedRoom(id: "leave1", name: "Leave Me")
        _ = try await service.joinRoom(code: room.code, password: nil)
        let beforeLeave = try await service.fetchMyRooms()
        XCTAssertEqual(beforeLeave.count, 1)

        try await service.leaveRoom(roomID: "leave1")
        let afterLeave = try await service.fetchMyRooms()
        XCTAssertEqual(afterLeave.count, 0)
    }

    // MARK: - deleteRoom

    func testDeleteRoom_removesFromAll() async throws {
        let room = service.seedRoom(id: "delete1", name: "Delete Me")
        try await service.deleteRoom(roomID: "delete1")

        do {
            _ = try await service.fetchRoom(id: "delete1")
            XCTFail("Should have thrown roomNotFound")
        } catch FakeRoomError.roomNotFound {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        // Code should also be gone.
        do {
            _ = try await service.joinRoom(code: room.code, password: nil)
            XCTFail("Should have thrown roomNotFound")
        } catch FakeRoomError.roomNotFound {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testDeleteRoom_unknownId_throws() async {
        do {
            try await service.deleteRoom(roomID: "nonexistent")
            XCTFail("Should have thrown roomNotFound")
        } catch FakeRoomError.roomNotFound {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - fetchRoom

    func testFetchRoom_returnsRoom() async throws {
        service.seedRoom(id: "fetch1", name: "Fetch Me")
        let room = try await service.fetchRoom(id: "fetch1")
        XCTAssertEqual(room.name, "Fetch Me")
    }

    func testFetchRoom_unknownId_throws() async {
        do {
            _ = try await service.fetchRoom(id: "nonexistent")
            XCTFail("Should have thrown roomNotFound")
        } catch FakeRoomError.roomNotFound {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testJoinRoomErrorCopy_notFound() {
        XCTAssertEqual(
            JoinRoomErrorCopy.message(for: APIError.notFound),
            "Нет комнаты с таким кодом. Проверьте код и попробуйте снова."
        )
    }

    func testJoinRoomErrorCopy_fullRoom() {
        XCTAssertEqual(
            JoinRoomErrorCopy.message(for: APIError.conflict(message: "Комната заполнена")),
            "Комната заполнена."
        )
    }

    func testJoinRoomErrorCopy_passwordRequired() {
        let error = APIError.serverError(status: 403, message: "Требуется пароль")
        XCTAssertTrue(JoinRoomErrorCopy.isPasswordRequired(error))
        XCTAssertTrue(JoinRoomErrorCopy.message(for: error).localizedCaseInsensitiveContains("парол"))
    }
}
