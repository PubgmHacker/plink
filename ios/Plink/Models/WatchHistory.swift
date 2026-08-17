import Foundation

// MARK: - Watch History Item (Блок 2 — история просмотров)
/// Запись о просмотренном контенте. Хранится локально (UserDefaults).
struct WatchHistoryItem: Codable, Identifiable, Sendable {
    let id: String                 // UUID
    let mediaItemId: String
    let title: String
    let thumbnailURL: String?
    let streamURL: String
    let mediaType: String          // "movie", "music", ...
    let source: String             // "youtube", "url", ...
    let watchedAt: Date
    let watchedDuration: TimeInterval   // сколько досмотрел
    let totalDuration: TimeInterval?

    /// Вспомогательный MediaItem для пересоздания комнаты «Посмотреть снова».
    var mediaItem: MediaItem {
        MediaItem(
            id: mediaItemId,
            title: title,
            artist: nil,
            thumbnailURL: thumbnailURL,
            streamURL: streamURL,
            duration: totalDuration,
            mediaType: MediaItem.MediaType(rawValue: mediaType) ?? .video,
            source: MediaItem.MediaSource(rawValue: source) ?? .url
        )
    }

    /// Отформатированная дата просмотра.
    var formattedDate: String {
        watchedAt.formatted(.relative(presentation: .named))
    }

    /// Прогресс просмотра (0.0–1.0), если известна общая длительность.
    var progress: Double? {
        guard let total = totalDuration, total > 0 else { return nil }
        return min(watchedDuration / total, 1.0)
    }
}

// MARK: - Watch History Manager (Блок 2)
/// Локальное хранилище истории просмотров. Лимит — 50 записей (экономия RAM).
@MainActor
final class WatchHistoryManager: ObservableObject {

    static let shared = WatchHistoryManager()

    @Published private(set) var history: [WatchHistoryItem] = []

    private let defaults = UserDefaults.standard
    private let storageKey = "rave_watch_history"
    private let maxItems = 50

    init() {
        load()
    }

    // MARK: - Add

    /// Добавляет запись о просмотре (дедуплицирует по mediaItemId).
    func add(item: WatchHistoryItem) {
        history.removeAll { $0.mediaItemId == item.mediaItemId }
        history.insert(item, at: 0)

        if history.count > maxItems {
            history.removeLast(history.count - maxItems)
        }
        persist()
    }

    /// Convenience-метод для добавления по MediaItem.
    func recordWatch(mediaItem: MediaItem, watchedDuration: TimeInterval = 0) {
        let item = WatchHistoryItem(
            id: UUID().uuidString,
            mediaItemId: mediaItem.id,
            title: mediaItem.title,
            thumbnailURL: mediaItem.thumbnailURL,
            streamURL: mediaItem.streamURL,
            mediaType: mediaItem.mediaType.rawValue,
            source: mediaItem.source.rawValue,
            watchedAt: Date(),
            watchedDuration: watchedDuration,
            totalDuration: mediaItem.duration
        )
        add(item: item)
    }

    // MARK: - Remove

    func remove(_ item: WatchHistoryItem) {
        history.removeAll { $0.id == item.id }
        persist()
    }

    func clearAll() {
        history.removeAll()
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func load() {
        if let data = defaults.data(forKey: storageKey),
           let items = try? JSONDecoder().decode([WatchHistoryItem].self, from: data) {
            history = items
        }
    }
}
