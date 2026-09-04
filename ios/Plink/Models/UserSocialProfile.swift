import Foundation

/// Social profile returned by GET /api/users/:id/profile and /users/me/profile
struct UserSocialProfile: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let avatarURL: String?
    let coverURL: String?
    /// Discord-style custom status (nil — not set, or an old backend).
    let statusText: String?
    let isOnline: Bool?
    let lastSeenAt: Date?
    let isPremium: Bool?
    /// Administrator seal (ADMIN / FOUNDER roles). nil — old backend.
    let isAdmin: Bool?
    let isDeleted: Bool?
    /// VK model: a closed profile shows stats, history and friends only to
    /// the owner's friends (nil — old backend, treated as open).
    let isClosed: Bool?
    /// The viewer is looking at themselves (the VK-style friends-of-friends
    /// drill can lead back to the viewer's own profile; nil — old backend).
    let isSelf: Bool?
    /// The viewer is a friend of the profile owner (nil — old backend or self).
    let isFriend: Bool?
    let friendsCount: Int
    let roomsCreated: Int
    let filmsWatched: Int
    let watchTimeMinutes: Int
    let watchHistory: [WatchHistoryEntry]
    /// Friends preview for the profile rail (up to 12; nil — old backend).
    let friends: [ProfileFriendPreview]?
    /// Earned achievement codes — the face shows them as capsules.
    let badges: [String]
    /// Every achievement with progress, earned or not (nil — old backend).
    let achievements: [Achievement]?
    /// 30-day activity digest in the viewer's calendar (nil — old backend
    /// or a closed profile seen by a stranger).
    let stats: ActivityStats?
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
        Self.durationText(minutes: watchTimeMinutes)
    }

    /// "12 ч" / "45 мин" — shared by the lifetime and the monthly figures.
    static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        if hours >= 1 { return "\(hours) ч" }
        return "\(minutes) мин"
    }

    /// Achievements for the stats screen. Old backends send only `badges`;
    /// those are mapped to fully earned achievements so the screen never
    /// goes blank behind a stale server.
    var resolvedAchievements: [Achievement] {
        if let achievements, !achievements.isEmpty { return achievements }
        return badges.compactMap { code in
            guard let badge = ProfileBadge.from(code: code) else { return nil }
            return Achievement(code: code, earned: true, progress: badge.target, target: badge.target)
        }
    }

    struct WatchHistoryEntry: Codable, Identifiable, Sendable, Equatable {
        let id: String
        let title: String
        /// Poster/banner of the media (http URL; nil — no art available).
        let thumb: String?
        /// MediaItem.mediaType at watch time: movie | series | music | video | livestream.
        let kind: String?
        let watchedAt: Date?
        let roomId: String?
    }

    /// One achievement with its progress towards the target.
    struct Achievement: Codable, Identifiable, Sendable, Equatable {
        let code: String
        let earned: Bool
        let progress: Int
        let target: Int

        var id: String { code }
        var badge: ProfileBadge? { ProfileBadge.from(code: code) }
        /// 0…1 share of the target, clamped — the bar never overflows.
        var fraction: Double {
            guard target > 0 else { return earned ? 1 : 0 }
            return min(1, max(0, Double(progress) / Double(target)))
        }
    }

    /// Activity digest: the last seven days (oldest → today), monthly
    /// totals, current daily streak and the dominant media kind.
    struct ActivityStats: Codable, Sendable, Equatable {
        let week: [Int]
        let weekFilms: Int
        let monthFilms: Int
        let monthMinutes: Int
        let streakDays: Int
        let topKind: String?

        /// Average runtime the server assumes per entry (mirrors the route).
        static let minutesPerFilm = 90

        /// Client-side twin of the backend digest, derived from the visible
        /// history. Used when the server omitted `stats` (older backend, or a
        /// closed profile whose history is still visible) so the hero figures
        /// never disagree with the rail right under them. Returns nil for an
        /// empty history — "nothing yet" is a different state than "zero".
        static func derived(from entries: [WatchHistoryEntry],
                            now: Date = Date(),
                            calendar: Calendar = .current) -> ActivityStats? {
            let dated = entries.compactMap { entry -> (day: Date, kind: String?)? in
                guard let at = entry.watchedAt else { return nil }
                return (calendar.startOfDay(for: at), entry.kind)
            }
            guard !dated.isEmpty else { return nil }
            let today = calendar.startOfDay(for: now)
            var week = Array(repeating: 0, count: 7)
            var days = Set<Date>()
            var kinds: [String: Int] = [:]
            var monthFilms = 0
            for item in dated {
                guard let age = calendar.dateComponents([.day], from: item.day, to: today).day,
                      age >= 0, age < 30 else { continue } // never count the future or >30d
                monthFilms += 1
                days.insert(item.day)
                if age < 7 { week[6 - age] += 1 }
                if let kind = item.kind { kinds[kind, default: 0] += 1 }
            }
            // Streak may be kept alive by yesterday — the day is not over yet.
            var streak = 0
            var cursor: Date? = days.contains(today)
                ? today
                : calendar.date(byAdding: .day, value: -1, to: today).flatMap { days.contains($0) ? $0 : nil }
            while let day = cursor, days.contains(day) {
                streak += 1
                cursor = calendar.date(byAdding: .day, value: -1, to: day)
            }
            let topKind = kinds.max { lhs, rhs in
                lhs.value < rhs.value || (lhs.value == rhs.value && lhs.key > rhs.key)
            }?.key
            return ActivityStats(week: week,
                                 weekFilms: week.reduce(0, +),
                                 monthFilms: monthFilms,
                                 monthMinutes: monthFilms * minutesPerFilm,
                                 streakDays: streak,
                                 topKind: topKind)
        }
    }

    /// Server digest when present, otherwise the local twin from the history.
    var resolvedStats: ActivityStats? {
        stats ?? ActivityStats.derived(from: watchHistory)
    }
}

/// A friend in the profile rail and in the full /users/:id/friends list.
struct ProfileFriendPreview: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let avatarURL: String?
    let isOnline: Bool?
    let lastSeenAt: Date?

    var displayTitle: String { displayName ?? username }
}

/// Achievement codes the server can award. "Host" achievements were
/// retired on 03.09.2026: owning a room is a plain fact, not a feat.
enum ProfileBadge: String, CaseIterable {
    case regular
    case cinemaniac
    case social
    case plink_plus

    @MainActor var title: String {
        switch self {
        case .regular: return LocalizationManager.shared.string(.badgeRegular)
        case .cinemaniac: return LocalizationManager.shared.string(.badgeCinemaniac)
        case .social: return LocalizationManager.shared.string(.badgeSocial)
        case .plink_plus: return LocalizationManager.shared.string(.badgePlinkPlus)
        }
    }

    /// How the achievement is earned — shown under the title on the stats screen.
    @MainActor var hint: String {
        switch self {
        case .regular: return LocalizationManager.shared.string(.badgeRegularHint)
        case .cinemaniac: return LocalizationManager.shared.string(.badgeCinemaniacHint)
        case .social: return LocalizationManager.shared.string(.badgeSocialHint)
        case .plink_plus: return LocalizationManager.shared.string(.badgePlinkPlusHint)
        }
    }

    var symbol: String {
        switch self {
        case .regular: return "star.fill"
        case .cinemaniac: return "film.fill"
        case .social: return "person.2.fill"
        case .plink_plus: return "sparkles"
        }
    }

    /// Mirrors ACHIEVEMENT_TARGETS on the server; used only when an old
    /// backend sends bare badge codes without progress.
    var target: Int {
        switch self {
        case .regular: return 10
        case .cinemaniac: return 100
        case .social: return 50
        case .plink_plus: return 1
        }
    }

    static func from(code: String) -> ProfileBadge? {
        ProfileBadge(rawValue: code)
    }
}

@MainActor
enum SocialProfileService {
    /// Viewer's UTC offset in minutes (Moscow = 180): the activity digest
    /// buckets days by the viewer's calendar, not the server's.
    private static var tzQuery: [String: String] {
        ["tz": String(TimeZone.current.secondsFromGMT() / 60)]
    }

    static func fetch(userId: String) async throws -> UserSocialProfile {
        try await APIClient.shared.request("users/\(userId)/profile", query: tzQuery)
    }

    static func fetchMe() async throws -> UserSocialProfile {
        try await APIClient.shared.request("users/me/profile", query: tzQuery)
    }

    /// Full friends list. Throws APIError on 403 (closed profile).
    static func fetchFriends(userId: String) async throws -> [ProfileFriendPreview] {
        struct FriendsResponse: Decodable { let friends: [ProfileFriendPreview] }
        let response: FriendsResponse = try await APIClient.shared.request("users/\(userId)/friends")
        return response.friends
    }
}
