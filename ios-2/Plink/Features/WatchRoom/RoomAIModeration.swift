// Plink/Features/WatchRoom/RoomAIModeration.swift — M16
// ИИ-модератор: события мута едут по чат-протоколу (как poll/countdown/priv).
// Сервер шлёт chat.broadcast от "plink-ai-moderator" с маркером + JSON.

import Foundation

enum RoomAIModWire {
    static let marker = "\u{2063}plink.mod\u{2063}"

    struct Event: Codable {
        let action: String      // "mute"
        let userId: String      // кого замутили
        let username: String
        let seconds: Int
        let reason: String      // "profanity" | "nsfw_image"
    }

    static func decode(_ text: String) -> Event? {
        guard text.hasPrefix(marker) else { return nil }
        let json = String(text.dropFirst(marker.count))
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Event.self, from: data)
    }

    static func reasonText(_ reason: String) -> String {
        switch reason {
        case "profanity": return "нецензурная лексика"
        case "nsfw_image": return "запрещённое фото"
        default: return "нарушение правил"
        }
    }
}
