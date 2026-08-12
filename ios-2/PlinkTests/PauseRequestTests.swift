// PlinkTests/PauseRequestTests.swift
//
// M26 — «Попросить паузу»: провод → политика очереди → модель.
//
// Фича устроена так, что сервер плеер НЕ трогает: гость отправляет просьбу,
// хост решает. Значит вся ответственность за честность — на клиенте, и ломается
// она тихо. Три места, где именно:
//
//   1. Кодирование. Серверная схема strict + .optional(): отсутствие ключа
//      reason проходит, "reason": null — нет. Дефолтный Encodable положил бы
//      null, и КАЖДАЯ просьба без пометки отбивалась бы как SCHEMA_INVALID.
//   2. Офлайн-очередь. Просьба намеренно НЕ копится: доставленная через
//      полминуты после реконнекта, она просит остановить другой кадр. Значит
//      модель обязана вернуть отказ, а не сделать вид, что отправила.
//   3. Модель. Хост видит подсказку, гость — только строку в чате; своё эхо
//      подсказку не показывает; кулдаун не переживает переподключение.
//
// Ни один из этих отказов не виден в UI-тесте: экран выглядит одинаково и когда
// просьба ушла, и когда её съел энкодер.

import XCTest
@testable import Plink

@MainActor
final class PauseRequestTests: XCTestCase {

    private let roomId = "11111111-2222-3333-4444-555555555555"
    private let meId = "00000000-0000-4000-8000-0000000000aa"
    private let guestId = "00000000-0000-4000-8000-0000000000bb"

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
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "pause.request должен кодироваться в JSON-объект"
        )
        return object
    }

    private func pauseRequestedJSON(
        userId: String,
        username: String = "guest",
        reason: String? = "отойду",
        serverTimeMs: Int64 = 1_769_472_000_000
    ) -> String {
        let reasonField = reason.map { "\"reason\": \"\($0)\"," } ?? "\"reason\": null,"
        return """
        {
          "type": "pause.requested",
          "protocolVersion": 2,
          "roomId": "\(roomId)",
          "userId": "\(userId)",
          "username": "\(username)",
          \(reasonField)
          "serverTimeMs": \(serverTimeMs)
        }
        """
    }

    private func decodePauseRequested(_ json: String) throws -> RealtimeServerMessage {
        try JSONDecoder().decode(RealtimeServerMessage.self, from: Data(json.utf8))
    }

    // MARK: - 1. Кодирование исходящей просьбы

    func testPauseRequest_encodesWireFieldsExactly() throws {
        let object = try encode(.pauseRequest(.init(roomId: roomId, reason: "отойду на минуту")))
        XCTAssertEqual(object["type"] as? String, "pause.request")
        XCTAssertEqual(object["protocolVersion"] as? Int, 2)
        XCTAssertEqual(object["roomId"] as? String, roomId)
        XCTAssertEqual(object["reason"] as? String, "отойду на минуту")
        // strict-схема: ничего лишнего.
        XCTAssertEqual(Set(object.keys), ["type", "protocolVersion", "roomId", "reason"])
    }

    /// Главный тест файла. Ключ reason обязан ОТСУТСТВОВАТЬ, а не быть null:
    /// PauseRequestSchema — .strict() с .optional(), null он отвергает.
    func testPauseRequest_withoutReason_omitsKeyEntirelyNotNull() throws {
        let object = try encode(.pauseRequest(.init(roomId: roomId)))
        XCTAssertFalse(
            object.keys.contains("reason"),
            "reason: null отбивается сервером как SCHEMA_INVALID — ключа быть не должно"
        )
        XCTAssertEqual(Set(object.keys), ["type", "protocolVersion", "roomId"])
    }

    func testPauseRequest_blankReasonTreatedAsAbsent() throws {
        for blank in ["", "   ", "\n\t "] {
            let object = try encode(.pauseRequest(.init(roomId: roomId, reason: blank)))
            XCTAssertFalse(
                object.keys.contains("reason"),
                "Пробельная пометка \(blank.debugDescription) не проходит min(1) на сервере"
            )
        }
    }

    func testPauseRequest_trimsReasonAndClampsTo120() throws {
        let object = try encode(.pauseRequest(.init(roomId: roomId, reason: "  подожди  ")))
        XCTAssertEqual(object["reason"] as? String, "подожди")

        let long = String(repeating: "я", count: 500)
        let clamped = try encode(.pauseRequest(.init(roomId: roomId, reason: long)))
        // Сервер режет по max(120) отказом, а не усечением — клиент обязан
        // сам уложиться в границу, иначе длинная пометка теряет всю просьбу.
        XCTAssertEqual((clamped["reason"] as? String)?.count, 120)
    }

    // MARK: - 2. Декодирование входящего события

    func testPauseRequested_decodesFromWire() throws {
        let decoded = try decodePauseRequested(pauseRequestedJSON(userId: guestId))
        guard case .pauseRequested(let event) = decoded else {
            return XCTFail("Ожидался кейс pauseRequested, получено: \(decoded)")
        }
        XCTAssertEqual(event.type, "pause.requested")
        XCTAssertEqual(event.protocolVersion, 2)
        XCTAssertEqual(event.roomId, roomId)
        XCTAssertEqual(event.userId, guestId)
        XCTAssertEqual(event.username, "guest")
        XCTAssertEqual(event.reason, "отойду")
        XCTAssertEqual(event.serverTimeMs, 1_769_472_000_000)
    }

    func testPauseRequested_decodesExplicitNullReason() throws {
        let decoded = try decodePauseRequested(pauseRequestedJSON(userId: guestId, reason: nil))
        guard case .pauseRequested(let event) = decoded else {
            return XCTFail("Ожидался кейс pauseRequested, получено: \(decoded)")
        }
        XCTAssertNil(event.reason)
    }

    func testPauseRequested_decodesMissingReasonKey() throws {
        // Сервер шлёт null, но контракт не должен рассыпаться, если поле
        // однажды начнут опускать.
        let json = """
        {
          "type": "pause.requested", "protocolVersion": 2,
          "roomId": "\(roomId)", "userId": "\(guestId)",
          "username": "guest", "serverTimeMs": 1
        }
        """
        guard case .pauseRequested(let event) = try decodePauseRequested(json) else {
            return XCTFail("Ожидался кейс pauseRequested")
        }
        XCTAssertNil(event.reason)
    }

    func testPauseRequested_rejectsWrongProtocolVersion() {
        let json = """
        {
          "type": "pause.requested", "protocolVersion": 1,
          "roomId": "\(roomId)", "userId": "\(guestId)",
          "username": "guest", "reason": null, "serverTimeMs": 1
        }
        """
        XCTAssertThrowsError(try decodePauseRequested(json))
    }

    // MARK: - 3. Политика офлайн-очереди

    func testPauseRequest_neverQueuedOffline_whileChatIs() {
        let client = makeClient()  // state == .idle, транспорта нет
        XCTAssertEqual(client.queuedUserMessageCount, 0)

        client.send(.pauseRequest(.init(roomId: roomId, reason: "отойду")))
        XCTAssertEqual(
            client.queuedUserMessageCount, 0,
            "Просьба о паузе, доставленная после реконнекта, просит остановить другой кадр"
        )

        // Контроль: чат в тех же условиях как раз обязан копиться.
        client.send(.chatSend(.init(roomId: roomId, clientMessageId: "c1", text: "привет")))
        XCTAssertEqual(client.queuedUserMessageCount, 1)
    }

    // MARK: - 4. Модель: исходящая просьба

    func testRequestPause_offlineWhenNotConnected() {
        let model = makeModel()
        XCTAssertEqual(model.requestPause(), .offline)
    }

    func testRequestPause_redundantForHost() {
        let model = makeModel(hostId: meId)
        model.sessionDidConnect(role: .host)
        XCTAssertTrue(model.isHost)
        // У хоста есть настоящая кнопка паузы — просить ему некого.
        XCTAssertEqual(model.requestPause(), .redundantForHost)
    }

    func testRequestPause_sentThenThrottled() {
        let model = makeModel(hostId: guestId)
        model.sessionDidConnect(role: .viewer)
        XCTAssertFalse(model.isHost)

        XCTAssertEqual(model.requestPause(reason: "отойду"), .sent)
        // Серверный лимит — 1 просьба в 10 с. Локальный кулдаун чуть шире,
        // чтобы гонка часов не превращала законный тап в код ошибки.
        XCTAssertEqual(model.requestPause(), .throttled)
        XCTAssertEqual(model.requestPause(reason: "ну пожалуйста"), .throttled)
    }

    func testRequestPause_cooldownDoesNotSurviveReconnect() {
        let model = makeModel(hostId: guestId)
        model.sessionDidConnect(role: .viewer)
        XCTAssertEqual(model.requestPause(), .sent)
        XCTAssertEqual(model.requestPause(), .throttled)

        // Разрыв связи — просьба всё равно не доехала бы; после возврата
        // человек не должен упираться в кулдаун от прошлой сессии.
        model.disconnect()
        model.sessionDidConnect(role: .viewer)
        XCTAssertEqual(model.requestPause(), .sent)
    }

    // MARK: - 5. Модель: входящая просьба

    func testHandlePauseRequested_showsPromptToHostAndSystemLine() throws {
        let model = makeModel(hostId: meId)
        model.sessionDidConnect(role: .host)

        model.handleOtherMessage(try decodePauseRequested(pauseRequestedJSON(userId: guestId)))

        let prompt = try XCTUnwrap(model.pendingPauseRequest, "Хост обязан увидеть просьбу")
        XCTAssertEqual(prompt.userId, guestId)
        XCTAssertEqual(prompt.username, "guest")
        XCTAssertEqual(prompt.reason, "отойду")

        let line = try XCTUnwrap(model.chatMessages.last)
        XCTAssertEqual(line.senderId, "plink-system")
        XCTAssertTrue(line.text.contains("guest"), "В строке чата должно быть имя: \(line.text)")
    }

    func testHandlePauseRequested_guestSeesLineButNoPrompt() throws {
        let model = makeModel(hostId: guestId)
        model.sessionDidConnect(role: .viewer)

        let other = "00000000-0000-4000-8000-0000000000cc"
        model.handleOtherMessage(try decodePauseRequested(pauseRequestedJSON(userId: other)))

        // Гость не может поставить паузу — подсказка с кнопкой была бы ложью.
        XCTAssertNil(model.pendingPauseRequest)
        // Но знать, что просьба уже висит, ему нужно: иначе просят все разом.
        XCTAssertEqual(model.chatMessages.last?.senderId, "plink-system")
    }

    func testHandlePauseRequested_ownEchoDoesNotPromptSelf() throws {
        let model = makeModel(hostId: meId)
        model.sessionDidConnect(role: .host)

        // Событие рассылается всей комнате, включая автора. Хост, попросивший
        // сам себя (теоретически — до смены роли), не должен получить окно.
        model.handleOtherMessage(try decodePauseRequested(pauseRequestedJSON(userId: meId)))
        XCTAssertNil(model.pendingPauseRequest)
        XCTAssertEqual(model.chatMessages.count, 1)
    }

    func testHandlePauseRequested_emptyUsernameFallsBackToGuest() throws {
        let model = makeModel(hostId: meId)
        model.sessionDidConnect(role: .host)

        model.handleOtherMessage(
            try decodePauseRequested(pauseRequestedJSON(userId: guestId, username: ""))
        )
        XCTAssertEqual(model.pendingPauseRequest?.username, "Гость")
    }

    func testHandlePauseRequested_latestRequestReplacesPrompt() throws {
        let model = makeModel(hostId: meId)
        model.sessionDidConnect(role: .host)

        model.handleOtherMessage(
            try decodePauseRequested(userId: guestId, at: 1_769_472_000_000)
        )
        let first = try XCTUnwrap(model.pendingPauseRequest?.id)

        let another = "00000000-0000-4000-8000-0000000000cc"
        model.handleOtherMessage(
            try decodePauseRequested(userId: another, at: 1_769_472_005_000)
        )
        let second = try XCTUnwrap(model.pendingPauseRequest)
        XCTAssertNotEqual(second.id, first, "Свежая просьба обязана вытеснить старую")
        XCTAssertEqual(second.userId, another)
        // Обе видны в чате — вытеснение подсказки не стирает историю.
        XCTAssertEqual(model.chatMessages.count, 2)
    }

    // MARK: - 6. Модель: ответ хоста

    func testResolvePauseRequest_dismissClearsWithoutPausing() throws {
        let model = makeModel(hostId: meId)
        model.sessionDidConnect(role: .host)
        model.handleOtherMessage(try decodePauseRequested(pauseRequestedJSON(userId: guestId)))
        XCTAssertNotNil(model.pendingPauseRequest)

        model.resolvePauseRequest(pause: false)
        XCTAssertNil(model.pendingPauseRequest)
        XCTAssertFalse(model.coordinator.isPlaying)
    }

    func testResolvePauseRequest_acceptClearsPrompt() throws {
        let model = makeModel(hostId: meId)
        model.sessionDidConnect(role: .host)
        model.handleOtherMessage(try decodePauseRequested(pauseRequestedJSON(userId: guestId)))

        model.resolvePauseRequest(pause: true)
        XCTAssertNil(model.pendingPauseRequest)
    }

    func testResolvePauseRequest_withoutPendingIsNoop() {
        let model = makeModel(hostId: meId)
        model.sessionDidConnect(role: .host)
        XCTAssertNil(model.pendingPauseRequest)
        model.resolvePauseRequest(pause: true)  // не должно ничего сломать
        XCTAssertNil(model.pendingPauseRequest)
    }

    func testDisconnect_clearsPendingPrompt() throws {
        let model = makeModel(hostId: meId)
        model.sessionDidConnect(role: .host)
        model.handleOtherMessage(try decodePauseRequested(pauseRequestedJSON(userId: guestId)))
        XCTAssertNotNil(model.pendingPauseRequest)

        // Иначе просьба переживает выход из комнаты и всплывает в следующей.
        model.disconnect()
        XCTAssertNil(model.pendingPauseRequest)
    }

    // MARK: - Хелпер с таймстемпом

    private func decodePauseRequested(userId: String, at serverTimeMs: Int64) throws -> RealtimeServerMessage {
        try decodePauseRequested(pauseRequestedJSON(userId: userId, serverTimeMs: serverTimeMs))
    }
}
