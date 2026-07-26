import SwiftUI

// MARK: - Telegram 2026 Chat Navigation Header (Liquid Glass)
// Replicates the TG iOS Jan–Jul 2026 chat header:
// • Ultra-thin blur bar (Liquid Glass)
// • Back button with unread badge
// • Centered avatar + name + online status
// • Phone + Video call buttons (right side)
// • Tap header → profile sheet

// MARK: - Chat Header

struct TGChatHeaderView: View {
    let name: String
    let subtitle: String          // "в сети" / "был(а) в 18:32" / "печатает..."
    let isOnline: Bool
    let isTyping: Bool
    let avatarURL: URL?
    let avatarLetter: String
    let unreadBack: Int           // badge on back button
    let accentColor: Color
    let onBack: () -> Void
    let onTapHeader: () -> Void
    let onCall: () -> Void
    let onVideo: () -> Void
    let onTheme: () -> Void

    var body: some View {
        ZStack {
            // Liquid Glass background
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.07),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 0.5)
                }

            HStack(spacing: 0) {
                // ── Back button ──
                Button(action: onBack) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .frame(width: 44, height: 44)

                        if unreadBack > 0 {
                            Text(unreadBack > 99 ? "99+" : "\(unreadBack)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.red))
                                .offset(x: 4, y: -2)
                        }
                    }
                }
                .padding(.leading, 4)

                Spacer()

                // ── Center: avatar + name + status ──
                Button(action: onTapHeader) {
                    HStack(spacing: 10) {
                        TGHeaderAvatar(
                            url: avatarURL,
                            letter: avatarLetter,
                            isOnline: isOnline,
                            accentColor: accentColor
                        )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            if isTyping {
                                TGTypingIndicator(color: accentColor)
                            } else {
                                Text(subtitle)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(
                                        isOnline ? accentColor : Color.white.opacity(0.55)
                                    )
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // ── Right: Call + Video + Theme ──
                HStack(spacing: 2) {
                    TGHeaderButton(icon: "phone", color: accentColor, action: onCall)
                    TGHeaderButton(icon: "video", color: accentColor, action: onVideo)
                    // M25 UX: тема чата теперь в привычном TG-меню «···»
                    Menu {
                        Button(action: onTheme) { Label(LocalizationManager.shared.string(.dmChatTheme), systemImage: "paintbrush") }
                        Button(action: onTapHeader) { Label(LocalizationManager.shared.string(.tabProfile), systemImage: "person.crop.circle") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.07)))
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(height: 52)
        }
        .frame(height: 52)
    }
}

// MARK: - Header Avatar

struct TGHeaderAvatar: View {
    let url: URL?
    let letter: String
    let isOnline: Bool
    let accentColor: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            fallbackCircle
                        }
                    }
                } else {
                    fallbackCircle
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))

            if isOnline {
                Circle()
                    .fill(Color(red: 0.20, green: 0.78, blue: 0.35))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1.5))
                    .offset(x: 1, y: 1)
            }
        }
    }

    private var fallbackCircle: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [accentColor, accentColor.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(letter)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Header Icon Button

struct TGHeaderButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Typing Indicator (Telegram animated dots)
// FIX: replaced Timer with task-based approach to avoid memory leaks
// and Swift 6 concurrency issues.

struct TGTypingIndicator: View {
    let color: Color
    @State private var animatingDot: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .scaleEffect(animatingDot == i ? 1.45 : 0.75)
                    .opacity(animatingDot == i ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.35),
                        value: animatingDot
                    )
            }
        }
        .task {
            // FIX: task is automatically cancelled when view disappears
            while !Task.isCancelled {
                for dot in 0..<3 {
                    await MainActor.run {
                        withAnimation { animatingDot = dot }
                    }
                    try? await Task.sleep(for: .milliseconds(400))
                    if Task.isCancelled { break }
                }
            }
        }
    }
}

// MARK: - TG Input Bar (Liquid Glass pill)

struct TGInputBar: View {
    @Binding var text: String
    let accentColor: Color
    let replyTarget: String?    // preview text
    let onSend: () -> Void
    let onAttach: () -> Void
    let onMic: () -> Void
    let onEmoji: () -> Void
    let onCancelReply: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Liquid Glass separator
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.5)

            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [Color.white.opacity(0.05), Color.clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                VStack(spacing: 8) {
                    // Reply bar
                    if let reply = replyTarget {
                        HStack {
                            Rectangle()
                                .fill(accentColor)
                                .frame(width: 2, height: 32)
                                .cornerRadius(1)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Ответить")
                                    .font(.caption.bold())
                                    .foregroundStyle(accentColor)
                                Text(reply)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(action: onCancelReply) {
                                Image(systemName: "xmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white.opacity(0.5))
                                    .frame(width: 28, height: 28)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                    }

                    // Main input row
                    HStack(spacing: 8) {
                        // Attach
                        Button(action: onAttach) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(accentColor)
                                .frame(width: 36, height: 36)
                        }

                        // Text pill
                        HStack(spacing: 6) {
                            Button(action: onEmoji) {
                                Image(systemName: "face.smiling")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white.opacity(0.45))
                            }

                            TextField("Сообщение", text: $text, axis: .vertical)
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .tint(accentColor)
                                .focused($focused)
                                .lineLimit(1...5)

                            if !text.isEmpty {
                                Button(action: {}) {
                                    Image(systemName: "face.smiling.inverse")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white.opacity(0.30))
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.10))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                                )
                        )

                        // Send / Mic
                        if text.isEmpty {
                            Button(action: onMic) {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(accentColor.opacity(0.85)))
                            }
                        } else {
                            Button(action: {
                                onSend()
                            }) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(accentColor))
                                    .scaleEffect(text.isEmpty ? 0.8 : 1.0)
                                    .animation(.spring(response: 0.25), value: text.isEmpty)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

// MARK: - TG Message Bubble (Telegram 2026 style)
// NOTE: Uses TGMsgBubbleShape to avoid naming conflict with V5BubbleShape.

struct TGMessageBubble: View {
    let text: String
    let time: String
    let isOwn: Bool
    let isRead: Bool
    let theme: TGChatTheme
    let reactions: [(emoji: String, count: Int)]
    let replyPreview: String?
    let onReply: () -> Void
    let onReact: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            if isOwn { Spacer(minLength: 52) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                // Reply quote
                if let reply = replyPreview {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(theme.accentColor)
                            .frame(width: 2)
                            .cornerRadius(1)
                        Text(reply)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }

                // Bubble body
                VStack(alignment: .trailing, spacing: 4) {
                    Text(text)
                        .font(.system(size: 16))
                        .foregroundStyle(isOwn ? theme.ownTextColor : theme.incomingTextColor)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 4) {
                        Text(time)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))

                        if isOwn {
                            Image(systemName: isRead ? "checkmark.message.fill" : "checkmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(
                                    isRead
                                        ? Color(red: 0.20, green: 0.78, blue: 0.35)
                                        : Color.white.opacity(0.45)
                                )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    if isOwn {
                        TGMsgBubbleShape(isOwn: true)
                            .fill(
                                LinearGradient(
                                    colors: theme.ownBubbleColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                TGMsgBubbleShape(isOwn: true)
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.18), .clear],
                                            startPoint: .topLeading,
                                            endPoint: .center
                                        )
                                    )
                            )
                    } else {
                        TGMsgBubbleShape(isOwn: false)
                            .fill(theme.incomingBubbleColor)
                            .overlay(
                                TGMsgBubbleShape(isOwn: false)
                                    .stroke(theme.incomingBubbleBorder, lineWidth: 0.5)
                            )
                    }
                }
                .shadow(color: .black.opacity(isOwn ? 0.25 : 0.15), radius: 4, x: 0, y: 2)
                .contextMenu {
                    Button { onReply() }  label: { Label("Ответить", systemImage: "arrowshape.turn.up.left") }
                    Button { onReact() }  label: { Label("Реакция", systemImage: "face.smiling") }
                    Button { UIPasteboard.general.string = text } label: { Label("Копировать", systemImage: "doc.on.doc") }
                    Divider()
                    Button(role: .destructive) { onDelete() } label: { Label("Удалить", systemImage: "trash") }
                }

                // Reactions
                if !reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(reactions, id: \.emoji) { r in
                            TGReactionChipView(emoji: r.emoji, count: r.count, accentColor: theme.accentColor, incBubble: theme.incomingBubbleColor)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }

            if !isOwn { Spacer(minLength: 52) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

// MARK: - TG Bubble Shape
// Named TGMsgBubbleShape to avoid conflict with V5BubbleShape in PlinkBubbleStyle.swift

struct TGMsgBubbleShape: Shape {
    let isOwn: Bool
    /// When true applies the Telegram "tail" corner.
    var isTailed: Bool = true

    func path(in rect: CGRect) -> Path {
        // Telegram iOS 2026: 18pt large corners, 4pt tail corner
        let large: CGFloat = 18
        let tail: CGFloat  = isTailed ? 4 : large

        let tl: CGFloat = isOwn ? large : tail
        let tr: CGFloat = isOwn ? tail  : large
        let bl: CGFloat = large
        let br: CGFloat = large

        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Reaction Chip
// Renamed TGReactionChipView to avoid conflict with TGReactionChip in TGChatTheme.swift

struct TGReactionChipView: View {
    let emoji: String
    let count: Int
    let accentColor: Color
    let incBubble: Color

    var body: some View {
        HStack(spacing: 3) {
            Text(emoji).font(.system(size: 11))
            Text("\(count)").font(.system(size: 10, weight: .medium)).foregroundStyle(accentColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(incBubble)
                .overlay(Capsule().stroke(accentColor.opacity(0.4), lineWidth: 0.5))
        )
    }
}

// MARK: - Day Divider

struct TGDayDivider: View {
    let label: String
    let theme: TGChatTheme

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                )
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
