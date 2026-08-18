import Foundation

// MARK: - User Model
//
// Telegram-style naming split.
//   - `username`  → unique @tag (e.g. "@alex_films"), used for search/friends/deeplinks
//   - `displayName` → human-readable nick (e.g. "Alex Films"), shown in chat/profile
//
// Before v11, `username` was used for both — confusing because users couldn't have
// a fancy display name with spaces/emoji separate from their unique @tag.
//
// `displayName` is OPTIONAL in JSON — old backends (pre-v11) don't send it,
// so we fall back to `username` for backward compatibility.

struct User: Codable, Identifiable, Sendable {
    let id: String
    let username: String          // unique @tag, e.g. "alex_films"
    let email: String
    let avatarURL: String?
    /// Base64 avatar bytes, stored in the database rather than on disk: the
    /// deployment target has an ephemeral filesystem, so an uploaded file is gone
    /// on the next deploy.
    let avatarData: String?
    /// Telegram-style display name (separate from @username).
    /// nil on old backends → falls back to username.
    let displayName: String?
    /// Profile cover photo URL (background banner on profile screen).
    let coverURL: String?
    let isOnline: Bool
    let isPremium: Bool
    /// Авторитетная дата окончания Plink+ с сервера (`GET /users/me`,
    /// `PATCH /users/me`). nil означает одно из трёх:
    ///   - сервер поле не прислал (`/auth/signin`, `/auth/signup` его не отдают);
    ///   - `premiumUntil = null` в БД, а `isPremium = true` → пожизненный доступ;
    ///   - Plink+ вообще нет.
    /// Во всех трёх случаях клиент трактует nil как «дату не трогаем»
    /// (см. `PremiumStatusManager.syncFromServer`).
    let premiumUntil: Date?
    let role: String?
    let createdAt: Date

    /// Initials for avatar placeholder — prefer displayName, fall back to username.
    var initials: String {
        let source = (displayName?.isEmpty == false ? displayName : username) ?? ""
        let parts = source.split(separator: " ")
        let letters = parts.compactMap { $0.first }.prefix(2)
        return letters.map { String($0).uppercased() }.joined()
    }

    /// Display name shown in UI — Telegram-style: displayName if set, else username.
    /// This is the ONLY property UI code should use for "what to show as the name".
    var displayTitle: String {
        displayName?.isEmpty == false ? displayName! : username
    }

    /// @-prefixed tag for search/deeplinks — same as username but with leading @.
    var atTag: String {
        "@\(username)"
    }

    /// True if user has admin role
    var isAdmin: Bool {
        (role ?? "").uppercased() == "ADMIN" || (role ?? "").uppercased() == "FOUNDER"
    }

    var shortId: String {
        guard id.count >= 12 else { return "#\(id)" }
        let short = String(id.suffix(8))
        return "#\(short)"
    }

    var fullId: String {
        id
    }

    static var preview: User {
        User(
            id: "user_001",
            username: "alex_films",
            email: "alex@example.com",
            avatarURL: nil,
            displayName: "Alex Films",
            coverURL: nil,
            isOnline: true,
            isPremium: false,
            role: nil,
            createdAt: Date()
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, username, email, avatarURL
        case avatarData
        case displayName
        case coverURL
        case isOnline, isPremium
        case premiumUntil
        case role, createdAt
    }

    init(id: String, username: String, email: String, avatarURL: String?,
         avatarData: String? = nil,
         displayName: String? = nil, coverURL: String? = nil,
         isOnline: Bool, isPremium: Bool, premiumUntil: Date? = nil,
         role: String? = nil, createdAt: Date) {
        self.id = id
        self.username = username
        self.email = email
        self.avatarURL = avatarURL
        self.avatarData = avatarData
        self.displayName = displayName
        self.coverURL = coverURL
        self.isOnline = isOnline
        self.isPremium = isPremium
        self.premiumUntil = premiumUntil
        self.role = role
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        email = try container.decode(String.self, forKey: .email)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        avatarData = try container.decodeIfPresent(String.self, forKey: .avatarData)
        // Optional fields, fall back gracefully on old backends
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        coverURL = try container.decodeIfPresent(String.self, forKey: .coverURL)
        isOnline = try container.decodeIfPresent(Bool.self, forKey: .isOnline) ?? true
        isPremium = try container.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        premiumUntil = Self.decodeLenientDate(container, forKey: .premiumUntil)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    /// Дата, которая НИКОГДА не роняет декодирование всей модели.
    ///
    /// Причина: `User` декодируют разные JSONDecoder'ы с разной
    /// `dateDecodingStrategy`. APIClient использует кастомную стратегию с
    /// `.withFractionalSeconds` (сервер отдаёт JS `toISOString()`:
    /// «2026-08-25T10:00:00.000Z»), а вот кэш профиля и сторонние вызовы
    /// `JSONDecoder()` — стратегию по умолчанию, которая на такой строке
    /// бросает `typeMismatch`. Обязательное `createdAt` из-за этого уже
    /// теряется молча; новое поле Plink+ такой хрупкости добавлять не должно.
    ///
    /// Порядок: сначала текущая стратегия декодера, затем ручной разбор
    /// ISO8601 (с миллисекундами и без). Не разобрали → nil = «сервер даты
    /// не сообщил», что для `syncFromServer` означает «не трогать».
    private static func decodeLenientDate(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key),
              !raw.isEmpty else { return nil }
        return iso8601Date(from: raw)
    }

    /// ISO8601 с миллисекундами и без. Форматтеры создаются локально —
    /// `ISO8601DateFormatter` не Sendable, разделяемый static сломал бы
    /// строгую проверку конкурентности.
    static func iso8601Date(from raw: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }

    /// Разбор профиля из кэша `rave_saved_user` (UserDefaults).
    ///
    /// Кэш пишется `JSONEncoder` со стратегией `.iso8601`,
    /// а читали его голым `JSONDecoder()` со стратегией `.deferredToDate` — на
    /// `createdAt` всегда прилетал typeMismatch, ошибка глоталась через `try?`,
    /// и фолбэк «узнать свой userID без сети» был мёртвым во всех четырёх местах,
    /// где его звали. Здесь стратегия согласована с записью.
    /// Принимает обе формы записи, которые встречаются в кэше: ISO8601-строку
    /// (`JSONEncoder` со стратегией `.iso8601` — так пишет `AuthService.cacheUser`)
    /// и число секунд от reference date (стратегия по умолчанию `.deferredToDate`,
    /// которой пользуются остальные места записи). Раньше читатель понимал только
    /// вторую форму и молча возвращал nil на продовых данных.
    static func decodeCached(_ data: Data) -> User? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let raw = try? container.decode(String.self) {
                guard let date = iso8601Date(from: raw) else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: decoder.codingPath, debugDescription: "Не ISO8601: \(raw)")
                    )
                }
                return date
            }
            let seconds = try container.decode(Double.self)
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        return try? decoder.decode(User.self, from: data)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(email, forKey: .email)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try container.encodeIfPresent(avatarData, forKey: .avatarData)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(coverURL, forKey: .coverURL)
        try container.encode(isOnline, forKey: .isOnline)
        try container.encode(isPremium, forKey: .isPremium)
        try container.encodeIfPresent(premiumUntil, forKey: .premiumUntil)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - Minimal User (for room participants list)
struct UserPreview: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let username: String
    let avatarURL: String?
    let avatarData: String?  // Base64, as in `User` above.
    /// Optional display name (back-compat: nil on old backends)
    let displayName: String?
    let isOnline: Bool

    /// Display title — same logic as User.displayTitle
    var displayTitle: String {
        displayName?.isEmpty == false ? displayName! : username
    }

    /// Explicit init with displayName defaulting to nil.
    init(id: String, username: String, avatarURL: String?,
         avatarData: String? = nil, displayName: String? = nil, isOnline: Bool) {
        self.id = id
        self.username = username
        self.avatarURL = avatarURL
        self.avatarData = avatarData
        self.displayName = displayName
        self.isOnline = isOnline
    }

    static var preview: UserPreview {
        UserPreview(id: "user_002", username: "jordan", avatarURL: nil, displayName: nil, isOnline: true)
    }
}
