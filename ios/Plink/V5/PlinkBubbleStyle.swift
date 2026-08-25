//
//  PlinkBubbleStyle.swift
//  Plink
//
//  P1 — BubbleStyle protocol, registry, and renderer.
//  Implements Section 2.3 of PLINK_CUSTOMIZATION_AUTH_ADMIN_SPEC_FOR_GLM_5_2.md
//
//  Rules:
//  - BubbleStyle belongs to SENDER. ID rides with message (`ChatMessage.bubbleStyle`).
//  - Server validates premium IDs at send time only.
//  - All clients MUST render premium styles even for free recipients.
//  - Only the last 3-5 visible messages animate; older = static snapshot.
//  - Forbidden: infinite fast flicker, resize-after-layout, text animation,
//    heavy shaders on all messages simultaneously.
//
//  This file is the new single source of truth for bubble rendering.
//  Replaces the old `StyledChatBubble.swift`, `WatchChatBubble.swift`,
//  and the old `Models/BubbleStyle.swift` enum.
//

import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - BubbleStyleRegistry

enum BubbleStyleRegistry {
    static func descriptor(id: String) -> AppearanceDescriptor? {
        AppearanceCatalog.bubbleStatic.first { $0.id == id }
            ?? AppearanceCatalog.bubbleAnimated.first { $0.id == id }
    }

    /// Always returns a renderable descriptor — falls back to `bubble-quiet`.
    static func safeDescriptor(id: String?) -> AppearanceDescriptor {
        guard let id, let d = descriptor(id: id) else {
            return AppearanceCatalog.bubbleStatic.first { $0.id == "bubble-quiet" }!
        }
        return d
    }

    /// Bridge from legacy backend IDs (`default`, `cute_duck`, `neon_cyber`,
    /// `admin_bubble`) to the new V5 IDs. Old messages from before the V5
    /// rollout will continue to render — they map to the closest new style.
    static func migrateLegacyID(_ raw: String?) -> String {
        switch raw ?? "default" {
        case "default":       return "bubble-quiet"
        case "cute_duck":     return "bubble-quiet"
        case "neon_cyber":    return "bubble-accent"
        case "admin_bubble":  return "bubble-cine-artdeco"
        case "bubble-ink-flow": return "bubble-cine-marquee"
        case "bubble-comet":    return "bubble-cine-noir"
        case "bubble-signal":   return "bubble-accent"
        // Убранные бесплатные рамки → два стандартных стиля
        case "bubble-frame-cat", "bubble-frame-dog", "bubble-frame-hearts":
            return "bubble-quiet"
        // Старые премиум-рамки → детальный кино-набор
        case "bubble-frame-bunny", "bubble-frame-panda", "bubble-frame-frog":
            return "bubble-cine-marquee"
        case "bubble-frame-fox", "bubble-frame-bear", "bubble-frame-dino":
            return "bubble-cine-filmreel"
        case "bubble-frame-flowers":
            return "bubble-cine-artdeco"
        case "bubble-frame-unicorn", "bubble-frame-rainbow", "bubble-frame-stars":
            return "bubble-cine-vippass"
        case "bubble-pulse-ring": return "bubble-accent"
        case "bubble-prism":      return "bubble-cine-noir"
        default:              return raw ?? "bubble-quiet"
        }
    }
}

// MARK: - TikTok-style frame models (decorative borders + animal corners)

/// One “frame model” — like TikTok chat frames: fill, border, corner mascots.
enum BubbleFrameModel: String, CaseIterable, Sendable {
    case quiet
    case accent
    case cat
    case dog
    case hearts
    case bunny
    case panda
    case fox
    case bear
    case unicorn
    case dino
    case stars
    case flowers
    case rainbow
    case frog
    case pulse
    case prism

    static func resolve(styleID: String?) -> BubbleFrameModel {
        let id = BubbleStyleRegistry.migrateLegacyID(styleID)
        switch id {
        case "bubble-quiet": return .quiet
        case "bubble-accent": return .accent
        case "bubble-frame-cat": return .cat
        case "bubble-frame-dog": return .dog
        case "bubble-frame-hearts": return .hearts
        case "bubble-frame-bunny": return .bunny
        case "bubble-frame-panda": return .panda
        case "bubble-frame-fox": return .fox
        case "bubble-frame-bear": return .bear
        case "bubble-frame-unicorn": return .unicorn
        case "bubble-frame-dino": return .dino
        case "bubble-frame-stars": return .stars
        case "bubble-frame-flowers": return .flowers
        case "bubble-frame-rainbow": return .rainbow
        case "bubble-frame-frog": return .frog
        case "bubble-pulse-ring": return .pulse
        case "bubble-prism": return .prism
        default: return .quiet
        }
    }

    /// Corner stickers (TikTok puts animals on frame corners).
    var cornerEmojis: (tl: String?, tr: String?, bl: String?, br: String?) {
        switch self {
        case .quiet, .accent, .pulse, .prism:
            return (nil, nil, nil, nil)
        case .cat:
            return ("🐱", "🐱", "🐾", "🐾")
        case .dog:
            return ("🐶", "🐶", "🦴", "🐾")
        case .hearts:
            return ("💕", "💖", "💗", "💘")
        case .bunny:
            return ("🐰", "🐰", "🥕", "✨")
        case .panda:
            return ("🐼", "🐼", "🎋", "🍃")
        case .fox:
            return ("🦊", "🦊", "🍂", "✨")
        case .bear:
            return ("🐻", "🐻", "🍯", "💤")
        case .unicorn:
            return ("🦄", "✨", "🌈", "💫")
        case .dino:
            return ("🦕", "🦕", "🌿", "🥚")
        case .stars:
            return ("⭐", "✨", "🌙", "💫")
        case .flowers:
            return ("🌸", "🌼", "🌺", "🌷")
        case .rainbow:
            return ("🌈", "✨", "☁️", "💛")
        case .frog:
            return ("🐸", "🐸", "🍃", "💚")
        }
    }

    var borderColors: [Color] {
        switch self {
        case .quiet: return [Color.white.opacity(0.14)]
        case .accent: return [Color(hex: "#00D4FF"), Color(hex: "#3FE8C8")]
        case .cat: return [Color(hex: "#FF8DC7"), Color(hex: "#FFC6E8"), Color(hex: "#FF6BB5")]
        case .dog: return [Color(hex: "#F5A962"), Color(hex: "#FFD4A3")]
        case .hearts: return [Color(hex: "#FF6B9D"), Color(hex: "#FFB3C7")]
        case .bunny: return [Color(hex: "#E8D5FF"), Color(hex: "#C4B5FD")]
        case .panda: return [Color.white.opacity(0.9), Color.black.opacity(0.55)]
        case .fox: return [Color(hex: "#FF7A18"), Color(hex: "#FFD29D")]
        case .bear: return [Color(hex: "#A67C52"), Color(hex: "#E8C4A0")]
        case .unicorn: return [Color(hex: "#F0ABFC"), Color(hex: "#A5B4FC"), Color(hex: "#67E8F9")]
        case .dino: return [Color(hex: "#4ADE80"), Color(hex: "#86EFAC")]
        case .stars: return [Color(hex: "#6366F1"), Color(hex: "#FDE68A")]
        case .flowers: return [Color(hex: "#FB7185"), Color(hex: "#F9A8D4")]
        case .rainbow: return [
            Color(hex: "#F87171"), Color(hex: "#FBBF24"),
            Color(hex: "#34D399"), Color(hex: "#60A5FA"), Color(hex: "#A78BFA")
        ]
        case .frog: return [Color(hex: "#4ADE80"), Color(hex: "#BBF7D0")]
        case .pulse: return [Color(hex: "#3FE8C8"), Color(hex: "#00D4FF")]
        case .prism: return [Color(hex: "#F59E0B"), Color(hex: "#3FE8C8"), Color(hex: "#A855F7")]
        }
    }

    /// Fully opaque fills (Telegram rule: wallpaper never shows through the capsule).
    var fillColors: [Color] {
        switch self {
        case .quiet:
            // Incoming default — solid slate (see PlinkMessageBubble for own/incoming split)
            return [Color(hex: "#2B2F36")]
        case .accent, .pulse:
            return [Color(hex: "#00D4FF"), Color(hex: "#3FE8C8")]
        case .cat:
            return [Color(hex: "#4A2540"), Color(hex: "#6B3558")]
        case .dog:
            return [Color(hex: "#4A3220"), Color(hex: "#6B4528")]
        case .hearts:
            return [Color(hex: "#4A1E36"), Color(hex: "#6B2A48")]
        case .bunny:
            return [Color(hex: "#352850"), Color(hex: "#4A3A6B")]
        case .panda:
            return [Color(hex: "#1E1E1E"), Color(hex: "#2E2E2E")]
        case .fox:
            return [Color(hex: "#4A2814"), Color(hex: "#6B3A1C")]
        case .bear:
            return [Color(hex: "#352418"), Color(hex: "#4A3522")]
        case .unicorn:
            return [Color(hex: "#352050"), Color(hex: "#28365A")]
        case .dino:
            return [Color(hex: "#1A3222"), Color(hex: "#284A32")]
        case .stars:
            return [Color(hex: "#181A3A"), Color(hex: "#242858")]
        case .flowers:
            return [Color(hex: "#3A1C2E"), Color(hex: "#4A283C")]
        case .rainbow:
            return [Color(hex: "#22223A"), Color(hex: "#2E2E52")]
        case .frog:
            return [Color(hex: "#1A3220"), Color(hex: "#284A2C")]
        case .prism:
            return [Color(hex: "#221A3A"), Color(hex: "#342858")]
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .quiet: return 0.8
        case .accent, .pulse: return 1.6
        case .rainbow, .unicorn, .prism: return 2.4
        default: return 2.0
        }
    }

    var isDecorative: Bool {
        switch self {
        case .quiet, .accent, .pulse, .prism: return false
        default: return true
        }
    }
}

// MARK: - BubbleStyleRenderer

/// Renders a single chat bubble with the style indicated by `message.bubbleStyle`.
/// Pass `indexFromBottom` to control animation — only the last 5 messages animate;
/// older ones render as static snapshots.
///
/// Works with the existing `ChatMessage` model (no model changes required).
internal struct BubbleStyleRenderer<Content: View>: View {
    let message: ChatMessage
    let isOutgoing: Bool
    let indexFromBottom: Int   // 0 = most recent
    let content: () -> Content

    @State private var animatePulse = false
    @State private var animateComet = false
    @State private var animateSignal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let animationThreshold = 5   // only last 5 animate

    init(
        message: ChatMessage,
        isOutgoing: Bool,
        indexFromBottom: Int = 0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.message = message
        self.isOutgoing = isOutgoing
        self.indexFromBottom = indexFromBottom
        self.content = content
    }

    var body: some View {
        let migratedID = BubbleStyleRegistry.migrateLegacyID(message.bubbleStyle)
        let desc = BubbleStyleRegistry.safeDescriptor(id: migratedID)
        let shouldAnimate = indexFromBottom < animationThreshold && !reduceMotion

        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground(desc))
            .overlay(bubbleOverlay(desc, animate: shouldAnimate))
            .clipShape(V5BubbleShape(isOutgoing: isOutgoing))
            .onAppear {
                guard shouldAnimate else { return }
                triggerAnimation(for: desc.id)
            }
    }

    // MARK: - Background

    @ViewBuilder
    private func bubbleBackground(_ desc: AppearanceDescriptor) -> some View {
        switch desc.id {
        case "bubble-quiet":
            Color.white.opacity(0.06)
        case "bubble-accent":
            LinearGradient(
                colors: desc.previewColors.map { Color(hex: $0) },
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case "bubble-ink-flow":
            TimelineView(.animation) { ctx in
                inkFlowGradient(t: ctx.date.timeIntervalSinceReferenceDate, desc: desc)
            }
        case "bubble-prism":
            TimelineView(.animation) { ctx in
                prismGradient(t: ctx.date.timeIntervalSinceReferenceDate, desc: desc)
            }
        default:
            Color.white.opacity(0.06)
        }
    }

    // MARK: - Animated gradient helpers (extracted so TimelineView closure
    // is a single View expression — Swift 5.9 @ViewBuilder doesn't accept
    // `let` statements followed by a View in all contexts).

    private func inkFlowGradient(t: Double, desc: AppearanceDescriptor) -> some View {
        LinearGradient(
            colors: [
                Color(hex: desc.previewColors[0]),
                Color(hex: desc.previewColors[1]),
                Color(hex: desc.previewColors[0])
            ],
            startPoint: UnitPoint(x: 0.5 + 0.4 * sin(t * 0.3), y: 0),
            endPoint: UnitPoint(x: 0.5 + 0.4 * cos(t * 0.3), y: 1)
        )
    }

    private func prismGradient(t: Double, desc: AppearanceDescriptor) -> some View {
        LinearGradient(
            colors: desc.previewColors.map { Color(hex: $0) },
            startPoint: UnitPoint(x: 0.5 + 0.5 * cos(t * 0.18), y: 0.5 + 0.5 * sin(t * 0.18)),
            endPoint: UnitPoint(x: 0.5 - 0.5 * cos(t * 0.18), y: 0.5 - 0.5 * sin(t * 0.18))
        )
    }

    // MARK: - Overlay

    @ViewBuilder
    private func bubbleOverlay(_ desc: AppearanceDescriptor, animate: Bool) -> some View {
        switch desc.id {
        case "bubble-pulse-ring":
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    Color(hex: desc.previewColors[0]),
                    lineWidth: 2
                )
                .opacity(animatePulse && animate ? 1 : 0)
                .scaleEffect(animatePulse && animate ? 1.04 : 1.0)

        case "bubble-comet":
            GeometryReader { geo in
                Circle()
                    .fill(Color(hex: desc.previewColors[0]))
                    .frame(width: 6, height: 6)
                    .blur(radius: 2)
                    .opacity(animateComet && animate ? 0.9 : 0)
                    .offset(x: animateComet && animate ? geo.size.width - 12 : 0, y: 4)
            }
            .mask(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 8)
            )

        case "bubble-signal":
            HStack(spacing: 4) {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .strokeBorder(
                            Color(hex: desc.previewColors[i % desc.previewColors.count]),
                            lineWidth: 1.5
                        )
                        .scaleEffect(animateSignal && animate ? 1.4 : 0.9)
                        .opacity(animateSignal && animate ? 0 : 0.7)
                }
            }
            .frame(width: 18, height: 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(6)

        case "bubble-ink-flow", "bubble-prism":
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)

        case "bubble-accent":
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)

        default: // bubble-quiet
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        }
    }

    // MARK: - Trigger

    private func triggerAnimation(for id: String) {
        switch id {
        case "bubble-pulse-ring":
            withAnimation(.easeOut(duration: 0.7)) { animatePulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                animatePulse = false
            }
        case "bubble-comet":
            withAnimation(.easeInOut(duration: 0.6)) { animateComet = true }
        case "bubble-signal":
            withAnimation(.easeOut(duration: 0.6)) { animateSignal = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.6)) { animateSignal = false }
            }
        default:
            break
        }
    }
}

// MARK: - V5BubbleShape (renamed to avoid clash with any legacy BubbleShape)

/// Telegram-sized capsule bubble: large continuous corners; slight tail cut
/// only on the last message of a group (via isLastInGroup on the parent).
struct V5BubbleShape: Shape {
    let isOutgoing: Bool
    /// When false (middle of chain), use fully rounded capsule corners.
    var isLastInGroup: Bool = true

    func path(in rect: CGRect) -> Path {
        // Telegram iOS: short messages read as true capsules (radius ≈ half height),
        // multi-line bubbles keep a large continuous corner (~20–22pt).
        let r = min(22, max(16, rect.height / 2))
        var path = Path()
        // Tail corner is softer than a sharp point (TG ≈ 6–8pt)
        let tail: CGFloat = isLastInGroup ? 8 : r
        let tl: CGFloat = isOutgoing ? r : (isLastInGroup ? tail : r)
        let tr: CGFloat = isOutgoing ? (isLastInGroup ? tail : r) : r
        let bl: CGFloat = r
        let br: CGFloat = r
        path.addRoundedRect(
            in: rect,
            cornerRadii: RectangleCornerRadii(
                topLeading: tl, bottomLeading: bl,
                bottomTrailing: br, topTrailing: tr
            )
        )
        return path
    }
}

// MARK: - Telegram bubble metrics (shared DM + room)

/// Canonical sizes so DM / room / preview all match Telegram proportions.
enum PlinkTelegramBubbleMetrics {
    /// Telegram iOS message body ≈ 17pt
    static let fontSize: CGFloat = 17
    static let padH: CGFloat = 15
    static let padV: CGFloat = 11
    static let decorativePadH: CGFloat = 20
    static let decorativePadV: CGFloat = 13
    static let decorativeOuter: CGFloat = 11
    /// Telegram bubble max width as share of available chat width.
    static let maxWidthRatio: CGFloat = 0.78
    static let maxBubbleWidth: CGFloat = 320
    static let maxPhotoBubbleWidth: CGFloat = 260
    static let maxPhotoBubbleHeight: CGFloat = 320
    static let minVoiceBubbleWidth: CGFloat = 168
    static let maxVoiceBubbleWidth: CGFloat = 238
    static let avatarSize: CGFloat = 32
    /// Vertical gap between consecutive same-sender messages.
    /// Was 2 — too tight, bubbles visually overlapped on iOS 17+.
    /// 6 gives clean separation without breaking Telegram cluster feel.
    static let clusterGapSame: CGFloat = 6
    static let clusterGapNew: CGFloat = 10
}

// MARK: - BubbleIndexTracker

/// Computes `indexFromBottom` for each message in a list. Only the last
/// `animationThreshold` items animate.
enum BubbleIndexTracker {
    static func indexFromBottom(messageID: String, in messages: [ChatMessage]) -> Int {
        guard let idx = messages.lastIndex(where: { $0.id == messageID }) else {
            return .max
        }
        return messages.count - 1 - idx
    }
}

// MARK: - User preference (Оформление → Бабл-стиль)

enum PlinkBubbleStylePrefs {
    static let storageKey = "plink.bubbleStyleID"

    static var currentID: String {
        UserDefaults.standard.string(forKey: storageKey)
            ?? AppearanceCatalog.defaultBubbleStyleID
    }

    static func set(_ id: String) {
        UserDefaults.standard.set(id, forKey: storageKey)
        NotificationCenter.default.post(name: .plinkBubbleStyleChanged, object: id)
    }

    static var allStyles: [AppearanceDescriptor] {
        AppearanceCatalog.bubbleStatic + AppearanceCatalog.bubbleAnimated
    }
}

extension Notification.Name {
    static let plinkBubbleStyleChanged = Notification.Name("plink.bubbleStyleChanged")
}

// MARK: - Wire format (style rides with message text — all clients see it)

/// Embeds the sender's bubble style into message text so every device can
/// render it without relying on local preferences.
/// Format: `[[bs:STYLE_ID]]actual message text`
enum PlinkBubbleWire {
    private static let prefix = "[[bs:"
    private static let suffix = "]]"

    /// Encode style for transport. Free-tier safe styles always allowed;
    /// premium IDs still travel so free recipients can *see* them.
    static func encode(text: String, styleID: String?) -> String {
        let raw = (styleID ?? PlinkBubbleStylePrefs.currentID).trimmingCharacters(in: .whitespacesAndNewlines)
        let id = BubbleStyleRegistry.migrateLegacyID(raw.isEmpty ? nil : raw)
        // Strip accidental nested markers from body
        let body = decode(text).text
        return "\(prefix)\(id)\(suffix)\(body)"
    }

    static func decode(_ raw: String) -> (styleID: String?, text: String) {
        guard raw.hasPrefix(prefix),
              let end = raw.range(of: suffix) else {
            return (nil, raw)
        }
        let idStart = raw.index(raw.startIndex, offsetBy: prefix.count)
        let id = String(raw[idStart..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(raw[end.upperBound...])
        guard !id.isEmpty, id.count <= 64, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            return (nil, raw)
        }
        return (BubbleStyleRegistry.migrateLegacyID(id), body)
    }
}

// MARK: - Telegram-style message clustering

/// Avatar + name only on group edges (like Telegram).
struct ChatClusterLayout: Equatable {
    /// Show avatar on this row (last message of consecutive same-sender group).
    let showAvatar: Bool
    /// Show sender name (first message of group, incoming only).
    let showName: Bool
    /// First bubble in a same-sender run.
    let isFirstInGroup: Bool
    /// Last bubble in a same-sender run.
    let isLastInGroup: Bool
    /// Spacing *before* this row.
    let topPadding: CGFloat

    static func compute(
        senderId: String,
        previousSenderId: String?,
        nextSenderId: String?,
        isOwn: Bool
    ) -> ChatClusterLayout {
        let samePrev = previousSenderId == senderId
        let sameNext = nextSenderId == senderId
        return ChatClusterLayout(
            showAvatar: !sameNext,
            showName: !isOwn && !samePrev,
            isFirstInGroup: !samePrev,
            isLastInGroup: !sameNext,
            topPadding: samePrev
                ? PlinkTelegramBubbleMetrics.clusterGapSame
                : PlinkTelegramBubbleMetrics.clusterGapNew
        )
    }
}

// MARK: - Shared bubble for DM + room chat (TikTok frames + glass capsules)

/// Renders text with the **sender's** bubble / frame style.
/// TikTok-style models add animal corners + colored borders (synced via wire).
struct PlinkMessageBubble: View {
    let text: String
    let isOwn: Bool
    /// Sender style ID from the message (not local prefs for peers).
    var styleID: String? = nil
    /// Defaults to Telegram body size (17pt).
    var fontSize: CGFloat = PlinkTelegramBubbleMetrics.fontSize
    /// Telegram tail: only last in group gets the "pointy" corner.
    var isLastInGroup: Bool = true

    private var frame: BubbleFrameModel {
        if let styleID, !styleID.isEmpty {
            return BubbleFrameModel.resolve(styleID: styleID)
        }
        if isOwn {
            return BubbleFrameModel.resolve(styleID: PlinkBubbleStylePrefs.currentID)
        }
        return .quiet
    }

    private var shape: V5BubbleShape {
        V5BubbleShape(isOutgoing: isOwn, isLastInGroup: isLastInGroup)
    }

    private var resolvedStyleID: String {
        if let styleID, !styleID.isEmpty { return styleID }
        if isOwn { return PlinkBubbleStylePrefs.currentID }
        return "bubble-quiet"
    }

    var body: some View {
        // Детальные кино-баблы Plink+ — pixel-perfect PNG-арт из референса
        if let cine = CinemaBubbleStyle(rawValue: BubbleStyleRegistry.migrateLegacyID(resolvedStyleID)) {
            CinemaImageBubble(text: text, style: cine, fontSize: fontSize)
        } else {
            standardBubble
        }
    }

    // MARK: - Standard bubble (Telegram night style)
    // Непрозрачная заливка + форма с хвостиком (V5BubbleShape). Прошлая
    // версия рисовала «TikTok-пилюли»: чужие сообщения — чёрная капсула
    // 45–60% прозрачности, которая на тёмном фоне комнаты сливалась в ничто,
    // и свои/чужие переставали различаться; готовые fillLayer/borderLayer
    // при этом лежали мёртвым кодом. Возвращены как единственный путь.
    @ViewBuilder
    private var standardBubble: some View {
        let isDecorative = frame.isDecorative
        let padH: CGFloat = isDecorative ? PlinkTelegramBubbleMetrics.decorativePadH : PlinkTelegramBubbleMetrics.padH
        let padV: CGFloat = isDecorative ? PlinkTelegramBubbleMetrics.decorativePadV : PlinkTelegramBubbleMetrics.padV

        MessageRichText(text: text, fontSize: fontSize, textColor: bubbleTextColor)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .background(fillLayer.clipShape(shape))
            .overlay(borderLayer)
            .overlay(alignment: .center) {
                if isDecorative { TikTokFrameDecor(frame: frame) }
            }
            .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
    }

    /// Белый на тёмных заливках; тёмный — на ярких циановых (accent/pulse),
    /// у которых fillColors светлее текста.
    private var bubbleTextColor: Color {
        switch frame {
        case .accent, .pulse: return Color(hex: "#08222B")
        default: return .white
        }
    }

    @ViewBuilder
    private var fillLayer: some View {
        switch frame {
        case .quiet:
            if isOwn {
                // Исходящие — акцентный градиент (тот же outgoingBubble, что у
                // голосовых и фото): один цвет исходящих во всех чатах, вместо
                // сине-зелёного градиента, живущего отдельно от палитры.
                Cinema2026.outgoingBubble
            } else {
                // Telegram night incoming: clean graphite gray — readable on any wallpaper.
                LinearGradient(
                    colors: [
                        Color(hex: "#2B3138"),
                        Color(hex: "#232930")
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        default:
            LinearGradient(
                colors: frame.fillColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var borderLayer: some View {
        if frame.borderColors.count >= 2 {
            shape
                .stroke(
                    AngularGradient(
                        colors: frame.borderColors + [frame.borderColors[0]],
                        center: .center
                    ),
                    lineWidth: frame.borderWidth
                )
        } else {
            // Soft edge so solid capsules separate from wallpaper patterns
            shape
                .stroke(
                    isOwn
                        ? Color.white.opacity(0.22)
                        : Color.white.opacity(0.14),
                    lineWidth: max(frame.borderWidth, 1)
                )
        }
    }
}

// MARK: - Chat image compression/cache

struct ChatCompressedImage: Sendable {
    let dataURL: String
    let image: UIImage
    let byteCount: Int
}

enum ChatImageCompressor {
    static func compress(_ data: Data, maxDimension: CGFloat = 1600, maxBytes: Int = 2_100_000) throws -> ChatCompressedImage {
        guard let source = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
        let normalized = normalize(source)
        let resized = resize(normalized, maxDimension: maxDimension)
        var quality: CGFloat = 0.82
        var jpeg = resized.jpegData(compressionQuality: quality)
        while let current = jpeg, current.count > maxBytes, quality > 0.42 {
            quality -= 0.08
            jpeg = resized.jpegData(compressionQuality: quality)
        }
        guard let final = jpeg, final.count <= maxBytes else { throw URLError(.dataLengthExceedsMaximum) }
        return ChatCompressedImage(
            dataURL: "data:image/jpeg;base64,\(final.base64EncodedString())",
            image: resized,
            byteCount: final.count
        )
    }

    private static func normalize(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

@MainActor
final class ChatPhotoCache {
    static let shared = ChatPhotoCache()
    private var images: [String: UIImage] = [:]

    func register(_ image: UIImage, for messageId: String) {
        images[messageId] = image
    }

    func promote(from localId: String, to serverId: String) {
        if let image = images[localId] {
            images[serverId] = image
        }
    }

    func image(for messageId: String) -> UIImage? {
        images[messageId]
    }
}

// MARK: - Shared photo bubble

struct PlinkPhotoMessageBubble: View {
    let imageURL: URL?
    let localImage: UIImage?
    let caption: String
    let isOwn: Bool
    var styleID: String? = nil
    var isPending: Bool = false
    var isFailed: Bool = false
    var isLastInGroup: Bool = true

    @State private var remoteImage: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false

    private var shape: V5BubbleShape {
        V5BubbleShape(isOutgoing: isOwn, isLastInGroup: isLastInGroup)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: caption.isEmpty ? 0 : 8) {
            photoContent
                .frame(maxWidth: PlinkTelegramBubbleMetrics.maxPhotoBubbleWidth)
                .frame(height: 188)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if isPending || isFailed {
                        HStack(spacing: 4) {
                            Image(systemName: isFailed ? "exclamationmark.triangle.fill" : "arrow.up.circle.fill")
                            Text(isFailed ? "Ошибка" : "Отправка")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.48), in: Capsule())
                        .padding(8)
                    }
                }

            if !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MessageRichText(text: caption, fontSize: PlinkTelegramBubbleMetrics.fontSize, textColor: .white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .background(
            ZStack {
                Color(hex: "#1A1C20")
                photoFillLayer.opacity(caption.isEmpty ? 0.72 : 1)
            }
        )
        .clipShape(shape)
        .overlay(photoBorderLayer)
        .shadow(color: .black.opacity(0.20), radius: 3, y: 1)
        .task(id: imageURL?.absoluteString) {
            await loadRemoteIfNeeded()
        }
        .accessibilityLabel(caption.isEmpty ? "Фото" : "Фото: \(caption)")
    }

    @ViewBuilder
    private var photoContent: some View {
        if let localImage {
            Image(uiImage: localImage)
                .resizable()
                .scaledToFill()
        } else if let remoteImage {
            Image(uiImage: remoteImage)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 8) {
                    Image(systemName: loadFailed ? "photo.badge.exclamationmark" : "photo")
                        .font(.system(size: 28, weight: .semibold))
                    Text(loadFailed ? "Не удалось загрузить" : "Фото")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.white.opacity(0.72))
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .offset(y: 42)
                }
            }
        }
    }

    private func loadRemoteIfNeeded() async {
        guard localImage == nil, remoteImage == nil, let imageURL else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            var request = URLRequest(url: imageURL)
            let token = APIClient.shared.authToken ?? AuthTokenStore.shared.token
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                loadFailed = true
                return
            }
            remoteImage = image
        } catch {
            loadFailed = true
        }
    }

    @ViewBuilder
    private var photoFillLayer: some View {
        if isOwn {
            LinearGradient(colors: [Color(red: 0.22, green: 0.64, blue: 1.0), Color(red: 0.11, green: 0.78, blue: 0.48)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            LinearGradient(colors: [Color(hex: "#2B3138"), Color(hex: "#232930")], startPoint: .top, endPoint: .bottom)
        }
    }

    private var photoBorderLayer: some View {
        shape.stroke(isOwn ? Color.white.opacity(0.22) : Color.white.opacity(0.14), lineWidth: 1)
    }
}

// MARK: - TikTok frame decorations (corner mascots)

// MARK: - Cinema premium bubbles (pixel-perfect PNG art from reference)

/// 5 детальных кино-баблов Plink+. Арт хранится в Resources/CinemaBubbles/
/// и растягивается 9-slice'ом, сохраняя орнаменты по краям 1:1.
enum CinemaBubbleStyle: String, CaseIterable, Sendable {
    case artdeco  = "bubble-cine-artdeco"
    case filmreel = "bubble-cine-filmreel"
    case marquee  = "bubble-cine-marquee"
    case vippass  = "bubble-cine-vippass"
    case noir     = "bubble-cine-noir"

    var assetName: String {
        switch self {
        case .artdeco:  return "bubble-artdeco"
        case .filmreel: return "bubble-filmreel"
        case .marquee:  return "bubble-marquee"
        case .vippass:  return "bubble-vippass"
        case .noir:     return "bubble-noir"
        }
    }

    /// Цвет текста подобран под каждый арт.
    var textColor: Color {
        switch self {
        case .artdeco:  return Color(hex: "#F3D9A4")
        case .filmreel: return Color(hex: "#EAF2F8")
        case .marquee:  return Color(hex: "#FFE9B8")
        case .vippass:  return Color(hex: "#4A3208")
        case .noir:     return Color(hex: "#E8EDF4")
        }
    }

    /// Боковой отступ 9-slice (защищает орнаменты/бобины/надписи от растяжения).
    var sideInset: CGFloat {
        switch self {
        case .artdeco:  return 70
        case .filmreel: return 85
        case .marquee:  return 50
        case .vippass:  return 100
        case .noir:     return 60
        }
    }

    /// Вертикальный отступ 9-slice.
    var vInset: CGFloat {
        switch self {
        case .artdeco:  return 24
        case .filmreel: return 28
        case .marquee:  return 28
        case .vippass:  return 30
        case .noir:     return 28
        }
    }
}

/// Кэш арт-изображений кино-баблов. PNG приводится к ширине 340pt,
/// чтобы 9-slice-вставки соответствовали экранным размерам.
@MainActor
enum CinemaBubbleAssets {
    private static var cache: [String: UIImage] = [:]
    private static let targetWidth: CGFloat = 340

    static func image(for style: CinemaBubbleStyle) -> UIImage? {
        if let cached = cache[style.assetName] { return cached }
        guard let url = Bundle.main.url(
            forResource: style.assetName,
            withExtension: "png",
            subdirectory: "CinemaBubbles"
        ), let raw = UIImage(contentsOfFile: url.path) else { return nil }
        let scale = targetWidth / max(raw.size.width, 1)
        let size = CGSize(width: targetWidth, height: raw.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0 // native screen scale
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            raw.draw(in: CGRect(origin: .zero, size: size))
        }
        cache[style.assetName] = scaled
        return scaled
    }
}

/// Рендер кино-бабла: текст поверх 9-slice арт-подложки.
struct CinemaImageBubble: View {
    let text: String
    let style: CinemaBubbleStyle
    var fontSize: CGFloat = PlinkTelegramBubbleMetrics.fontSize

    var body: some View {
        MessageRichText(text: text, fontSize: fontSize, textColor: style.textColor)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
            .padding(.horizontal, style.sideInset * 0.55 + 14)
            .padding(.vertical, 16)
            .frame(minWidth: style.sideInset * 1.4 + 48, minHeight: style.vInset * 2 + 8)
            .background {
                if let art = CinemaBubbleAssets.image(for: style) {
                    Image(uiImage: art)
                        .resizable(
                            capInsets: EdgeInsets(
                                top: style.vInset,
                                leading: style.sideInset,
                                bottom: style.vInset,
                                trailing: style.sideInset
                            ),
                            resizingMode: .stretch
                        )
                } else {
                    // Fallback, если арт не найден в бандле
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(hex: "#2B2F36"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color(hex: "#D4A24C").opacity(0.6), lineWidth: 1.5)
                        )
                }
            }
            .shadow(color: .black.opacity(0.30), radius: 5, y: 2)
    }
}

// MARK: - TikTok frame decorations (corner mascots)

/// Animals / stickers sit on bubble corners — same idea as TikTok message frames.
private struct TikTokFrameDecor: View {
    let frame: BubbleFrameModel

    var body: some View {
        let c = frame.cornerEmojis
        GeometryReader { geo in
            let s: CGFloat = min(22, max(16, geo.size.height * 0.28))
            ZStack {
                if let e = c.tl {
                    Text(e).font(.system(size: s))
                        .position(x: 2, y: 2)
                        .offset(x: s * 0.15, y: s * 0.1)
                }
                if let e = c.tr {
                    Text(e).font(.system(size: s))
                        .position(x: geo.size.width - 2, y: 2)
                        .offset(x: -s * 0.15, y: s * 0.1)
                }
                if let e = c.bl {
                    Text(e).font(.system(size: s * 0.85))
                        .position(x: 4, y: geo.size.height - 2)
                        .offset(x: s * 0.1, y: -s * 0.1)
                }
                if let e = c.br {
                    Text(e).font(.system(size: s * 0.85))
                        .position(x: geo.size.width - 4, y: geo.size.height - 2)
                        .offset(x: -s * 0.1, y: -s * 0.1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
