import Foundation

/// Строгий матч хоста по списку разрешённых доменов.
///
/// Аудит (июль 2026) поймал дыру `host.contains("vk.com")`. Она пережила
/// переезд кода: `MediaSourceResolver.swift` удалён, но тот же приём остался
/// в `ServiceBrowserView.detectVideoURL` и `serviceFromURL`.
///
/// Почему `contains` опасен именно здесь: результат матча решает, чей URL
/// попадёт в `DetectedVideo.embedURL` и загрузится в WKWebView комнаты для
/// **всех участников**. Хост `evil-vk.com.ru` содержит подстроку `vk.com`,
/// то есть страница атакующего проходила как «видео ВКонтакте» — с шапкой
/// сервиса, иконкой и доверием, которое даёт узнаваемый бренд. Дальше это
/// обычный фишинг логина VK внутри нашего приложения.
///
/// Правильная семантика: хост совпадает с доменом ровно, либо является его
/// поддоменом — то есть заканчивается на `"." + домен`. Ничего больше.
///
///     PlinkHost.matches("m.vk.com",      anyOf: ["vk.com"])  // true  — поддомен
///     PlinkHost.matches("vk.com",        anyOf: ["vk.com"])  // true  — сам домен
///     PlinkHost.matches("evil-vk.com.ru", anyOf: ["vk.com")] // false — фишинг
///     PlinkHost.matches("notvk.com",     anyOf: ["vk.com"])  // false — префикс
enum PlinkHost {

    /// `true`, если `host` — это `domain` или его поддомен.
    ///
    /// Регистр не важен (DNS-имена case-insensitive), завершающая точка
    /// («vk.com.» — валидный абсолютный FQDN) отбрасывается.
    static func matches(_ host: String?, domain: String) -> Bool {
        guard let normalizedHost = normalize(host), let target = normalize(domain) else {
            return false
        }
        if normalizedHost == target { return true }
        return normalizedHost.hasSuffix("." + target)
    }

    /// `true`, если `host` совпадает хотя бы с одним доменом из списка.
    static func matches(_ host: String?, anyOf domains: [String]) -> Bool {
        domains.contains { matches(host, domain: $0) }
    }

    /// `true`, если хост URL совпадает хотя бы с одним доменом из списка.
    static func matches(url: URL?, anyOf domains: [String]) -> Bool {
        matches(url?.host, anyOf: domains)
    }

    /// Приводит имя к сравнимому виду: нижний регистр, без завершающей точки.
    /// Возвращает `nil` для пустого результата — пустой хост не совпадает ни с чем.
    private static func normalize(_ value: String?) -> String? {
        guard var name = value?.lowercased() else { return nil }
        while name.hasSuffix(".") { name.removeLast() }
        return name.isEmpty ? nil : name
    }
}

// MARK: - Домены поддерживаемых сервисов

/// Единственный список доменов на приложение. Раньше он был размазан по
/// `switch`-ам в `ServiceBrowserView` в двух несогласованных вариантах:
/// `detectVideoURL` знал про `rutube.ru` и `rutube.video`, а `serviceFromURL`
/// матчил просто `"rutube"` — то есть `rutube.evil.com` классифицировался как
/// Rutube. Теперь оба читают отсюда.
extension PlinkHost {

    static let youtubeDomains  = ["youtube.com", "youtu.be", "youtube-nocookie.com"]
    static let vkDomains       = ["vk.com", "vk.ru", "vkvideo.ru"]
    static let rutubeDomains   = ["rutube.ru", "rutube.video"]
    static let netflixDomains  = ["netflix.com"]
    static let disneyDomains   = ["disneyplus.com"]
    static let kinopoiskDomains = ["kinopoisk.ru", "hd.kinopoisk.ru"]
    static let iviDomains      = ["ivi.ru", "ivi.tv"]
    static let okkoDomains     = ["okko.tv"]
    static let winkDomains     = ["wink.ru"]
    static let startDomains    = ["start.ru"]
    static let premierDomains  = ["premier.one"]
    static let smotrimDomains  = ["smotrim.ru"]
    static let kionDomains     = ["kion.ru"]

    static func isYouTube(_ url: URL?) -> Bool { matches(url: url, anyOf: youtubeDomains) }
    static func isVK(_ url: URL?) -> Bool      { matches(url: url, anyOf: vkDomains) }
    static func isRutube(_ url: URL?) -> Bool  { matches(url: url, anyOf: rutubeDomains) }
}
