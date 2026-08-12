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
            "auth/guest",
            "auth/vk",
            "auth/yandex",
        ]
        return publicPaths.contains(where: { path.hasPrefix($0) })
    }

    /// Плинк+ 02.08.2026: 402 и 503 — это не «ошибки сервера», а два штатных
    /// продуктовых ответа, на которые UI реагирует по-разному:
    /// 402 → экран покупки, 503 → честное «скоро». Раньше оба падали в default
    /// и показывались как «Ошибка сервера (402)».
    private static func productError(status: Int, data: Data) -> APIError? {
        let body = try? JSONDecoder().decode(APIErrorBody.self, from: data)
        switch status {
        case 402:
            return .subscriptionRequired(
                feature: body?.feature ?? "unknown",
                product: body?.product ?? "plink_plus",
                message: body?.message ?? "Для этой функции нужна подписка Плинк+"
            )
        case 503:
            return .unavailable(
                reason: body?.reason ?? "unavailable",
                message: body?.message ?? "Функция пока недоступна"
            )
        default:
            return nil
        }
    }

    // Аудит 26.07.2026 P0: раньше ЛЮБОЙ 401 немедленно постил plinkSessionExpired
    // и выбрасывал на логин, хотя в Keychain лежал валидный refresh-токен, а
    // серверный TTL access-токена (1 час) короче клиентского хардкода (24 часа).
    // Теперь: один тихий рефреш → повтор запроса; sessionExpired — только если
    // рефреш не помог.
    func request<T: Decodable>(
        _ path: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        query: [String: String]? = nil
    ) async throws -> T {
        do {
            return try await performRequest(path, method: method, body: body, query: query, isRetry: false)
        } catch APIError.unauthorizedNeedsRefresh {
            if await AuthService.shared.refreshSessionToken() != nil {
                return try await performRequest(path, method: method, body: body, query: query, isRetry: true)
            }
            await Self.postSessionExpired()
            throw APIError.unauthorized
        }
    }

    private func performRequest<T: Decodable>(
        _ path: String,
        method: HTTPMethod,
        body: Encodable?,
        query: [String: String]?,
        isRetry: Bool
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
                    return empty.emptyValue() as? T ?? EmptyResponse() as! T
                }
                // If T is Optional, decode returns nil — wrap in try?
                if T.self == EmptyResponse.self {
                    return EmptyResponse() as! T
                }
            }
            return try decoder.decode(T.self, from: data)
        case 401:
            // Аудит 26.07.2026 P1: на публичных auth-маршрутах 401 = неверные креды,
            // а не «Сессия истекла» — отдаём осмысленный текст вместо unauthorized.
            if Self.isPublicAuthEndpoint(path) {
                let serverMsg = Self.parseErrorMessage(data: data)
                let friendly: String
                if let serverMsg, serverMsg.lowercased() != "invalid credentials" {
                    friendly = serverMsg
                } else {
                    friendly = "Неверный email или пароль"
                }
                throw APIError.invalidCredentials(message: friendly)
            }
            if !isRetry {
                throw APIError.unauthorizedNeedsRefresh
            }
            await Self.postSessionExpired()
            throw APIError.unauthorized
        case 402, 503:
            // Плинк+: подписка или «функция ещё не включена» — см. productError.
            if let productError = Self.productError(status: httpResponse.statusCode, data: data) {
                throw productError
            }
            throw APIError.serverError(status: httpResponse.statusCode, message: "Request failed")
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

    /// Аудит 26.07.2026 P1: post только с main-потока — подписчик
    /// (AuthLaunchGate) мутирует @State и зовёт @MainActor-методы.
    @MainActor
    static func postSessionExpired() {
        NotificationCenter.default.post(name: Notification.Name("plinkSessionExpired"), object: nil)
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
        do {
            try await performRequestNoBody(path, method: method, body: body, query: query, isRetry: false)
        } catch APIError.unauthorizedNeedsRefresh {
            if await AuthService.shared.refreshSessionToken() != nil {
                return try await performRequestNoBody(path, method: method, body: body, query: query, isRetry: true)
            }
            await Self.postSessionExpired()
            throw APIError.unauthorized
        }
    }

    private func performRequestNoBody(
        _ path: String,
        method: HTTPMethod,
        body: Encodable?,
        query: [String: String]?,
        isRetry: Bool
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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401:
            // Аудит 26.07.2026 P1: те же правила, что и в request<T> —
            // на публичных auth-маршрутах 401 = неверные креды, post — только с main.
            if Self.isPublicAuthEndpoint(path) {
                let serverMsg = Self.parseErrorMessage(data: data)
                let friendly: String
                if let serverMsg, serverMsg.lowercased() != "invalid credentials" {
                    friendly = serverMsg
                } else {
                    friendly = "Неверный email или пароль"
                }
                throw APIError.invalidCredentials(message: friendly)
            }
            if !isRetry {
                throw APIError.unauthorizedNeedsRefresh
            }
            await Self.postSessionExpired()
            throw APIError.unauthorized
        // Плинк+ 02.08.2026: те же два продуктовых кода, что и в request<T>.
        // Без этого ветка requestNoBody молча теряла бы причину отказа.
        case 402, 503:
            if let productError = Self.productError(status: httpResponse.statusCode, data: data) {
                throw productError
            }
            throw APIError.serverError(status: httpResponse.statusCode, message: "Request failed")
        // 🔧 FIX M7: requestNoBody was missing 404 handling
        case 404:
            throw APIError.notFound
        case 409:
            // Аудит 26.07.2026 P1: парсим реальное тело ответа (раньше — Data())
            let serverMsg = Self.parseErrorMessage(data: data)
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
    /// Аудит 26.07.2026 P0: внутренний сигнал «401 на первой попытке» —
    /// обёртка request/requestNoBody ловит его, делает одиночный refresh и
    /// повторяет запрос. Наружу этот кейс не выходит.
    case unauthorizedNeedsRefresh
    /// Аудит 26.07.2026 P1: 401 на публичных auth-маршрутах (signin/signup) —
    /// это неверные креды, а не истёкшая сессия. Отдельный кейс с текстом сервера.
    case invalidCredentials(message: String)
    /// Плинк+ 02.08.2026: 402 — функция требует подписки. По этому кейсу
    /// UI обязан открыть экран покупки, а не алерт с ошибкой.
    /// `feature` говорит, что именно закрыто (например room_rtc) — по нему
    /// выбирается триггер пэйволла и источник в аналитике.
    case subscriptionRequired(feature: String, product: String, message: String)
    /// Плинк+ 02.08.2026: 503 — функция ещё не включена на сервере
    /// (reason=not_configured — нет ключей LiveKit). Это НЕ повод продавать
    /// подписку и НЕ повод показывать ошибку — нужно честное «скоро».
    case unavailable(reason: String, message: String)
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
        // Наружу не выходит — обёртка request/requestNoBody перехватывает.
        case .unauthorizedNeedsRefresh: return "Сессия истекла. Войдите заново."
        case .invalidCredentials(let msg): return msg
        case .subscriptionRequired(_, _, let msg): return msg
        case .unavailable(_, let msg): return msg
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
    /// Плинк+ 02.08.2026: сервер различает причины отказа машиночитаемо:
    /// plus_required / not_configured. Опознавать их по тексту сообщения нельзя —
    /// текст меняется и локализуется.
    let reason: String?
    let feature: String?
    let product: String?
}
