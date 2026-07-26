import Foundation
import SwiftUI

// MARK: - Playback Mode
/// Как сервис воспроизводится. Определяет технический путь.
enum PlaybackMode: String, Sendable {
    /// Прямой поток в AVPlayer (YouTube через extraction, MP4/M3U8/HLS).
    case directStream
    /// WebView с JS-bridge синхронизацией (кинотеатры — нужна подписка).
    case webview
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
    private static func key(for service: ServiceType) -> String {
        "plink.service_auth.\(service.rawValue)"
    }

    static func hasAccess(to service: ServiceType) -> Bool {
        guard service.requiresAuth else { return true }
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
        case .youtube, .vk, .rutube, .netflix, .disney: return .direct
        case .browser, .customURL: return .universal
        case .kinopoisk, .ivi, .okko, .wink, .start, .premier, .smotrim, .kion: return .cinema
        }
    }

    /// Сервисы данной группы.
    static func services(in group: Group) -> [VideoService] {
        allCases.filter { $0.group == group }
    }

    // MARK: - Playback

    var playbackMode: PlaybackMode {
        switch group {
        case .direct, .universal: return .directStream
        case .cinema: return .webview
        }
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
        "Требуется активная подписка \(title). Plink не предоставляет контент — вы входите в свой аккаунт."
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
        case .youtube: return "Миллиарды видео"
        case .vk: return "Видео и клипы"
        case .rutube: return "Шоу и стримы"
        case .netflix: return "Фильмы и сериалы"
        case .disney: return "Marvel, Star Wars и др."
        case .browser: return "Открыть любой сайт"
        case .customURL: return "Прямая ссылка .mp4 / .m3u8"
        case .kinopoisk: return "Фильмы и сериалы"
        case .ivi: return "Кино и мультфильмы"
        case .okko: return "Спорт и кино"
        case .wink: return "Кино и ТВ"
        case .start: return "Сериалы и шоу"
        case .premier: return "Премьеры и спорт"
        case .smotrim: return "Телеканалы и шоу"
        case .kion: return "Кино и сериалы"
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
