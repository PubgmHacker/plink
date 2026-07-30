// PlinkTests/RoomLiveThemeTests.swift
//
// P1 5.11 — живые темы комнаты: провод → стор → рендер-слой.
//
// Что закрываем:
//   1. декодирование wire-сообщения room.appearance.updated (strict-формат
//      бэкенда: contracts/realtime-v2.ts → RoomAppearanceUpdatedSchema);
//   2. разбор строки Room.appearance из БД тем же типом (там есть лишние
//      аудит-поля updatedAt/updatedBy — они обязаны быть опциональны);
//   3. применение через RoomAppearanceStore.applyServerUpdate;
//   4. откат на defaultStatic при неизвестном themeId;
//   5. клэмп intensity до 0.44 (V4 cap).

import XCTest
@testable import Plink

// MARK: - Стаб прав

private final class StubEntitlement: EntitlementProviding {
    let isPlinkPlus: Bool
    var plinkPlusExpiresAt: Date? { nil }
    init(isPlinkPlus: Bool) { self.isPlinkPlus = isPlinkPlus }
    func refresh() async {}
}

// MARK: - Стаб транспорта PATCH

/// Записывает, что реально ушло на сервер, и умеет отвечать ошибкой.
@MainActor
private final class StubTransport {
    private(set) var sent: [RoomAppearanceUpdate] = []
    var failure: Error?

    func send(_ roomID: String, _ body: RoomAppearanceUpdate) async throws {
        sent.append(body)
        if let failure { throw failure }
    }
}

@MainActor
final class RoomLiveThemeTests: XCTestCase {

    private func makeStore(
        isHost: Bool = true,
        premium: Bool = true,
        transport: StubTransport? = nil
    ) -> RoomAppearanceStore {
        var wire: RoomAppearanceStore.Transport?
        if let transport {
            wire = { room, body in try await transport.send(room, body) }
        }
        return RoomAppearanceStore(
            roomID: "11111111-2222-3333-4444-555555555555",
            isHost: isHost,
            entitlement: StubEntitlement(isPlinkPlus: premium),
            transport: wire
        )
    }

    // MARK: - 1. Wire

    func testRoomAppearanceUpdated_decodesFromWire() throws {
        let json = """
        {
          "type": "room.appearance.updated",
          "protocolVersion": 2,
          "roomId": "11111111-2222-3333-4444-555555555555",
          "appearance": {
            "themeId": "room-neon-rain",
            "themeRevision": 3,
            "intensity": 0.44,
            "motionEnabled": true
          },
          "serverTimeMs": 1769472000000
        }
        """
        let decoded = try JSONDecoder().decode(
            RealtimeServerMessage.self,
            from: Data(json.utf8)
        )
        guard case .roomAppearanceUpdated(let event) = decoded else {
            return XCTFail("Ожидался кейс roomAppearanceUpdated, получено: \(decoded)")
        }
        XCTAssertEqual(event.type, "room.appearance.updated")
        XCTAssertEqual(event.protocolVersion, 2)
        XCTAssertEqual(event.roomId, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(event.appearance.themeId, "room-neon-rain")
        XCTAssertEqual(event.appearance.themeRevision, 3)
        XCTAssertEqual(event.appearance.intensity, 0.44, accuracy: 0.0001)
        XCTAssertTrue(event.appearance.motionEnabled)
        XCTAssertEqual(event.serverTimeMs, 1_769_472_000_000)
        // На проводе аудит-полей нет — они существуют только в БД.
        XCTAssertNil(event.appearance.updatedAt)
        XCTAssertNil(event.appearance.updatedBy)
    }

    func testRoomAppearanceUpdated_rejectsWrongProtocolVersion() {
        let json = """
        {
          "type": "room.appearance.updated",
          "protocolVersion": 1,
          "roomId": "room-1",
          "appearance": {
            "themeId": "room-aurora", "themeRevision": 1,
            "intensity": 0.2, "motionEnabled": true
          },
          "serverTimeMs": 1
        }
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(RealtimeServerMessage.self, from: Data(json.utf8))
        )
    }

    // MARK: - 2. Строка Room.appearance из БД

    func testAppearancePayload_decodesDatabaseStringWithAuditFields() throws {
        // Ровно то, что кладёт в БД PATCH /rooms/:id/appearance.
        let dbString = """
        {
          "themeId": "room-aurora",
          "themeRevision": 1,
          "intensity": 0.44,
          "motionEnabled": true,
          "updatedAt": "2026-07-26T10:00:00.000Z",
          "updatedBy": "user-1"
        }
        """
        let payload = try JSONDecoder().decode(
            RealtimeServerMessage.RoomAppearanceUpdated.Payload.self,
            from: Data(dbString.utf8)
        )
        XCTAssertEqual(payload.themeId, "room-aurora")
        XCTAssertEqual(payload.updatedBy, "user-1")
        XCTAssertEqual(payload.updatedAt, "2026-07-26T10:00:00.000Z")

        let appearance = RoomAppearance(wire: payload)
        XCTAssertEqual(appearance.themeId, "room-aurora")
        XCTAssertTrue(appearance.isLiveTheme)
    }

    // MARK: - 3. Применение в сторе

    func testApplyServerUpdate_appliesKnownTheme() {
        let store = makeStore()
        XCTAssertEqual(store.appearance.themeId, "room-default-static")

        store.applyServerUpdate(RoomAppearance(
            themeId: "room-cinema-dust",
            themeRevision: 2,
            intensity: 0.30,
            motionEnabled: false
        ))

        XCTAssertEqual(store.appearance.themeId, "room-cinema-dust")
        XCTAssertEqual(store.appearance.themeRevision, 2)
        XCTAssertEqual(store.appearance.intensity, 0.30, accuracy: 0.0001)
        XCTAssertFalse(store.appearance.motionEnabled)
        XCTAssertTrue(RoomLiveTheme.isActive(store.appearance))
    }

    func testApplyServerUpdate_fromWireEvent() throws {
        let store = makeStore()
        let event = RealtimeServerMessage.RoomAppearanceUpdated(
            roomId: "room-1",
            appearance: .init(
                themeId: "room-afterparty",
                themeRevision: 1,
                intensity: 0.25,
                motionEnabled: true
            ),
            serverTimeMs: 1
        )
        store.applyServerUpdate(RoomAppearance(wire: event.appearance))
        XCTAssertEqual(store.appearance.themeId, "room-afterparty")
        XCTAssertEqual(store.appearance.intensity, 0.25, accuracy: 0.0001)
    }

    // MARK: - 4. Неизвестная тема → defaultStatic

    func testApplyServerUpdate_unknownThemeFallsBackToDefaultStatic() {
        let store = makeStore()
        store.applyServerUpdate(RoomAppearance(
            themeId: "room-theme-from-the-future",
            themeRevision: 9,
            intensity: 0.40,
            motionEnabled: true
        ))
        XCTAssertEqual(store.appearance.themeId, RoomAppearance.staticThemeId)
        XCTAssertFalse(store.appearance.isLiveTheme)
        XCTAssertFalse(RoomLiveTheme.isActive(store.appearance))
        // Ревизия берётся у каталожного дефолта, а не у неизвестной темы.
        XCTAssertEqual(store.appearance.themeRevision, RoomAppearance.defaultStatic.themeRevision)
    }

    func testApplyServerUpdate_revokedThemeRollsBackFromLive() {
        let store = makeStore()
        store.applyServerUpdate(RoomAppearance(themeId: "room-deep-sea", intensity: 0.44))
        XCTAssertEqual(store.appearance.themeId, "room-deep-sea")

        store.applyServerUpdate(RoomAppearance(themeId: "room-removed", intensity: 0.44))
        XCTAssertEqual(store.appearance.themeId, RoomAppearance.staticThemeId)
    }

    // MARK: - 5. Клэмп интенсивности

    func testIntensity_clampedToV4Cap() {
        XCTAssertEqual(
            RoomAppearance(themeId: "room-aurora", intensity: 5.0).intensity,
            0.44,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            RoomAppearance(themeId: "room-aurora", intensity: -1.0).intensity,
            0.0,
            accuracy: 0.0001
        )
    }

    func testApplyServerUpdate_clampsIntensityFromServer() {
        let store = makeStore()
        store.applyServerUpdate(RoomAppearance(
            themeId: "room-neon-rain",
            themeRevision: 1,
            intensity: 0.99,
            motionEnabled: true
        ))
        XCTAssertEqual(store.appearance.intensity, 0.44, accuracy: 0.0001)
    }

    // MARK: - Рендер-слой: пять тем реально различимы

    func testEveryCatalogRoomThemeHasRenderStyle() {
        for descriptor in AppearanceCatalog.roomLive {
            XCTAssertNotNil(
                RoomLiveThemeStyle(rawValue: descriptor.id),
                "Тема \(descriptor.id) продаётся в каталоге, но её нечем нарисовать"
            )
        }
        XCTAssertEqual(RoomLiveThemeStyle.allCases.count, AppearanceCatalog.roomLive.count)
    }

    func testScrimOpacity_onlyDimsWhenLiveThemeActive() {
        XCTAssertEqual(RoomLiveTheme.scrimOpacity(.defaultStatic), 1.0, accuracy: 0.0001)
        let live = RoomAppearance(themeId: "room-aurora", intensity: 0.44)
        XCTAssertLessThan(RoomLiveTheme.scrimOpacity(live), 1.0)
        XCTAssertGreaterThan(RoomLiveTheme.scrimOpacity(live), 0.3)
    }

    // Ревью 26.07.2026: «Уменьшение прозрачности» раньше учитывалось только в
    // подложке, а фон чата/пресенс-бара всё равно становился полупрозрачным —
    // ровно под текстом и ровно наоборот тому, что просит настройка.
    func testScrimOpacity_opaqueUnderReduceTransparency() {
        let live = RoomAppearance(themeId: "room-aurora", intensity: 0.44)
        XCTAssertEqual(
            RoomLiveTheme.scrimOpacity(live, reduceTransparency: true),
            1.0,
            accuracy: 0.0001
        )
    }

    // В landscape подложки за поверхностью нет (её перекрывает плеер) —
    // полупрозрачный чат показывал бы под текстом само видео.
    func testScrimOpacity_opaqueWhenBackdropHidden() {
        let live = RoomAppearance(themeId: "room-aurora", intensity: 0.44)
        XCTAssertEqual(
            RoomLiveTheme.scrimOpacity(live, backdropVisible: false),
            1.0,
            accuracy: 0.0001
        )
    }

    // MARK: - Роль

    func testSetHost_flipsHostFlag() {
        let store = makeStore(isHost: false)
        XCTAssertFalse(store.isHost)
        store.setHost(true)
        XCTAssertTrue(store.isHost)
    }

    func testUpdateTheme_rejectedForNonHost() async {
        let store = makeStore(isHost: false)
        do {
            try await store.updateTheme(to: "room-aurora")
            XCTFail("Не-хост не может менять тему комнаты")
        } catch {
            guard case RoomAppearanceError.notHost = error else {
                return XCTFail("Ожидался .notHost, получено: \(error)")
            }
        }
        XCTAssertEqual(store.appearance.themeId, RoomAppearance.staticThemeId)
    }

    // Ревью 26.07.2026: локальная проверка прав БОЛЬШЕ НЕ БЛОКИРУЕТ. По правилу
    // C9 PremiumStatusManager на холодном старте всегда отдаёт isPremium=false,
    // пока не ответит сервер, — и платящий хост получал отказ без запроса.
    func testUpdateTheme_withoutLocalEntitlement_stillAsksServer() async throws {
        let transport = StubTransport()
        let store = makeStore(isHost: true, premium: false, transport: transport)

        try await store.updateTheme(to: "room-aurora")

        XCTAssertEqual(transport.sent.count, 1, "PATCH обязан уйти — авторитет у сервера")
        XCTAssertEqual(transport.sent.first?.themeId, "room-aurora")
        XCTAssertEqual(store.appearance.themeId, "room-aurora")
    }

    // Отказ приходит от сервера (403 PREMIUM_REQUIRED) — с его текстом.
    func testUpdateTheme_serverPremiumRejectionKeepsServerMessage() async {
        let transport = StubTransport()
        transport.failure = APIError.serverError(
            status: 403,
            message: "Живые темы комнаты доступны в Plink+"
        )
        let store = makeStore(isHost: true, premium: false, transport: transport)
        do {
            try await store.updateTheme(to: "room-aurora")
            XCTFail("403 PREMIUM_REQUIRED должен пробрасываться наверх")
        } catch {
            guard case RoomAppearanceError.requiresPlinkPlus = error else {
                return XCTFail("Ожидался .requiresPlinkPlus, получено: \(error)")
            }
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                "Живые темы комнаты доступны в Plink+"
            )
        }
        XCTAssertEqual(transport.sent.count, 1)
        // Сервер отказал — локально тема не применяется.
        XCTAssertEqual(store.appearance.themeId, RoomAppearance.staticThemeId)
    }

    // На бесплатной статике премиум-гейта на сервере нет вовсе
    // (FREE_ROOM_THEME_IDS), значит 403 там — только requireHost.
    func testUpdateTheme_forbiddenOnFreeStaticMapsToNotHost() async {
        let transport = StubTransport()
        transport.failure = APIError.serverError(
            status: 403,
            message: "Only host can control playback"
        )
        let store = makeStore(isHost: true, premium: true, transport: transport)
        do {
            try await store.updateTheme(to: RoomAppearance.staticThemeId)
            XCTFail("403 обязан пробрасываться наверх")
        } catch {
            guard case RoomAppearanceError.notHost = error else {
                return XCTFail("Ожидался .notHost, получено: \(error)")
            }
        }
    }

    // MARK: - Гонка гидрации и realtime

    func testHydration_ignoredAfterRealtimeUpdate() {
        let store = makeStore()
        store.applyServerUpdate(RoomAppearance(themeId: "room-neon-rain", intensity: 0.44))
        // Опоздавший GET /rooms/:id со старым значением из БД.
        store.applyHydration(RoomAppearance(themeId: "room-aurora", intensity: 0.10))
        XCTAssertEqual(store.appearance.themeId, "room-neon-rain")
    }

    func testHydration_appliedWhenNothingAuthoritativeYet() {
        let store = makeStore()
        store.applyHydration(RoomAppearance(themeId: "room-aurora", intensity: 0.20))
        XCTAssertEqual(store.appearance.themeId, "room-aurora")
        // Событие всё ещё сильнее гидрации.
        store.applyServerUpdate(RoomAppearance(themeId: "room-deep-sea", intensity: 0.44))
        XCTAssertEqual(store.appearance.themeId, "room-deep-sea")
    }

    func testHydration_ignoredAfterHostCommit() async throws {
        let transport = StubTransport()
        let store = makeStore(transport: transport)
        try await store.updateTheme(to: "room-afterparty")
        store.applyHydration(RoomAppearance(themeId: "room-aurora", intensity: 0.10))
        XCTAssertEqual(store.appearance.themeId, "room-afterparty")
    }

    func testUpdateTheme_unknownThemeRejectedBeforeNetwork() async {
        let store = makeStore()
        do {
            try await store.updateTheme(to: "room-nope")
            XCTFail("Неизвестная тема не должна доходить до сети")
        } catch {
            guard case RoomAppearanceError.unknownTheme = error else {
                return XCTFail("Ожидался .unknownTheme, получено: \(error)")
            }
        }
    }
}
