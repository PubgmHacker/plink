// Plink/V4/PlinkV4BackendBridge.swift — P0 Roadmap
// Connects V4 pixel-perfect views to real RoomService/FriendManager/AuthService/MediaService.
// NO placeholders, NO fake data.

import SwiftUI
import UIKit
import Observation

// MARK: - V4 Rooms Store (P0.2)

@MainActor
@Observable
final class V4RoomsStore {
    enum LoadState: Sendable { case idle, loading, loaded, empty, failed(String) }
    private(set) var state: LoadState = .idle
    private(set) var rooms: [Room] = []
    private(set) var myRooms: [Room] = []
    private let roomService: RoomService

    init(roomService: RoomService) { self.roomService = roomService }

    func load() async {
        state = .loading
        do {
            // Public live rooms only (backend + client filter empty/ended)
            async let publicActive = roomService.fetchActiveRooms()
            async let mineActive = roomService.fetchMyActiveRooms()
            let pub = try await publicActive
            let mine = (try? await mineActive) ?? []
            // Merge by id — prefer fresher mine rows for host's own rooms
            var byId: [String: Room] = [:]
            for r in pub where r.isActive && r.participantCount > 0 { byId[r.id] = r }
            for r in mine where r.isActive && r.participantCount > 0 { byId[r.id] = r }
            let active = Array(byId.values).sorted { $0.createdAt > $1.createdAt }
            rooms = active
            myRooms = mine
            state = active.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMyRooms() async {
        do {
            myRooms = try await roomService.fetchMyActiveRooms()
        } catch {}
    }

    func loadHistory() async -> [Room] {
        (try? await roomService.fetchMyRoomHistory()) ?? []
    }

    func join(code: String, password: String? = nil) async throws -> Room {
        try await roomService.joinRoom(code: code, password: password)
    }

    func joinByID(_ room: Room) async throws -> Room {
        try await roomService.fetchRoom(id: room.id)
    }

    // M34: герой — приоритет активным комнатам друзей
    var heroRoom: Room? {
        let friendNames = Set(FriendManager.shared.friends.map { $0.username.lowercased() })
        return rooms.first(where: { $0.isActive && friendNames.contains($0.hostName.lowercased()) }) ?? rooms.first
    }
    var railRooms: [Room] { Array(rooms.filter { $0.id != heroRoom?.id }.prefix(6)) }
}

// MARK: - V4 Search Store (P0.3)

@MainActor
@Observable
final class V4SearchStore {
    enum SearchState: Sendable { case idle, loading, loaded([V4SearchResult]), empty, failed(String) }
    private(set) var state: SearchState = .idle
    private(set) var trending: [V4SearchResult] = []
    private var searchTask: Task<Void, Never>?
    private let apiBase = PlinkConfig.baseURLString

    func loadTrending() async {
        guard let url = URL(string: "\(apiBase)/api/media/trending?regionCode=RU&maxResults=20") else { return }
        do {
            var req = URLRequest(url: url)
            if let token = KeychainHelper.read(for: "rave_auth_token") {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            trending = resp.results.map(V4SearchResult.init)
        } catch {}
    }

    func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { state = .idle; return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            await self.performSearch(trimmed)
        }
    }

    private func performSearch(_ query: String) async {
        state = .loading
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(apiBase)/api/media/search?q=\(encoded)&limit=20") else { return }
        do {
            var req = URLRequest(url: url)
            if let token = KeychainHelper.read(for: "rave_auth_token") {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            let results = resp.results.map(V4SearchResult.init)
            state = results.isEmpty ? .empty : .loaded(results)
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct V4SearchResult: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let duration: String?
    let isSelectable: Bool

    init(from v: YouTubeVideoSummary) {
        id = v.videoId
        title = v.title
        subtitle = v.channelTitle
        artworkURL = v.thumbnailURLString.flatMap(URL.init(string:))
        let secs = v.durationSeconds ?? v.duration ?? 0
        if secs > 0 {
            let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
            duration = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        } else { duration = nil }
        isSelectable = v.isEmbeddable
    }
}

// MARK: - V4 Friends Store (P1.1)

@MainActor
@Observable
final class V4FriendsStore {
    enum LoadState: Sendable, Equatable {
        case idle, loading, loaded, empty, failed(String)
    }
    private(set) var state: LoadState = .idle
    private(set) var friends: [Friend] = []
    private(set) var requests: [FriendRequest] = []
    private(set) var outgoing: [FriendRequest] = []
    /// Exposed for Add Friend sheet (search / send)
    let friendManager: FriendManager

    init(friendManager: FriendManager) { self.friendManager = friendManager }

    func load() async {
        state = .loading
        await friendManager.loadAll()
        friends = friendManager.friends
        requests = friendManager.incomingRequests
        outgoing = friendManager.outgoingRequests
        // Chats section should show "loaded" whenever we have friends,
        // even if requests are empty (sender after accept on other phone).
        state = friends.isEmpty && requests.isEmpty && outgoing.isEmpty ? .empty : .loaded
    }

    /// Quiet refresh without full-screen loading spinner (poll / tab focus).
    func refreshQuietly() async {
        await friendManager.loadAll()
        friends = friendManager.friends
        requests = friendManager.incomingRequests
        outgoing = friendManager.outgoingRequests
        if case .loading = state { return }
        state = friends.isEmpty && requests.isEmpty && outgoing.isEmpty ? .empty : .loaded
    }

    func invite(userID: String, username: String) async {
        _ = await friendManager.sendRequest(to: userID, username: username)
        await load()
    }

    func accept(_ request: FriendRequest) async {
        await friendManager.acceptRequest(request)
        await load()
    }

    func decline(_ request: FriendRequest) async {
        await friendManager.declineRequest(request)
        await load()
    }
}

// MARK: - V4 AI Store (P0.4)

@MainActor
@Observable
final class V4AIStore {
    struct Message: Identifiable, Hashable {
        let id = UUID()
        let isOwn: Bool
        let text: String
        let isBot: Bool
        var proposedAction: AIProposedAction?
    }

    private(set) var messages: [Message] = [
        Message(isOwn: false, text: "Привет! Я Plink AI. Спроси про фильмы, попроси создать комнату или узнать что смотрят друзья.", isBot: true)
    ]
    private(set) var state: String = "Готов помочь"
    private(set) var lastSuggestions: [String] = []  // M34: подсказки после ответа

    // M33: персистентная история чата между запусками
    private struct SavedMessage: Codable { let isBot: Bool; let text: String }
    private static let historyKey = "plink.ai.history.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let saved = try? JSONDecoder().decode([SavedMessage].self, from: data),
           !saved.isEmpty {
            messages = saved.map { Message(isOwn: !$0.isBot, text: $0.text, isBot: $0.isBot) }
        }
    }

    private func persist() {
        let saved = messages.suffix(40).map { SavedMessage(isBot: $0.isBot, text: $0.text) }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    // M34: очистить историю чата
    func clearHistory() {
        messages = [Message(isOwn: false, text: "Привет! Я Plink AI. Спроси про фильмы, попроси создать комнату или узнать что смотрят друзья.", isBot: true)]
        lastSuggestions = []
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
    }

    func setStatus(_ text: String) {
        state = text
    }
    private let apiBase = PlinkConfig.baseURLString

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(Message(isOwn: true, text: trimmed, isBot: false))
        persist()
        AnalyticsService.shared.track("ai_message_sent")  // M35: funnel
        state = "Думаю…"

        do {
            var req = URLRequest(url: URL(string: "\(apiBase)/api/ai/chat")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = KeychainHelper.read(for: "rave_auth_token") {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            // Send full conversation history — not just the latest message.
            // Backend sends ALL messages to OpenRouter for context memory.
            let conversationMessages: [[String: String]] = messages.map { msg in
                [
                    "role": msg.isBot ? "assistant" : "user",
                    "content": msg.text
                ]
            } + [["role": "user", "content": trimmed]]
            let body: [String: Any] = [
                "messages": conversationMessages,
                "context": ["roomId": NSNull()],
                "mode": "assistant"
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let resp = try JSONDecoder().decode(AIChatResponse.self, from: data)
            messages.append(Message(
                isOwn: false,
                text: resp.message,
                isBot: true,
                proposedAction: resp.proposedAction
            ))
            lastSuggestions = resp.suggestions ?? []
            persist()
            state = "Готов помочь"
        } catch {
            messages.append(Message(isOwn: false, text: "Не удалось ответить. Попробуйте снова.", isBot: true))
            persist()
            state = "Ошибка"
        }
    }

    /// P0.4: Confirm a proposed AI action. Returns the created Room if successful.
    func confirmAction(_ action: AIProposedAction) async -> Room? {
        do {
            var req = URLRequest(url: URL(string: "\(apiBase)/api/ai/confirm-action")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = KeychainHelper.read(for: "rave_auth_token") {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let body: [String: Any] = [
                "confirmationId": action.confirmationId,
                "idempotencyKey": UUID().uuidString
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let resp = try JSONDecoder().decode(ConfirmActionResponse.self, from: data)
            return resp.room
        } catch {
            return nil
        }
    }
}

struct AIChatResponse: Decodable {
    let message: String
    let suggestions: [String]?
    let proposedAction: AIProposedAction?
}

struct ConfirmActionResponse: Decodable {
    let success: Bool
    let room: Room?
}

struct AIProposedAction: Decodable, Hashable {
    let type: String
    let confirmationId: String
    let expiresAt: String?
    let payloadPreview: AIPayloadPreview?
}

struct AIPayloadPreview: Decodable, Hashable {
    let title: String?
    let privacy: String?
    let queueCount: Int?
}

// MARK: - V4 Profile Store (P1.3)

@MainActor
@Observable
final class V4ProfileStore {
    private(set) var displayName: String = "Загрузка…"
    private(set) var username: String = ""
    private(set) var email: String = ""
    private(set) var avatarURL: URL?
    /// Instant local preview (survives dismiss before AsyncImage refetch)
    private(set) var localAvatarImage: UIImage?
    private(set) var isPremium: Bool = false
    private(set) var premiumUntil: Date?
    private(set) var isAdmin: Bool = false
    private(set) var selectedTheme: V4Theme = .electric
    private let authService: AuthService
    private let defaults = UserDefaults.standard

    private var avatarFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plink_avatar.jpg")
    }

    init(authService: AuthService) {
        self.authService = authService
        if let saved = defaults.string(forKey: "v4_theme") {
            selectedTheme = V4Theme(rawValue: saved) ?? .electric
        }
        loadSavedAvatar()
    }

    func load() async {
        // Prefer server user; keep local image if server URL missing
        do {
            let user = try await authService.fetchCurrentUser()
            applyUser(user)
            authService.updateCachedUser(user)
        } catch {
            if let user = await authService.currentUser() {
                applyUser(user)
            }
        }
        // Always try disk for instant paint
        if localAvatarImage == nil {
            loadLocalAvatarFile()
        }
    }

    /// Apply user fields to the profile tab (after save or notification).
    func applyUser(_ user: User) {
        displayName = (user.displayName?.isEmpty == false) ? user.displayName! : user.username
        username = user.username
        email = user.email
        isPremium = user.isPremium
        isAdmin = user.isAdmin
        // Authoritative premium from server (clears sticky local Plink+ on free devices)
        PremiumStatusManager.shared.syncFromServer(
            isPremium: user.isPremium,
            expiry: user.isPremium ? premiumUntil : nil
        )
        if let raw = user.avatarURL, !raw.isEmpty {
            avatarURL = Self.cacheBustedURL(from: raw)
            defaults.set(avatarURL?.absoluteString, forKey: "plink_user_avatar_url")
        }
        defaults.set(displayName, forKey: "plink_current_display_name")
        defaults.set(user.role ?? "USER", forKey: "plink_current_user_role")
        defaults.set(user.id, forKey: "plink_current_user_id")
        // Force friend-list / chat avatars to refetch after profile avatar change
        PlinkAvatarURL.bumpSessionBust()
    }

    func selectTheme(_ theme: V4Theme) {
        selectedTheme = theme
        defaults.set(theme.rawValue, forKey: "v4_theme")
    }

    /// Apply avatar (local image always; server URL when available).
    func applyAvatar(image: UIImage, serverURL: URL?) {
        self.localAvatarImage = image
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: avatarFileURL, options: .atomic)
        }
        var urlString: String?
        if let serverURL, serverURL.scheme == "http" || serverURL.scheme == "https" {
            let busted = Self.cacheBustedURL(from: serverURL.absoluteString) ?? serverURL
            self.avatarURL = busted
            urlString = busted.absoluteString
            defaults.set(urlString, forKey: "plink_user_avatar_url")
        }
        if let u = authService.currentUserValue {
            let updated = User(
                id: u.id,
                username: u.username,
                email: u.email,
                avatarURL: urlString ?? u.avatarURL,
                avatarData: u.avatarData,
                displayName: u.displayName,
                coverURL: u.coverURL,
                isOnline: u.isOnline,
                isPremium: u.isPremium,
                role: u.role,
                createdAt: u.createdAt
            )
            authService.updateCachedUser(updated)
        }
        NotificationCenter.default.post(name: ProfileViewModel.avatarChangedNotification, object: nil)
    }

    func loadSavedAvatar() {
        if let saved = defaults.string(forKey: "plink_user_avatar_url") {
            self.avatarURL = URL(string: saved)
        }
        loadLocalAvatarFile()
    }

    private func loadLocalAvatarFile() {
        if FileManager.default.fileExists(atPath: avatarFileURL.path),
           let data = try? Data(contentsOf: avatarFileURL),
           let img = UIImage(data: data) {
            localAvatarImage = img
        }
    }

    static func cacheBustedURL(from raw: String) -> URL? {
        guard var components = URLComponents(string: raw) else { return URL(string: raw) }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "t" || $0.name == "v" }
        items.append(URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970))))
        components.queryItems = items
        return components.url
    }
}
