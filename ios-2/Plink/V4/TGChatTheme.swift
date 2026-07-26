import SwiftUI

// MARK: - Telegram 2026 Chat Theme System
// Based on Telegram iOS January–July 2026 Liquid Glass redesign
// FIX: UIScreen.main replaced with GeometryReader to avoid iOS 16 deprecation

// MARK: - Theme Model

struct TGChatTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    // Own bubble (outgoing)
    let ownBubbleColors: [Color]
    // Incoming bubble
    let incomingBubbleColor: Color
    let incomingBubbleBorder: Color
    // Wallpaper
    let wallpaperColors: [Color]
    let wallpaperStyle: WallpaperStyle
    // Accent
    let accentColor: Color
    // Text
    let ownTextColor: Color
    let incomingTextColor: Color

    enum WallpaperStyle {
        case solidColor
        case gradient
        case animated
        case pattern
    }
}

// MARK: - Theme Catalog (Telegram 2026 official themes)

enum TGChatThemeCatalog {

    static let classic = TGChatTheme(
        id: "tg-classic",
        name: "Classic",
        icon: "📱",
        ownBubbleColors: [Color(hex: "#007AFF"), Color(hex: "#0AA0FF")],
        incomingBubbleColor: Color.white.opacity(0.16),
        incomingBubbleBorder: Color.white.opacity(0.22),
        wallpaperColors: [Color(hex: "#152232"), Color(hex: "#1A3A5C"), Color(hex: "#0D2137")],
        wallpaperStyle: .gradient,
        accentColor: Color(hex: "#007AFF"),
        ownTextColor: .white,
        incomingTextColor: .white
    )

    static let night = TGChatTheme(
        id: "tg-night",
        name: "Night",
        icon: "🌙",
        ownBubbleColors: [Color(hex: "#2EA6FF"), Color(hex: "#00C6FF")],
        incomingBubbleColor: Color(hex: "#212121").opacity(0.85),
        incomingBubbleBorder: Color.white.opacity(0.10),
        wallpaperColors: [Color(hex: "#0A0A0A"), Color(hex: "#111111")],
        wallpaperStyle: .solidColor,
        accentColor: Color(hex: "#2EA6FF"),
        ownTextColor: .white,
        incomingTextColor: Color(hex: "#ECECEC")
    )

    static let day = TGChatTheme(
        id: "tg-day",
        name: "Day",
        icon: "☀️",
        ownBubbleColors: [Color(hex: "#007AFF"), Color(hex: "#4FC3F7")],
        incomingBubbleColor: Color.white.opacity(0.95),
        incomingBubbleBorder: Color.black.opacity(0.08),
        wallpaperColors: [Color(hex: "#F0F4F8"), Color(hex: "#DDEEFF")],
        wallpaperStyle: .gradient,
        accentColor: Color(hex: "#007AFF"),
        ownTextColor: .white,
        incomingTextColor: Color(hex: "#1A1A1A")
    )

    static let teal = TGChatTheme(
        id: "tg-teal",
        name: "Teal",
        icon: "🌊",
        ownBubbleColors: [Color(hex: "#00B4D8"), Color(hex: "#0077B6")],
        incomingBubbleColor: Color(hex: "#0D3347").opacity(0.8),
        incomingBubbleBorder: Color(hex: "#00B4D8").opacity(0.25),
        wallpaperColors: [
            Color(hex: "#03045E"), Color(hex: "#023E8A"),
            Color(hex: "#0077B6"), Color(hex: "#00B4D8")
        ],
        wallpaperStyle: .gradient,
        accentColor: Color(hex: "#00B4D8"),
        ownTextColor: .white,
        incomingTextColor: .white
    )

    static let violet = TGChatTheme(
        id: "tg-violet",
        name: "Violet",
        icon: "💜",
        ownBubbleColors: [Color(hex: "#7C3AED"), Color(hex: "#A855F7")],
        incomingBubbleColor: Color(hex: "#2D1B69").opacity(0.75),
        incomingBubbleBorder: Color(hex: "#A855F7").opacity(0.30),
        wallpaperColors: [
            Color(hex: "#0F0720"), Color(hex: "#1A0A3D"),
            Color(hex: "#2D1B69"), Color(hex: "#4C1D95")
        ],
        wallpaperStyle: .gradient,
        accentColor: Color(hex: "#A855F7"),
        ownTextColor: .white,
        incomingTextColor: .white
    )

    static let rose = TGChatTheme(
        id: "tg-rose",
        name: "Rose",
        icon: "🌸",
        ownBubbleColors: [Color(hex: "#F43F5E"), Color(hex: "#FB7185")],
        incomingBubbleColor: Color(hex: "#4C0519").opacity(0.65),
        incomingBubbleBorder: Color(hex: "#FB7185").opacity(0.30),
        wallpaperColors: [
            Color(hex: "#1A0010"), Color(hex: "#3B0026"),
            Color(hex: "#6B0038"), Color(hex: "#9D0B4E")
        ],
        wallpaperStyle: .gradient,
        accentColor: Color(hex: "#F43F5E"),
        ownTextColor: .white,
        incomingTextColor: .white
    )

    static let forest = TGChatTheme(
        id: "tg-forest",
        name: "Forest",
        icon: "🌲",
        ownBubbleColors: [Color(hex: "#059669"), Color(hex: "#34D399")],
        incomingBubbleColor: Color(hex: "#052E16").opacity(0.75),
        incomingBubbleBorder: Color(hex: "#34D399").opacity(0.25),
        wallpaperColors: [
            Color(hex: "#052E16"), Color(hex: "#14532D"),
            Color(hex: "#166534"), Color(hex: "#065F46")
        ],
        wallpaperStyle: .gradient,
        accentColor: Color(hex: "#34D399"),
        ownTextColor: .white,
        incomingTextColor: .white
    )

    // Telegram Jul 2026 special: Liquid Glass (clear + refraction)
    static let liquidGlass = TGChatTheme(
        id: "tg-liquid-glass",
        name: "Liquid Glass",
        icon: "✨",
        ownBubbleColors: [Color(hex: "#5856D6").opacity(0.88), Color(hex: "#007AFF").opacity(0.88)],
        incomingBubbleColor: Color.white.opacity(0.08),
        incomingBubbleBorder: Color.white.opacity(0.28),
        wallpaperColors: [
            Color(hex: "#1C1C3A"), Color(hex: "#0A1628"),
            Color(hex: "#2C1654"), Color(hex: "#0D2137")
        ],
        wallpaperStyle: .animated,
        accentColor: Color(hex: "#5E5CE6"),
        ownTextColor: .white,
        incomingTextColor: .white
    )

    static let all: [TGChatTheme] = [
        classic, liquidGlass, night, day, teal, violet, rose, forest
    ]

    static func theme(id: String) -> TGChatTheme {
        all.first { $0.id == id } ?? classic
    }
}

// MARK: - Theme Preference Store
// FIX: marked @MainActor to avoid Swift 6 concurrency warnings

@MainActor
final class TGChatThemeStore: ObservableObject {
    static let shared = TGChatThemeStore()
    private let key = "plink_tg_chat_theme_id"

    @Published var current: TGChatTheme

    private init() {
        let saved = UserDefaults.standard.string(forKey: "plink_tg_chat_theme_id") ?? "tg-liquid-glass"
        self.current = TGChatThemeCatalog.theme(id: saved)
    }

    func select(_ theme: TGChatTheme) {
        UserDefaults.standard.set(theme.id, forKey: key)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            current = theme
        }
    }
}

// MARK: - Liquid Glass Modifier (iOS 26 / Telegram 2026)

struct LiquidGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let intensity: Double // 0.0 – 1.0

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.45 * intensity),
                                        Color.white.opacity(0.08 * intensity)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.75
                            )
                    )
            )
            .shadow(color: Color.black.opacity(0.18 * intensity), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 18, intensity: Double = 1.0) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, intensity: intensity))
    }
}

// MARK: - Animated Wallpaper View (Telegram 2026 style)
// FIX: replaced UIScreen.main.bounds with GeometryReader to avoid deprecation

struct TGAnimatedWallpaper: View {
    let theme: TGChatTheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Base gradient
                LinearGradient(
                    colors: theme.wallpaperColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if theme.wallpaperStyle == .animated {
                    TGOrbsLayer(theme: theme, size: geo.size)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Orbs layer extracted to keep TimelineView closure pure
// FIX: separated into its own view to avoid capturing mutable state in TimelineView

struct TGOrbsLayer: View {
    let theme: TGChatTheme
    let size: CGSize

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = tl.date.timeIntervalSince1970
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    let fi = Double(i)
                    let x = (0.3 + 0.35 * sin(t * 0.3 + fi * 1.2)) * size.width
                    let y = (0.2 + 0.5 * cos(t * 0.25 + fi * 0.8)) * size.height
                    let col = theme.wallpaperColors[i % theme.wallpaperColors.count]
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [col.opacity(0.45), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        .frame(width: 350, height: 350)
                        .position(x: x, y: y)
                        .blur(radius: 60)
                }
            }
            .drawingGroup() // FIX: composites orbs off-screen for perf
        }
    }
}

// MARK: - Theme Picker Sheet (Telegram 2026 style)
// FIX: @StateObject instead of @ObservedObject with default value

struct TGThemePickerSheet: View {
    @StateObject private var store = TGChatThemeStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Тема чата")
                        .font(.title2.bold())
                        .padding(.horizontal)

                    // Preview
                    TGChatBubblePreview(theme: store.current)
                        .padding(.horizontal)
                        .animation(.spring(response: 0.4), value: store.current.id)

                    Text("Выберите тему")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                        ForEach(TGChatThemeCatalog.all) { theme in
                            TGThemeCell(theme: theme, isSelected: store.current.id == theme.id) {
                                store.select(theme)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(.black.opacity(0.92))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(store.current.accentColor)
                }
            }
        }
    }
}

// MARK: - Theme Cell

struct TGThemeCell: View {
    let theme: TGChatTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: theme.wallpaperColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)

                    // Mini bubble preview
                    VStack(spacing: 4) {
                        HStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: theme.ownBubbleColors,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 32, height: 10)
                        }
                        HStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.incomingBubbleColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(theme.incomingBubbleBorder, lineWidth: 0.5)
                                )
                                .frame(width: 40, height: 10)
                            Spacer()
                        }
                    }
                    .padding(8)

                    if isSelected {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(theme.accentColor, lineWidth: 2.5)
                            .frame(width: 72, height: 72)

                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.accentColor)
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 72, height: 72, alignment: .bottomTrailing)
                            .padding(4)
                    }
                }

                Text(theme.icon + " " + theme.name)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mini Chat Preview

struct TGChatBubblePreview: View {
    let theme: TGChatTheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: theme.wallpaperColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 180)

            VStack(alignment: .leading, spacing: 8) {
                // Incoming
                HStack(alignment: .bottom, spacing: 8) {
                    Circle()
                        .fill(theme.accentColor.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .overlay(Text("А").font(.caption2.bold()).foregroundStyle(.white))

                    TGMiniPreviewBubble(text: "Привет! Как дела? 😊", isOwn: false, theme: theme)
                    Spacer()
                }

                HStack(alignment: .bottom, spacing: 8) {
                    Spacer()
                    TGMiniPreviewBubble(text: "Отлично, спасибо!", isOwn: true, theme: theme)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    Circle()
                        .fill(theme.accentColor.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .overlay(Text("А").font(.caption2.bold()).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        TGMiniPreviewBubble(text: "Смотрим кино? 🎬", isOwn: false, theme: theme)
                        HStack(spacing: 4) {
                            TGReactionChip(emoji: "❤️", count: 2, theme: theme)
                            TGReactionChip(emoji: "😍", count: 1, theme: theme)
                        }
                    }
                    Spacer()
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Mini Preview Bubble (used in theme picker preview only)
// Named TGMiniPreviewBubble to avoid conflict with TGBubble usage elsewhere.

struct TGMiniPreviewBubble: View {
    let text: String
    let isOwn: Bool
    let theme: TGChatTheme

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(isOwn ? theme.ownTextColor : theme.incomingTextColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if isOwn {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: theme.ownBubbleColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.incomingBubbleColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(theme.incomingBubbleBorder, lineWidth: 0.5)
                        )
                }
            }
    }
}

// MARK: - Reaction Chip (theme picker preview)

struct TGReactionChip: View {
    let emoji: String
    let count: Int
    let theme: TGChatTheme

    var body: some View {
        HStack(spacing: 3) {
            Text(emoji).font(.system(size: 11))
            Text("\(count)").font(.system(size: 10, weight: .medium)).foregroundStyle(theme.accentColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(theme.incomingBubbleColor)
                .overlay(Capsule().stroke(theme.accentColor.opacity(0.4), lineWidth: 0.5))
        )
    }
}
