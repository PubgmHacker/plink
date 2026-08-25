import Foundation

/// Social profile returned by GET /api/users/:id/profile and /users/me/profile
struct UserSocialProfile: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let avatarURL: String?
    let coverURL: String?
    /// Discord-style custom status (nil — не задан или старый бэкенд).
    let statusText: String?
    let isOnline: Bool?
    let lastSeenAt: Date?
    let isPremium: Bool?
    let isDeleted: Bool?
    /// VK-стиль: закрытый профиль — статистика, просмотры и друзья видны
    /// только друзьям владельца (nil — старый бэкенд, считаем открытым).
    let isClosed: Bool?
    /// Вьюер смотрит сам на себя (рекурсия ВК может привести к своему
    /// профилю через список друзей друга; nil — старый бэкенд).
    let isSelf: Bool?
    /// Вьюер — друг владельца профиля (nil — старый бэкенд или свой профиль).
    let isFriend: Bool?
    let friendsCount: Int
    let roomsCreated: Int
    let filmsWatched: Int
    let watchTimeMinutes: Int
    let watchHistory: [WatchHistoryEntry]
    /// Превью друзей для рельсы на профиле (до 12; nil — старый бэкенд).
    let friends: [ProfileFriendPreview]?
    let badges: [String]
    let joinedAt: Date?

    var deleted: Bool {
        isDeleted == true || username.hasPrefix("deleted_")
    }

    var closed: Bool { isClosed == true }

    var displayTitle: String {
        if deleted { return "Удалённый аккаунт" }
        return displayName ?? username
    }

    var presenceText: String {
        if deleted { return "аккаунт удалён" }
        return FriendPresence.displayText(isOnline: isOnline == true, lastSeenAt: lastSeenAt)
    }

    var watchHoursText: String {
        let hours = watchTimeMinutes / 60
        if hours >= 1 { return "\(hours) ч" }
        return "\(watchTimeMinutes) мин"
    }

    struct WatchHistoryEntry: Codable, Identifiable, Sendable, Equatable {
        let id: String
        let title: String
        /// Постер/баннер медиа (http-URL; nil — арт недоступен).
        let thumb: String?
        /// MediaItem.mediaType на момент просмотра: movie | series | music | video | livestream.
        let kind: String?
        let watchedAt: Date?
        let roomId: String?
    }
}

/// Друг в рельсе профиля и в полном списке /users/:id/friends.
struct ProfileFriendPreview: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let avatarURL: String?
    let isOnline: Bool?
    let lastSeenAt: Date?

    var displayTitle: String { displayName ?? username }
}

enum ProfileBadge: String, CaseIterable {
    case cinemaniac
    case social
    case host
    case host_rising
    case regular
    case plink_plus

    var title: String {
        switch self {
        case .cinemaniac: return "Киноман"
        case .social: return "Социальный"
        case .host: return "Хост"
        case .host_rising: return "Хост+"
        case .regular: return "Завсегдатай"
        case .plink_plus: return "Plink+"
        }
    }

    var symbol: String {
        switch self {
        case .cinemaniac: return "film.fill"
        case .social: return "person.2.fill"
        case .host, .host_rising: return "crown.fill"
        case .regular: return "star.fill"
        case .plink_plus: return "sparkles"
        }
    }

    static func from(code: String) -> ProfileBadge? {
        ProfileBadge(rawValue: code)
    }
}

@MainActor
enum SocialProfileService {
    static func fetch(userId: String) async throws -> UserSocialProfile {
        try await APIClient.shared.request("users/\(userId)/profile")
    }

    static func fetchMe() async throws -> UserSocialProfile {
        try await APIClient.shared.request("users/me/profile")
    }

    /// Полный список друзей пользователя. Бросает APIError при 403 (закрытый профиль).
    static func fetchFriends(userId: String) async throws -> [ProfileFriendPreview] {
        struct FriendsResponse: Decodable { let friends: [ProfileFriendPreview] }
        let response: FriendsResponse = try await APIClient.shared.request("users/\(userId)/friends")
        return response.friends
    }
}
