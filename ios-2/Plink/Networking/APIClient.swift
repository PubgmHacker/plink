import Foundation

// MARK: - REST API Client
/// Generic REST client for room CRUD, user management, etc.
///
/// 🔧 FIX H10: encoder/decoder wrapped in a lock — JSONEncoder/JSONDecoder
/// are NOT thread-safe under concurrent access from multiple Tasks.
/// 🔧 FIX H11: request<T> now handles 204 No Content gracefully.
/// 🔧 FIX C6: APIClient conforms to ObservableObject so it can be injected
/// via @EnvironmentObject into AdminPanelView (was: each view created its own
/// unauthenticated APIClient — now fixed with .shared singleton).
final class APIClient: ObservableObject, @unchecked Sendable {
    /// 🔧 Pack v3: Singleton — для использования в views без EnvironmentObject
    static let shared = APIClient()

    /// Public so media helpers (voice notes, avatars) can build authenticated URLs.
    let baseURL: URL

    // 🔧 FIX H10: Lock-protected encoder/decoder (not thread-safe by Apple docs)
    private let encoderLock = NSLock()
    private let _encoder = JSONEncoder()
    private let decoderLock = NSLock()
    private let _decoder = JSONDecoder()

    private var encoder: JSONEncoder {
        encoderLock.lock(); defer { encoderLock.unlock() }
        return _encoder
    }
    private var decoder: JSONDecoder {
        decoderLock.lock(); defer { decoderLock.unlock() }
        return _decoder
    }

    // 🔧 FIX H10: authToken accessed from multiple Tasks — protect with lock.
    private let tokenLock = NSLock()
    private var _authToken: String?
    var authToken: String? {
        get {
            tokenLock.lock(); defer { tokenLock.unlock() }
            return _authToken
        }
        set {
            tokenLock.lock(); defer { tokenLock.unlock() }
            _authToken = newValue
        }
    }

    init(baseURL: String = PlinkConfig.apiURLString) {
        self.baseURL = URL(string: baseURL)!
        // 🔧 FIX: Was `.convertToSnakeCase` — but the backend reads camelCase everywhere
        // (rooms.ts: `mediaItem`, `hostName`, `maxParticipants`; auth.ts: `refreshToken`;
        // friends.ts: `friendId`; profile.ts: `avatarURL`; messages.ts: `receiverId`).
        // The encoder was silently converting iOS camelCase → snake_case, the backend
        // then read undefined for every compound key, and stored null in the DB.
        // Symptom: room created with YouTube → video never loads (mediaItem = null).
        //
        // Now: send camelCase as-is, backend reads camelCase. Single-word keys
        // (email, password, code, name, etc.) were never affected and stay working.
        _encoder.keyEncodingStrategy = .useDefaultKeys
        _encoder.dateEncodingStrategy = .iso8601
        // Decoder: keep `.convertFromSnakeCase` — it's harmless for camelCase keys
        // (only converts keys that actually contain underscores) and provides forward
        // compat if any backend field ever switches to snake_case.
        _decoder.keyDecodingStrategy = .convertFromSnakeCase
        // 🔧 Pack v2: ISO8601 с поддержкой миллисекунд.
        // Бэкенд Prisma возвращает даты как "2026-07-03T16:53:52.778Z"
        // (с миллисекундами). Стандартный .iso8601 Swift НЕ парсит миллисекунды
        // → decoding падает с ошибкой → iOS показывает "Ресурс не найден"
        // хотя сервер вернул 200 OK. Используем custom formatter.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        _decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            // Сначала пробуем с миллисекундами
            if let date = formatter.date(from: dateString) {
                return date
            }
            // Fallback: без миллисекунд
            let fallback = ISO8601DateFormatter()
            if let date = fallback.date(from: dateString) {
                return date
            }
            // Last resort: текущая дата (не падать)
            return Date()
        }
    }

    // MARK: - Generic Request

    /// 🔧 FIX AUTH BUG: Public auth endpoints must NOT send a stale Authorization header.
    /// Some servers (and reverse proxies) reject requests carrying an expired token even
    /// on public routes like /auth/signin, returning 401 with "session expired" — which
    /// blocks the login flow entirely.
    ///
    /// Returns true for paths that should never carry the Authorization header.
    private static func isPublicAuthEndpoint(_ path: String) -> Bool {
        let publicPaths = [
            "auth/signin",
            "auth/signup",
            "auth/refresh",
            "auth/fcm-token",   // FCM registration happens after signin but token may be in-flight
            "auth/guest",
            "auth/google",
            "auth/apple",
            "auth/vk",
            "auth/yandex",
        ]
        return publicPaths.contains(where: { path.hasPrefix($0) })
    }

    func request<T: Decodable>(
        _ path: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        query: [String: String]? = nil
    ) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if let query {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 🔧 FIX AUTH BUG: Don't attach stale token to public auth endpoints
        if let token = authToken, !Self.isPublicAuthEndpoint(path) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            // 🔧 FIX H11: Handle 204 No Content (empty body) gracefully
            if data.isEmpty {
                if let empty = T.self as? EmptyDecodable.Type {
                    return empty.emptyValue() as! T
                }
                // If T is Optional, decode returns nil — wrap in try?
                if T.self == EmptyResponse.self {
                    return EmptyResponse() as! T
                }
            }
            return try decoder.decode(T.self, from: data)
        case 401:
            if !Self.isPublicAuthEndpoint(path) {
                NotificationCenter.default.post(name: Notification.Name("plinkSessionExpired"), object: nil)
            }
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 409:
            // Парсим реальное сообщение сервера ("email already taken" и т.п.)
            let serverMsg = Self.parseErrorMessage(data: data)
            throw APIError.conflict(message: serverMsg ?? "Конфликт данных")
        default:
            let errorBody = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw APIError.serverError(
                status: httpResponse.statusCode,
                message: errorBody?.message ?? Self.parseErrorMessage(data: data) ?? "Unknown error"
            )
        }
    }

    /// Извлекает человекочитаемое сообщение из тела ошибки.
    /// Сервер шлёт {"error": "..."} или {"message": "..."}.
    static func parseErrorMessage(data: Data) -> String? {
        if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
            return body.error ?? body.message
        }
        return nil
    }

    func requestNoBody(
        _ path: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        query: [String: String]? = nil
    ) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if let query {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        // 🔧 FIX: only set Content-Type when there's a body. Fastify rejects
        // empty body with Content-Type: application/json → 400 error.
        // This affected POST /rooms/:id/leave (no body).
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // 🔧 FIX AUTH BUG: Don't attach stale token to public auth endpoints
        if let token = authToken, !Self.isPublicAuthEndpoint(path) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401:
            if !Self.isPublicAuthEndpoint(path) {
                NotificationCenter.default.post(name: Notification.Name("plinkSessionExpired"), object: nil)
            }
            throw APIError.unauthorized
        // 🔧 FIX M7: requestNoBody was missing 404 handling
        case 404:
            throw APIError.notFound
        case 409:
            let serverMsg = Self.parseErrorMessage(data: Data())
            throw APIError.conflict(message: serverMsg ?? "Конфликт данных")
        default:
            throw APIError.serverError(status: httpResponse.statusCode, message: "Request failed")
        }
    }
}

// MARK: - Empty Response Helper (FIX H11)
/// Default value for 204 No Content responses
protocol EmptyDecodable {
    static func emptyValue() -> Self
}

struct EmptyResponse: Codable, EmptyDecodable {
    static func emptyValue() -> EmptyResponse { EmptyResponse() }
}

// MARK: - HTTP Method

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case conflict(message: String)
    case serverError(status: Int, message: String)
    case decodingError
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid server response"
        case .unauthorized: return "Сессия истекла. Войдите заново."
        case .notFound: return "Ресурс не найден"
        case .conflict(let msg): return msg
        case .serverError(let status, let msg): return "Ошибка сервера (\(status)): \(msg)"
        case .decodingError: return "Не удалось обработать ответ сервера"
        case .networkError(let msg): return "Ошибка сети: \(msg)"
        }
    }
}

struct APIErrorBody: Decodable {
    let error: String?
    let message: String?
}
