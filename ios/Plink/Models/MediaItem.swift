import Foundation

// MARK: - Media Item
struct MediaItem: Codable, Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let title: String
    let artist: String?           // For music
    let thumbnailURL: String?
    let streamURL: String         // Direct playable URL
    let duration: TimeInterval?
    let mediaType: MediaType
    let source: MediaSource
    /// 🔧 v97: YouTube video ID for server-side extraction.
    /// instead of ?b64url=... — backend extracts URL with its own IP.
    var videoId: String?

    enum MediaType: String, Codable, Sendable {
        case movie = "movie"
        case series = "series"
        case music = "music"
        case video = "video"
        case livestream = "livestream"
    }

    enum MediaSource: String, Codable, Sendable {
        case url = "url"              // Direct URL
        case youtube = "youtube"
        case plex = "plex"
        case jellyfin = "jellyfin"
        case local = "local"
    }

    var displayTitle: String {
        if let artist {
            return "\(artist) — \(title)"
        }
        return title
    }

    /// App Store builds must not play raw CDN extract URLs (Guideline 5.x / ToS).
    /// DEBUG builds may still recognise googlevideo for internal QA.
    var isBlockedInAppStoreBuild: Bool {
        #if DEBUG
        return false
        #else
        let lower = streamURL.lowercased()
        return lower.contains("googlevideo.com")
            || (lower.contains("youtube-stream") && lower.contains("/api/media/"))
        #endif
    }

    /// 🔧 FIX: Determines how this media should be played back.
    /// - YouTube embed URLs → WebView (official IFrame / player API).
    /// - Direct stream URLs (.mp4, .m3u8, HLS) → AVPlayer.
    /// - Cinema / OTT pages → WebView (host subscription).
    /// - Default unknown HTML → WebView.
    ///
    /// Release: googlevideo.com / legacy extract proxies are not treated as
    /// playable streams (see `isBlockedInAppStoreBuild`).
    var effectivePlaybackMode: PlaybackMode {
        let lower = streamURL.lowercased()

        // Direct streamable formats — AVPlayer handles these
        if lower.hasSuffix(".mp4")
            || lower.hasSuffix(".m3u8")
            || lower.contains(".m3u8?")
            || lower.contains(".mp4?")
            || lower.hasSuffix(".mov")
            || lower.hasSuffix(".mkv") {
            return .directStream
        }

        #if DEBUG
        // Internal QA only: direct CDN / proxy streams from extract experiments.
        if lower.contains("googlevideo.com/videoplayback") {
            return .directStream
        }
        if lower.contains("plink-backend") && lower.contains("youtube-stream") {
            return .directStream
        }
        if lower.contains("/api/media/") && lower.contains("-stream") {
            return .directStream
        }
        #endif

        // YouTube source — always WebView (embed URL or watch URL, both HTML)
        // NOTE: this check is now only hit if extraction FAILED and we fell back
        // to the embed URL. With successful v8 backend extraction, source is
        // changed to .url before this check runs.
        if source == .youtube { return .webview }

        // YouTube embed URL pattern (even if source wasn't set to .youtube)
        if lower.contains("youtube.com/embed/") || lower.contains("youtu.be/") {
            return .webview
        }

        // VK/RuTube embed URLs are also HTML pages
        if lower.contains("vk.com/video_ext") || lower.contains("rutube.ru/play/embed") {
            return .webview
        }

        // Default: if URL doesn't end with a known media extension, treat as HTML page
        // (cinema sites, generic web pages, etc.)
        return .webview
    }

    var formattedDuration: String? {
        guard let duration else { return nil }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static var preview: MediaItem {
        MediaItem(
            id: "media_001",
            title: "Big Buck Bunny",
            artist: nil,
            thumbnailURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Big_buck_bunny_poster_big.jpg/800px-Big_buck_bunny_poster_big.jpg",
            streamURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
            duration: 596,
            mediaType: .movie,
            source: .url
        )
    }

    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool {
        lhs.id == rhs.id
    }
}
