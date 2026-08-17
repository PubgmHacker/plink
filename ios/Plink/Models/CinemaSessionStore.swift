import Foundation
import WebKit

/// Один постоянный cookie-jar для Яндекс ID и кинотеатров.
/// YouTube-поиск остаётся в `.nonPersistent()`, иначе антибот YouTube
/// путает сессию плеера комнаты и каталога.
enum CinemaSessionStore {
    /// Стабильный UUID — тот же store после перезапуска приложения.
    private static let identifier = UUID(uuidString: "7C3E9A10-2B54-4F8D-9E61-A0C4D8B2F715")!

    static var persistent: WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: identifier)
    }

    static func store(persistingCookies: Bool) -> WKWebsiteDataStore {
        persistingCookies ? persistent : .nonPersistent()
    }

    static func removeCookies(matchingHosts hosts: [String]) {
        let store = persistent
        store.httpCookieStore.getAllCookies { cookies in
            for cookie in cookies where hosts.contains(where: { host in
                cookieHost(cookie.domain, matches: host)
            }) {
                store.httpCookieStore.delete(cookie)
            }
        }
    }

    private static func cookieHost(_ cookieDomain: String, matches host: String) -> Bool {
        let domain = cookieDomain.hasPrefix(".") ? String(cookieDomain.dropFirst()) : cookieDomain
        return domain == host || domain.hasSuffix(".\(host)") || host.hasSuffix(".\(domain)")
    }
}

/// Внешние аккаунты, которые хост подключает в профиле один раз.
enum LinkedExternalAccount: String, CaseIterable, Identifiable {
    case yandex
    case kinopoisk
    case ivi
    case okko
    case wink
    case start
    case premier
    case kion
    case netflix
    case disney

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yandex: return "Яндекс ID"
        case .kinopoisk: return "Кинопоиск"
        case .ivi: return "Иви"
        case .okko: return "Okko"
        case .wink: return "Wink"
        case .start: return "START"
        case .premier: return "Premier"
        case .kion: return "KION"
        case .netflix: return "Netflix"
        case .disney: return "Disney+"
        }
    }

    var symbol: String {
        switch self {
        case .yandex: return "y.circle.fill"
        case .kinopoisk: return "film.stack"
        case .ivi: return "tv.fill"
        case .okko: return "sparkles.tv"
        case .wink: return "eye.fill"
        case .start: return "play.circle.fill"
        case .premier: return "crown.fill"
        case .kion: return "k.circle.fill"
        case .netflix: return "n.square.fill"
        case .disney: return "d.square.fill"
        }
    }

    var videoService: VideoService? {
        switch self {
        case .yandex: return nil
        case .kinopoisk: return .kinopoisk
        case .ivi: return .ivi
        case .okko: return .okko
        case .wink: return .wink
        case .start: return .start
        case .premier: return .premier
        case .kion: return .kion
        case .netflix: return .netflix
        case .disney: return .disney
        }
    }

    var loginURL: URL {
        switch self {
        case .yandex:
            return URL(string: "https://passport.yandex.ru/auth")!
        default:
            return URL(string: videoService?.browseURL ?? "https://yandex.ru")!
        }
    }

    var cookieHosts: [String] {
        switch self {
        case .yandex:
            return ["yandex.ru", "yandex.com", "ya.ru", "yandex.net"]
        case .kinopoisk:
            return ["kinopoisk.ru"]
        case .ivi:
            return ["ivi.ru"]
        case .okko:
            return ["okko.tv"]
        case .wink:
            return ["wink.ru"]
        case .start:
            return ["start.ru"]
        case .premier:
            return ["premier.one"]
        case .kion:
            return ["kion.ru"]
        case .netflix:
            return ["netflix.com"]
        case .disney:
            return ["disneyplus.com"]
        }
    }

    var isConnected: Bool {
        switch self {
        case .yandex:
            return ServiceAuthStore.hasYandexID
        default:
            guard let svc = videoService else { return false }
            return ServiceAuthStore.hasAccess(to: svc.serviceType)
        }
    }

    func markConnected() {
        switch self {
        case .yandex:
            ServiceAuthStore.markYandexID(true)
        default:
            guard let svc = videoService else { return }
            ServiceAuthStore.markAuthorized(svc.serviceType)
        }
    }

    func disconnect() {
        switch self {
        case .yandex:
            ServiceAuthStore.markYandexID(false)
        default:
            guard let svc = videoService else { return }
            ServiceAuthStore.logout(svc.serviceType)
        }
        CinemaSessionStore.removeCookies(matchingHosts: cookieHosts)
    }

    static var connectedCount: Int {
        allCases.filter(\.isConnected).count
    }
}
