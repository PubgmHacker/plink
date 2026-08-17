import SwiftUI

// MARK: - ServiceLogoView
/// 🔧 REAL LOGOS: Uses actual brand logos from Assets.xcassets.
/// Two modes:
///   1. Icon mode (default): square logo only
///   2. Wordmark mode: logo + full brand name text beside it
///
/// Logos were downloaded from:
///   - Wikimedia Commons (SVG → PNG) for: YouTube, VK, Netflix, Disney+
///   - Official site favicons (Google S2 favicon API, 128px) for:
///     Rutube, Кинопоиск, Ivi, Okko, Wink, Start, Premier, Smotrim, KION
struct ServiceLogoView: View {
    let service: VideoService
    var size: CGFloat = 48
    /// 🔧 NEW: When true, shows the logo + full brand name text beside it (horizontal wordmark).
    /// When false (default), shows just the square logo icon.
    var wordmark: Bool = false

    /// 🔧 Convenience init from MediaItem.MediaSource — converts via rawValue.
    init(service source: MediaItem.MediaSource, size: CGFloat = 48, wordmark: Bool = false) {
        self.service = VideoService(rawValue: source.rawValue) ?? .youtube
        self.size = size
        self.wordmark = wordmark
    }

    init(service: VideoService, size: CGFloat = 48, wordmark: Bool = false) {
        self.service = service
        self.size = size
        self.wordmark = wordmark
    }

    // 🔧 FIX 4.5: Static cache — loaded once, reused forever
    private static let imageCache: [String: UIImage] = {
        var cache: [String: UIImage] = [:]
        for svc in VideoService.allCases {
            if let name = svc.assetName, let img = UIImage(named: name) {
                cache[name] = img
            }
        }
        return cache
    }()

    var body: some View {
        if wordmark {
            wordmarkView
        } else {
            iconView
        }
    }

    // MARK: - Icon mode (square logo only)

    private var iconView: some View {
        Group {
            if let imageName = service.assetName, let uiImage = Self.imageCache[imageName] {
                Image(uiImage: uiImage)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                fallbackLogo
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Wordmark mode (logo + brand name text)
    /// 🔧 NEW: Shows the real logo + full brand name in the brand's accent color.
    /// This gives the effect of a full wordmark logo without needing to download
    /// a separate wordmark image for each service.

    private var wordmarkView: some View {
        HStack(spacing: 10) {
            // Real logo icon
            iconView

            // Full brand name in brand accent color
            Text(service.brandName)
                .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                .foregroundColor(service.accentColor)
                .lineLimit(1)
        }
        .frame(height: size)
    }

    /// Fallback when asset is missing — uses brand accent color + service initial.
    private var fallbackLogo: some View {
        ZStack {
            Circle()
                .fill(service.accentColor)
                .frame(width: size, height: size)
            Text(String(service.title.prefix(1)).uppercased())
                .font(.system(size: size * 0.5, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

// MARK: - VideoService + Asset Name + Brand Name

extension VideoService {
    /// Asset catalog image name for this service's real logo, or nil if no asset.
    var assetName: String? {
        switch self {
        case .youtube:      return "ServiceLogoYoutube"
        case .vk:           return "ServiceLogoVk"
        case .rutube:       return "ServiceLogoRutube"
        case .netflix:      return "ServiceLogoNetflix"
        case .disney:       return "ServiceLogoDisney"
        case .kinopoisk:    return "ServiceLogoKinopoisk"
        case .ivi:          return "ServiceLogoIvi"
        case .okko:         return "ServiceLogoOkko"
        case .wink:         return "ServiceLogoWink"
        case .start:        return "ServiceLogoStart"
        case .premier:      return "ServiceLogoPremier"
        case .smotrim:      return "ServiceLogoSmotrim"
        case .kion:         return "ServiceLogoKion"
        case .browser:      return nil
        case .customURL:    return nil
        }
    }

    /// 🔧 NEW: Full brand name for wordmark display.
    /// Uses the official marketing name, not the short title.
    var brandName: String {
        switch self {
        case .youtube:      return "YouTube"
        case .vk:           return "VK Видео"        // 🔧 was "VK", now "VK Видео" per user request
        case .rutube:       return "Rutube"
        case .netflix:      return "Netflix"
        case .disney:       return "Disney+"
        case .browser:      return "Браузер"
        case .customURL:    return "Своя ссылка"
        case .kinopoisk:    return "Кинопоиск"
        case .ivi:          return "ivi"
        case .okko:         return "OKKO"
        case .wink:         return "Wink"
        case .start:        return "START"
        case .premier:      return "PREMIER"
        case .smotrim:      return "Смотрим"
        case .kion:         return "KION"
        }
    }

    /// 🔧 NEW: The URL to browse this service's content in a WebView.
    /// Used by ServiceBrowserView to load the service's catalog page.
    ///
    /// 🔧 v9 (July 2026): YouTube changed from search 'music 2025' to
    /// /feed/trending — shows trending videos instead of arbitrary music
    /// search results. User-reported: 'почему пользователей сразу кидает на
    /// запрос music 2025 если они его не делали? лучше кидать на тренды'.
    var browseURL: String {
        switch self {
        case .youtube:      return "https://www.youtube.com/feed/trending"
        case .vk:           return "https://vk.com/video"
        case .rutube:       return "https://rutube.ru/"
        case .netflix:      return "https://www.netflix.com/browse"
        case .disney:       return "https://www.disneyplus.com/"
        case .kinopoisk:    return "https://kinopoisk.ru/"
        case .ivi:          return "https://www.ivi.ru/"
        case .okko:         return "https://okko.tv/"
        case .wink:         return "https://wink.ru/"
        case .start:        return "https://start.ru/"
        case .premier:      return "https://premier.one/"
        case .smotrim:      return "https://smotrim.ru/"
        case .kion:         return "https://kion.ru/"
        case .browser:      return "https://www.google.com/"
        case .customURL:    return "https://www.google.com/" // 🔧 Pack v3: был "" → URL(string: "")! crash
        }
    }
}

// MARK: - Backwards Compatibility Alias
typealias ServiceLogoIcon = ServiceLogoView
