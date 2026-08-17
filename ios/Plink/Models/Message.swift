import Foundation

// MARK: - Chat Message
struct ChatMessage: Codable, Identifiable, Sendable {
    let id: String
    let roomID: String
    let senderID: String
    let senderName: String
    let text: String
    let timestamp: Date
    var isRead: Bool
    var senderAvatarURL: String?
    /// 🔧 Pack v3: Role of sender (USER/MODERATOR/ADMIN/FOUNDER) — для подсветки админов
    var senderRole: String?
    /// 🔧 v11 (July 2026): Telegram-style display name (separate from @username).
    /// Nil on old backends → falls back to senderName.
    var senderDisplayName: String?
    /// 🔧 v10 (July 2026): Bubble style — confirmed by server in processMessageStyle().
    /// Clients must render based on this value (server-confirmed), NOT on what
    /// the local user "thinks" they picked. The server may downgrade a requested
    /// style to 'default' if the user lacks permission. See BubbleStyle.swift.
    var bubbleStyle: String?

    /// 🔧 FIX: Custom CodingKeys — backend sends camelCase, but some fields
    /// might come as snake_case from older code. Also handle missing isRead
    /// (backend doesn't send it — default to false).
    enum CodingKeys: String, CodingKey {
        case id, roomID, senderID, senderName, text, timestamp
        case isRead = "is_read"  // backend doesn't send this — decodeIfPresent
        case senderAvatarURL, senderRole
        case senderDisplayName
        case bubbleStyle = "bubbleStyle"  // 🔧 v10: backend sends camelCase
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        roomID = try c.decode(String.self, forKey: .roomID)
        senderID = try c.decode(String.self, forKey: .senderID)
        senderName = try c.decode(String.self, forKey: .senderName)
        text = try c.decode(String.self, forKey: .text)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        isRead = try c.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        senderAvatarURL = try c.decodeIfPresent(String.self, forKey: .senderAvatarURL)
        senderRole = try c.decodeIfPresent(String.self, forKey: .senderRole)
        senderDisplayName = try c.decodeIfPresent(String.self, forKey: .senderDisplayName)
        // 🔧 v10: bubbleStyle is optional — old messages (pre-v10) won't have it.
        // Default to 'default' for backward compatibility.
        bubbleStyle = try c.decodeIfPresent(String.self, forKey: .bubbleStyle) ?? "default"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(roomID, forKey: .roomID)
        try c.encode(senderID, forKey: .senderID)
        try c.encode(senderName, forKey: .senderName)
        try c.encode(text, forKey: .text)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(isRead, forKey: .isRead)
        try c.encodeIfPresent(senderAvatarURL, forKey: .senderAvatarURL)
        try c.encodeIfPresent(senderRole, forKey: .senderRole)
        try c.encodeIfPresent(senderDisplayName, forKey: .senderDisplayName)
        try c.encodeIfPresent(bubbleStyle, forKey: .bubbleStyle)
    }

    // 🔧 Direct init for local messages
    init(id: String, roomID: String, senderID: String, senderName: String,
         text: String, timestamp: Date, isRead: Bool,
         senderAvatarURL: String?, senderRole: String? = nil,
         senderDisplayName: String? = nil,
         bubbleStyle: String? = nil) {
        self.id = id
        self.roomID = roomID
        self.senderID = senderID
        self.senderName = senderName
        self.text = text
        self.timestamp = timestamp
        self.isRead = isRead
        self.senderAvatarURL = senderAvatarURL
        self.senderRole = senderRole
        self.senderDisplayName = senderDisplayName
        self.bubbleStyle = bubbleStyle ?? "default"
    }

    /// 🔧 Pack v3: True если отправитель — админ
    var isSenderAdmin: Bool {
        (senderRole ?? "").uppercased() == "ADMIN" || (senderRole ?? "").uppercased() == "FOUNDER"
    }

    /// 🔧 v11: Telegram-style display name — prefer senderDisplayName, fall back to senderName.
    /// UI code should use this for showing the sender's name in chat bubbles.
    var displaySenderName: String {
        (senderDisplayName?.isEmpty == false) ? senderDisplayName! : senderName
    }

    /// 🔧 v10 → V5: bubble style ID is now used directly as a string.
    /// The old `BubbleStyle` enum and `effectiveBubbleStyle` accessor have been
    /// removed. Use `BubbleStyleRegistry.safeDescriptor(id: message.bubbleStyle)`
    /// to resolve the descriptor for rendering. Legacy backend IDs (`default`,
    /// `cute_duck`, `neon_cyber`, `admin_bubble`) are migrated automatically
    /// via `BubbleStyleRegistry.migrateLegacyID(_:)`.
    var bubbleStyleID: String? { bubbleStyle }

    var timeString: String {
        timestamp.formatted(.dateTime.hour().minute())
    }

    /// Первые инициалы имени для fallback-аватарки
    var initials: String {
        let parts = senderName.split(separator: " ")
        let letters = parts.compactMap { $0.first }.prefix(2)
        return letters.map { String($0).uppercased() }.joined()
    }

    static var preview: ChatMessage {
        ChatMessage(
            id: "msg_001",
            roomID: "room_001",
            senderID: "user_001",
            senderName: "Alex",
            text: "This is awesome! 🎬",
            timestamp: .now.addingTimeInterval(-120),
            isRead: true,
            senderAvatarURL: nil
        )
    }
}

// MARK: - System Message (join/leave notifications)
struct SystemMessage: Identifiable, Sendable {
    let id = UUID().uuidString
    let roomID: String
    let text: String
    let timestamp: Date

    var timeString: String {
        timestamp.formatted(.dateTime.hour().minute())
    }
}

// MARK: - Chat Payload (WebSocket outbound)
/// Сетевая структура для отправки текстовых сообщений через WebSocket.
/// JSON-схема совпадает с бэкенд-типом `ChatPayload` (server/src/types/index.ts):
///   { type, roomID, senderID, senderName, text, bubbleStyle }
///
/// 🔧 v10 (July 2026): added `bubbleStyle` field. This is the user's REQUESTED
/// style — the server runs processMessageStyle() on it and may downgrade to
/// 'default'. The server-confirmed style comes back in the broadcast
/// ChatMessage's `bubbleStyle` field, which is what clients should render.
struct ChatPayload: Codable, Sendable {
    let type: String          // всегда "chat"
    let roomID: String
    let senderID: String
    let senderName: String
    let text: String
    /// 🔧 v10: requested bubble style (HINT to server). Server may override.
    /// For backward compatibility with old backends, this field is optional
    /// in the JSON — old backends will simply ignore it.
    let bubbleStyle: String?
}
