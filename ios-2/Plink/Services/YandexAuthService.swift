import Foundation
import AuthenticationServices

// MARK: - Yandex Auth Service
/// Аутентификация через Яндекс ID (OAuth 2.0) с использованием
/// ASWebAuthenticationSession — системного безопасного браузера.
///
/// Поток:
/// 1. Открываем ASWebAuthenticationSession → Яндекс OAuth consent screen
/// 2. Пользователь даёт доступ → получаем authorization code
/// 3. Code → backend → JWT (наш собственный токен)
/// 4. Проверяем Яндекс Плюс подписку (через backend-прокси)
///
/// Гостевой режим: пользователь может пропустить авторизацию
/// и смотреть контент хоста бесплатно.
@MainActor
final class YandexAuthService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var isAuthenticated = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isPlus = false
    @Published private(set) var user: YandexUser?
    @Published var errorMessage: String?

    // MARK: - Configuration

    /// Зарегистрировать приложение в Яндекс OAuth: https://oauth.yandex.ru/client/new
    private let clientID: String
    private let redirectURI: String
    private let redirectScheme: String
    private let backendURL: URL

    private var session: ASWebAuthenticationSession?

    // MARK: - Init

    /// 🔧 FIX C14: Read clientID from Info.plist (was: hardcoded placeholder).
    /// Set YANDEX_CLIENT_ID in your xcconfig file or build settings.
    init(
        clientID: String? = nil,
        redirectScheme: String = "syncwatch",
        backendURL: URL = URL(string: PlinkConfig.apiURLString)!
    ) {
        // Resolve Yandex client ID: explicit param → Info.plist → fail-safe empty
        let resolvedClientID: String = clientID
            ?? (Bundle.main.object(forInfoDictionaryKey: "YANDEX_CLIENT_ID") as? String)
            ?? ""
        self.clientID = resolvedClientID
        self.redirectScheme = redirectScheme
        self.redirectURI = "\(redirectScheme)://oauth"
        self.backendURL = backendURL
        super.init()

        // Восстанавливаем токен из Keychain при запуске
        if let token = KeychainHelper.read(for: "yandex_jwt"),
           !token.isEmpty {
            isAuthenticated = true
            Task { await fetchProfile(token: token) }
        }
    }

    // MARK: - Sign In

    func signInWithYandex() async throws {
        guard !isAuthenticating else { return }

        // 🔧 FIX C14: Fail early with a clear error if clientID is not configured.
        // (was: silently hit Yandex OAuth with 'yandex_client_id_placeholder')
        guard !clientID.isEmpty else {
            errorMessage = "Yandex Client ID не настроен. Установите YANDEX_CLIENT_ID в xcconfig."
            throw YandexAuthError.clientIDNotConfigured
        }

        isAuthenticating = true
        errorMessage = nil

        defer { isAuthenticating = false }

        // 1. Получаем authorization code
        let authURL = URL(string: "https://oauth.yandex.ru/authorize?" +
            "response_type=code" +
            "&client_id=\(clientID)" +
            "&redirect_uri=\(redirectURI)" +
            "&scope=login:info+login:email+userinfo:user_plus_subscriber" +
            "&force_confirm=yes"
        )!

        do {
            let code = try await runAuthSession(url: authURL)

            // 2. Обмениваем code на JWT через backend
            let token = try await exchangeCodeForToken(code)
            KeychainHelper.save(token, for: "yandex_jwt")

            // 3. Загружаем профиль
            await fetchProfile(token: token)

            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Гостевой вход — без Яндекс ID.
    func signInAsGuest() {
        isAuthenticated = true
        isPlus = false
        user = YandexUser(
            id: "guest_\(UUID().uuidString.prefix(8))",
            displayName: "Гость",
            email: nil,
            avatarURL: nil
        )
    }

    // MARK: - Sign Out

    func signOut() {
        isAuthenticated = false
        isPlus = false
        user = nil
        KeychainHelper.delete(for: "yandex_jwt")
    }

    // MARK: - ASWebAuthenticationSession

    private func runAuthSession(url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: redirectScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: YandexAuthError.missingCode)
                    return
                }

                continuation.resume(returning: code)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
            self.session = session
        }
    }

    // MARK: - Backend Exchange

    private func exchangeCodeForToken(_ code: String) async throws -> String {
        var request = URLRequest(url: backendURL.appendingPathComponent("auth/yandex"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": code,
            "redirect_uri": redirectURI,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw YandexAuthError.exchangeFailed
        }

        let payload = try JSONDecoder().decode(YandexTokenResponse.self, from: data)
        return payload.token
    }

    // MARK: - Profile & Plus Status

    private func fetchProfile(token: String) async {
        var request = URLRequest(url: backendURL.appendingPathComponent("user/profile"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let profile = try JSONDecoder().decode(YandexProfileResponse.self, from: data)
            user = YandexUser(
                id: profile.id,
                displayName: profile.displayName,
                email: profile.email,
                avatarURL: profile.avatarURL
            )
            isPlus = profile.isPlus
        } catch {
            // Non-fatal: профиль не критичен
        }
    }
}

// MARK: - Presentation Context

extension YandexAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Models

struct YandexUser: Identifiable, Codable {
    let id: String
    let displayName: String
    let email: String?
    let avatarURL: String?
}

private struct YandexTokenResponse: Codable {
    let token: String
}

private struct YandexProfileResponse: Codable {
    let id: String
    let displayName: String
    let email: String?
    let avatarURL: String?
    let isPlus: Bool
}

enum YandexAuthError: LocalizedError {
    case missingCode
    case exchangeFailed
    case clientIDNotConfigured

    var errorDescription: String? {
        switch self {
        case .missingCode:
            return "Не удалось получить код авторизации от Яндекса."
        case .exchangeFailed:
            return "Не удалось обменять код на токен. Попробуйте позже."
        case .clientIDNotConfigured:
            return "Yandex Client ID не настроен. Установите YANDEX_CLIENT_ID в xcconfig."
        }
    }
}

// MARK: - Yandex Auth Errors
/// 🔧 FIX C14: Clear error for misconfigured Yandex client ID — merged into YandexAuthError above.
