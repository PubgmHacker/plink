import Foundation

// MARK: - Media Service
/// Metadata helper for YouTube links (title / thumb / duration).
///
/// **App Store path:** playback uses the official YouTube IFrame player
/// (`/api/media/youtube-player` → WKWebView). This service must NOT be used
/// to feed raw CDN (`googlevideo.com`) URLs into AVPlayer in Release builds.
///
/// Legacy extract endpoints remain for DEBUG / internal QA only.
/// Error handling covers network failures, private/unavailable videos, and
/// rate limits.

@MainActor
final class MediaService {

    // MARK: - Configuration

    private let apiBaseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // Simple in-memory cache to avoid re-extracting the same video
    private var cache: [String: ExtractedMedia] = [:]

    init(apiBaseURL: String = PlinkConfig.apiURLString) {
        self.apiBaseURL = URL(string: apiBaseURL)!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 90
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Public API

    /// Resolve media metadata for a YouTube URL.
    /// Release builds reject legacy direct-stream extraction at compile time.
    func extract(youTubeURL: String) async throws -> ExtractedMedia {
        #if DEBUG
        // 0. Validate input (accept watch / youtu.be / embed / shorts URLs)
        guard isValidYouTubeURL(youTubeURL) else {
            throw MediaError.invalidURL
        }

        let videoID = extractVideoID(from: youTubeURL) ?? youTubeURL

        // 1. Cache hit?
        if let cached = cache[videoID] {
            return cached
        }

        // 2. Build request — POST /api/media/extract-url with {url}
        let endpoint = apiBaseURL.appendingPathComponent("media/extract-url")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Attach JWT if available
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // 🔧 v8: backend extractStream expects a watch URL, not embed URL.
        // Convert embed → watch before sending.
        let urlToSend: String
        if youTubeURL.contains("youtube.com/embed/") {
            urlToSend = "https://www.youtube.com/watch?v=\(videoID)"
        } else {
            urlToSend = youTubeURL
        }

        let body = ExtractRequest(url: urlToSend)
        request.httpBody = try encoder.encode(body)

        // 3. Send (with one retry on transient failure)
        let data: Data
        do {
            data = try await performRequest(request)
        } catch {
            // Single retry for transient network blips
            data = try await performRequest(request)
        }

        // 4. Decode — backend /extract-url returns StreamInfo format:
        //    {id, title, author, thumbnailURL, streamURL, duration, isLive, extractor, formats?}
        // 🔧 v44.2: reverted v44.1 change — this is the correct format that
        // plink-backend/src/services/streamExtractor.ts actually returns.
        let response = try decoder.decode(ExtractResponse.self, from: data)

        // 5. Validate the stream URL is actually usable
        guard let streamURL = URL(string: response.streamURL),
              !response.streamURL.isEmpty else {
            throw MediaError.invalidStreamURL
        }

        // Hard block: never hand googlevideo CDN URLs to the player in ship builds.
        if response.streamURL.lowercased().contains("googlevideo.com") {
            throw MediaError.blocked("Direct stream URLs not allowed in App Store build")
        }

        let media = ExtractedMedia(
            id: response.id,
            title: response.title,
            // 🔧 v8: backend StreamInfo uses 'author' (not 'artist'), map it
            artist: response.author,
            thumbnailURL: response.thumbnailURL.flatMap(URL.init(string:)),
            streamURL: streamURL,
            duration: response.duration,
            format: response.format ?? "mp4",
            quality: response.quality ?? "unknown",
            isLive: response.isLive ?? false
        )

        // Cache it
        cache[videoID] = media
        return media
        #else
        throw MediaError.blocked("Direct stream URLs not allowed in App Store build")
        #endif
    }

    /// Validate a URL before committing to a full extraction (cheaper server call).
    func validate(url: String) async throws -> ValidationResult {
        #if DEBUG
        let endpoint = apiBaseURL.appendingPathComponent("media/extract/validate")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try encoder.encode(ValidateRequest(url: url))

        let data = try await performRequest(request)
        return try decoder.decode(ValidationResult.self, from: data)
        #else
        throw MediaError.blocked("Legacy media validation not allowed in App Store build")
        #endif
    }

    /// Convert an ExtractedMedia into the app's MediaItem model for AVPlayer + sync.
    func makeMediaItem(from extracted: ExtractedMedia) -> MediaItem {
        MediaItem(
            id: extracted.id,
            title: extracted.title,
            artist: extracted.artist,
            thumbnailURL: extracted.thumbnailURL?.absoluteString,
            streamURL: extracted.streamURL.absoluteString,
            duration: extracted.duration,
            mediaType: extracted.isLive ? .livestream : .video,
            source: .youtube
        )
    }

    // MARK: - Auth

    /// JWT token — set after login. Required by the authenticated backend endpoint.
    private var authToken: String?

    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    // MARK: - Network

    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw MediaError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            return data

        case 401:
            throw MediaError.unauthorized

        case 404:
            throw MediaError.notFound

        case 422:
            // Backend says video unavailable / restricted
            let errBody = try? decoder.decode(ErrorBody.self, from: data)
            throw MediaError.videoUnavailable(errBody?.error ?? "Video unavailable")

        case 429:
            throw MediaError.rateLimited

        default:
            let errBody = try? decoder.decode(ErrorBody.self, from: data)
            throw MediaError.serverError(http.statusCode, errBody?.error)
        }
    }

    // MARK: - URL Validation

    private func isValidYouTubeURL(_ url: String) -> Bool {
        let patterns = [
            #"https?://(www\.)?youtube\.com/watch\?v=[\w-]+"#,
            #"https?://youtu\.be/[\w-]+"#,
            #"https?://(www\.)?youtube\.com/shorts/[\w-]+"#,
            #"https?://(www\.)?youtube\.com/embed/[\w-]+"#,
        ]
        return patterns.contains { pattern in
            url.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func extractVideoID(from url: String) -> String? {
        // youtu.be/<id>
        if let id = url.range(of: #"/([\w-]{11})(?:\?|$|/)"#, options: .regularExpression) {
            return String(url[id]).trimmingCharacters(in: CharacterSet(charactersIn: "/?"))
        }
        // watch?v=<id>
        if let components = URLComponents(string: url),
           let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        return nil
    }
}

// MARK: - DTOs

struct ExtractRequest: Codable {
    let url: String
}

struct ValidateRequest: Codable {
    let url: String
}

struct ExtractResponse: Codable {
    /// 🔧 v44.2: matches plink-backend StreamInfo (streamExtractor.ts):
    /// {id, title, author, thumbnailURL, streamURL, duration, isLive, extractor}
    let id: String
    let title: String
    let author: String?
    let thumbnailURL: String?
    let streamURL: String
    let duration: Double?
    let format: String?
    let quality: String?
    let isLive: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, author
        case thumbnailURL
        case streamURL, duration, format, quality
        case isLive
    }
}

struct ExtractedMedia {
    let id: String
    let title: String
    let artist: String?
    let thumbnailURL: URL?
    let streamURL: URL
    let duration: Double?
    let format: String
    let quality: String
    let isLive: Bool
}

struct ValidationResult: Codable {
    let supported: Bool
    let type: String
    let message: String
}

private struct ErrorBody: Codable {
    let error: String
}

// MARK: - Errors

enum MediaError: LocalizedError {
    case invalidURL
    case invalidStreamURL
    case invalidResponse
    case unauthorized
    case notFound
    case rateLimited
    case videoUnavailable(String)
    case serverError(Int, String?)
    case blocked(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That doesn't look like a valid YouTube link."
        case .invalidStreamURL:
            return "Couldn't get a playable stream from this video."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .notFound:
            return "The extraction endpoint was not found."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .blocked(let detail):
            return detail
        case .videoUnavailable(let detail):
            return detail
        case .serverError(let code, let msg):
            return "Server error (\(code)): \(msg ?? "unknown")"
        }
    }
}
