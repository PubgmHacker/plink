import SwiftUI

// MARK: - Telegram-style bright wallpapers with 3D sticker patterns

enum PlinkChatWallpaper: String, CaseIterable, Identifiable, Sendable {
    case cosmos
    case candy
    case ocean
    case jungle
    case sunset
    case neon
    case ice
    case party

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cosmos: return "Космос"
        case .candy: return "Конфеты"
        case .ocean: return "Океан"
        case .jungle: return "Джунгли"
        case .sunset: return "Закат"
        case .neon: return "Неон"
        case .ice: return "Лёд"
        case .party: return "Вечеринка"
        }
    }

    /// Bright base gradient (Telegram wallpapers are vivid, not near-black).
    var colors: [Color] {
        switch self {
        case .cosmos:
            return [Color(hex: 0x1A0B3C), Color(hex: 0x2D1B69), Color(hex: 0x0F3460)]
        case .candy:
            return [Color(hex: 0xFF6B9D), Color(hex: 0xC44DFF), Color(hex: 0x6B8CFF)]
        case .ocean:
            return [Color(hex: 0x0077B6), Color(hex: 0x00B4D8), Color(hex: 0x48CAE4)]
        case .jungle:
            return [Color(hex: 0x1B4332), Color(hex: 0x2D6A4F), Color(hex: 0x40916C)]
        case .sunset:
            return [Color(hex: 0xFF6B35), Color(hex: 0xF72585), Color(hex: 0x7209B7)]
        case .neon:
            return [Color(hex: 0x0D0221), Color(hex: 0x240046), Color(hex: 0x5A189A)]
        case .ice:
            return [Color(hex: 0xCAF0F8), Color(hex: 0x90E0EF), Color(hex: 0x48CAE4)]
        case .party:
            return [Color(hex: 0xFF006E), Color(hex: 0x8338EC), Color(hex: 0x3A86FF)]
        }
    }

    /// Floating “3D” sticker emojis (Telegram-like decorative models on wallpaper).
    var stickers: [String] {
        switch self {
        case .cosmos: return ["🪐", "⭐", "🚀", "👽", "🌙", "✨", "🛸", "💫"]
        case .candy: return ["🍬", "🍭", "🧁", "🍩", "🍓", "🎀", "💖", "🦄"]
        case .ocean: return ["🐠", "🐙", "🌊", "🐚", "🦈", "🪸", "🐬", "⚓"]
        case .jungle: return ["🌴", "🦜", "🦁", "🐸", "🍃", "🦋", "🌺", "🐵"]
        case .sunset: return ["🌅", "🦩", "☀️", "🍑", "🧡", "🏝️", "🔥", "✨"]
        case .neon: return ["💜", "🔮", "⚡", "👾", "🎮", "💿", "💜", "✨"]
        case .ice: return ["❄️", "🐧", "🏔️", "💎", "🧊", "🦭", "💙", "⭐"]
        case .party: return ["🎉", "🎈", "🎊", "🥳", "🍾", "🪩", "🎵", "✨"]
        }
    }

    var isLight: Bool {
        self == .ice || self == .candy || self == .ocean
    }

    @ViewBuilder
    var background: some View {
        GeometryReader { geo in
            ZStack {
                // Bright multi-stop gradient
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Soft light orbs for depth (3D feel)
                Circle()
                    .fill(Color.white.opacity(isLight ? 0.28 : 0.10))
                    .frame(width: geo.size.width * 0.55)
                    .blur(radius: 50)
                    .offset(x: -geo.size.width * 0.2, y: -geo.size.height * 0.15)

                Circle()
                    .fill(colors.last?.opacity(0.38) ?? Color.purple.opacity(0.28))
                    .frame(width: geo.size.width * 0.7)
                    .blur(radius: 60)
                    .offset(x: geo.size.width * 0.25, y: geo.size.height * 0.35)

                // Pattern of 3D stickers (kept quieter so bubbles stay primary, like Telegram)
                TelegramStickerField(stickers: stickers, size: geo.size, isLight: isLight)

                // Very light vignette — improves bubble separation without killing wallpaper
                LinearGradient(
                    colors: [
                        Color.black.opacity(isLight ? 0.06 : 0.12),
                        .clear,
                        Color.black.opacity(isLight ? 0.08 : 0.16)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

/// Scattered sticker “models” like Telegram animated wallpaper patterns.
private struct TelegramStickerField: View {
    let stickers: [String]
    let size: CGSize
    let isLight: Bool

    var body: some View {
        let cols = 5
        let rows = 9
        let cellW = size.width / CGFloat(cols)
        let cellH = size.height / CGFloat(rows)

        Canvas { ctx, _ in
            // Soft bubble circles behind stickers
            for r in 0..<rows {
                for c in 0..<cols {
                    let seed = r * 17 + c * 31
                    let ox = CGFloat((seed * 13) % 17) - 8
                    let oy = CGFloat((seed * 7) % 15) - 7
                    let cx = CGFloat(c) * cellW + cellW * 0.5 + ox
                    let cy = CGFloat(r) * cellH + cellH * 0.5 + oy
                    let rad = 10 + CGFloat(seed % 10)
                    let circle = Path(ellipseIn: CGRect(x: cx - rad, y: cy - rad, width: rad * 2, height: rad * 2))
                    ctx.fill(circle, with: .color(.white.opacity(isLight ? 0.18 : 0.07)))
                }
            }
        }
        .overlay {
            // Emoji stickers as “3D models”
            ForEach(0..<(cols * rows), id: \.self) { i in
                let r = i / cols
                let c = i % cols
                let seed = r * 17 + c * 31
                // Skip some cells for airiness
                if seed % 3 != 0 {
                    let emoji = stickers[seed % stickers.count]
                    let ox = CGFloat((seed * 13) % 17) - 8
                    let oy = CGFloat((seed * 7) % 15) - 7
                    let fontSize = CGFloat(22 + (seed % 14))
                    let rot = Double((seed * 11) % 40) - 20
                    Text(emoji)
                        .font(.system(size: fontSize))
                        .shadow(color: .black.opacity(isLight ? 0.10 : 0.28), radius: 2, y: 1)
                        .rotationEffect(.degrees(rot))
                        .scaleEffect(0.78 + CGFloat(seed % 5) * 0.05)
                        .position(
                            x: CGFloat(c) * cellW + cellW * 0.5 + ox,
                            y: CGFloat(r) * cellH + cellH * 0.5 + oy
                        )
                        // Stickers are decoration only — must not compete with message capsules
                        .opacity(isLight ? 0.42 : 0.38)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

enum PlinkChatWallpaperPrefs {
    static let storageKey = "plink.chatWallpaperID"

    static var current: PlinkChatWallpaper {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? PlinkChatWallpaper.cosmos.rawValue
        // Migrate old dim defaults
        if raw == "defaultDark" || raw == "telegramBlue" || raw == "night"
            || raw == "purpleMist" || raw == "graphite" || raw == "aurora"
            || raw == "forest" {
            return .cosmos
        }
        return PlinkChatWallpaper(rawValue: raw) ?? .cosmos
    }

    static func set(_ wallpaper: PlinkChatWallpaper) {
        UserDefaults.standard.set(wallpaper.rawValue, forKey: storageKey)
        NotificationCenter.default.post(name: .plinkChatWallpaperChanged, object: wallpaper.rawValue)
    }
}

extension Notification.Name {
    static let plinkChatWallpaperChanged = Notification.Name("plink.chatWallpaperChanged")
}
