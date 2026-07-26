// Plink/Design/Cinematic/CinemaComponents.swift
//
// Shared design primitives that complete the Cinema2026 design system.
// These were referenced from Home / Profile / Friends / Admin / Settings
// but had no definition — defined here so the whole app compiles.

import SwiftUI

// MARK: - glassCard modifier
//
// Frosted-glass surface used across cards, panels and sheets.
// Renders a translucent white overlay with a hairline border and
// soft shadow — tuned to sit on top of Cinema2026.background.

extension View {
    /// Frosted-glass card surface.
    /// - Parameters:
    ///   - cornerRadius: Corner radius in points.
    ///   - opacity: Background white opacity (0.0 – 1.0). Default 0.05.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 16, opacity: Double = 0.05) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(opacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
    }

    /// Soft neon glow shadow (formerly in Color+Theme.swift).
    func neonGlow(color: Color = Cinema2026.accent, radius: CGFloat = 14, y: CGFloat = 4) -> some View {
        self.shadow(color: color.opacity(0.45), radius: radius, x: 0, y: y)
    }

    /// Chat text shadow for readability over video (formerly in Color+Theme.swift).
    func chatTextShadow() -> some View {
        self.shadow(color: .black.opacity(0.9), radius: 2.5, x: 0, y: 1)
    }
}

// MARK: - PremiumButtonStyle
//
// Pressable button style used for primary CTAs across the app.
// Supports an optional `glowColor` for accent-specific glow.

struct PremiumButtonStyle: ButtonStyle {
    var glowColor: Color = Cinema2026.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [glowColor, glowColor.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: glowColor.opacity(configuration.isPressed ? 0.15 : 0.35),
                radius: configuration.isPressed ? 6 : 12,
                x: 0,
                y: configuration.isPressed ? 2 : 6
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Color hex initializer
//
// Formerly in Color+Theme.swift. Used by AvatarView and others.

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}


// MARK: - LivingHomeStateOverlay (moved from deleted PlinkLivingHome.swift)
@available(iOS 17.0, *)
struct LivingHomeStateOverlay: View {
    let isLoading: Bool
    var body: some View {
        if isLoading {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Cinema2026.surface.opacity(0.4))
                    .frame(height: 280)
                    .padding(.horizontal, 14)
                ForEach(0..<2, id: \.self) { _ in
                    HStack {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Cinema2026.surface.opacity(0.3))
                                .frame(width: 140, height: 80)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .redacted(reason: .placeholder)
            .accessibilityLabel("Загрузка ленты")
        }
    }
}

// MARK: - CinematicPrimaryButtonStyle (used by PlinkPlusPaywall)
struct CinematicPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(colors: [Cinema2026.accent, Cinema2026.accent.opacity(0.8)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - CinemaRadius (used by PlinkPlusPaywall)
enum CinemaRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 14
    static let large: CGFloat = 20
    static let extraLarge: CGFloat = 28
}

// MARK: - PosterImage (used by CompactRoomRail)
struct PosterImage: View {
    let url: String?
    var body: some View {
        AsyncImage(url: URL(string: url ?? "")) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(Cinema2026.surface)
        }
    }
}

// MARK: - adminStroke + premiumStroke (used by AvatarView's RingModifier)

private struct VIPAvatarRingModifier: ViewModifier {
    let colors: [Color]
    let lineWidth: CGFloat
    let glowColor: Color
    let animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0

    func body(content: Content) -> some View {
        let shouldAnimate = animated && !reduceMotion
        content
            .overlay {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: colors + [colors.first ?? .clear],
                            center: .center
                        ),
                        lineWidth: lineWidth
                    )
                    .rotationEffect(.degrees(shouldAnimate ? rotation : 0))
                    .shadow(color: glowColor.opacity(0.32), radius: lineWidth * 2.2)
                    .drawingGroup(opaque: false)
            }
            .onAppear {
                guard shouldAnimate, rotation == 0 else { return }
                withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

extension View {
    func adminStroke(lineWidth: CGFloat = 2, animated: Bool = true) -> some View {
        self.modifier(
            VIPAvatarRingModifier(
                colors: [Color(hex: 0xFF2D55), Color(hex: 0x7A0019), Color(hex: 0xFF4A4A)],
                lineWidth: lineWidth,
                glowColor: Color(hex: 0xFF2D55),
                animated: animated
            )
        )
    }

    func premiumStroke(lineWidth: CGFloat = 2, animated: Bool = true) -> some View {
        self.modifier(
            VIPAvatarRingModifier(
                colors: [Color(hex: 0xFFD700), Color(hex: 0xB87333), Color(hex: 0xFFB000)],
                lineWidth: lineWidth,
                glowColor: Color(hex: 0xFFD700),
                animated: animated
            )
        )
    }
}

// MARK: - PulsingDot, LiveBadge, dismissKeyboardOnTap, shimmerGradientText, View.if
struct PulsingDot: View {
    let color: Color
    @State private var pulse = false
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .scaleEffect(pulse ? 1.3 : 1.0)
            .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 3) { PulsingDot(color: .white); Text("LIVE").font(.system(size: 9, weight: .black)) }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Cinema2026.danger, in: Capsule()).foregroundStyle(.white)
    }
}

extension View {
    @ViewBuilder func ifTransform<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    }
}

extension Text {
    func adminShimmerText() -> some View { self.foregroundStyle(Cinema2026.amber).shadow(color: Cinema2026.amber.opacity(0.4), radius: 4) }
}

extension View {
    func shimmerGradientText(colors: [Color] = [Cinema2026.accent, Cinema2026.amber]) -> some View {
        self.foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            .shadow(color: colors.first?.opacity(0.4) ?? .clear, radius: 4)
    }
}

// MARK: - ConditionalBreathing, GlassButtonStyle, RaveTextFieldStyle, ConditionalGlow
struct ConditionalBreathing: ViewModifier {
    let isActive: Bool; let maxScale: CGFloat; let period: Double
    @State private var breathing = false
    func body(content: Content) -> some View {
        content.scaleEffect(isActive && breathing ? maxScale : 1.0)
            .onAppear { guard isActive else { return }; withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) { breathing = true } }
    }
}

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Cinema2026.text)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct RaveTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.font(.system(size: 16)).foregroundStyle(Cinema2026.text)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Cinema2026.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Cinema2026.divider, lineWidth: 0.5))
    }
}

struct ConditionalGlow: ViewModifier {
    let isActive: Bool; let color: Color
    let minRadius: CGFloat; let maxRadius: CGFloat
    let minOpacity: Double; let maxOpacity: Double; let period: Double
    @State private var pulse = false
    func body(content: Content) -> some View {
        content.shadow(color: isActive ? color.opacity(pulse ? maxOpacity : minOpacity) : .clear,
                       radius: isActive ? (pulse ? maxRadius : minRadius) : 0)
            .onAppear { guard isActive else { return }; withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

// MARK: - premiumGlass + glowPulse + telegramGlass
extension View {
    @ViewBuilder func premiumGlass(cornerRadius: CGFloat = 16, opacity: Double = 0.06, ringColor: LinearGradient = Cinema2026.timeline, glow: Bool = false) -> some View {
        self.background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.white.opacity(opacity)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(ringColor, lineWidth: glow ? 1.5 : 0.5))
            .shadow(color: glow ? Cinema2026.accent.opacity(0.2) : Color.black.opacity(0.15), radius: glow ? 12 : 6, x: 0, y: glow ? 4 : 2)
    }

    @ViewBuilder func glowPulse(color: Color = Cinema2026.accent, minRadius: CGFloat = 8, maxRadius: CGFloat = 16, minOpacity: Double = 0.2, maxOpacity: Double = 0.5, period: Double = 2.0, radius: CGFloat? = nil, duration: Double? = nil) -> some View {
        self.modifier(ConditionalGlow(isActive: true, color: color, minRadius: radius ?? minRadius, maxRadius: radius ?? maxRadius, minOpacity: minOpacity, maxOpacity: maxOpacity, period: duration ?? period))
    }

    @ViewBuilder func telegramGlass(cornerRadius: CGFloat = 16, opacity: Double = 0.06, borderColor: Color = Color.white.opacity(0.08)) -> some View {
        self.background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.white.opacity(opacity)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(borderColor, lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 2)
    }
}

// MARK: - LivingHomeStateOverlay

// MARK: - EmojiPickerGrid (DM chat — free unicode + Plink+ packs)
struct EmojiPickerGrid: View {
    @Binding var chatText: String
    @ObservedObject private var premium = PremiumStatusManager.shared
    @State private var packIndex = 0
    @State private var upsell: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private var packs: [EmojiPack] { PlinkEmojiCatalog.dmAllPacks }
    private var current: EmojiPack {
        guard packIndex >= 0, packIndex < packs.count else { return packs[0] }
        return packs[packIndex]
    }

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(packs.enumerated()), id: \.element.id) { index, pack in
                        let locked = pack.isPremium && !premium.isPremium
                        Button {
                            if locked {
                                upsell = "«\(pack.name)» — только Plink+"
                                HapticManager.errorOccurred()
                            } else {
                                packIndex = index
                                upsell = nil
                                HapticManager.selection()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if pack.isPremium {
                                    Image(systemName: locked ? "lock.fill" : "crown.fill")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Text(pack.name)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(packIndex == index ? Cinema2026.background : Cinema2026.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                packIndex == index ? Cinema2026.accent : Cinema2026.raised.opacity(0.9),
                                in: Capsule()
                            )
                            .opacity(locked ? 0.55 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let upsell {
                Text(upsell)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Cinema2026.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(current.emojis, id: \.self) { token in
                        Button { pick(token) } label: {
                            Group {
                                if PlinkEmojiCatalog.usesCustomArt(current.name) || token.hasPrefix("emoji_") {
                                    EmojiAssetImage(name: token, pack: current.name)
                                        .frame(width: 32, height: 32)
                                } else {
                                    Text(token).font(.system(size: 26))
                                }
                            }
                            .frame(width: 40, height: 40)
                            .opacity(current.isPremium && !premium.isPremium ? 0.4 : 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Emoji \(token)")
                    }
                }
            }
            .frame(maxHeight: 180)
        }
        .padding(12)
        .background(Cinema2026.surface.opacity(0.97), in: RoundedRectangle(cornerRadius: 16))
    }

    private func pick(_ token: String) {
        if current.isPremium && !premium.isPremium {
            upsell = "Эмодзи Plink+ — оформите подписку"
            HapticManager.errorOccurred()
            return
        }
        if PlinkEmojiCatalog.usesCustomArt(current.name) || token.hasPrefix("emoji_") {
            chatText += PlinkEmojiCatalog.encodeToken(pack: current.name, name: token)
        } else {
            chatText += token
        }
        HapticManager.impact(.light)
        AnalyticsService.shared.emojiUsed(current.isPremium ? "plink_plus" : "free")
    }
}

// MARK: - Rich message (unicode + :pack/name: custom emojis)

struct MessageRichText: View {
    let text: String
    var fontSize: CGFloat = 16
    /// Telegram-readable body on solid bubbles (default white on dark/colored fills).
    var textColor: Color = .white

    var body: some View {
        let parts = PlinkEmojiCatalog.splitMessage(text)
        if parts.count == 1, case .custom(let pack, let name) = parts[0] {
            EmojiAssetImage(name: name, pack: pack)
                .frame(width: 72, height: 72)
        } else {
            PlinkEmojiFlow(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case .text(let s):
                        Text(s)
                            .font(.system(size: fontSize, weight: .regular))
                            .foregroundStyle(textColor)
                            // Slight shadow so glyphs never vanish on busy wallpaper edges
                            .shadow(color: .black.opacity(0.22), radius: 0.5, y: 0.5)
                    case .custom(let pack, let name):
                        EmojiAssetImage(name: name, pack: pack)
                            .frame(width: fontSize + 10, height: fontSize + 10)
                    }
                }
            }
        }
    }
}

/// Simple wrap layout for mixed text + custom emoji.
struct PlinkEmojiFlow<Content: View>: View {
    var spacing: CGFloat = 4
    @ViewBuilder var content: Content

    var body: some View {
        PlinkEmojiFlowLayout(spacing: spacing) { content }
    }
}

private struct PlinkEmojiFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 280
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, h: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxW, x > 0 {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            h = max(h, y + rowH)
        }
        return CGSize(width: maxW, height: max(h, rowH))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

// MARK: - V4AIState (used by WatchRoomModel + RoomAIAssistantBanner)
enum V4AIState: String, Sendable {
    case idle, listening, thinking, speaking, moderating, offline, failed
}

// MARK: - Rave Color Aliases (for PaywallView, ProfileView compatibility)
// These map old rave* names to Cinema2026 equivalents.

extension Color {
    static var ravePrimary: Color { Cinema2026.accent }
    static var raveSecondary: Color { Cinema2026.accent }
    static var raveAccent: Color { Cinema2026.accent }
    static var raveBackground: Color { Cinema2026.background }
    static var raveCard: Color { Cinema2026.surface }
    static var raveSurface: Color { Cinema2026.surface }
    static var raveRaised: Color { Cinema2026.raised }
    static var raveDivider: Color { Cinema2026.divider }
    static var raveTextPrimary: Color { Cinema2026.text }
    static var raveTextSecondary: Color { Cinema2026.secondary }
    static var raveTextTertiary: Color { Cinema2026.secondary }
    static var raveMuted: Color { Cinema2026.secondary }
    static var raveDanger: Color { Cinema2026.danger }
    static var raveWarning: Color { Cinema2026.amber }
    static var raveGreen: Color { Color(red: 0.15, green: 0.85, blue: 0.64) }
    static var raveCyan: Color { Cinema2026.accent }
    static var raveCoral: Color { Color(red: 1.0, green: 0.42, blue: 0.42) }
    static var raveGradient: LinearGradient {
        LinearGradient(colors: [Cinema2026.accent, Color(red: 0.15, green: 0.85, blue: 0.64)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Bio Color Aliases (for ProfileView, RaveCloneApp compatibility)
extension Color {
    static var bioCyan: Color { Cinema2026.accent }
    static var bioEmerald: Color { Color(red: 0.15, green: 0.85, blue: 0.64) }
    static var bioTeal: Color { Color(red: 0.05, green: 0.71, blue: 0.79) }
    static var bioAmber: Color { Cinema2026.amber }
    static var bioCoral: Color { Color(red: 1.0, green: 0.42, blue: 0.42) }
    static var bioRose: Color { Color(red: 1.0, green: 0.56, blue: 0.67) }
    static var bioObsidian: Color { Cinema2026.background }
    static var bioNeonRing: LinearGradient {
        LinearGradient(colors: [Color.bioCyan.opacity(0.5), Color.bioEmerald.opacity(0.25)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - FeatureFlags stub (for PresenceBar, RaveCloneApp)

// MARK: - Missing types for DiscoveryHomeView

extension CinemaRadius {
    static let poster: CGFloat = 12
    static let card: CGFloat = 13
    static let control: CGFloat = 14
    static let panel: CGFloat = 20
}

// ParticipantAvatarStack — overlapping avatar circles
struct ParticipantAvatarStack: View {
    let participants: [UserPreview]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(participants.prefix(3).enumerated()), id: \.offset) { index, p in
                Circle()
                    .fill(Cinema2026.accent.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(String((p.displayName ?? p.username).prefix(1)).uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .overlay(Circle().stroke(Cinema2026.background, lineWidth: 2))
                    .zIndex(Double(3 - index))
            }
        }
    }
}

// hoverScale modifier
extension View {
    func hoverScale(_ active: Bool = true) -> some View {
        self.scaleEffect(active ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.2), value: active)
    }
}

// ShimmerView — loading placeholder
struct ShimmerView: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Cinema2026.surface,
                        Cinema2026.raised,
                        Cinema2026.surface,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .opacity(0.6)
    }
}
