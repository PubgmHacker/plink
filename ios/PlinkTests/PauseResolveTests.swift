// PlinkTests/PauseResolveTests.swift
//
// M27 — вердикт хоста по просьбе о паузе: провод → политика очереди → модель.
// Зеркало PauseRequestTests: те же три тихих места отказа.
//
//   1. Кодирование. Серверная схема strict + .optional(): отсутствие ключа
//      requestUserId проходит, "requestUserId": null — SCHEMA_INVALID.
//   2. Офлайн-очередь. Вердикт не копится: доставленный после реконнекта,
//      он отвечает на просьбу, которой уже никто не ждёт.
//   3. Модель. Системную строку видят все, кроме самого хоста (своё эхо);
//      висящая подсказка гасится у любого клиента — вопрос уже закрыт.

import XCTest
@testable import Plink

@MainActor
final class PauseResolveTests: XCTestCase {

    private let roomId = "11111111-2222-3333-4444-555555555555"
    private let meId = "00000000-0000-4000-8000-0000000000aa"
    private let guestId = "00000000-0000-4000-8000-0000000000bb"
    private let hostId = "00000000-0000-4000-8000-0000000000cc"

    // MARK: - Хелперы

    private func makeModel(hostId: String? = nil) -> WatchRoomModel {
        WatchRoomModel(
            roomId: roomId,
            currentUserId: meId,
            currentUsername: "me",
            baseEndpoint: URL(string: "https://plink.test")!,
            ticketProvider: { room in
                RealtimeTicket(jwt: "test-jwt", roomId: room, expiresInSec: 60)
            },
            roomHostId: hostId
        )
    }

    private func makeClient() -> RealtimeClient {
        RealtimeClient(
            baseEndpoint: URL(string: "https://plink.test")!,
            ticketProvider: { room in
                RealtimeTicket(jwt: "test-jwt", roomId: room, expiresInSec: 60)
            }
        )
    }

    private func encode(_ msg: RealtimeClientMessage) throws -> [String: Any] {
        let data = try JSONEncoder().encode(msg)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "pause.resolve должен кодироваться в JSON-объект"
        )
    }

    private func pauseResolvedJSON(
        hostId: String,
        hostName: String = "alice",
        accepted: Bool = false,
        requestUserId: String? = nil,
        serverTimeMs: Int64 = 1_769_472_000_000
    ) -> String {
        let requestField = requestUserId.map { "\"requestUserId\": \"\($0)\"," }
            ?? "\"requestUserId\": null,"
        return """
        {
          "type": "pause.resolved",
          "protocolVersion": 2,
          "roomId": "\(roomId)",
          "hostId": "\(hostId)",
          "hostName": "\(hostName)",
          "accepted": \(accepted),
          \(requestField)
          "serverTimeMs": \(serverTimeMs)
        }
        """
    }

    private func decodePauseResolved(_ json: String) throws -> RealtimeServerMessage {
        try JSONDecoder().decode(RealtimeServerMessage.self, from: Data(json.utf8))
    }

    private func pauseRequestedJSON(userId: String) -> String {
        """
        {
          "type": "pause.requested", "protocolVersion": 2,
          "roomId": "\(roomId)", "userId": "\(userId)",
          "username": "guest", "reason": null, "serverTimeMs": 1
        }
        """
    }

    // MARK: - 1. Кодирование исходящего вердикта

    func testPauseResolve_encodesWireFieldsExactly() throws {
        let object = try encode(.pauseResolve(.init(
            roomId: roomId, accepted: true, requestUserId: guestId
        )))
        XCTAssertEqual(object["type"] as? String, "pause.resolve")
        XCTAssertEqual(object["protocolVersion"] as? Int, 2)
        XCTAssertEqual(object["roomId"] as? String, roomId)
        XCTAssertEqual(object["accepted"] as? Bool, true)
        XCTAssertEqual(object["requestUserId"] as? String, guestId)
        // strict-схема: ничего лишнего.
        XCTAssertEqual(Set(object.keys), ["type", "protocolVersion", "roomId", "accepted", "requestUserId"])
    }

    /// Главный тест файла: ключ requestUserId обязан ОТСУТСТВОВАТЬ, а не быть
    /// null — PauseResolveSchema .strict() с .optional() null отвергает.
    func testPauseResolve_withoutRequester_omitsKeyEntirelyNotNull() throws {
        let object = try encode(.pauseResolve(.init(roomId: roomId, accepted: false)))
        XCTAssertFalse(
            object.keys.contains("requestUserId"),
            "requestUserId: null отбивается сервером как SCHEMA_INVALID — ключа быть не должно"
        )
        XCTAssertEqual(Set(object.keys), ["type", "protocolVersion", "roomId", "accepted"])
    }

    func testPauseResolve_blankRequesterTreatedAsAbsent() throws {
        let object = try encode(.pauseResolve(.init(roomId: roomId, accepted: true, requestUserId: "  ")))
        XCTAssertFalse(object.keys.contains("requestUserId"))
    }

    // MARK: - 2. Декодирование входящего вердикта

    func testPauseResolved_decodesFromWire() throws {
        let decoded = try decodePauseResolved(pauseResolvedJSON(
            hostId: hostId, accepted: true, requestUserId: guestId
        ))
        guard case .pauseResolved(let event) = decoded else {
            return XCTFail("Ожидался кейс pauseResolved, получено: \(decoded)")
        }
        XCTAssertEqual(event.type, "pause.resolved")
        XCTAssertEqual(event.protocolVersion, 2)
        XCTAssertEqual(event.roomId, roomId)
        XCTAssertEqual(event.hostId, hostId)
        XCTAssertEqual(event.hostName, "alice")
        XCTAssertTrue(event.accepted)
        XCTAssertEqual(event.requestUserId, guestId)
        XCTAssertEqual(event.serverTimeMs, 1_769_472_000_000)
    }

    func testPauseResolved_decodesExplicitNullRequester() throws {
        let decoded = try decodePauseResolved(pauseResolvedJSON(hostId: hostId))
        guard case .pauseResolved(let event) = decoded else {
            return XCTFail("Ожидался кейс pauseResolved")
        }
        XCTAssertNil(event.requestUserId)
    }

    func testPauseResolved_rejectsWrongProtocolVersion() {
        let json = """
        {
          "type": "pause.resolved", "protocolVersion": 1,
          "roomId": "\(roomId)", "hostId": "\(hostId)",
          "hostName": "alice", "accepted": true,
          "requestUserId": null, "serverTimeMs": 1
        }
        """
        XCTAssertThrowsError(try decodePauseResolved(json))
    }

    // MARK: - 3. Политика офлайн-очереди

    func testPauseResolve_neverQueuedOffline() {
        let client = makeClient()  // state == .idle, транспорта нет
        client.send(.pauseResolve(.init(roomId: roomId, accepted: true, requestUserId: guestId)))
        XCTAssertEqual(
            client.queuedUserMessageCount, 0,
            "Вердикт по просьбе, которой уже никто не ждёт, не должен копиться"
        )
    }

    // MARK: - 4. Модель: входящий вердикт

    func testHandlePauseResolved_appendsSystemLineForGuests() throws {
        let model = makeModel(hostId: hostId)
        model.sessionDidConnect(role: .viewer)

        model.handleOtherMessage(try decodePauseResolved(pauseResolvedJSON(
            hostId: hostId, accepted: false, requestUserId: guestId
        )))

        let line = try XCTUnwrap(model.chatMessages.last, "Гость обязан увидеть вердикт")
        XCTAssertEqual(line.senderId, "plink-system")
        XCTAssertTrue(line.text.contains("alice"), "В строке должно быть имя хоста: \(line.text)")
    }

    func testHandlePauseResolved_ownEchoIsSilentForHost() throws {
        let model = makeModel(hostId: meId)
        model.sessionDidConnect(role: .host)

        // The host just pressed the button themselves; the echo must not duplicate the chat line.
        model.handleOtherMessage(try decodePauseResolved(pauseResolvedJSON(hostId: meId)))
        XCTAssertTrue(model.chatMessages.isEmpty)
    }

    func testHandlePauseResolved_clearsPendingPromptEverywhere() throws {
        // Scenario: the host is on TWO devices. The first shows the prompt,
        // the second answers. The first must drop the banner: the question is closed.
        let model = makeModel(hostId: meId)
        model.sessionDidConnect(role: .host)
        model.handleOtherMessage(try JSONDecoder().decode(
            RealtimeServerMessage.self, from: Data(pauseRequestedJSON(userId: guestId).utf8)
        ))
        XCTAssertNotNil(model.pendingPauseRequest)

        model.handleOtherMessage(try decodePauseResolved(pauseResolvedJSON(
            hostId: hostId, accepted: true, requestUserId: guestId
        )))
        XCTAssertNil(model.pendingPauseRequest, "Решённая просьба не должна висеть баннером")
    }

    func testHandlePauseResolved_emptyHostNameFallsBackToLocalizedHost() throws {
        let model = makeModel(hostId: hostId)
        model.sessionDidConnect(role: .viewer)

        model.handleOtherMessage(try decodePauseResolved(pauseResolvedJSON(
            hostId: hostId, hostName: ""
        )))
        let line = try XCTUnwrap(model.chatMessages.last)
        XCTAssertFalse(
            line.text.contains("  "),
            "Пустое имя не должно оставлять дыру в строке: \(line.text)"
        )
    }

    // MARK: - 5. Model: outgoing verdict

    func testResolvePauseRequest_declineStillClearsPromptAndDoesNotPause() throws {
        let model = makeModel(hostId: meId)
        model.sessionDidConnect(role: .host)
        model.handleOtherMessage(try JSONDecoder().decode(
            RealtimeServerMessage.self, from: Data(pauseRequestedJSON(userId: guestId).utf8)
        ))
        XCTAssertNotNil(model.pendingPauseRequest)

        model.resolvePauseRequest(pause: false)
        XCTAssertNil(model.pendingPauseRequest)
        XCTAssertFalse(model.coordinator.isPlaying)
    }

    func testResolvePauseRequest_withoutPendingSendsNothing() {
        let model = makeModel(hostId: meId)
        model.sessionDidConnect(role: .host)
        // No pending request means no verdict (see the guard in resolvePauseRequest).
        model.resolvePauseRequest(pause: true)
        XCTAssertNil(model.pendingPauseRequest)
        XCTAssertTrue(model.chatMessages.isEmpty)
    }
}
