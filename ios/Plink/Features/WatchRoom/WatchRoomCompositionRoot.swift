// Plink/Features/WatchRoom/WatchRoomCompositionRoot.swift
// Сборка экрана комнаты: единственное место, где создаётся WatchRoomModel.
//
// Владелец модели — WatchRoomContainer: он держит её в @State и зовёт
// makeModelForRoom один раз за сессию комнаты.

import SwiftUI

public enum WatchRoomCompositionRoot {
    /// Модель должна создаваться ОДИН раз и жить в
    /// @State владельца (WatchRoomContainer) — makeScreenForRoom из body
    /// пересоздавал WatchRoomModel на каждом пересчёте: комната сбрасывалась,
    /// старый WebSocket утекал.
    @MainActor
    static func makeModelForRoom(
        room: Room,
        userId: String,
        username: String,
        apiBaseURL: URL,
        wsBaseURL: URL,
        authToken: String
    ) -> WatchRoomModel {
        makeV2Model(
            roomId: room.id,
            userId: userId,
            username: username,
            mediaSource: mediaSourceFromRoom(room),
            mediaId: mediaIdFromRoom(room),
            roomCode: room.code,
            apiBaseURL: apiBaseURL,
            wsBaseURL: wsBaseURL,
            authToken: authToken,
            hostId: room.hostID
        )
    }

    /// Public so WatchRoomModel can recover media after a stripped create/join payload.
    static func mediaSource(from room: Room) -> PlaybackSource? {
        mediaSourceFromRoom(room)
    }

    /// Derive PlaybackSource from room.mediaItem
    private static func mediaSourceFromRoom(_ room: Room) -> PlaybackSource? {
        guard let mediaItem = room.mediaItem else { return nil }

        // Prefer explicit / extracted YouTube video id → official IFrame player
        if let ytId = resolveYouTubeVideoId(from: mediaItem) {
            return .youtube(ytId)
        }

        // Rutube embed / watch URL
        if let rutubeId = extractRutubeVideoId(from: mediaItem.streamURL) {
            return .rutube(rutubeId)
        }

        if let vkId = extractVKVideoId(from: mediaItem.streamURL) {
            return .vk(vkId)
        }

        // Direct stream URL → native AVPlayer; other HTTPS pages use the
        // generic embedded WKWebView controller so premium/cinema links still
        // get a player surface instead of "Нет видео".
        let urlString = mediaItem.streamURL
        if let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" {
            if urlString.contains(".m3u8") {
                return .hls(url, headers: [:])
            }
            if urlString.contains(".mp4") || urlString.hasSuffix(".mov") {
                return .mp4(url, headers: [:])
            }
            return .embed(url)
        }
        return nil
    }

    /// Derive a PlaybackSource from a raw stream URL — used when the host
    /// promotes a queued item via «включить сейчас» (RoomQueueWire.Item has a
    /// streamURL string, not a Room). Same provider order as
    /// mediaSourceFromRoom so a queued item plays through the right controller.
    static func mediaSource(fromStreamURL urlString: String, videoIdHint: String? = nil) -> PlaybackSource? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hint = videoIdHint?.trimmingCharacters(in: .whitespacesAndNewlines),
           isValidYouTubeVideoId(hint) {
            return .youtube(hint)
        }
        if let ytId = extractYouTubeVideoId(from: trimmed) { return .youtube(ytId) }
        if let rutubeId = extractRutubeVideoId(from: trimmed) { return .rutube(rutubeId) }
        if let vkId = extractVKVideoId(from: trimmed) { return .vk(vkId) }
        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" {
            if trimmed.contains(".m3u8") { return .hls(url, headers: [:]) }
            if trimmed.contains(".mp4") || trimmed.hasSuffix(".mov") { return .mp4(url, headers: [:]) }
            return .embed(url)
        }
        return nil
    }

    /// Resolve a valid 11-char YouTube id from mediaItem fields.
    private static func resolveYouTubeVideoId(from mediaItem: MediaItem) -> String? {
        // 1) Explicit videoId field
        if let raw = mediaItem.videoId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if isValidYouTubeVideoId(raw) { return raw }
            if let fromField = extractYouTubeVideoId(from: raw) { return fromField }
        }
        // 2) Any youtu URL in streamURL / id — even if source was lost as "url"
        if let fromURL = extractYouTubeVideoId(from: mediaItem.streamURL) { return fromURL }
        let bare = mediaItem.streamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidYouTubeVideoId(bare) { return bare }
        let bareId = mediaItem.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidYouTubeVideoId(bareId) { return bareId }
        if let fromId = extractYouTubeVideoId(from: mediaItem.id) { return fromId }
        // 3) Thumbnail often embeds the id: …/vi/VIDEO_ID/…
        if let thumb = mediaItem.thumbnailURL, let fromThumb = extractYouTubeVideoId(from: thumb) {
            return fromThumb
        }
        return nil
    }

    private static func isValidYouTubeVideoId(_ id: String) -> Bool {
        guard id.count == 11 else { return false }
        return id.allSatisfy { c in
            c.isLetter || c.isNumber || c == "_" || c == "-"
        }
    }

    /// Extract 11-char YouTube video ID from various URL formats.
    /// - https://youtu.be/VIDEO_ID
    /// - https://www.youtube.com/watch?v=VIDEO_ID
    /// - https://www.youtube.com/embed/VIDEO_ID
    /// - https://youtube.com/shorts/VIDEO_ID
    private static func extractYouTubeVideoId(from url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidYouTubeVideoId(trimmed) { return trimmed }

        let lower = trimmed.lowercased()
        guard lower.contains("youtube.com") || lower.contains("youtu.be") else { return nil }

        // youtu.be/VIDEO_ID
        if lower.contains("youtu.be/") {
            let parts = trimmed.split(separator: "/")
            if let last = parts.last {
                let id = String(last).split(separator: "?").first.map(String.init) ?? String(last)
                if isValidYouTubeVideoId(id) { return id }
            }
        }

        // youtube.com/watch?v=VIDEO_ID (also handles mobile / music hosts)
        if let components = URLComponents(string: trimmed) {
            if let vParam = components.queryItems?.first(where: { $0.name == "v" })?.value {
                if isValidYouTubeVideoId(vParam) { return vParam }
            }
        }

        // youtube.com/embed/VIDEO_ID or youtube.com/shorts/VIDEO_ID or /live/VIDEO_ID
        for marker in ["/embed/", "/shorts/", "/live/", "/v/"] {
            if let range = lower.range(of: marker) {
                let after = trimmed[range.upperBound...]
                let id = String(after.split(separator: "?").first ?? Substring(after))
                    .split(separator: "/").first
                    .map(String.init) ?? ""
                if isValidYouTubeVideoId(id) { return id }
            }
        }

        return nil
    }

    /// VK: https://vk.com/video_ext.php?... , /video-123_456 или /clip-123_456.
    ///
    /// Матч строго по хосту (PlinkHost). Раньше проверка была `lower.contains("vk.com")`
    /// по ВСЕЙ строке URL — то есть `https://evil.ru/watch?ref=vk.com` проходил
    /// как видео ВК, и функция возвращала этот же URL (см. fallback `return url`),
    /// который уходил в `.vk(...)` и грузился в плеер комнаты у всех участников.
    private static func extractVKVideoId(from url: String) -> String? {
        // Разбор один на всё приложение: `RoomCreateMedia` тянет `oid_id`
        // строго из пути. Прежний вариант резал строку по подстроке «video»
        // и в худшем случае возвращал сам URL — плеер получал не тот id.
        RoomCreateMedia.extractVKVideoId(from: url)
    }

    /// Rutube: https://rutube.ru/video/<32-hex>/ or /play/embed/<id>/
    ///
    /// Тот же строгий матч по хосту, что и в VK: подстрока в query или пути
    /// больше не считается признаком сервиса.
    private static func extractRutubeVideoId(from url: String) -> String? {
        guard let parsed = URL(string: url),
              PlinkHost.matches(parsed.host, anyOf: PlinkHost.rutubeDomains) else { return nil }
        let parts = url.split(separator: "/").map(String.init)
        for (idx, part) in parts.enumerated() {
            let clean = part.split(separator: "?").first.map(String.init) ?? part
            // 32-char hex is the classic Rutube video id
            if clean.count == 32, clean.allSatisfy({ $0.isHexDigit }) {
                return clean
            }
            if part == "embed" || part == "video", idx + 1 < parts.count {
                let next = parts[idx + 1].split(separator: "?").first.map(String.init) ?? parts[idx + 1]
                if next.count >= 8 { return next }
            }
        }
        return nil
    }

    /// Derive mediaId from room.mediaItem
    private static func mediaIdFromRoom(_ room: Room) -> String? {
        guard let mediaItem = room.mediaItem else { return nil }
        return mediaItem.videoId ?? mediaItem.id
    }

    /// Creates the v2 WatchRoomModel with all dependencies wired.
    @MainActor
    private static func makeV2Model(
        roomId: String,
        userId: String,
        username: String,
        mediaSource: PlaybackSource?,
        mediaId: String?,
        roomCode: String?,
        apiBaseURL: URL,
        wsBaseURL: URL,
        authToken: String,
        hostId: String? = nil
    ) -> WatchRoomModel {
        let catchupClient = RESTChatCatchupClient(
            baseURL: apiBaseURL,
            authToken: authToken
        )
        // Тот же auth-токен — рекап ходит на /api/ai/room-recap.
        let recapClient = RESTRoomRecapClient(
            baseURL: apiBaseURL,
            authToken: authToken
        )

        let ticketProvider: (String) async throws -> RealtimeTicket = { roomId in
            try await fetchTicket(
                apiBaseURL: apiBaseURL,
                authToken: authToken,
                roomId: roomId
            )
        }

        return WatchRoomModel(
            roomId: roomId,
            currentUserId: userId,
            currentUsername: username,
            baseEndpoint: wsBaseURL,
            ticketProvider: ticketProvider,
            mediaSource: mediaSource,
            mediaId: mediaId,
            roomCode: roomCode,
            chatCatchupClient: catchupClient,
            roomRecapClient: recapClient,
            roomHostId: hostId
        )
    }

    /// Fetches a realtime ticket from POST /api/realtime/ticket
    private static func fetchTicket(
        apiBaseURL: URL,
        authToken: String,
        roomId: String
    ) async throws -> RealtimeTicket {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/realtime/ticket"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["roomId": roomId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(TicketResponse.self, from: data)
        return RealtimeTicket(
            jwt: decoded.ticket,
            roomId: decoded.roomId ?? roomId,
            expiresInSec: decoded.expiresInSec
        )
    }
}

// MARK: - Feature flags (remote config with cached fallback)

public enum FeatureFlags {
    private static let cacheKey = "plink.feature_flags_cache"
    private static let cacheTTL: TimeInterval = 300  // 5 minutes

    /// P1 audit: kill-switch for native YouTube stream extraction (App Store
    /// review safety). Remote flag key: "youtube_native_extraction".
    /// Defaults to TRUE; flip the remote flag (or the DEBUG UserDefaults
    /// override) to force the embedded-player path without an app update.
    public static var youtubeNativeExtraction: Bool {
        if UserDefaults.standard.object(forKey: "plink.yt_native_extraction_debug") != nil {
            return UserDefaults.standard.bool(forKey: "plink.yt_native_extraction_debug")
        }
        return cachedRemoteFlags["youtube_native_extraction"] ?? true
    }

    /// Cached remote flags fetched from backend
    private static var cachedRemoteFlags: [String: Bool] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode(RemoteFlagCache.self, from: data),
              Date().timeIntervalSince(cache.fetchedAt) < cacheTTL else {
            return [:]
        }
        return cache.flags
    }

    /// Забирает удалённые флаги с бэкенда — вызывается при запуске.
    public static func fetchRemoteFlags(apiBaseURL: URL, authToken: String) async {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/feature-flags"))
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode([RemoteFlagDTO].self, from: data)
            var flags: [String: Bool] = [:]
            for flag in decoded {
                flags[flag.key] = (flag.value.lowercased() == "true")
            }
            let cache = RemoteFlagCache(flags: flags, fetchedAt: Date())
            if let cacheData = try? JSONEncoder().encode(cache) {
                UserDefaults.standard.set(cacheData, forKey: cacheKey)
            }
        } catch {
            // Network error — keep using cached/UserDefaults
        }
    }
}

private struct RemoteFlagCache: Codable {
    let flags: [String: Bool]
    let fetchedAt: Date
}

private struct RemoteFlagDTO: Decodable {
    let key: String
    let value: String
}

// MARK: - REST chat catch-up client

public final class RESTChatCatchupClient: ChatCatchupClient, @unchecked Sendable {
    private let baseURL: URL
    // Use AuthTokenProvider instead of fixed String
    private let tokenProvider: AuthTokenProvider?

    public init(baseURL: URL, authToken: String) {
        self.baseURL = baseURL
        self.tokenProvider = nil  // Legacy mode — fixed token
        self._fixedToken = authToken
    }

    // Init with token provider for refresh support
    public init(baseURL: URL, tokenProvider: AuthTokenProvider) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self._fixedToken = nil
    }

    private var _fixedToken: String?

    // currentToken must hop to MainActor since AuthTokenProvider is @MainActor
    private func currentToken() async -> String? {
        if let provider = tokenProvider {
            return await MainActor.run { provider.currentToken }
        }
        return _fixedToken
    }

    // refresh-on-401 helper
    private func refreshToken() async -> String? {
        if let provider = tokenProvider {
            return await provider.refreshToken()
        }
        return _fixedToken
    }

    // Make request with auth, retry on 401
    private func makeAuthenticatedRequest(url: URL) async throws -> (Data, HTTPURLResponse) {
        guard let token = await currentToken() else {
            throw URLError(.userAuthenticationRequired)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // On 401, refresh token and retry once
        if http.statusCode == 401, let newToken = await refreshToken() {
            request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            (data, response) = try await URLSession.shared.data(for: request)
            guard let http2 = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            if http2.statusCode == 401 {
                throw URLError(.userAuthenticationRequired)
            }
            if http2.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            return (data, http2)
        }

        if http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    public func fetchMessages(roomId: String, after: String?) async throws -> ChatCatchupResponse {
        guard let baseURL = URL(string: "\(PlinkConfig.baseURLString)/api/rooms/\(roomId)/messages"),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        var items = [URLQueryItem(name: "limit", value: "100")]
        if let after = after {
            items.append(URLQueryItem(name: "cursor", value: after))
        }
        components.queryItems = items

        guard let url = components.url else { throw APIError.invalidResponse }
        let (data, _) = try await makeAuthenticatedRequest(url: url)
        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        return ChatCatchupResponse(
            messages: decoded.messages.map { m in
                ChatCatchupMessage(
                    messageId: m.messageId,
                    clientMessageId: m.clientMessageId,
                    senderId: m.senderId,
                    senderName: m.senderName,
                    text: m.text,
                    createdAtMs: m.createdAtMs,
                    mediaType: m.mediaType,
                    hasMedia: m.hasMedia ?? false
                )
            },
            hasMore: decoded.hasMore,
            nextCursor: decoded.nextCursor
        )
    }

    public func fetchParticipants(roomId: String) async throws -> [ParticipantSnapshot] {
        let url = baseURL.appendingPathComponent("api/rooms/\(roomId)/participants")
        let (data, _) = try await makeAuthenticatedRequest(url: url)
        let decoded = try JSONDecoder().decode(ParticipantsResponse.self, from: data)
        var result = decoded.participants.map { p in
            ParticipantSnapshot(userId: p.userId, username: p.username)
        }
        // Backend returns host separately with online status.
        // Merge host into participants list if they're online and not already
        // in the list — otherwise the host (who has no RoomParticipant row)
        // never appears in the presence bar.
        if let host = decoded.host, host.online {
            if !result.contains(where: { $0.userId == host.userId }) {
                result.append(ParticipantSnapshot(userId: host.userId, username: host.username))
            }
        }
        return result
    }
}

// MARK: - REST room recap client

public final class RESTRoomRecapClient: RoomRecapClient, @unchecked Sendable {
    private let baseURL: URL
    private let authToken: String

    public init(baseURL: URL, authToken: String) {
        self.baseURL = baseURL
        self.authToken = authToken
    }

    public func fetchRecap(roomId: String, sinceMs: Int64) async throws -> RoomRecapResponse {
        let url = baseURL.appendingPathComponent("api/ai/room-recap")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "roomId": roomId,
            "sinceMs": sinceMs,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(RoomRecapResponse.self, from: data)
    }
}

// MARK: - Decodable response models

private struct TicketResponse: Decodable {
    let ticket: String
    let roomId: String?
    let expiresInSec: Int
    let protocol_: [String]?

    enum CodingKeys: String, CodingKey {
        case ticket
        case roomId
        case expiresInSec
        case protocol_ = "protocol"
    }
}

private struct MessagesResponse: Decodable {
    let messages: [MessageDTO]
    let hasMore: Bool
    let nextCursor: String?  // Opaque server cursor
}

// Participant snapshot response
private struct ParticipantsResponse: Decodable {
    let participants: [ParticipantDTO]
    // Host returned separately with online status
    let host: HostDTO?
}

private struct HostDTO: Decodable {
    let userId: String
    let username: String
    let online: Bool
}

private struct ParticipantDTO: Decodable {
    let userId: String
    let username: String
}

private struct MessageDTO: Decodable {
    let messageId: String
    let clientMessageId: String?
    let senderId: String
    let senderName: String
    let text: String
    let createdAtMs: Int64
    let mediaType: String?
    let hasMedia: Bool?
}
