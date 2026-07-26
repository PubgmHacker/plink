import Foundation

// MARK: - Home View Model
@MainActor
@Observable
final class HomeViewModel {

    // MARK: - State

    var rooms: [Room] = []
    /// 🔧 NEW: User's own rooms (created + previously joined)
    var myRooms: [Room] = []
    var isLoading = false
    var errorMessage: String?
    var showCreateRoom = false
    var showJoinRoom = false
    var searchText = ""
    var selectedRoom: Room?

    var filteredRooms: [Room] {
        // Сначала убираем заблокированных хостов (Блок 1 — мгновенная локальная фильтрация).
        let notBlocked = blockManager.filterRooms(rooms)

        if searchText.isEmpty {
            return notBlocked
        }
        return notBlocked.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.hostName.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Суммарное количество участников во всех активных комнатах —
    /// метрика для шапки Discovery Dashboard («123 watching now»).
    var totalActiveParticipants: Int {
        rooms.filter { $0.isActive }.reduce(0) { $0 + $1.participantCount }
    }

    /// Топ-5 комнат по количеству участников (тренды).
    var trendingRooms: [Room] {
        blockManager.filterRooms(rooms)
            .filter { $0.participantCount > 0 }
            .sorted { $0.participantCount > $1.participantCount }
            .prefix(5)
            .map { $0 }
    }

    /// Активные комнаты, отсортированные по популярности.
    var activeRooms: [Room] {
        blockManager.filterRooms(rooms)
            .filter { $0.isActive }
            .sorted { $0.participantCount > $1.participantCount }
    }

    // MARK: - Services

    private let roomService: RoomServiceProtocol
    private let authService: AuthServiceProtocol

    /// Локальный менеджер блокировок (Блок 1 — UGC).
    @MainActor let blockManager = UserBlockManager()

    // MARK: - Init

    init(roomService: RoomServiceProtocol, authService: AuthServiceProtocol) {
        self.roomService = roomService
        self.authService = authService
    }

    // MARK: - Actions

    func loadRooms() async {
        isLoading = true
        errorMessage = nil

        do {
            rooms = try await roomService.fetchActiveRooms()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 🔧 NEW: Load user's own rooms (created + joined history)
    func loadMyRooms() async {
        do {
            myRooms = try await roomService.fetchMyRooms()
        } catch {
            Logger.api.error("[HomeVM] loadMyRooms error: \(error.localizedDescription)")
        }
    }

    func createRoom(name: String, maxParticipants: Int, mediaItem: MediaItem?, privacy: RoomPrivacy = .publicRoom, password: String? = nil) async throws -> Room {
        let request = CreateRoomRequest(
            name: name,
            maxParticipants: maxParticipants,
            mediaItem: mediaItem,
            privacy: privacy,
            password: password,
            hostName: authService.currentUserValue?.username
        )
        let room = try await roomService.createRoom(request)
        rooms.insert(room, at: 0)
        return room
    }

    func joinRoom(code: String, password: String? = nil) async throws -> Room {
        let room = try await roomService.joinRoom(code: code, password: password)
        rooms.insert(room, at: 0)
        return room
    }

    // MARK: - Delete Room

    /// 🔧 NEW: Удаление комнаты (только host). Вызывает DELETE /rooms/:id на бэкенде,
    /// после чего каскадно удаляются все participants, messages, playback states.
    /// Локально убираем комнату из `rooms` и `myRooms` списков для мгновенного UI feedback.
    /// В случае ошибки — пробрасываем наверх для показа alert.
    @MainActor
    func deleteRoom(_ room: Room) async throws {
        try await roomService.deleteRoom(roomID: room.id)
        // Убираем из обоих локальных списков (instant UI feedback)
        rooms.removeAll { $0.id == room.id }
        myRooms.removeAll { $0.id == room.id }
    }

    func refresh() async {
        await loadRooms()
    }

    // MARK: - UGC Moderation (Блок 1)

    /// Блокирует хоста комнаты и мгновенно убирает его комнаты из списка.
    func blockRoom(_ room: Room) {
        blockManager.blockUser(room.hostID)
        // filteredRooms пересчитается автоматически (зависит от blockManager.blockedUserIds).
        // Принудительно триггерим обновление @Observable через мутацию массива.
        rooms = rooms.filter { $0.hostID != room.hostID }
    }

    /// Разблокирует пользователя.
    func unblockUser(_ userId: String) {
        blockManager.unblockUser(userId)
    }
}
