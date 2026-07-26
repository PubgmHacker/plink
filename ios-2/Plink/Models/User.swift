import Foundation

// MARK: - User Model
//
// 🔧 v11 (July 2026): Telegram-style naming split.
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
    /// P0: Base64 avatar data stored in DB (replaces filesystem for Railway persistence)
    let avatarData: String?
    /// 🔧 v11: Telegram-style display name (separate from @username).
    /// nil on old backends → falls back to username.
    let displayName: String?
    /// 🔧 v11: profile cover photo URL (background banner on profile screen).
    let coverURL: String?
    let isOnline: Bool
    let isPremium: Bool
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
        case isOnline, isPremium, role, createdAt
    }

    init(id: String, username: String, email: String, avatarURL: String?,
         avatarData: String? = nil,
         displayName: String? = nil, coverURL: String? = nil,
         isOnline: Bool, isPremium: Bool, role: String? = nil, createdAt: Date) {
        self.id = id
        self.username = username
        self.email = email
        self.avatarURL = avatarURL
        self.avatarData = avatarData
        self.displayName = displayName
        self.coverURL = coverURL
        self.isOnline = isOnline
        self.isPremium = isPremium
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
        // 🔧 v11: optional fields, fall back gracefully on old backends
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        coverURL = try container.decodeIfPresent(String.self, forKey: .coverURL)
        isOnline = try container.decodeIfPresent(Bool.self, forKey: .isOnline) ?? true
        isPremium = try container.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        role = try container.decodeIfPresent(String.self, forKey: .role)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
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
        try container.encodeIfPresent(role, forKey: .role)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - Minimal User (for room participants list)
struct UserPreview: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let username: String
    let avatarURL: String?
    let avatarData: String?  // P0: base64 support
    /// 🔧 v11: optional display name (back-compat: nil on old backends)
    let displayName: String?
    let isOnline: Bool

    /// Display title — same logic as User.displayTitle
    var displayTitle: String {
        displayName?.isEmpty == false ? displayName! : username
    }

    /// 🔧 v11: explicit init with displayName defaulting to nil.
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
