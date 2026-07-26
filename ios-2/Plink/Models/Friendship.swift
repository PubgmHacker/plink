import Foundation

// MARK: - Friendship Models (Блок 3 — социальный слой)
/// Статусы дружбы между пользователями.
enum FriendshipStatus: String, Codable, Sendable {
    case pending      // Заявка отправлена, ждёт ответа
    case accepted     // Дружба подтверждена
    case declined     // Заявка отклонена
    case blocked      // Пользователь заблокирован
}

// MARK: - Friend
/// Полноценный друг (с подтверждённой дружбой).
struct Friend: Codable, Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let username: String
    let avatarURL: String?
    let isOnline: Bool
    let friendsSince: Date
    /// Optional Telegram-style display name (may be nil on older payloads).
    var displayName: String? = nil
    /// ISO last-seen from server (nil if unknown).
    var lastSeenAt: Date? = nil
    /// Server pin flag (optional — local FriendPinStore is authoritative for UI order).
    var isPinned: Bool? = nil
    /// Lower = higher among pinned (server).
    var pinOrder: Int? = nil
    /// Server avatar revision (ms). Changes only when friend uploads a new photo.
    var avatarVersion: Int64? = nil
    /// Telegram soft-delete tombstone.
    var isDeleted: Bool? = nil

    /// Конвертация в UserPreview для UI-компонентов.
    var asUserPreview: UserPreview {
        UserPreview(id: id, username: username, avatarURL: avatarURL, isOnline: isOnline)
    }

    var deleted: Bool {
        if isDeleted == true { return true }
        return username.hasPrefix("deleted_")
    }

    /// Name shown in UI — displayName if set, else @username.
    var displayTitle: String {
        if deleted { return "Удалённый аккаунт" }
        if let d = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            return d
        }
        return username
    }

    /// Single letter for avatar fallback — never uses current user.
    var initials: String {
        if deleted { return "—" }
        return PlinkAvatarURL.letter(from: displayTitle)
    }

    /// «В сети» / «Был(а) N мин. назад» / «Не в сети»
    var presenceText: String {
        if deleted { return "аккаунт удалён" }
        return FriendPresence.displayText(isOnline: isOnline, lastSeenAt: lastSeenAt)
    }
}

// MARK: - Presence copy (RU, Telegram-style)

enum FriendPresence {
    /// Telegram RU status line under the name in a private chat.
    static func displayText(isOnline: Bool, lastSeenAt: Date?) -> String {
        // Fresh last-seen wins over a sticky isOnline flag
        if let last = lastSeenAt {
            let sec = Date().timeIntervalSince(last)
            if sec < 0 || sec < 15 { return "в сети" }
            if isOnline && sec < 60 { return "в сети" }
            // Telegram-style: seconds for very recent
            if sec < 60 {
                let s = max(1, Int(sec))
                if s == 1 { return "был(а) 1 секунду назад" }
                if s < 5 { return "был(а) \(s) секунды назад" }
                if s < 20 { return "был(а) \(s) секунд назад" }
                return "был(а) \(s) секунд назад"
            }
            if sec < 3600 {
                let m = max(1, Int(sec / 60))
                if m == 1 { return "был(а) 1 минуту назад" }
                if m < 5 { return "был(а) \(m) минуты назад" }
                return "был(а) \(m) минут назад"
            }
            if sec < 86_400 {
                let h = max(1, Int(sec / 3600))
                if h == 1 { return "был(а) 1 час назад" }
                if h < 5 { return "был(а) \(h) часа назад" }
                return "был(а) \(h) часов назад"
            }
            let cal = Calendar.current
            if cal.isDateInYesterday(last) {
                let t = last.formatted(Date.FormatStyle().hour().minute())
                return "был(а) вчера в \(t)"
            }
            if sec < 86_400 * 7 {
                let d = max(1, Int(sec / 86_400))
                return "был(а) \(d) \(dayWord(d)) назад"
            }
            let df = DateFormatter()
            df.locale = Locale(identifier: "ru_RU")
            df.dateFormat = "d MMM"
            return "был(а) \(df.string(from: last))"
        }
        if isOnline { return "в сети" }
        // Telegram privacy: last-seen hidden → soft status
        return "был(а) недавно"
    }

    /// Compact status for the chat header capsule (Telegram 2026 style).
    static func headerStatus(isOnline: Bool, lastSeenAt: Date?) -> String {
        if isOnline { return "в сети" }
        guard let last = lastSeenAt else { return "был(а) недавно" }
        let sec = Date().timeIntervalSince(last)
        if sec < 90 { return "в сети" }
        if sec < 15 * 60 { return "был(а) недавно" }
        return displayText(isOnline: false, lastSeenAt: last)
    }

    private static func dayWord(_ d: Int) -> String {
        let n = d % 100
        let n1 = d % 10
        if n > 10 && n < 20 { return "дней" }
        if n1 == 1 { return "день" }
        if n1 >= 2 && n1 <= 4 { return "дня" }
        return "дней"
    }
}

// MARK: - Friend Request
/// Входящая или исходящая заявка в друзья.
struct FriendRequest: Codable, Identifiable, Sendable {
    let id: String              // ID заявки
    let fromUser: UserPreview   // Кто отправил
    let toUser: UserPreview     // Кому отправлено
    let status: FriendshipStatus
    let createdAt: Date

    var isIncoming: Bool {
        // Определяется контекстом (входящие vs исходящие списки).
        true
    }

    var formattedDate: String {
        createdAt.formatted(.relative(presentation: .named))
    }
}

// MARK: - Friendship Link Type (для Deep-Linking)
/// Тип ссылки-приглашения (Блок 3 — Universal Links).
enum DeepLinkType: Sendable, Equatable {
    case room(code: String)        // https://yourdomain.com/r/<code>
    case friendInvite(userId: String)  // https://yourdomain.com/u/<userId>
    case none
}
