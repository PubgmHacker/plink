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
                    .fill(Color.white.opacity(isLight ? 0.20 : 0.06))
                    .frame(width: geo.size.width * 0.55)
                    .blur(radius: 50)
                    .offset(x: -geo.size.width * 0.2, y: -geo.size.height * 0.15)

                Circle()
                    .fill(colors.last?.opacity(0.22) ?? Color.purple.opacity(0.18))
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

/// Узор обоев — как в Telegram: плотная монохромная сетка, а не выставка
/// цветных стикеров. Раньше эмодзи были 22–36pt в цвете при 0.38 прозрачности
/// и перебивали сами сообщения; теперь это фактура, которую замечаешь вторым
/// взглядом. Обесцвечивание + blend делают узор частью подложки, а не слоем
/// картинок поверх неё.
private struct TelegramStickerField: View {
    let stickers: [String]
    let size: CGSize
    let isLight: Bool

    var body: some View {
        let cols = 6
        let cellW = size.width / CGFloat(cols)
        let rows = max(6, Int((size.height / cellW).rounded(.up)))
        let cellH = size.height / CGFloat(rows)

        ZStack {
            ForEach(0..<(cols * rows), id: \.self) { i in
                let r = i / cols
                let c = i % cols
                let seed = r * 17 + c * 31
                // Половина ячеек пустая — иначе узор превращается в ковёр.
                if seed % 2 == 0 {
                    let emoji = stickers[seed % stickers.count]
                    let ox = CGFloat((seed * 13) % 15) - 7
                    let oy = CGFloat((seed * 7) % 13) - 6
                    let glyph = CGFloat(15 + (seed % 8))
                    let rot = Double((seed * 11) % 30) - 15
                    Text(emoji)
                        .font(.system(size: glyph))
                        .rotationEffect(.degrees(rot))
                        .position(
                            x: CGFloat(c) * cellW + cellW * 0.5 + ox,
                            y: CGFloat(r) * cellH + cellH * 0.5 + oy
                        )
                }
            }
        }
        .saturation(0)
        .opacity(isLight ? 0.16 : 0.22)
        .blendMode(isLight ? .multiply : .plusLighter)
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
