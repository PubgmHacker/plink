import Foundation
import Combine

// MARK: - Friend Manager v3 (Real API + search/request/accept)
/// HTTP → /api/friends/*
@MainActor
final class FriendManager: ObservableObject {

    /// Shared instance so DM / list / profile all see the same friends + avatar versions.
    static let shared = FriendManager(api: APIClient.shared)

    @Published private(set) var friends: [Friend] = []
    @Published private(set) var incomingRequests: [FriendRequest] = []
    @Published private(set) var outgoingRequests: [FriendRequest] = []
    @Published private(set) var searchResults: [UserPreview] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastSuccessMessage: String?
    /// Bumps when any friend's avatarURL / version changes (DM headers observe this).
    @Published private(set) var avatarEpoch: Int = 0

    var onIncomingRequest: ((FriendRequest) -> Void)?
    var onFriendAdded: ((Friend) -> Void)?

    private let api: APIClient

    /// friendId → last activity we observed (DM message time) — max with server lastSeen.
    private var localActivityAt: [String: Date] = [:]

    init(api: APIClient) {
        self.api = api
        NotificationCenter.default.addObserver(
            forName: .plinkFriendActivity,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let id = note.object as? String else { return }
            let at = (note.userInfo?["at"] as? Date) ?? Date()
            Task { @MainActor in
                self?.noteActivity(friendId: id, at: at)
            }
        }
    }

    /// Record that a friend was active (sent a DM). Refreshes presence text immediately.
    func noteActivity(friendId: String, at date: Date = Date()) {
        let prev = localActivityAt[friendId]
        if prev == nil || date > (prev ?? .distantPast) {
            localActivityAt[friendId] = date
        }
        // Patch friend row in-place for instant UI
        if let idx = friends.firstIndex(where: { $0.id == friendId }) {
            let f = friends[idx]
            let last = max(f.lastSeenAt ?? .distantPast, date)
            let online = Date().timeIntervalSince(last) < 60
            // Never "revive" a tombstoned peer via local activity.
            if f.deleted {
                objectWillChange.send()
                return
            }
            friends[idx] = Friend(
                id: f.id,
                username: f.username,
                avatarURL: f.avatarURL,
                isOnline: online || f.isOnline,
                friendsSince: f.friendsSince,
                displayName: f.displayName,
                lastSeenAt: last,
                isPinned: f.isPinned,
                pinOrder: f.pinOrder,
                avatarVersion: f.avatarVersion,
                isDeleted: f.isDeleted
            )
            objectWillChange.send()
        }
    }

    private func applyLocalPresenceHints(_ friend: Friend) -> Friend {
        if friend.deleted { return friend }
        let hinted = localActivityAt[friend.id]
        let serverLast = friend.lastSeenAt
        let best: Date? = {
            switch (hinted, serverLast) {
            case let (h?, s?): return max(h, s)
            case let (h?, nil): return h
            case let (nil, s?): return s
            default: return nil
            }
        }()
        guard let best else { return friend }
        let age = Date().timeIntervalSince(best)
        let online = age < 60 || friend.isOnline
        return Friend(
            id: friend.id,
            username: friend.username,
            avatarURL: friend.avatarURL,
            isOnline: online,
            friendsSince: friend.friendsSince,
            displayName: friend.displayName,
            lastSeenAt: best,
            isPinned: friend.isPinned,
            pinOrder: friend.pinOrder,
            avatarVersion: friend.avatarVersion,
            isDeleted: friend.isDeleted
        )
    }

    // MARK: - Load All

    func loadAll() async {
        ensureToken()
        // Sequential on MainActor — avoid racing @Published arrays
        await loadFriends()
        await loadIncomingRequests()
        await loadOutgoingRequests()
        // Drop outgoing that are now friends (accepted on the other device)
        let friendIds = Set(friends.map(\.id))
        outgoingRequests.removeAll { friendIds.contains($0.toUser.id) }
    }

    private func ensureToken() {
        if api.authToken == nil {
            api.authToken = KeychainHelper.read(for: "rave_auth_token")
                ?? AuthService.shared.authToken
        }
    }

    func loadFriends() async {
        ensureToken()
        guard api.authToken != nil else { return }
        do {
            let dtos: [FriendDTO] = try await api.request("friends")
            var next = dtos.map { $0.toFriend() }
            // Apply local activity hints (DM received) so last-seen isn't stuck 2h
            next = next.map { applyLocalPresenceHints($0) }
            // Realtime avatar: when server ?v= / avatarVersion changes, drop cache
            // for that user so list + open DM show the new photo immediately.
            let prevAvatars = Dictionary(uniqueKeysWithValues: friends.map { ($0.id, $0.avatarURL ?? "") })
            let prevVersions = Dictionary(uniqueKeysWithValues: friends.map {
                ($0.id, $0.avatarVersion.map(String.init) ?? "")
            })
            var anyAvatarChange = false
            for f in next {
                let verStr = f.avatarVersion.map(String.init)
                let changed = PlinkAvatarURL.noteAvatar(
                    userId: f.id,
                    storedURL: f.avatarURL,
                    version: verStr
                )
                let urlChanged = (prevAvatars[f.id] ?? "") != (f.avatarURL ?? "")
                let verChanged = (prevVersions[f.id] ?? "") != (verStr ?? "")
                // Only treat as change after we already had a previous value for this friend
                let hadPrev = prevAvatars[f.id] != nil
                if changed || (hadPrev && (urlChanged || verChanged)) {
                    anyAvatarChange = true
                    if urlChanged || verChanged {
                        PlinkAvatarImageCache.shared.removeAll(matchingUserId: f.id)
                        NotificationCenter.default.post(
                            name: .plinkUserAvatarDidChange,
                            object: f.id,
                            userInfo: ["url": f.avatarURL as Any]
                        )
                    }
                }
            }
            friends = next
            FriendPinStore.shared.mergeFromServer(friends)
            if anyAvatarChange {
                avatarEpoch &+= 1
                // Session bust already posted inside noteAvatar when version flips;
                // ensure observers refresh even if only URL string changed.
                NotificationCenter.default.post(name: .plinkAvatarsDidChange, object: PlinkAvatarURL.sessionBust)
            }
            Logger.api.info("Friends loaded")
        } catch {
            Logger.api.warn("Friends load failed")
        }
    }

    /// Pin / unpin friend (Telegram). Updates local store immediately, syncs server.
    @discardableResult
    func setPinned(friendId: String, pinned: Bool) async -> Bool {
        if pinned {
            guard FriendPinStore.shared.pin(friendId) else {
                errorMessage = "Максимум 10 закреплений"
                return false
            }
        } else {
            FriendPinStore.shared.unpin(friendId)
        }
        ensureToken()
        struct Body: Encodable { let pin: Bool }
        struct Resp: Decodable { let success: Bool?; let isPinned: Bool? }
        do {
            let _: Resp = try await api.request(
                "friends/\(friendId)/pin",
                method: .post,
                body: Body(pin: pinned)
            )
            return true
        } catch {
            // Local pin already applied — list still works offline
            Logger.api.warn("Friend pin sync failed")
            return true
        }
    }

    func loadIncomingRequests() async {
        guard api.authToken != nil else { return }
        do {
            let dtos: [IncomingRequestDTO] = try await api.request("friends/requests/incoming")
            incomingRequests = dtos.map { $0.toFriendRequest() }
        } catch {
            Logger.api.warn("Incoming friend requests load failed")
        }
    }

    func loadOutgoingRequests() async {
        guard api.authToken != nil else { return }
        do {
            let dtos: [OutgoingRequestDTO] = try await api.request("friends/requests/outgoing")
            outgoingRequests = dtos.map { $0.toFriendRequest() }
        } catch {
            // Older backends without outgoing endpoint — keep local list
            Logger.api.warn("Outgoing friend requests load failed")
        }
    }

    /// Alias used by older call sites
    func loadRequests() async {
        await loadIncomingRequests()
        await loadOutgoingRequests()
    }

    // MARK: - Send Request

    @discardableResult
    func sendRequest(to userId: String, username: String) async -> Bool {
        struct Body: Encodable { let friendId: String }
        do {
            let resp: SendRequestResponse = try await api.request(
                "friends/request",
                method: .post,
                body: Body(friendId: userId)
            )
            if resp.autoAccepted == true {
                lastSuccessMessage = "\(username) теперь у вас в друзьях"
                await loadAll()
                return true
            }
            lastSuccessMessage = "Заявка отправлена"
            // Optimistic outgoing
            let preview = UserPreview(id: userId, username: username, avatarURL: nil, isOnline: false)
            let me = UserPreview(id: "me", username: "me", avatarURL: nil, isOnline: true)
            let req = FriendRequest(
                id: resp.id ?? UUID().uuidString,
                fromUser: me,
                toUser: preview,
                status: .pending,
                createdAt: Date()
            )
            if !outgoingRequests.contains(where: { $0.toUser.id == userId }) {
                outgoingRequests.insert(req, at: 0)
            }
            await loadOutgoingRequests()
            return true
        } catch {
            errorMessage = friendlyError(error)
            Logger.api.warn("Friend request send failed")
            return false
        }
    }

    /// Search by @username and send in one step
    @discardableResult
    func sendRequestByUsername(_ username: String) async -> Bool {
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        guard !clean.isEmpty else {
            errorMessage = "Введите @username"
            return false
        }
        struct Body: Encodable { let username: String }
        do {
            let resp: SendRequestResponse = try await api.request(
                "friends/request",
                method: .post,
                body: Body(username: clean)
            )
            if resp.autoAccepted == true {
                lastSuccessMessage = "@\(clean) теперь у вас в друзьях"
            } else {
                lastSuccessMessage = "Заявка отправлена"
            }
            await loadAll()
            return true
        } catch {
            errorMessage = friendlyError(error)
            return false
        }
    }

    // MARK: - Accept / Decline

    func acceptRequest(_ request: FriendRequest) async {
        struct Body: Encodable { let status: String }
        do {
            let _: SuccessDTO = try await api.request(
                "friends/requests/\(request.id)",
                method: .put,
                body: Body(status: "accepted")
            )
            incomingRequests.removeAll { $0.id == request.id }
            let newFriend = Friend(
                id: request.fromUser.id,
                username: request.fromUser.username,
                avatarURL: request.fromUser.avatarURL,
                isOnline: request.fromUser.isOnline,
                friendsSince: Date(),
                displayName: nil,
                lastSeenAt: nil,
                isDeleted: false
            )
            if !friends.contains(where: { $0.id == newFriend.id }) {
                friends.append(newFriend)
            }
            onFriendAdded?(newFriend)
            lastSuccessMessage = "\(request.fromUser.username) добавлен в друзья"
            await loadFriends()
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    func declineRequest(_ request: FriendRequest) async {
        struct Body: Encodable { let status: String }
        do {
            let _: SuccessDTO = try await api.request(
                "friends/requests/\(request.id)",
                method: .put,
                body: Body(status: "rejected")
            )
            incomingRequests.removeAll { $0.id == request.id }
            lastSuccessMessage = "Заявка отклонена"
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    func removeFriend(_ friend: Friend) async {
        do {
            try await api.requestNoBody("friends/\(friend.id)", method: .delete)
            friends.removeAll { $0.id == friend.id }
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Search

    func searchUsers(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        guard api.authToken != nil else {
            searchResults = []
            return
        }
        let cleanedQuery = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        isLoading = true
        defer { isLoading = false }
        do {
            let dtos: [UserPreviewDTO] = try await api.request("friends/search", query: ["q": cleanedQuery])
            searchResults = dtos.map { $0.toUserPreview() }
        } catch {
            Logger.api.warn("Friend search failed")
            searchResults = []
            errorMessage = friendlyError(error)
        }
    }

    func isFriend(_ userId: String) -> Bool {
        friends.contains { $0.id == userId }
    }

    func hasOutgoingRequest(to userId: String) -> Bool {
        outgoingRequests.contains { $0.toUser.id == userId }
    }

    func generateInviteLink(userId: String) -> URL {
        URL(string: "\(ShareManager.shareBaseURL)/u/\(userId)")!
    }

    private func friendlyError(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .conflict(let message):
                if message.lowercased().contains("already") { return "Уже друзья или заявка отправлена" }
                return message
            case .notFound:
                return "Пользователь не найден"
            case .serverError(_, let message):
                return message
            case .unauthorized:
                return "Войдите в аккаунт"
            default:
                return error.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

// MARK: - DTOs

private struct FriendDTO: Decodable {
    let id: String
    let username: String
    let avatarURL: String?
    let isOnline: Bool?
    let friendsSince: Date?
    let displayName: String?
    let lastSeenAt: Date?
    let isPinned: Bool?
    let pinOrder: Int?
    let avatarVersion: Int64?
    let isDeleted: Bool?

    func toFriend() -> Friend {
        let deleted = isDeleted == true || username.hasPrefix("deleted_")
        return Friend(
            id: id,
            username: username,
            avatarURL: deleted ? nil : avatarURL,
            isOnline: deleted ? false : (isOnline ?? false),
            friendsSince: friendsSince ?? Date(),
            displayName: deleted ? "Удалённый аккаунт" : displayName,
            lastSeenAt: deleted ? nil : lastSeenAt,
            isPinned: isPinned,
            pinOrder: pinOrder,
            avatarVersion: avatarVersion,
            isDeleted: deleted
        )
    }
}

private struct IncomingRequestDTO: Decodable {
    let id: String
    let fromUser: UserPreviewDTO
    let status: String
    let createdAt: Date?

    func toFriendRequest() -> FriendRequest {
        FriendRequest(
            id: id,
            fromUser: fromUser.toUserPreview(),
            toUser: UserPreview(id: "me", username: "me", avatarURL: nil, isOnline: true),
            status: .pending,
            createdAt: createdAt ?? Date()
        )
    }
}

private struct OutgoingRequestDTO: Decodable {
    let id: String
    let toUser: UserPreviewDTO
    let status: String
    let createdAt: Date?

    func toFriendRequest() -> FriendRequest {
        FriendRequest(
            id: id,
            fromUser: UserPreview(id: "me", username: "me", avatarURL: nil, isOnline: true),
            toUser: toUser.toUserPreview(),
            status: .pending,
            createdAt: createdAt ?? Date()
        )
    }
}

private struct UserPreviewDTO: Decodable {
    let id: String
    let username: String
    let avatarURL: String?
    let isOnline: Bool?
    let displayName: String?

    func toUserPreview() -> UserPreview {
        UserPreview(id: id, username: username, avatarURL: avatarURL, isOnline: isOnline ?? false)
    }
}

private struct SendRequestResponse: Decodable {
    let success: Bool?
    let id: String?
    let status: String?
    let friendId: String?
    let autoAccepted: Bool?
}

private struct SuccessDTO: Decodable {
    let success: Bool?
}
