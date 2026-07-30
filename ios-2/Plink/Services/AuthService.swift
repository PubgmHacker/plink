import Foundation

// MARK: - Auth Service (Production — real server registration)
/// Настоящая авторизация через сервер: /api/auth/signup, /api/auth/signin.
/// Сервер создаёт пользователя в PostgreSQL, хеширует пароль (SHA-256),
/// выдаёт JWT. Токен сохраняется и прокидывается во все сервисы.
///
/// 🔧 FIX C2: JWT now stored in Keychain (not UserDefaults) via KeychainHelper.
/// 🔧 FIX C3: getFreshToken() now actually refreshes via /auth/refresh.
/// 🔧 FIX H14: AuthService is @MainActor — currentUser restore is synchronous.
enum AuthRestoreResult: Sendable, Equatable {
    case authenticated
    case offlineAuthenticated
    case unauthenticated
    case expired
}

@MainActor
final class AuthService: AuthServiceProtocol, @unchecked Sendable {

    private let api: APIClient
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let savedUser = "rave_saved_user"           // ← non-secret profile, OK in UserDefaults
        static let authToken = "rave_auth_token"            // ← Keychain
        static let tokenExpiry = "rave_token_expiry"        // ← Keychain (string)
        static let refreshToken = "rave_refresh_token"      // ← Keychain
        static let fcmToken = "rave_fcm_token"              // ← non-secret, OK in UserDefaults
    }

    // MARK: - Stored User + Token

    private(set) var currentUser: User?
    /// 🔧 Pack v3: Protocol-required synchronous accessor
    var currentUserValue: User? { currentUser }
    private(set) var authToken: String?
    private(set) var tokenExpiry: TimeInterval = 0
    private(set) var refreshToken: String?
    private(set) var fcmToken: String?

    // MARK: - Init

    init(api: APIClient) {
        self.api = api
        restoreSessionFromStorage()
        api.authToken = authToken
    }

    /// Decode cached user with ISO8601 — default JSONDecoder fails on
    /// `createdAt` written by cacheUser, leaving currentUser=nil while JWT still works.
    private static func decodeCachedUser(_ data: Data) -> User? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = withFrac.date(from: str) { return d }
            let plain = ISO8601DateFormatter()
            if let d = plain.date(from: str) { return d }
            return Date()
        }
        if let user = try? dec.decode(User.self, from: data) { return user }
        // Last resort: ignore dates
        let fallback = JSONDecoder()
        return try? fallback.decode(User.self, from: data)
    }

    /// Reload token + user from Keychain / UserDefaults into this instance.
    func restoreSessionFromStorage() {
        if let data = defaults.data(forKey: Keys.savedUser),
           let user = Self.decodeCachedUser(data) {
            self.currentUser = user
            defaults.set(user.id, forKey: "plink_current_user_id")
            defaults.set(user.username, forKey: "plink_current_username")
            defaults.set(user.displayName ?? user.username, forKey: "plink_current_display_name")
        }

        // Аудит 26.07.2026 (P1 5.10): единая точка чтения токена — AuthTokenStore
        // (сам разбирается с легаси-ключом `rave_auth_token`).
        self.authToken = AuthTokenStore.shared.token
        if let expiryStr = KeychainHelper.read(for: Keys.tokenExpiry),
           let expiry = TimeInterval(expiryStr) {
            self.tokenExpiry = expiry
        }
        self.refreshToken = KeychainHelper.read(for: Keys.refreshToken)
        self.fcmToken = defaults.string(forKey: Keys.fcmToken)
        api.authToken = authToken
    }

    /// Public rebind used by WatchRoom / room create when shared session looks empty.
    func rebindSessionFromStorage() {
        restoreSessionFromStorage()
    }

    /// MVP launch gate: restore cached session, refresh token if needed, then
    /// validate it against `/users/me`. Only an explicit 401 clears the session;
    /// transient network/backend failures keep the cached user in offline mode.
    func restoreAndValidateSession() async -> AuthRestoreResult {
        restoreSessionFromStorage()

        guard authToken != nil else {
            return .unauthenticated
        }

        guard await getFreshToken() != nil else {
            signOutLocally(postNotification: false)
            return .expired
        }

        do {
            _ = try await fetchCurrentUser()
            return .authenticated
        } catch APIError.unauthorized {
            signOutLocally(postNotification: false)
            return .expired
        } catch {
            return currentUser == nil ? .unauthenticated : .offlineAuthenticated
        }
    }

    // MARK: - Sign In (реальный запрос к серверу)

    func signIn(email: String, password: String) async throws -> User {
        let body = SignInRequest(email: email, password: password)
        let response: AuthResponse = try await api.request("auth/signin", method: .post, body: body)

        let user = User(
            id: response.user.id,
            username: response.user.username,
            email: response.user.email,
            avatarURL: response.user.avatarURL,
            avatarData: response.user.avatarData,
            isOnline: true,
            isPremium: response.user.isPremium ?? false,
            premiumUntil: response.user.premiumUntil,
            role: response.user.role,
            createdAt: response.user.createdAt ?? Date()
        )

        let expiry = response.expiryEpochSeconds
        await cacheToken(response.token, expiry: expiry, refreshToken: response.refreshToken)
        cacheUser(user)
        // 🔧 FIX M6: Sync premium status from server (authoritative source).
        // Local UserDefaults flag is now a hint, not authority.
        // Дата: /auth/signin её не отдаёт → nil = «дату не трогаем»; настоящую
        // принесёт fetchCurrentUser (/users/me) или refreshEntitlement ниже.
        PremiumStatusManager.shared.syncFromServer(
            isPremium: user.isPremium,
            expiry: user.premiumUntil
        )
        refreshEntitlementExpiryIfPremium(serverIsPremium: user.isPremium)
        await registerFCMIfPresent()
        AnalyticsService.shared.login()
        return user
    }

    // MARK: - Sign Up (реальная регистрация на сервере)

    func signUp(email: String, password: String, username: String) async throws -> User {
        let body = SignUpRequest(email: email, password: password, username: username)
        let response: AuthResponse = try await api.request("auth/signup", method: .post, body: body)

        let user = User(
            id: response.user.id,
            username: response.user.username,
            email: response.user.email,
            avatarURL: response.user.avatarURL,
            avatarData: response.user.avatarData,
            isOnline: true,
            isPremium: response.user.isPremium ?? false,
            premiumUntil: response.user.premiumUntil,
            role: response.user.role,
            createdAt: response.user.createdAt ?? Date()
        )

        let expiry = response.expiryEpochSeconds
        await cacheToken(response.token, expiry: expiry, refreshToken: response.refreshToken)
        cacheUser(user)
        // 🔧 FIX M6: Sync premium status from server (authoritative source).
        // /auth/signup дату не отдаёт → nil = «дату не трогаем».
        PremiumStatusManager.shared.syncFromServer(
            isPremium: user.isPremium,
            expiry: user.premiumUntil
        )
        refreshEntitlementExpiryIfPremium(serverIsPremium: user.isPremium)
        await registerFCMIfPresent()
        AnalyticsService.shared.signUp()
        return user
    }

    // MARK: - Sign Out

    func signOut() async throws {
        signOutLocally(postNotification: true)
    }

    // MARK: - Current User

    func currentUser() async -> User? {
        currentUser
    }

    // MARK: - Delete Account

    /// 🔧 Pack v3: DELETE /users/me — полное удаление аккаунта на сервере.
    /// Fallback на signOut если endpoint не реализован (404).
    func deleteAccount() async throws {
        do {
            try await api.requestNoBody("users/me", method: .delete)
        } catch APIError.notFound {
            // Fallback для старого бэкенда без DELETE /users/me
            Logger.api.warn("DELETE /users/me not implemented — signing out locally only")
        } catch APIError.unauthorized {
            Logger.api.warn("Cannot delete account: unauthorized (token expired)")
        } catch {
            Logger.api.error("Account deletion failed: \(error.localizedDescription)")
        }
        try await signOut()
    }

    // MARK: - Token Management

    /// 🔧 FIX C3: Actually refreshes the JWT via /auth/refresh when within 5 min of expiry.
    /// Falls back to the existing token if no refresh token is available.
    ///
    /// 🔧 FIX AUTH BUG: If refresh fails (e.g. /auth/refresh endpoint not implemented
    /// on server yet, returns 404), we NO LONGER force signOut. Instead we return the
    /// existing token and let the next API call decide. This prevents the cold-launch
    /// signOut cascade that locked users out of the app.
    func getFreshToken() async -> String? {
        guard let token = authToken else { return nil }
        let now = Date().timeIntervalSince1970

        // Refresh if within 5 min of expiry (or past it)
        if now >= tokenExpiry - 300 {
            // Try refresh, but fall back to existing token if it fails.
            // Only signOut if we get an explicit 401 from the refresh endpoint
            // (which means the refresh token itself is invalid).
            if let refreshed = await refreshJWT() {
                return refreshed
            }
            // Return existing token — the next request will 401 if truly expired,
            // and the caller can handle that case explicitly.
            return token
        }
        return token
    }

    /// 🔧 FIX C3: Real refresh — POST /auth/refresh with the refresh token.
    /// 🔧 FIX AUTH BUG: Only signs out on explicit 401 (refresh token invalid).
    /// Other errors (404 endpoint missing, network error) just return nil.
    // Аудит 26.07.2026 P0: одиночный (single-flight) рефреш для retry-on-401.
    // Параллельные 401 не должны запускать два refresh: ротация с реюз-детектом
    // на сервере расценила бы второй вызов как кражу токена и отозвала бы всё
    // семейство — пользователь вылетел бы со всех устройств.
    private var refreshInFlight: Task<String?, Never>?

    func refreshSessionToken() async -> String? {
        if let inflight = refreshInFlight { return await inflight.value }
        let task = Task { await self.refreshJWT() }
        refreshInFlight = task
        let value = await task.value
        refreshInFlight = nil
        return value
    }

    private func refreshJWT() async -> String? {
        guard let refreshToken else { return nil }

        struct RefreshBody: Encodable { let refreshToken: String }
        do {
            let response: AuthResponse = try await api.request(
                "auth/refresh",
                method: .post,
                body: RefreshBody(refreshToken: refreshToken)
            )
            let expiry = response.expiryEpochSeconds
            await cacheToken(response.token, expiry: expiry, refreshToken: response.refreshToken ?? refreshToken)
            return response.token
        } catch APIError.unauthorized {
            // Refresh token itself is invalid/expired — sign out.
            Logger.api.error("Refresh token invalid — signing out")
            try? await signOut()
            return nil
        } catch {
            // Network error, 404 (endpoint not implemented), etc.
            // Don't signOut — just return nil and let caller use existing token.
            Logger.api.error("Token refresh failed (non-auth): \(error.localizedDescription)")
            return nil
        }
    }

    private func cacheToken(_ token: String, expiry: TimeInterval, refreshToken: String?) async {
        authToken = token
        tokenExpiry = expiry
        self.refreshToken = refreshToken
        api.authToken = token

        // 🔧 FIX C2: Persist to Keychain (was: defaults.set)
        // P1 5.10: прямой save в легаси-ключ убран — AuthTokenStore.save ниже
        // пишет в оба ключа (plink_auth_token + rave_auth_token).
        KeychainHelper.save(String(expiry), for: Keys.tokenExpiry)
        if let refreshToken {
            KeychainHelper.save(refreshToken, for: Keys.refreshToken)
        }
        // Аудит 26.07.2026: код M39 (ClockSync, StoreKitManager, ModerationService,
        // PushNotificationService, AIStreamClient) читает токен через AuthTokenStore.
        // Без этой строки у них был бы пустой токен до первой миграции, а кэш
        // хранилища оставался бы устаревшим после повторного входа.
        AuthTokenStore.shared.save(token)
    }

    // Аудит 26.07.2026: POST /auth/signout-others отзывает ВСЕ refresh-токены
    // пользователя и выдаёт новую пару для текущего устройства. Раньше клиент
    // игнорировал тело ответа (requestNoBody) — локальный refresh-токен
    // оставался отозванным, и на следующем /auth/refresh это устройство тоже
    // вылетало из аккаунта. cacheToken приватный, поэтому нужен внутренний
    // метод, чтобы V5-мост (PlinkAuthBridge) мог сохранить переизданную пару.
    func applyReissuedTokens(token: String, refreshToken: String?, accessExpiresAtMs: Double? = nil) async {
        let expiry = (accessExpiresAtMs.map { $0 / 1000 })
            ?? Date().addingTimeInterval(86400).timeIntervalSince1970
        await cacheToken(token, expiry: expiry, refreshToken: refreshToken)
    }

    // MARK: - Premium entitlement

    /// Аудит 26.07.2026 (P2): signIn/signUp передавали в syncFromServer эхо
    /// локального `subscriptionExpiry` — серверная дата истечения не доходила
    /// до клиента ни при одном входе (ответы /auth/* не содержат premiumUntil).
    /// Авторитетную дату отдаёт `GET /api/billing/entitlements`; ходит туда
    /// живой IAP-стек, поэтому просто дёргаем его после сохранения токена.
    ///
    /// Ревью 26.07.2026: запрос идёт ТОЛЬКО когда сервер подтвердил Plink+, и
    /// в фоне. Две причины: (1) при `isPremium == false` офлайн-фолбэк
    /// `StoreManager.refreshEntitlement` (локальные StoreKit-транзакции при
    /// 5xx/обрыве сети) мог включить премиум аккаунту, которому сервер отказал
    /// строкой выше; (2) вход не должен ждать биллинговый эндпоинт (у него нет
    /// своего таймаута, дефолт URLSession — 60 с).
    private func refreshEntitlementExpiryIfPremium(serverIsPremium: Bool) {
        guard serverIsPremium else { return }
        Task { await self.refreshEntitlementExpiry() }
    }

    private func refreshEntitlementExpiry() async {
        if StoreManager.shared.apiBaseURL == nil {
            StoreManager.shared.apiBaseURL = URL(string: PlinkConfig.baseURLString)
        }
        await StoreManager.shared.refreshEntitlement()
    }

    // MARK: - FCM Token

    func setFCMToken(_ token: String) async {
        fcmToken = token
        defaults.set(token, forKey: Keys.fcmToken)
        registerFCMToken(token)
    }

    private func registerFCMIfPresent() async {
        guard let fcmToken else { return }
        registerFCMToken(fcmToken)
    }

    private func registerFCMToken(_ token: String) {
        struct FCMBody: Encodable { let token: String }
        let body = FCMBody(token: token)
        Task {
            do {
                try await api.requestNoBody("auth/fcm-token", method: .post, body: body)
            } catch {
                Logger.api.error("[Auth] FCM token registration failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    private func cacheUser(_ user: User) {
        // ISO8601 so re-decode after relaunch works with User.createdAt
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(user) {
            defaults.set(data, forKey: Keys.savedUser)
        }
        currentUser = user
        // 🔧 Pack v3: Сохраняем user data для чата (определение "моё/чужое" + админ)
        defaults.set(user.id, forKey: "plink_current_user_id")
        defaults.set(user.username, forKey: "plink_current_username")
        defaults.set(user.displayName ?? user.username, forKey: "plink_current_display_name")
        defaults.set(user.role ?? "USER", forKey: "plink_current_user_role")
        // After registration / login — ready for one-time gallery prompt on avatar change
        Task { @MainActor in
            PlinkPermissions.markPostAuthSession()
        }
        NotificationCenter.default.post(name: .plinkProfileDidUpdate, object: user)
    }

    // 🔧 Pack v3: Fetch fresh user from server
    ///
    /// Аудит 26.07.2026 (P2): единственный ответ, где сервер сообщает
    /// авторитетную дату окончания Plink+ (`premiumUntil` в select
    /// profile.ts). Раньше она до `PremiumStatusManager` не доходила, и он
    /// узнавал дату только от `/api/billing/entitlements`. Синхронизируем
    /// здесь — новых сетевых запросов это не добавляет.
    func fetchCurrentUser() async throws -> User {
        let user: User = try await api.request("users/me", method: .get)
        cacheUser(user)
        // nil (пожизненный Plink+ или поле не пришло) = «дату не трогать».
        PremiumStatusManager.shared.syncFromServer(
            isPremium: user.isPremium,
            expiry: user.premiumUntil
        )
        return user
    }

    // 🔧 Pack v3: Update profile on server
    // 🔧 v11 (July 2026): added displayName + coverURL params (Telegram-style
    // naming split + profile cover photo).
    func updateProfile(
        username: String? = nil,
        avatarURL: String? = nil,
        displayName: String? = nil,
        coverURL: String? = nil
    ) async throws -> User {
        struct UpdateBody: Encodable {
            let username: String?
            let avatarURL: String?
            let displayName: String?
            let coverURL: String?
        }
        let body = UpdateBody(
            username: username,
            avatarURL: avatarURL,
            displayName: displayName,
            coverURL: coverURL
        )
        let user: User = try await api.request("users/me", method: .patch, body: body)
        cacheUser(user)
        return user
    }

    // 🔧 Pack v3: Update local cached user
    func updateCachedUser(_ user: User) {
        cacheUser(user)
    }

    // 🔧 Pack v3: Verify admin code
    func verifyAdminCode(email: String, code: String) async throws -> User {
        struct AdminVerifyBody: Encodable {
            let email: String
            let code: String
        }
        let body = AdminVerifyBody(email: email, code: code)
        let response: AuthResponse = try await api.request("auth/admin-verify", method: .post, body: body)

        let user = User(
            id: response.user.id,
            username: response.user.username,
            email: response.user.email,
            avatarURL: response.user.avatarURL,
            avatarData: response.user.avatarData,
            isOnline: true,
            isPremium: response.user.isPremium ?? true,
            premiumUntil: response.user.premiumUntil,
            role: response.user.role,
            createdAt: response.user.createdAt ?? Date()
        )

        let expiry = response.expiryEpochSeconds
        await cacheToken(response.token, expiry: expiry, refreshToken: response.refreshToken)
        cacheUser(user)
        return user
    }
}

// MARK: - API Request/Response Models

struct SignInRequest: Codable, Sendable {
    let email: String
    let password: String
}

struct SignUpRequest: Codable, Sendable {
    let email: String
    let password: String
    let username: String
}

struct AuthResponse: Codable, Sendable {
    let token: String
    let user: AuthUser
    /// 🔧 FIX C3: Server may also return a long-lived refresh token.
    let refreshToken: String?
    /// Аудит 26.07.2026: сервер присылает точный срок жизни access-токена
    /// (epoch в миллисекундах). Раньше клиент игнорировал поле и хардкодил
    /// 24 часа при серверном TTL в 1 час.
    let accessExpiresAt: Double?
}

extension AuthResponse {
    /// Серверный срок в секундах epoch; фолбэк — прежние 24 часа.
    var expiryEpochSeconds: TimeInterval {
        if let ms = accessExpiresAt, ms > 0 { return ms / 1000 }
        return Date().addingTimeInterval(86400).timeIntervalSince1970
    }
}

struct AuthUser: Codable, Sendable {
    let id: String
    let username: String
    let email: String
    let avatarURL: String?
    let avatarData: String?  // P0: base64 avatar support
    let isOnline: Bool?
    let isPremium: Bool?
    /// Сегодня `/auth/signin` и `/auth/signup` дату не отдают (select в
    /// auth.ts: id/username/email/role/isPremium) — поле всегда nil.
    /// Объявлено ради forward-compat: как только бэкенд начнёт её слать,
    /// дата дойдёт до PremiumStatusManager без правок клиента.
    let premiumUntil: Date?
    let role: String?
    let createdAt: Date?
}

// MARK: - Local Sign Out (for V4/V5 compatibility)
// AuthService.shared is already defined in V5/PlinkSessionSyncGate.swift

extension AuthService {
    /// Synchronous local sign-out (no network call).
    /// Clears Keychain tokens + cached user immediately.
    func signOutLocally(postNotification: Bool = true) {
        // P1 5.10: прямой delete легаси-ключа убран — clear() ниже удаляет оба.
        KeychainHelper.delete(for: Keys.tokenExpiry)
        KeychainHelper.delete(for: Keys.refreshToken)
        // Аудит 26.07.2026: без этого после выхода оставались и второй ключ
        // Keychain (`plink_auth_token`), и токен в памяти AuthTokenStore —
        // покупки, модерация и пуши продолжали ходить с токеном вышедшего
        // пользователя. clear() удаляет оба ключа и сбрасывает кэш.
        AuthTokenStore.shared.clear()
        // Событие было описано, но не вызывалось — без него не посчитать отток.
        AnalyticsService.shared.logout()
        defaults.removeObject(forKey: Keys.savedUser)
        defaults.removeObject(forKey: "plink_current_user_id")
        defaults.removeObject(forKey: "plink_current_username")
        defaults.removeObject(forKey: "plink_current_display_name")
        defaults.removeObject(forKey: "plink_current_user_role")
        authToken = nil
        tokenExpiry = 0
        refreshToken = nil
        api.authToken = nil
        currentUser = nil
        if postNotification {
            NotificationCenter.default.post(name: .plinkSignedOut, object: nil)
        }
    }
}
