//  MediaSourceResolver.swift
//  Plink — M39
//
//  Два бага из аудита исправлены здесь:
//   ℗ 4: было `host.contains("vk.com")` — ссылка evil-vk.com.ru считалась VK.
//        Стало точное совпадение домена или его поддомена.
//   ℗ 5: ссылка без схемы (rutube.ru/video/…) не распознавалась вообще.
//
//  Легальная позиция: мы НЕ проксируем и НЕ скачиваем чужое видео.
//  Для площадок используется только официальный embed-плеер. Это именно тот пункт,
//  на котором погорел Rave — его убрали из App Store.

import Foundation

enum MediaSourceKind: String, CaseIterable {
    case rutube, vk, ok, dzen, youtube, vimeo, personalFile, unknown

    var displayName: String {
        switch self {
        case .rutube: return "Rutube"
        case .vk: return "VK Видео"
        case .ok: return "Одноклассники"
        case .dzen: return "Дзен"
        case .youtube: return "YouTube"
        case .vimeo: return "Vimeo"
        case .personalFile: return "Ваш файл"
        case .unknown: return "Неизвестный источник"
        }
    }

    var iconName: String {
        switch self {
        case .rutube, .vk, .ok, .dzen, .youtube, .vimeo: return "play.rectangle.fill"
        case .personalFile: return "folder.fill"
        case .unknown: return "questionmark.square.dashed"
        }
    }
}

enum PlaybackStrategy {
    /// Официальный плеер площадки в WebView. Правообладатели получают свои показы и рекламу.
    case officialEmbed(URL)
    /// Собственный файл пользователя — можно играть в AVPlayer с точной синхронизацией.
    case nativePlayer(URL)
    /// Честный отказ с объяснением вместо молчаливого чёрного экрана.
    case unsupported(reason: String)
}

struct ResolvedMedia {
    let kind: MediaSourceKind
    let videoID: String?
    let originalURL: URL
    let strategy: PlaybackStrategy
    /// Точная синхронизация возможна только там, где мы управляем плеером.
    let supportsPreciseSync: Bool
}

enum MediaSourceResolver {

    private static let personalFileHosts: Set<String> = [
        "cdn.plink.app", "files.plink.app",
        "storage.yandexcloud.net", "getfile.dokpub.com",
    ]

    private static let videoExtensions = [".mp4", ".m3u8", ".mov", ".webm"]

    /// Строгое сравнение домена: совпадение целиком или как поддомен.
    /// Именно этого не было в v1, и оттуда бралась уязвимость.
    private static func match(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    /// Добавляет схему, если человек вставил «rutube.ru/video/…» без https.
    static func normalize(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.lowercased().hasPrefix("http") ? trimmed : "https://" + trimmed
        if let url = URL(string: withScheme) { return url }

        let encoded = withScheme.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
        return encoded.flatMap(URL.init(string:))
    }

    static func resolve(_ raw: String) -> ResolvedMedia {
        guard let url = normalize(raw), let rawHost = url.host?.lowercased() else {
            let fallback = URL(string: "https://plink.app")!
            return ResolvedMedia(kind: .unknown, videoID: nil, originalURL: fallback,
                                 strategy: .unsupported(reason: "Не похоже на ссылку на видео."),
                                 supportsPreciseSync: false)
        }

        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let path = url.path

        // —— Rutube ——
        if match(host, "rutube.ru") {
            if let id = path.split(separator: "/").last.map(String.init), !id.isEmpty,
               path.contains("/video/") || path.contains("/play/") {
                let embed = URL(string: "https://rutube.ru/play/embed/\(id)")!
                return ResolvedMedia(kind: .rutube, videoID: id, originalURL: url,
                                     strategy: .officialEmbed(embed), supportsPreciseSync: false)
            }
        }

        // —— VK Видео ——
        if match(host, "vk.com") || match(host, "vkvideo.ru") || match(host, "m.vk.com") {
            if let range = path.range(of: "video") {
                let tail = String(path[range.upperBound...])
                let parts = tail.split(separator: "_")
                if parts.count == 2 {
                    let oid = String(parts[0])
                    let vid = String(parts[1])
                    let embed = URL(string: "https://vk.com/video_ext.php?oid=\(oid)&id=\(vid)&hd=2&js_api=1")!
                    return ResolvedMedia(kind: .vk, videoID: "\(oid)_\(vid)", originalURL: url,
                                         strategy: .officialEmbed(embed), supportsPreciseSync: false)
                }
            }
        }

        // —— Одноклассники ——
        if match(host, "ok.ru") || match(host, "odnoklassniki.ru") {
            if let id = path.split(separator: "/").last.map(String.init), !id.isEmpty, path.contains("video") {
                let embed = URL(string: "https://ok.ru/videoembed/\(id)")!
                return ResolvedMedia(kind: .ok, videoID: id, originalURL: url,
                                     strategy: .officialEmbed(embed), supportsPreciseSync: false)
            }
        }

        // —— Дзен ——
        if match(host, "dzen.ru") {
            if let id = path.split(separator: "/").last.map(String.init), !id.isEmpty {
                let embed = URL(string: "https://dzen.ru/embed/\(id)?from_block=partner&from=zen")!
                return ResolvedMedia(kind: .dzen, videoID: id, originalURL: url,
                                     strategy: .officialEmbed(embed), supportsPreciseSync: false)
            }
        }

        // —— YouTube ——
        if match(host, "youtube.com") || match(host, "youtu.be") || match(host, "youtube-nocookie.com") {
            var id: String?
            if match(host, "youtu.be") {
                id = path.split(separator: "/").last.map(String.init)
            } else if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
                id = items.first(where: { $0.name == "v" })?.value
            }
            if id == nil, path.contains("/embed/") || path.contains("/shorts/") {
                id = path.split(separator: "/").last.map(String.init)
            }
            if let id, id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil {
                let embed = URL(string: "https://www.youtube.com/embed/\(id)?enablejsapi=1&playsinline=1&rel=0")!
                return ResolvedMedia(kind: .youtube, videoID: id, originalURL: url,
                                     strategy: .officialEmbed(embed), supportsPreciseSync: false)
            }
        }

        // —— Vimeo ——
        if match(host, "vimeo.com") {
            if let id = path.split(separator: "/").last.map(String.init),
               id.range(of: "^[0-9]+$", options: .regularExpression) != nil {
                let embed = URL(string: "https://player.vimeo.com/video/\(id)?api=1&playsinline=1")!
                return ResolvedMedia(kind: .vimeo, videoID: id, originalURL: url,
                                     strategy: .officialEmbed(embed), supportsPreciseSync: false)
            }
        }

        // —— Собственный файл ——
        let lowerPath = path.lowercased()
        let looksLikeVideoFile = videoExtensions.contains { lowerPath.hasSuffix($0) }
        let isTrustedHost = personalFileHosts.contains(host) || host.hasSuffix(".plink.app")

        if looksLikeVideoFile && isTrustedHost {
            // Только здесь возможна синхронизация с точностью до кадра.
            return ResolvedMedia(kind: .personalFile, videoID: nil, originalURL: url,
                                 strategy: .nativePlayer(url), supportsPreciseSync: true)
        }

        if looksLikeVideoFile {
            return ResolvedMedia(kind: .personalFile, videoID: nil, originalURL: url,
                                 strategy: .unsupported(reason: "Мы воспроизводим файлы только из вашего хранилища или облака. Загрузите видео в Plink."),
                                 supportsPreciseSync: false)
        }

        return ResolvedMedia(kind: .unknown, videoID: nil, originalURL: url,
                             strategy: .unsupported(reason: "Мы работаем с Rutube, VK Видео, Одноклассниками, Дзеном, YouTube, Vimeo и вашими файлами."),
                             supportsPreciseSync: false)
    }
}
