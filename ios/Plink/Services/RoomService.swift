import Foundation

// MARK: - Room Service
/// Manages room CRUD operations via REST API.
final class RoomService: RoomServiceProtocol {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - Create Room

    // События воронки были ОПИСАНЫ в AnalyticsService,
    // но не вызывались — 11 из 17. В том числе весь основной цикл продукта:
    // создание комнаты, вход и выход. Без них удержание D1/D7/D30 измерить
    // невозможно, а это метрика №1 для решения о масштабировании.
    // Трекинг ставится ЗДЕСЬ, а не в UI: так событие фиксируется независимо
    // от того, из какого экрана пришёл вызов, и ровно один раз.

    func createRoom(_ request: CreateRoomRequest) async throws -> Room {
        let room: Room = try await api.request("rooms", method: .post, body: request)
        AnalyticsService.shared.roomCreated(source: request.mediaItem?.source.rawValue ?? "unknown")
        return room
    }

    // MARK: - Join Room

    func joinRoom(code: String, password: String? = nil) async throws -> Room {
        let request = JoinRoomRequest(code: code, password: password)
        let room: Room = try await api.request("rooms/join", method: .post, body: request)
        AnalyticsService.shared.roomJoined(via: "code")
        return room
    }

    // MARK: - Leave Room

    func leaveRoom(roomID: String) async throws {
        try await api.requestNoBody("rooms/\(roomID)/leave", method: .post)
        AnalyticsService.shared.roomLeft()
        await MainActor.run {
            NotificationCenter.default.post(name: .plinkRoomsDidChange, object: roomID)
        }
    }

    /// Host soft-ends room (stays in history only).
    func endRoom(roomID: String) async throws {
        try await api.requestNoBody("rooms/\(roomID)/end", method: .post)
        await MainActor.run {
            NotificationCenter.default.post(name: .plinkRoomsDidChange, object: roomID)
        }
    }

    // MARK: - Fetch Active Rooms

    func fetchActiveRooms() async throws -> [Room] {
        let rooms: [Room] = try await api.request("rooms", method: .get)
        // Client-side guard: never show empty / ended shells in "watching now"
        return rooms.filter { $0.isActive && $0.participantCount >= 2 } // BUG-FIX: skip host-only rooms
    }

    // MARK: - Fetch Single Room

    func fetchRoom(id: String) async throws -> Room {
        try await api.request("rooms/\(id)")
    }

    // MARK: - Privacy (M15 — бар модерации)

    /// Хост меняет режим приватности живой комнаты.
    func updatePrivacy(roomID: String, privacy: RoomPrivacy, password: String?) async throws {
        struct Body: Encodable {
            let privacy: String
            let password: String?
        }
        try await api.requestNoBody(
            "rooms/\(roomID)/privacy",
            method: .patch,
            body: Body(privacy: privacy.rawValue, password: password)
        )
    }

    // MARK: - Delete Room

    func deleteRoom(roomID: String) async throws {
        try await api.requestNoBody("rooms/\(roomID)", method: .delete)
    }

    // fetchPublicRooms() удалён — роут /rooms/public на
    // сервере отдаёт 404 (rooms.ts), единственным потребителем был мёртвый
    // DiscoveryService.

    // MARK: - My Rooms

    func fetchMyRooms() async throws -> [Room] {
        try await fetchMyRooms(status: "all")
    }

    /// - Parameter status: `active` | `history` | `all`.
    func fetchMyRooms(status: String) async throws -> [Room] {
        // Строку запроса нельзя клеить к пути: APIClient собирает URL через
        // appendingPathComponent, который экранирует «?» в %3F — получался путь
        // «rooms/mine%3Fstatus=active» и стабильный 404. Из-за этого «мои комнаты»
        // и история не загружались вообще. Параметры идём через query:.
        return try await api.request(
            "rooms/mine",
            method: .get,
            query: status == "all" ? nil : ["status": status]
        )
    }

    /// Only rooms still joinable (live + people inside).
    func fetchMyActiveRooms() async throws -> [Room] {
        try await fetchMyRooms(status: "active")
    }

    /// Closed rooms for history UI.
    func fetchMyRoomHistory() async throws -> [Room] {
        try await fetchMyRooms(status: "history")
    }

    // MARK: - Start Stream (хост)

    func startRoom(roomID: String) async throws {
        struct Body: Encodable {}
        try await api.requestNoBody("rooms/\(roomID)/start", method: .post, body: Body())
    }

    // MARK: - Playback State

    func updatePlayback(roomID: String, time: TimeInterval, isPlaying: Bool) async throws {
        struct Body: Encodable {
            let time: TimeInterval
            let isPlaying: Bool
        }
        try await api.requestNoBody("rooms/\(roomID)/playback", method: .post, body: Body(time: time, isPlaying: isPlaying))
    }

    func fetchPlayback(roomID: String) async throws -> (time: TimeInterval, isPlaying: Bool) {
        struct PlaybackResponse: Decodable {
            let currentTime: TimeInterval?
            let isPlaying: Bool?
        }
        let resp: PlaybackResponse = try await api.request("rooms/\(roomID)/playback")
        return (resp.currentTime ?? 0, resp.isPlaying ?? false)
    }
}
