// Friends-tab "stories": what a friend watched over the last week (one slide
// per title, newest first) with their custom status as the opening slide.
// Mirrors GET /api/friends/stories.
import Foundation

struct FriendStorySlide: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let thumb: String?
    let kind: String?
    let watchedAt: Date?
    let roomId: String?

    var thumbURL: URL? { thumb.flatMap { URL(string: $0) } }
}

struct FriendStoryOwner: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let username: String
    let displayName: String?
    let avatarURL: String?
    let isOnline: Bool
    let lastSeenAt: Date?
    let statusText: String?
    let slides: [FriendStorySlide]

    var displayTitle: String {
        let name = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? username : name
    }
    var initials: String { String(displayTitle.prefix(1)).uppercased() }
    var trimmedStatus: String? {
        let text = (statusText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    /// A ring is drawn only for people with something to show.
    var hasStory: Bool { !slides.isEmpty || trimmedStatus != nil }
    /// Fingerprint of the current content. The seen ledger stores it, so a new
    /// watch or a changed status re-lights the ring the way Telegram does.
    var contentKey: String { ([trimmedStatus ?? ""] + slides.map(\.id)).joined(separator: "|") }
    var latestWatchedAt: Date? { slides.first?.watchedAt }

    /// Bridge into the existing friend flows (DM, watch together, profile).
    var asFriend: Friend {
        Friend(
            id: id,
            username: username,
            avatarURL: avatarURL,
            isOnline: isOnline,
            friendsSince: Date(),
            displayName: displayName,
            lastSeenAt: lastSeenAt
        )
    }
}

struct FriendStoriesResponse: Codable, Sendable {
    let me: FriendStoryOwner?
    let friends: [FriendStoryOwner]
    let windowDays: Int?
}

/// Which stories the viewer has already opened — per owner, keyed by the
/// content fingerprint, persisted in UserDefaults. Opened = grey ring.
@MainActor
final class PlinkStorySeenLedger {
    static let shared = PlinkStorySeenLedger()
    private let key = "plink_stories_seen_v1"
    private var seen: [String: String]

    private init() {
        seen = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    func isSeen(_ owner: FriendStoryOwner) -> Bool { seen[owner.id] == owner.contentKey }

    func markSeen(_ owner: FriendStoryOwner) {
        seen[owner.id] = owner.contentKey
        UserDefaults.standard.set(seen, forKey: key)
    }
}
