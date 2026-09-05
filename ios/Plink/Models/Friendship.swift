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

    /// Вторая строка в списках людей. «в сети» важнее ника и показывается
    /// всегда; ник — только когда он добавляет факт. Без этого у человека
    /// без заданного имени displayTitle сам равен username (см. выше), и
    /// ряд читался «plink_sim_demo» / «@plink_sim_demo» — одно и то же дважды.
    /// `nil` означает «второй строки нет»: высоту ряда задаёт аватар, так что
    /// список от этого не становится рваным.
    var secondaryLine: (text: String, isOnline: Bool)? {
        if deleted { return nil }
        if isOnline { return ("в сети", true) }
        let handle = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty,
              handle.caseInsensitiveCompare(displayTitle) != .orderedSame
        else { return nil }
        return ("@\(handle)", false)
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

// MARK: - Русское склонение

/// Одно правило склонения на всё приложение. Раньше каждый форматтер решал
/// сам через порог «меньше пяти» — и presence выдавал «был(а) 43 минут
/// назад», потому что 43 не попадало ни в одну ветку. Правило смотрит на
/// последнюю цифру, кроме подросткового диапазона 11–14.
enum RussianPlural {
    /// Обобщённая по типу: вызывающему бывает нужно выбрать не готовое слово,
    /// а ключ локализации — правило от этого не меняется.
    static func word<T>(_ count: Int, _ one: T, _ few: T, _ many: T) -> T {
        let mod100 = abs(count) % 100
        let mod10 = abs(count) % 10
        if mod100 >= 11 && mod100 <= 14 { return many }
        if mod10 == 1 { return one }
        if mod10 >= 2 && mod10 <= 4 { return few }
        return many
    }

    /// Число вместе со словом: «43 минуты».
    static func counted(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(count) \(word(count, one, few, many))"
    }
}

// MARK: - Presence copy (RU, Telegram-style)

enum FriendPresence {
    /// Telegram RU status line under the name in a private chat.
    static func displayText(isOnline: Bool, lastSeenAt: Date?) -> String {
        // Fresh last-seen wins over a sticky isOnline flag
        if let last = lastSeenAt {
            let sec = Date().timeIntervalSince(last)
            if sec < 0 || sec < 15 { return "в сети · можно смотреть вместе" }
            if isOnline && sec < 60 { return "в сети · можно смотреть вместе" }
            // Telegram-style: seconds for very recent
            if sec < 60 {
                let s = max(1, Int(sec))
                return "был(а) \(RussianPlural.counted(s, "секунду", "секунды", "секунд")) назад"
            }
            if sec < 3600 {
                let m = max(1, Int(sec / 60))
                return "был(а) \(RussianPlural.counted(m, "минуту", "минуты", "минут")) назад"
            }
            if sec < 86_400 {
                let h = max(1, Int(sec / 3600))
                return "был(а) \(RussianPlural.counted(h, "час", "часа", "часов")) назад"
            }
            let cal = Calendar.current
            if cal.isDateInYesterday(last) {
                let t = last.formatted(Date.FormatStyle().hour().minute())
                return "был(а) вчера в \(t)"
            }
            if sec < 86_400 * 7 {
                let d = max(1, Int(sec / 86_400))
                return "был(а) \(RussianPlural.counted(d, "день", "дня", "дней")) назад"
            }
            // Дальше недели — дата. Две правки против прежнего "d MMM":
            // месяц пишется целиком (у всех соседних веток единица времени
            // написана словом — «3 дня назад», «вчера в 21:03», — и только
            // здесь торчало «26 авг.»), а год появляется, когда он не
            // текущий: без года «был(а) 26 авг.» одинаково значило прошлый
            // август и позапрошлый.
            let df = DateFormatter()
            df.locale = Locale(identifier: "ru_RU")
            let thisYear = cal.component(.year, from: Date())
            df.dateFormat = cal.component(.year, from: last) == thisYear
                ? "d MMMM"
                : "d MMMM y"
            return "был(а) \(df.string(from: last))"
        }
        if isOnline { return "в сети · можно смотреть вместе" }
        // Telegram privacy: last-seen hidden → soft status
        return "был(а) недавно"
    }

    /// How long after a last-seen timestamp the header still reads as online.
    /// A presence heartbeat can be missed without the friend having left, so the
    /// header does not flip to "was recently" on the first gap.
    static let onlineGraceWindow: TimeInterval = 90

    /// Whether the header should render this friend as online — the dot, not the
    /// text.
    ///
    /// Callers must use this rather than comparing `headerStatus(…)` against a
    /// display string. DMChatView did exactly that (`headerPresence == "в сети"`),
    /// which reconstructed this predicate from rendered Russian copy: it broke as
    /// soon as the language changed or the copy was edited, and it silently
    /// disagreed with `headerStatus` for a friend whose `isOnline` flag was set,
    /// because that branch returns a longer string.
    static func isEffectivelyOnline(isOnline: Bool, lastSeenAt: Date?) -> Bool {
        if isOnline { return true }
        guard let last = lastSeenAt else { return false }
        // A negative interval is clock skew — the timestamp is in the future — and
        // counts as online, matching headerStatus's `sec < onlineGraceWindow`.
        return Date().timeIntervalSince(last) < onlineGraceWindow
    }

    /// Compact status for the chat header capsule (Telegram 2026 style).
    static func headerStatus(isOnline: Bool, lastSeenAt: Date?) -> String {
        if isOnline { return "в сети" }
        guard let last = lastSeenAt else { return "был(а) недавно" }
        let sec = Date().timeIntervalSince(last)
        if sec < onlineGraceWindow { return "в сети" }
        if sec < 15 * 60 { return "был(а) недавно" }
        return displayText(isOnline: false, lastSeenAt: last)
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

/// Куда открыть мессенджер: личка или группа. Не URL — пуш, колокольчик, таб.
enum PlinkChatTarget: Sendable, Equatable {
    case dm(friendId: String)
    case group(groupId: String)
}
