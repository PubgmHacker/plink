import Foundation
import SwiftUI

// MARK: - Watchlist «Посмотреть позже» (M14)
/// Локальное хранилище отложенных видео. Лимит — 100 записей.
@MainActor
final class WatchlistService: ObservableObject {
    static let shared = WatchlistService()

    struct Entry: Codable, Identifiable, Sendable {
        let id: String          // mediaItem.id
        let mediaItem: MediaItem
        let addedAt: Date
    }

    @Published private(set) var entries: [Entry] = []
    private let storageKey = "plink.watchlist.v1"
    private let maxItems = 100

    private init() { load() }

    func contains(_ mediaId: String) -> Bool {
        entries.contains { $0.id == mediaId }
    }

    /// Добавить/убрать одним тапом (bookmark toggle).
    func toggle(_ item: MediaItem) {
        if contains(item.id) { remove(item.id) } else { add(item) }
    }

    func add(_ item: MediaItem) {
        guard !contains(item.id) else { return }
        entries.insert(Entry(id: item.id, mediaItem: item, addedAt: Date()), at: 0)
        if entries.count > maxItems { entries.removeLast(entries.count - maxItems) }
        save()
        HapticManager.impact(.light)
    }

    func remove(_ mediaId: String) {
        entries.removeAll { $0.id == mediaId }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = items
    }
}

// MARK: - Pending Resume («Продолжить просмотр»)
/// Одноразовая заявка «продолжить с таймкода». Ставится перед созданием
/// комнаты из истории; комната-хост забирает её после подключения и
/// делает синхронизированный seek для всех участников.
enum PlinkPendingResume {
    private static let key = "plink.pendingResume.v1"

    struct Payload: Codable {
        let mediaId: String
        let seconds: Double
        let setAt: Date
    }

    static func set(mediaId: String, seconds: Double) {
        let payload = Payload(mediaId: mediaId, seconds: seconds, setAt: Date())
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Забрать и очистить. Протухает через 10 минут; мелкие таймкоды игнорируются.
    static func take() -> Payload? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        guard Date().timeIntervalSince(payload.setAt) < 600, payload.seconds > 15 else { return nil }
        return payload
    }
}
