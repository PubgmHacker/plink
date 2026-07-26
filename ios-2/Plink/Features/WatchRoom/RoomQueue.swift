// Plink/Features/WatchRoom/RoomQueue.swift — M16
// Очередь видео комнаты: ИИ-ассистент и участники ставят ролики в очередь,
// апдейты едут по чат-протоколу (как poll/mod/priv) с маркером + JSON.

import Foundation

enum RoomQueueWire {
    static let marker = "\u{2063}plink.queue\u{2063}"

    struct Item: Codable, Identifiable, Equatable {
        let id: String
        let title: String
        let streamURL: String
        let source: String
        let addedBy: String
        let addedAtMs: Double
        /// M18: элемент поставлен с приоритетом Plink+.
        let priority: Bool?
    }

    struct Event: Codable {
        let queue: [Item]
        /// M17: хост нажал «включить сейчас» — сервер промоутит элемент в начало.
        let nowPlaying: Item?
    }

    static func decode(_ text: String) -> Event? {
        guard text.hasPrefix(marker) else { return nil }
        let json = String(text.dropFirst(marker.count))
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Event.self, from: data)
    }
}
