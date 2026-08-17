import Foundation

/// Сборка MediaItem при создании комнаты. Вынесено из UI, чтобы каждый
/// VideoService имел один проверяемый путь: YouTube/VK/Rutube — прямой синх,
/// кинотеатры — страница хоста (режим «ваш экран»), custom — файл или URL.
enum RoomCreateMedia {
    static func mediaItem(
        service: VideoService,
        video: DetectedVideo,
        roomName: String
    ) -> MediaItem {
        let title = roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (video.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? service.rawValue)
            : roomName
        let raw = video.embedURL.isEmpty ? video.originalURL : video.embedURL

        switch service {
        case .youtube:
            let vid = extractYouTubeID(from: video.originalURL)
                ?? extractYouTubeID(from: video.embedURL)
            let stream = vid.map { "https://www.youtube.com/watch?v=\($0)" } ?? raw
            return MediaItem(
                id: vid ?? UUID().uuidString,
                title: title,
                artist: nil,
                thumbnailURL: vid.map { "https://img.youtube.com/vi/\($0)/hqdefault.jpg" },
                streamURL: stream,
                duration: nil,
                mediaType: .video,
                source: .youtube,
                videoId: vid
            )

        case .vk:
            return MediaItem(
                id: UUID().uuidString,
                title: title,
                artist: nil,
                thumbnailURL: nil,
                streamURL: video.originalURL.isEmpty ? raw : video.originalURL,
                duration: nil,
                mediaType: .video,
                source: .url,
                videoId: extractVKVideoId(from: video.originalURL) ?? extractVKVideoId(from: raw)
            )

        case .rutube:
            let rid = extractRutubeVideoId(from: video.originalURL)
                ?? extractRutubeVideoId(from: video.embedURL)
            let stream = rid.map { "https://rutube.ru/play/embed/\($0)" } ?? raw
            return MediaItem(
                id: rid ?? UUID().uuidString,
                title: title,
                artist: nil,
                thumbnailURL: nil,
                streamURL: stream,
                duration: nil,
                mediaType: .video,
                source: .url,
                videoId: rid
            )

        case .customURL:
            let lower = raw.lowercased()
            let isFile = lower.contains(".m3u8") || lower.contains(".mp4") || lower.contains(".mov")
            return MediaItem(
                id: UUID().uuidString,
                title: title,
                artist: nil,
                thumbnailURL: nil,
                streamURL: raw,
                duration: nil,
                mediaType: .video,
                source: .url,
                videoId: isFile ? nil : raw
            )

        case .browser, .netflix, .disney, .kinopoisk, .ivi, .okko, .wink, .start, .premier, .smotrim, .kion:
            return MediaItem(
                id: UUID().uuidString,
                title: title,
                artist: nil,
                thumbnailURL: nil,
                streamURL: video.originalURL.isEmpty ? raw : video.originalURL,
                duration: nil,
                mediaType: .video,
                source: .url,
                videoId: nil
            )
        }
    }

    static func extractYouTubeID(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isYouTubeId(trimmed) { return trimmed }
        guard let url = URL(string: trimmed),
              PlinkHost.matches(url.host, anyOf: PlinkHost.youtubeDomains) else { return nil }
        if PlinkHost.matches(url.host, domain: "youtu.be") {
            let id = url.path.split(separator: "/").first.map(String.init) ?? url.lastPathComponent
            return isYouTubeId(id) ? id : nil
        }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let v = items.first(where: { $0.name == "v" })?.value, isYouTubeId(v) {
            return v
        }
        let lower = url.path.lowercased()
        for marker in ["/embed/", "/shorts/", "/live/", "/v/"] {
            if let range = lower.range(of: marker) {
                let after = String(url.path[range.upperBound...])
                let id = after.split(separator: "/").first.map(String.init) ?? ""
                if isYouTubeId(id) { return id }
            }
        }
        return nil
    }

    static func extractVKVideoId(from raw: String) -> String? {
        guard let url = URL(string: raw),
              PlinkHost.matches(url.host, anyOf: PlinkHost.vkDomains) else { return nil }
        if url.path.contains("video_ext.php"), let q = url.query, !q.isEmpty { return q }
        // Keep the leading minus: vk.com/video-123_456 → oid=-123 (group).
        if let match = url.path.range(of: #"video-?\d+_\d+"#, options: .regularExpression) {
            return String(url.path[match]).dropFirst(5).description
        }
        return nil
    }

    static func extractRutubeVideoId(from raw: String) -> String? {
        guard let url = URL(string: raw),
              PlinkHost.matches(url.host, anyOf: PlinkHost.rutubeDomains) else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        for (idx, part) in parts.enumerated() {
            if part.count == 32, part.allSatisfy(\.isHexDigit) { return part }
            if (part == "embed" || part == "video"), idx + 1 < parts.count {
                let next = parts[idx + 1]
                if next.count >= 8 { return next }
            }
        }
        return nil
    }

    private static func isYouTubeId(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
