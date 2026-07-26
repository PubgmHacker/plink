import Foundation

/// Social profile returned by GET /api/users/:id/profile and /users/me/profile
struct UserSocialProfile: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let avatarURL: String?
    let coverURL: String?
    let isOnline: Bool?
    let lastSeenAt: Date?
    let isPremium: Bool?
    let isDeleted: Bool?
    let friendsCount: Int
    let roomsCreated: Int
    let filmsWatched: Int
    let watchTimeMinutes: Int
    let watchHistory: [WatchHistoryEntry]
    let badges: [String]
    let joinedAt: Date?

    var deleted: Bool {
        isDeleted == true || username.hasPrefix("deleted_")
    }

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
        let watchedAt: Date?
        let roomId: String?
    }
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
}
