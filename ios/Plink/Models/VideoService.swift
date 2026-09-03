import Foundation
import SwiftUI

// MARK: - Playback Mode
/// Как сервис воспроизводится. Определяет технический путь.
///
/// Трансляции экрана в Plink нет и не будет: комната синхронизирует ВРЕМЯ,
/// а картинку каждый участник получает от самого сервиса. Поэтому режимов
/// ровно два — прямой поток и страница сервиса в плеере комнаты.
enum PlaybackMode: String, Sendable {
    /// Прямой поток в AVPlayer (YouTube через extraction, MP4/M3U8/HLS).
    case directStream
    /// Официальный плеер сервиса в WebView, синхронизируемый через JS-мост
    /// (кинотеатры, VK, Rutube, произвольная страница).
    case webview
}

// MARK: - Delivery bucket (честная витрина)
/// Продуктовая группировка: что открыто всем, а что живёт по подписке.
/// Сервисы из каталога НЕ удаляются — меняется только обещание после выбора.
enum DeliveryBucket: String, CaseIterable, Identifiable, Sendable {
    case worksNow
    case bySubscription

    var id: String { rawValue }

    @MainActor
    var sectionTitle: String {
        switch self {
        case .worksNow: return "ОТКРЫТО ВСЕМ"
        case .bySubscription: return "ПО ПОДПИСКЕ · КИНОТЕАТРЫ"
        }
    }

    @MainActor
    var sectionSubtitle: String {
        switch self {
        case .worksNow:
            return "Играет у всех сразу — выбирайте и смотрите вместе"
        case .bySubscription:
            return "Плеер сервиса открывается прямо в комнате. Каждый входит в свой аккаунт — Plink держит общее время."
        }
    }
}

// MARK: - Smart Wall Service Type

/// Service access type for Lazy Auth / Smart Wall.
/// Mirrors VideoService so existing room creation code can keep using VideoService.
enum ServiceType: String, CaseIterable, Identifiable, Sendable, Codable, Equatable, Hashable {
    case youtube
    case vk
    case rutube
    case netflix
    case disney
    case browser
    case customURL = "custom"
    case kinopoisk
    case ivi
    case okko
    case wink
    case start
    case premier
    case smotrim
    case kion

    var id: String { rawValue }

    init(service: VideoService) {
        self = ServiceType(rawValue: service.rawValue) ?? .youtube
    }

    /// True when host must authenticate with the external content service.
    var requiresAuth: Bool {
        switch self {
        case .youtube, .vk, .rutube, .smotrim, .browser, .customURL:
            return false
        case .netflix, .disney, .kinopoisk, .ivi, .okko, .wink, .start, .premier, .kion:
            return true
        }
    }
}

// MARK: - Service Auth Store

enum ServiceAuthStore {
    private static let yandexKey = "plink.service_auth.yandex_id"

    private static func key(for service: ServiceType) -> String {
        "plink.service_auth.\(service.rawValue)"
    }

    static var hasYandexID: Bool {
        UserDefaults.standard.bool(forKey: yandexKey)
    }

    static func markYandexID(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: yandexKey)
    }

    static func hasAccess(to service: ServiceType) -> Bool {
        guard service.requiresAuth else { return true }
        // Кинопоиск сидит на Яндекс ID — отдельный логин не нужен.
        if service == .kinopoisk && hasYandexID { return true }
        return UserDefaults.standard.bool(forKey: key(for: service))
    }

    static func markAuthorized(_ service: ServiceType) {
        UserDefaults.standard.set(true, forKey: key(for: service))
    }

    static func logout(_ service: ServiceType) {
        UserDefaults.standard.removeObject(forKey: key(for: service))
    }

    static var allAuthorizedServices: [ServiceType] {
        ServiceType.allCases.filter { hasAccess(to: $0) && $0.requiresAuth }
    }
}

// MARK: - Video Service
/// Поддерживаемые видеосервисы для выбора при создании комнаты.
///
/// Группировка:
/// - `.direct`: YouTube, VK Видео, RuTube — извлекаем прямой поток.
/// - `.cinema`: Кинопоиск, Иви, Okko, Wink, Start, Premier, Смотрим, КИОН — WebView + своя подписка.
/// - `.universal`: Браузер, Своя ссылка.
enum VideoService: String, CaseIterable, Identifiable, Sendable, Codable, Equatable, Hashable {
    // Прямые потоки
    case youtube
    case vk
    case rutube
    case netflix
    case disney

    // Универсальные
    case browser
    case customURL = "custom"

    // Кинотеатры (WebView)
    case kinopoisk
    case ivi
    case okko
    case wink
    case start
    case premier
    case smotrim
    case kion

    var id: String { rawValue }

    // MARK: - Grouping

    enum Group: String, CaseIterable, Identifiable {
        case direct
        case universal
        case cinema

        var id: String { rawValue }

        @MainActor
        var title: String {
            let l = LocalizationManager.shared
            switch self {
            case .direct: return l.string(.createSource)
            case .universal: return l.string(.createVideoLink)
            case .cinema: return l.string(.serviceCinemas)
            }
        }
    }

    var group: Group {
        switch self {
        case .youtube, .vk, .rutube: return .direct
        case .browser, .customURL: return .universal
        case .netflix, .disney, .kinopoisk, .ivi, .okko, .wink, .start, .premier, .smotrim, .kion:
            return .cinema
        }
    }

    /// Сервисы данной группы.
    static func services(in group: Group) -> [VideoService] {
        allCases.filter { $0.group == group }
    }

    /// Честная витрина: кинотеатры остаются в списке, но с пометкой «по подписке».
    /// «Смотрим» и браузер бесплатны, поэтому живут рядом с прямыми потоками.
    var deliveryBucket: DeliveryBucket {
        switch self {
        case .youtube, .vk, .rutube, .customURL, .browser, .smotrim:
            return .worksNow
        case .netflix, .disney, .kinopoisk, .ivi, .okko, .wink, .start, .premier, .kion:
            return .bySubscription
        }
    }

    /// Providers enabled for the first beta. They have a public discovery path
    /// and an official embedded player that can be controlled by the room.
    /// Other services stay visible as a roadmap, never as a button that silently
    /// creates a room whose player cannot start.
    var isAvailableInBeta: Bool {
        self == .youtube || self == .rutube || self == .vk
    }

    var betaAvailabilityLabel: String {
        isAvailableInBeta ? "Работает сейчас" : "Скоро"
    }

    // MARK: - Playback

    var playbackMode: PlaybackMode {
        switch self {
        case .youtube, .customURL:
            // YouTube uses its official embed in the room. Raw extraction is
            // an opt-in legacy diagnostic path, never the beta default.
            return .webview
        // VK и Rutube играют официальным эмбедом, кинотеатры — своей страницей.
        case .vk, .rutube, .browser, .smotrim,
             .netflix, .disney, .kinopoisk, .ivi, .okko, .wink, .start, .premier, .kion:
            return .webview
        }
    }

    /// Домены сервиса — по ним определяется, чья страница играет в комнате,
    /// и в чьём cookie-хранилище искать живую сессию.
    var hosts: [String] {
        switch self {
        case .youtube: return PlinkHost.youtubeDomains
        case .vk: return PlinkHost.vkDomains
        case .rutube: return PlinkHost.rutubeDomains
        case .netflix: return ["netflix.com"]
        case .disney: return ["disneyplus.com"]
        case .kinopoisk: return ["kinopoisk.ru", "hd.kinopoisk.ru"]
        case .ivi: return ["ivi.ru"]
        case .okko: return ["okko.tv"]
        case .wink: return ["wink.ru"]
        case .start: return ["start.ru"]
        case .premier: return ["premier.one"]
        case .smotrim: return ["smotrim.ru"]
        case .kion: return ["kion.ru"]
        case .browser, .customURL: return []
        }
    }

    /// Сервис, которому принадлежит страница. Нужен комнате: по URL медиа
    /// она понимает, какой логотип показать и чей вход предложить.
    static func service(forHost host: String?) -> VideoService? {
        guard let host, !host.isEmpty else { return nil }
        return allCases.first { service in
            !service.hosts.isEmpty && PlinkHost.matches(host, anyOf: service.hosts)
        }
    }

    static func service(forURL raw: String) -> VideoService? {
        service(forHost: URL(string: raw)?.host)
    }

    /// Host needs an active subscription on the service (Netflix/Disney + RU cinemas).
    /// Plink does not provide content — host logs into their own account.
    var requiresSubscription: Bool {
        serviceType.requiresAuth
    }

    /// Smart Wall auth requirement for this service.
    var requiresAuth: Bool {
        serviceType.requiresAuth
    }

    var serviceType: ServiceType {
        ServiceType(service: self)
    }

    /// Short App Store–safe disclaimer shown when host picks a subscription service.
    @MainActor
    var subscriptionDisclaimer: String {
        guard deliveryBucket == .bySubscription else {
            return "«\(title)» открыт всем — подписка не нужна."
        }
        return "«\(title)» играет прямо в комнате: вы выбираете тайтл в своём аккаунте, Plink синхронизирует время. Каждый смотрит через свою подписку — Plink не раздаёт контент и не обходит DRM."
    }

    // MARK: - Display

    @MainActor
    var title: String {
        let l = LocalizationManager.shared
        switch self {
        case .youtube: return l.string(.serviceYouTube)
        case .vk: return l.string(.serviceVK)
        case .rutube: return l.string(.serviceRuTube)
        case .netflix: return "Netflix"
        case .disney: return "Disney+"
        case .browser: return l.string(.serviceBrowser)
        case .customURL: return l.string(.serviceCustomURL)
        case .kinopoisk: return l.string(.serviceKinopoisk)
        case .ivi: return l.string(.serviceIvi)
        case .okko: return l.string(.serviceOkko)
        case .wink: return l.string(.serviceWink)
        case .start: return l.string(.serviceStart)
        case .premier: return l.string(.servicePremier)
        case .smotrim: return l.string(.serviceSmotrim)
        case .kion: return l.string(.serviceKion)
        }
    }

    /// Краткое описание для премиум-карточки выбора сервиса
    var subtitle: String {
        switch self {
        case .youtube: return "Ролики, стримы, трейлеры"
        case .vk: return "Клипы, сериалы, трансляции"
        case .rutube: return "Шоу, сериалы, стримы"
        case .netflix: return "Оригинальные сериалы и кино"
        case .disney: return "Marvel, Star Wars, Pixar"
        case .browser: return "Любая страница с плеером"
        case .customURL: return "Прямая ссылка .mp4 или .m3u8"
        case .kinopoisk: return "Большой каталог и Originals"
        case .ivi: return "Кино, сериалы, мультфильмы"
        case .okko: return "Кино и спортивные трансляции"
        case .wink: return "Кино и ТВ-каналы"
        case .start: return "Оригинальные сериалы START"
        case .premier: return "Шоу ТНТ и оригиналы"
        case .smotrim: return "Эфир ВГТРК и архив"
        case .kion: return "Кино и оригиналы KION"
        }
    }

    var icon: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .vk: return "v.square.fill"
        case .rutube: return "r.square.fill"
        case .netflix: return "n.square.fill"
        case .disney: return "d.square.fill"
        case .browser: return "safari.fill"
        case .customURL: return "link"
        case .kinopoisk: return "film.stack"
        case .ivi: return "tv.fill"
        case .okko: return "sparkles.tv"
        case .wink: return "eye.fill"
        case .start: return "play.circle.fill"
        case .premier: return "crown.fill"
        case .smotrim: return "antenna.radiowaves.left.and.right"
        case .kion: return "k.circle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .youtube: return Color(hex: 0xFF0000)
        case .vk: return Color(hex: 0x0077FF)
        case .rutube: return Color(hex: 0x000000)
        case .netflix: return Color(hex: 0xE50914)
        case .disney: return Color(hex: 0x113CCF)
        case .browser: return Color(hex: 0x0077FF)
        case .customURL: return Cinema2026.accent
        case .kinopoisk: return Color(hex: 0xFF6600)
        case .ivi: return Color(hex: 0xE40000)
        case .okko: return Color(hex: 0xFF0033)
        case .wink: return Color(hex: 0xFF0050)
        case .start: return Color(hex: 0x7B2CBF)
        case .premier: return Color(hex: 0xEF4444)
        case .smotrim: return Color(hex: 0x00A0AF)
        case .kion: return Color(hex: 0xF26B1F)
        }
    }

    @MainActor
    var placeholder: String {
        switch self {
        case .youtube: return "YouTube ссылка или нажмите «Поиск»"
        case .vk: return "https://vk.com/video..."
        case .rutube: return "https://rutube.ru/video/..."
        case .browser: return "https://любой-сайт.ru"
        case .customURL: return ".mp4 / .m3u8 / .mp3 URL"
        default:
            return "Вставьте ссылку \(title)"
        }
    }
}
