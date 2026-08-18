import Foundation

/// Host matching against an allowlist of domains.
///
/// The match result decides whose URL ends up in `DetectedVideo.embedURL` and
/// therefore loads in the room's `WKWebView` **for every participant**, which is
/// why the comparison has to be exact rather than convenient.
///
/// A substring check is not good enough: `evil-vk.com.ru` contains `vk.com`, so
/// it would pass as a VK video and render with the service's header, icon, and
/// the trust a recognised brand carries — a VK login phishing page inside the
/// app. Prefixes fail the same way in the other direction: `notvk.com` is not VK.
///
/// The correct rule is that a host matches a domain when it *is* that domain or
/// is a subdomain of it — nothing else.
///
///     PlinkHost.matches("m.vk.com",       anyOf: ["vk.com"])  // true  — subdomain
///     PlinkHost.matches("vk.com",         anyOf: ["vk.com"])  // true  — the domain
///     PlinkHost.matches("evil-vk.com.ru", anyOf: ["vk.com"])  // false
///     PlinkHost.matches("notvk.com",      anyOf: ["vk.com"])  // false
///
/// A CI step rejects any reintroduction of substring host matching in Swift.
/// See ADR-0004.
enum PlinkHost {

    /// `true` when `host` is `domain` or a subdomain of it.
    ///
    /// Case is irrelevant — DNS names are case-insensitive — and a trailing dot
    /// is dropped, since `vk.com.` is a valid absolute FQDN for the same host.
    static func matches(_ host: String?, domain: String) -> Bool {
        guard let normalizedHost = normalize(host), let target = normalize(domain) else {
            return false
        }
        if normalizedHost == target { return true }
        return normalizedHost.hasSuffix("." + target)
    }

    /// `true` when `host` matches at least one domain in the list.
    static func matches(_ host: String?, anyOf domains: [String]) -> Bool {
        domains.contains { matches(host, domain: $0) }
    }

    /// `true` when the URL's host matches at least one domain in the list.
    static func matches(url: URL?, anyOf domains: [String]) -> Bool {
        matches(url?.host, anyOf: domains)
    }

    /// Normalizes a name for comparison: lowercased, no trailing dot.
    /// Returns `nil` for an empty result — an empty host matches nothing.
    private static func normalize(_ value: String?) -> String? {
        guard var name = value?.lowercased() else { return nil }
        while name.hasSuffix(".") { name.removeLast() }
        return name.isEmpty ? nil : name
    }
}

// MARK: - Supported service domains

/// The app's single list of service domains. Both `ServiceBrowserView`
/// entry points — `detectVideoURL` and `serviceFromURL` — read from here, so a
/// service added to one is a service known to the other.
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
