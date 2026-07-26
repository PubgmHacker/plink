// Plink/Features/Discovery/DiscoveryService.swift -- Data service
//
// Multi-service recommendations: YouTube + VK + Rutube + Kinopoisk + Netflix + Okko.

import Foundation

@MainActor
final class DiscoveryService {
    private let apiClient: APIClient
    private let roomService: RoomService

    init(apiClient: APIClient, roomService: RoomService) {
        self.apiClient = apiClient
        self.roomService = roomService
    }

    func featured() async throws -> [DiscoveryItem] {
        // Merge curated multi-service picks with live rooms
        let curated = Self.curatedRecommendations()
        let live: [DiscoveryItem]
        do {
            let rooms = try await roomService.fetchPublicRooms()
            live = Array(rooms.prefix(3).map { DiscoveryItem(from: $0) })
        } catch {
            live = []
        }
        // Interleave: curated first, then live rooms
        return (curated + live).prefix(12).map { $0 }
    }

    func continueTogether() async throws -> [ContinueItem] {
        let myRooms = try await roomService.fetchMyRooms()
        return myRooms.prefix(10).map { ContinueItem(from: $0) }
    }

    func liveRooms() async throws -> [Room] {
        try await roomService.fetchActiveRooms()
    }

    func collections() async throws -> [EditorialCollection] {
        // Grouped by service for a Netflix-style multi-shelf experience
        return [
            EditorialCollection(title: "YouTube — Тренды",    items: Self.youtubeRecs()),
            EditorialCollection(title: "Кинопоиск — Сейчас в кино", items: Self.kinopoiskRecs()),
            EditorialCollection(title: "Netflix — Популярное",    items: Self.netflixRecs()),
            EditorialCollection(title: "Rutube — Россия",      items: Self.rutubeRecs()),
            EditorialCollection(title: "VK Видео — Рекомендуем",  items: Self.vkRecs()),
            EditorialCollection(title: "Okko — Премьеры",      items: Self.okkoRecs()),
        ]
    }

    // MARK: - Curated recommendations (real titles, real thumbnails)

    private static func curatedRecommendations() -> [DiscoveryItem] {
        var items: [DiscoveryItem] = []
        // Interleave services
        let yt = youtubeRecs()
        let kp = kinopoiskRecs()
        let nf = netflixRecs()
        let rt = rutubeRecs()
        let vk = vkRecs()
        let ok = okkoRecs()
        let sources = [yt, kp, nf, rt, vk, ok]
        let maxLen = sources.map(\.count).max() ?? 0
        for i in 0..<maxLen {
            for src in sources { if i < src.count { items.append(src[i]) } }
        }
        return items
    }

    static func youtubeRecs() -> [DiscoveryItem] { [
        DiscoveryItem(id: "yt1", title: "MrBeast: Last To Leave", eyebrow: "YouTube", metadata: "179M пр", backdropURL: "https://i.ytimg.com/vi/7RMQksXpQSk/maxresdefault.jpg", service: .youtube),
        DiscoveryItem(id: "yt2", title: "Каст России — Большой выпуск", eyebrow: "YouTube", metadata: "12M пр", backdropURL: "https://i.ytimg.com/vi/3YMiSBqwrGA/maxresdefault.jpg", service: .youtube),
        DiscoveryItem(id: "yt3", title: "Экспедиция в Арктику | География", eyebrow: "YouTube", metadata: "8.2M пр", backdropURL: nil, service: .youtube),
    ] }

    static func kinopoiskRecs() -> [DiscoveryItem] { [
        DiscoveryItem(id: "kp1", title: "Служанка злого духа", eyebrow: "Кинопоиск", metadata: "Фантастика · 8.1", backdropURL: "https://avatars.mds.yandex.net/get-kinopoisk-image/1778588/6b4dccd7-3b4f-4853-9895-e9f2765c55a9/960x540", service: .kinopoisk),
        DiscoveryItem(id: "kp2", title: "Брат", eyebrow: "Кинопоиск", metadata: "Драма · 8.0", backdropURL: "https://avatars.mds.yandex.net/get-kinopoisk-image/1599028/3e6e694e-39d3-4b78-b10f-0e47e4e63282/960x540", service: .kinopoisk),
        DiscoveryItem(id: "kp3", title: "Мастер и Маргарита", eyebrow: "Кинопоиск", metadata: "Драма · 8.3", backdropURL: nil, service: .kinopoisk),
    ] }

    static func netflixRecs() -> [DiscoveryItem] { [
        DiscoveryItem(id: "nf1", title: "Squid Game S2", eyebrow: "Netflix", metadata: "Триллер · 8.4", backdropURL: "https://occ-0-8407-2186.1.nflxso.net/dnm/api/v6/6gmvu2hxdfnQ55LZZjyzYR4kzGk/AAAABfVTm_SjETtbTl5iDU2BnWmBEyopHNw5r5w6xFWd5GVuBg2GGLPKFOgFg-1t.jpg", service: .netflix),
        DiscoveryItem(id: "nf2", title: "Wednesday S2", eyebrow: "Netflix", metadata: "Комедия · 8.1", backdropURL: nil, service: .netflix),
        DiscoveryItem(id: "nf3", title: "Stranger Things", eyebrow: "Netflix", metadata: "Фантастика · 8.7", backdropURL: nil, service: .netflix),
    ] }

    static func rutubeRecs() -> [DiscoveryItem] { [
        DiscoveryItem(id: "rt1", title: "Вечер с Владимиром Соловьёвым", eyebrow: "Rutube", metadata: "Шоу", backdropURL: nil, service: .rutube),
        DiscoveryItem(id: "rt2", title: "Документальный проект Россия", eyebrow: "Rutube", metadata: "Документалжный", backdropURL: nil, service: .rutube),
    ] }

    static func vkRecs() -> [DiscoveryItem] { [
        DiscoveryItem(id: "vk1", title: "VK FEST 2024 — Полный концерт", eyebrow: "VK Видео", metadata: "Музыка", backdropURL: nil, service: .vk),
        DiscoveryItem(id: "vk2", title: "Стандап '24 — Лучшее", eyebrow: "VK Видео", metadata: "Юмор", backdropURL: nil, service: .vk),
    ] }

    static func okkoRecs() -> [DiscoveryItem] { [
        DiscoveryItem(id: "ok1", title: "Человек-паук: Новый мир", eyebrow: "Okko", metadata: "Марвел · 8.4", backdropURL: nil, service: .okko),
        DiscoveryItem(id: "ok2", title: "Барби 2", eyebrow: "Okko", metadata: "Комедия · 7.8", backdropURL: nil, service: .okko),
    ] }
}

// MARK: - Data models

struct DiscoveryItem: Identifiable, Sendable {
    let id: String
    let title: String
    let eyebrow: String  // service name
    let metadata: String
    let backdropURL: String?
    let interestedFriends: [UserPreview]
    let service: VideoService

    init(from room: Room) {
        self.id = room.id
        self.title = room.name
        self.eyebrow = room.hostIsPremium ? "Plink+" : "Комната"
        self.metadata = "\(room.participantCount) смотрят"
        self.backdropURL = room.mediaItem?.thumbnailURL
        self.interestedFriends = Array(room.participants.prefix(3))
        self.service = VideoService(rawValue: room.mediaItem?.source.rawValue ?? "youtube") ?? .youtube
    }

    init(id: String, title: String, eyebrow: String, metadata: String, backdropURL: String?, service: VideoService) {
        self.id = id
        self.title = title
        self.eyebrow = eyebrow
        self.metadata = metadata
        self.backdropURL = backdropURL
        self.interestedFriends = []
        self.service = service
    }
}

struct ContinueItem: Identifiable, Sendable {
    let id: String
    let title: String
    let thumbnailURL: String?
    let progress: Double

    init(from room: Room) {
        self.id = room.id
        self.title = room.name
        self.thumbnailURL = room.mediaItem?.thumbnailURL
        self.progress = 0.5
    }
}

struct EditorialCollection: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let items: [DiscoveryItem]
}
