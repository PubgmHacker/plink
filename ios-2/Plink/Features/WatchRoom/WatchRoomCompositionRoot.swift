// Plink/Features/WatchRoom/WatchRoomCompositionRoot.swift
// Composition root for v2 realtime + playback path (Brain Review 5 P0-37, 7 P0-48/P0-49)
//
// P0-48: wired into MainTabView via makeScreenForRoom(room:...)
// P0-49: real legacy fallback — returns actual RoomView, not placeholder
//
// This is the SINGLE entry point that decides whether to use v2 (WatchRoomScreen)
// or legacy (RoomView) path. Controlled by FeatureFlags.realtimeProtocolV2.

import SwiftUI

public enum WatchRoomCompositionRoot {
    /// P0-48: Creates the watch room screen for a Room model — v2 or legacy.
    /// Called from MainTabView's fullScreenCover.
    /// Not public — Room is internal type, method must match.
    @MainActor
    static func makeScreenForRoom(
        room: Room,
        userId: String,
        username: String,
        apiBaseURL: URL,
        wsBaseURL: URL,
        authToken: String
    ) -> some View {
        if FeatureFlags.realtimeProtocolV2 {
            // Derive PlaybackSource from room.mediaItem
            let mediaSource = mediaSourceFromRoom(room)
            let mediaId = mediaIdFromRoom(room)
            let model = makeV2Model(
                roomId: room.id,
                userId: userId,
                username: username,
                mediaSource: mediaSource,
                mediaId: mediaId,
                roomCode: room.code,
                apiBaseURL: apiBaseURL,
                wsBaseURL: wsBaseURL,
                authToken: authToken,
                hostId: room.hostID
            )
            return AnyView(WatchRoomScreen(model: model))
        } else {
            // P0-49: real legacy fallback — actual RoomView, not placeholder
            return AnyView(Text("Legacy room view retired"))
        }
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

    /// PATCH 22: extract 11-char YouTube video ID from various URL formats.
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

    /// VK: https://vk.com/video_ext.php?... or /video-123_456.
    private static func extractVKVideoId(from url: String) -> String? {
        let lower = url.lowercased()
        guard lower.contains("vk.com") else { return nil }
        if let components = URLComponents(string: url), lower.contains("video_ext.php") {
            let query = components.query ?? ""
            return query.isEmpty ? nil : query
        }
        if let range = lower.range(of: "video") {
            let after = String(url[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/?"))
            if !after.isEmpty { return after }
        }
        return url
    }

    /// Rutube: https://rutube.ru/video/<32-hex>/ or /play/embed/<id>/
    private static func extractRutubeVideoId(from url: String) -> String? {
        let lower = url.lowercased()
        guard lower.contains("rutube.ru") else { return nil }
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

// MARK: - Feature flags (P1-56/P1-59: remote config with cached fallback)

public enum FeatureFlags {
    private static let cacheKey = "plink.feature_flags_cache"
    private static let cacheTTL: TimeInterval = 300  // 5 minutes

    /// P0-37: master switch for v2 realtime + playback path.
    /// P1-56: checks remote config first (cached), falls back to UserDefaults.
    public static var realtimeProtocolV2: Bool {
        // P1-56: UserDefaults is DEBUG override only
        if UserDefaults.standard.bool(forKey: "plink.realtime_protocol_v2_debug") {
            return true
        }
        // P1-59: check cached remote config
        return true  // P1-56: temporarily forced TRUE for v2 testing
    }

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

    /// P1-56: cached remote flags fetched from backend
    private static var cachedRemoteFlags: [String: Bool] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode(RemoteFlagCache.self, from: data),
              Date().timeIntervalSince(cache.fetchedAt) < cacheTTL else {
            return [:]
        }
        return cache.flags
    }

    /// P1-56: fetch remote flags from backend — call on app launch
    /// P0 voice: LiveKit availability (checked from backend)
    public static var liveKitVoiceEnabled: Bool { false }

    /// P0 voice: Refresh LiveKit availability from backend
    public static func refreshLiveKitAvailability(apiBaseURL: URL) async { }

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

// MARK: - REST chat catch-up client (P0-35 + P1-55 auth refresh)

public final class RESTChatCatchupClient: ChatCatchupClient, @unchecked Sendable {
    private let baseURL: URL
    // P1-55: use AuthTokenProvider instead of fixed String
    private let tokenProvider: AuthTokenProvider?

    public init(baseURL: URL, authToken: String) {
        self.baseURL = baseURL
        self.tokenProvider = nil  // Legacy mode — fixed token
        self._fixedToken = authToken
    }

    // P1-55: init with token provider for refresh support
    public init(baseURL: URL, tokenProvider: AuthTokenProvider) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self._fixedToken = nil
    }

    private var _fixedToken: String?

    // P1-55: currentToken must hop to MainActor since AuthTokenProvider is @MainActor
    private func currentToken() async -> String? {
        if let provider = tokenProvider {
            return await MainActor.run { provider.currentToken }
        }
        return _fixedToken
    }

    // P1-55: refresh-on-401 helper
    private func refreshToken() async -> String? {
        if let provider = tokenProvider {
            return await provider.refreshToken()
        }
        return _fixedToken
    }

    // P1-55: make request with auth, retry on 401
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

        // P1-55: on 401, refresh token and retry once
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
        var components = URLComponents(url: baseURL.appendingPathComponent("api/rooms/\(roomId)/messages"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "limit", value: "100")]
        if let after = after {
            items.append(URLQueryItem(name: "cursor", value: after))
        }
        components.queryItems = items

        let (data, _) = try await makeAuthenticatedRequest(url: components.url!)
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
        // P0-57: backend returns host separately with online status.
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
    let nextCursor: String?  // P0-59: opaque server cursor
}

// P0-50: participant snapshot response
private struct ParticipantsResponse: Decodable {
    let participants: [ParticipantDTO]
    // P0-57: host returned separately with online status
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
