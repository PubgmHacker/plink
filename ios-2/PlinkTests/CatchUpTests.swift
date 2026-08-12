// PlinkTests/CatchUpTests.swift
//
// M28 — «что я пропустил»: карточка появляется в момент опоздания,
// LLM-запрос — только по явному тапу.

import XCTest
@testable import Plink

@MainActor
final class CatchUpTests: XCTestCase {

    private let roomId = "11111111-2222-3333-4444-555555555555"
    private let meId = "00000000-0000-4000-8000-0000000000aa"

    private final class StubRecapClient: RoomRecapClient, @unchecked Sendable {
        var lastSinceMs: Int64?
        var response = RoomRecapResponse(recap: "говорили про финал", messageCount: 3)
        var shouldFail = false

        func fetchRecap(roomId: String, sinceMs: Int64) async throws -> RoomRecapResponse {
            lastSinceMs = sinceMs
            if shouldFail { throw URLError(.notConnectedToInternet) }
            return response
        }
    }

    private func makeModel(recap: StubRecapClient?) -> WatchRoomModel {
        WatchRoomModel(
            roomId: roomId,
            currentUserId: meId,
            currentUsername: "me",
            baseEndpoint: URL(string: "https://plink.test")!,
            ticketProvider: { room in
                RealtimeTicket(jwt: "test-jwt", roomId: room, expiresInSec: 60)
            },
            roomRecapClient: recap
        )
    }

    private func state(positionMs: Int64) -> RealtimeRoomState {
        RealtimeRoomState(
            protocolVersion: 2,
            roomId: roomId,
            epoch: 1,
            seq: 1,
            mediaId: "m1",
            positionMs: positionMs,
            playing: true,
            rate: 1,
            effectiveAtServerMs: 1,
            issuedBy: meId
        )
    }

    func testLateJoin_showsCatchUpAfterThreshold() async throws {
        let client = StubRecapClient()
        let model = makeModel(recap: client)
        model.sessionDidConnect(role: .viewer)
        model.applySnapshot(state(positionMs: 5 * 60_000))

        // Дать state pump применить snapshot.
        try? await Task.sleep(for: .milliseconds(50))

        let prompt = try XCTUnwrap(model.catchUpPrompt)
        XCTAssertEqual(prompt.kind, .lateJoin)
        XCTAssertEqual(prompt.missedMinutes, 5)
        // Запрос ещё НЕ ушёл — только карточка.
        XCTAssertNil(client.lastSinceMs)
    }

    func testLateJoin_belowThreshold_noPrompt() async {
        let model = makeModel(recap: StubRecapClient())
        model.sessionDidConnect(role: .viewer)
        model.applySnapshot(state(positionMs: 30_000))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(model.catchUpPrompt)
    }

    func testWithoutRecapClient_neverShowsPrompt() async {
        let model = makeModel(recap: nil)
        model.sessionDidConnect(role: .viewer)
        model.applySnapshot(state(positionMs: 10 * 60_000))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(model.catchUpPrompt)
    }

    func testRequestCatchUp_appendsPrivateLineAndClearsPrompt() async throws {
        let client = StubRecapClient()
        let model = makeModel(recap: client)
        model.sessionDidConnect(role: .viewer)
        model.applySnapshot(state(positionMs: 4 * 60_000))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertNotNil(model.catchUpPrompt)

        model.requestCatchUp()
        // Дождаться Task внутри requestCatchUp.
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertNil(model.catchUpPrompt)
        XCTAssertFalse(model.catchUpLoading)
        XCTAssertNotNil(client.lastSinceMs)
        let line = try XCTUnwrap(model.chatMessages.last)
        XCTAssertEqual(line.senderId, "plink-ai")
        XCTAssertTrue(line.text.contains("говорили про финал"))
    }

    func testDismissCatchUp_clearsWithoutNetwork() async {
        let client = StubRecapClient()
        let model = makeModel(recap: client)
        model.sessionDidConnect(role: .viewer)
        model.applySnapshot(state(positionMs: 4 * 60_000))
        try? await Task.sleep(for: .milliseconds(50))

        model.dismissCatchUp()
        XCTAssertNil(model.catchUpPrompt)
        XCTAssertNil(client.lastSinceMs)
        XCTAssertTrue(model.chatMessages.isEmpty)
    }

    func testPresenceStatusLine_pausedWhenRoomNotPlaying() async {
        let model = makeModel(recap: nil)
        model.sessionDidConnect(role: .viewer)
        let paused = RealtimeRoomState(
            protocolVersion: 2, roomId: roomId, epoch: 1, seq: 2,
            mediaId: "m1", positionMs: 1000, playing: false, rate: 1,
            effectiveAtServerMs: 1, issuedBy: meId
        )
        model.applySnapshot(paused)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(
            model.presenceStatusLine,
            LocalizationManager.shared.string(.presencePaused)
        )
    }
}
