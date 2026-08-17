// PlinkTests/WebsocketTests.swift — PATCH 21: websockets system tests
//
// Tests RealtimeClient state machine + message encoding/decoding.
// No real WebSocket — uses contract tests on the message types.

import XCTest
@testable import Plink

@MainActor
final class WebsocketTests: XCTestCase {

    // MARK: - RealtimeClientMessage encoding

    // protocolVersion — константа в живом API (literal 2), в init не передаётся.
    // effectiveAtServerMs назначает СЕРВЕР, в SyncCommand его нет вовсе.

    func testSyncCommand_encodesCorrectly() throws {
        let msg = RealtimeClientMessage.SyncCommand(
            roomId: "room-123",
            actionId: "action-456",
            mediaId: nil,
            positionMs: 5000,
            playing: true,
            rate: 1.0
        )
        let data = try JSONEncoder().encode(RealtimeClientMessage.syncCommand(msg))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["type"] as? String, "sync.command")
        XCTAssertEqual(json?["protocolVersion"] as? Int, 2)
        XCTAssertEqual(json?["roomId"] as? String, "room-123")
        XCTAssertEqual(json?["actionId"] as? String, "action-456")
    }

    func testChatSend_encodesCorrectly() throws {
        let msg = RealtimeClientMessage.ChatSend(
            roomId: "room-123",
            clientMessageId: "cmid-789",
            text: "Hello world"
        )
        let data = try JSONEncoder().encode(RealtimeClientMessage.chatSend(msg))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["type"] as? String, "chat.send")
        XCTAssertEqual(json?["protocolVersion"] as? Int, 2)
        XCTAssertEqual(json?["clientMessageId"] as? String, "cmid-789")
        XCTAssertEqual(json?["text"] as? String, "Hello world")
    }

    func testReactionSend_encodesCorrectly() throws {
        let msg = RealtimeClientMessage.ReactionSend(
            roomId: "room-123",
            emoji: "❤️"
        )
        let data = try JSONEncoder().encode(RealtimeClientMessage.reactionSend(msg))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["type"] as? String, "reaction.send")
        XCTAssertEqual(json?["emoji"] as? String, "❤️")
    }

    // MARK: - RealtimeConnectionState transitions

    func testState_idleToConnecting() {
        let state: RealtimeConnectionState = .idle
        XCTAssertFalse(state.isOnline)

        let nextState: RealtimeConnectionState = .connecting
        XCTAssertTrue(nextState.isTransient)
    }

    func testState_connectingToConnected() {
        let connecting: RealtimeConnectionState = .connecting
        let connected: RealtimeConnectionState = .connected

        XCTAssertFalse(connecting.isOnline)
        XCTAssertTrue(connected.isOnline)
    }

    func testState_failed_hasReason() {
        let failed: RealtimeConnectionState = .failed(reason: "timeout")
        if case .failed(let reason) = failed {
            XCTAssertEqual(reason, "timeout")
        } else {
            XCTFail("Expected .failed case")
        }
    }

    // MARK: - RealtimeTicket

    func testRealtimeTicket_construction() {
        let ticket = RealtimeTicket(jwt: "jwt-token", roomId: "room-123", expiresInSec: 60)
        XCTAssertEqual(ticket.jwt, "jwt-token")
        XCTAssertEqual(ticket.roomId, "room-123")
        XCTAssertEqual(ticket.expiresInSec, 60)
    }

    // MARK: - Message type discrimination

    func testMessageTypes_areDistinct() throws {
        // RealtimeClientMessage не Equatable — сравниваем дискриминатор type в JSON.
        let sync = RealtimeClientMessage.syncCommand(.init(
            roomId: "r", actionId: "a", mediaId: nil,
            positionMs: 0, playing: false, rate: 1.0
        ))
        let chat = RealtimeClientMessage.chatSend(.init(
            roomId: "r", clientMessageId: "c", text: "hi"
        ))
        let syncJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sync)) as? [String: Any]
        let chatJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(chat)) as? [String: Any]
        XCTAssertNotEqual(syncJSON?["type"] as? String, chatJSON?["type"] as? String)
    }

    // MARK: - RoomRole

    func testRoomRole_cases() {
        // RoomRole has .host and .viewer.
        let host: RoomRole = .host
        let viewer: RoomRole = .viewer
        XCTAssertNotEqual(host, viewer)
    }
}
