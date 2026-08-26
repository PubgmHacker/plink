// Plink/V4/V4RoomControlsRow.swift
// The control row inside a room.
//
// Layout: one flat row below the participants block — the privacy chip on the left, a
// compact cluster of circular icons on the right. Chat lives underneath it and is
// never overlapped.
//
// That last clause is the whole point, and two earlier designs are the reason it is
// written down rather than left to taste:
//
//  - A floating "liquid glass" capsule above the chat covered the messages.
//  - A collapsible panel with a toggle lost the user: once collapsed, there was no
//    way back to the controls.
//
// So: nothing collapses, and nothing floats over the chat.
//
// Sizes: 40 pt circles in a 44×44 pt hit area — the Apple HIG minimum.

import SwiftUI

// MARK: - Privacy level

/// Кто может войти в комнату без кода.
///
/// Код и ссылка работают всегда, на любом уровне — поэтому отдельного
/// режима "по приглашению" здесь нет, он был бы дублем ссылки.
/// Та же модель у Google Meet (Open / Trusted / Restricted).
enum V4RoomPrivacyLevel: Int, CaseIterable, Identifiable {
    /// Комната видна в общем списке открытых комнат.
    case everyone = 0
    /// Комната видна друзьям в ряду «Друзья в эфире».
    case friends = 1
    /// Комнаты нет ни в одном списке — только код и ссылка.
    case nobody = 2

    var id: Int { rawValue }

    /// Короткая подпись для чипа в строке управления.
    var chipTitle: String {
        switch self {
        case .everyone: return "Открытая"
        case .friends:  return "Друзья"
        case .nobody:   return "По коду"
        }
    }

    /// Заголовок строки в шторке выбора.
    var title: String {
        switch self {
        case .everyone: return "Все"
        case .friends:  return "Друзья"
        case .nobody:   return "Никто"
        }
    }

    /// Пояснение — что конкретно произойдёт, а не абстракция.
    var subtitle: String {
        switch self {
        case .everyone: return "Комната в общем списке"
        case .friends:  return "Друзья видят её в «Друзья в эфире»"
        case .nobody:   return "Комнаты нет ни в одном списке"
        }
    }

    var icon: String {
        switch self {
        case .everyone: return "globe"
        case .friends:  return "person.2"
        case .nobody:   return "lock"
        }
    }
}

// MARK: - Строка управления

struct V4RoomControlsRow: View {
    @Binding var privacy: V4RoomPrivacyLevel

    /// Сколько фильмов стоит в очереди.
    var queueCount: Int = 0

    var onTapPrivacy: () -> Void = {}
    var onOpenQueue: () -> Void = {}
    var onInvite: () -> Void = {}

    var accent: Color = V4.accent

    var body: some View {
        HStack(spacing: 8) {
            privacyChip

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                V4RoomIconButton(
                    glyph: .queue,
                    badgeCount: queueCount,
                    accent: accent,
                    action: onOpenQueue
                )
                .accessibilityLabel(queueCount > 0 ? "Очередь, \(queueCount)" : "Очередь")

                V4RoomIconButton(
                    glyph: .plus,
                    tinted: true,
                    accent: accent,
                    action: onInvite
                )
                .accessibilityLabel("Позвать")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var privacyChip: some View {
        Button(action: onTapPrivacy) {
            HStack(spacing: 5) {
                Image(systemName: privacy.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(privacy.chipTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.65)
            }
            .foregroundStyle(V4.ink.opacity(0.82))
            .padding(.horizontal, 11)
            .frame(minHeight: 30)
            .background(
                Capsule().fill(Color.white.opacity(0.08))
            )
            .overlay(
                Capsule().strokeBorder(V4.line, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Приватность комнаты: \(privacy.title)")
        .accessibilityHint("Открыть выбор, кто может войти без кода")
    }
}

// MARK: - Круглая кнопка

/// Круг 40 pt внутри зоны касания 44x44 pt.
///
/// Визуально кнопки остаются плотными, но промахнуться по ним нельзя —
/// Apple HIG требует минимум 44 pt на касание.
struct V4RoomIconButton: View {
    let glyph: V4Glyph
    /// Залитое начертание — только для активного состояния (микрофон включён).
    var filled: Bool = false
    var locked: Bool = false
    var tinted: Bool = false
    var badgeCount: Int = 0
    var accent: Color = V4.accent
    var action: () -> Void = {}

    @State private var pressed = false

    private var circleFill: Color {
        if tinted { return accent.opacity(0.16) }
        if locked { return Color.white.opacity(0.05) }
        return Color.white.opacity(0.09)
    }

    private var iconColor: Color {
        if tinted { return accent }
        if locked { return V4.ink.opacity(0.34) }
        return V4.ink
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(circleFill)
                    .frame(width: 40, height: 40)

                V4GlyphIcon(glyph: glyph, size: 17, filled: filled, weight: .regular)
                    .foregroundStyle(iconColor)

                if locked {
                    badge {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(V4.canvas)
                    }
                } else if badgeCount > 0 {
                    badge {
                        Text("\(min(badgeCount, 99))")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(V4.canvas)
                    }
                }
            }
            // Зона касания больше видимого круга.
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }

    @ViewBuilder
    private func badge<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 3)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(accent))
            .overlay(Capsule().strokeBorder(V4.canvas, lineWidth: 1.5))
            .offset(x: 15, y: -14)
    }
}

// MARK: - Шторка приватности

/// Поднимается поверх экрана комнаты с затемнением.
///
/// Важно: это оверлей, а не блок в потоке — кадр и чат остаются
/// на месте и ничего не съезжает вниз при открытии.
struct V4RoomPrivacySheet: View {
    @Binding var privacy: V4RoomPrivacyLevel
    let roomCode: String
    var accent: Color = V4.accent
    var onCopyLink: () -> Void = {}
    var onDone: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 38, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 16)

            Text("Кто может войти без кода")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(V4.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)

            VStack(spacing: 8) {
                ForEach(V4RoomPrivacyLevel.allCases) { level in
                    row(for: level)
                }
            }

            codeRow
                .padding(.top, 14)

            Button(action: onDone) {
                Text("Готово")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(V4.canvas)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
                    .background(Capsule().fill(accent))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 26)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 24
            )
            .fill(V4.surface)
        )
    }

    private func row(for level: V4RoomPrivacyLevel) -> some View {
        let selected = privacy == level
        return Button {
            privacy = level
        } label: {
            HStack(spacing: 12) {
                Image(systemName: level.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selected ? accent : V4.muted)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(V4.ink)
                    Text(level.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(V4.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? accent : V4.line)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? accent.opacity(0.12) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? accent.opacity(0.45) : V4.line, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    /// Код и ссылка работают на любом уровне приватности.
    private var codeRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Код комнаты")
                    .font(.system(size: 11))
                    .foregroundStyle(V4.muted)
                Text(roomCode)
                    .font(.system(size: 17, weight: .heavy, design: .monospaced))
                    .foregroundStyle(V4.ink)
                    .kerning(2)
            }

            Spacer(minLength: 8)

            Button(action: onCopyLink) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Ссылка")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(V4.ink)
                .padding(.horizontal, 13)
                .frame(minHeight: 34)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
    }
}

// MARK: - Preview

#Preview("Строка управления") {
    struct Demo: View {
        @State private var privacy: V4RoomPrivacyLevel = .nobody
        @State private var showSheet = false

        var body: some View {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.purple.opacity(0.5), .black],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 10)

                    V4RoomControlsRow(
                        privacy: $privacy,
                        queueCount: 3,
                        onTapPrivacy: { showSheet = true }
                    )
                    .padding(.top, 10)

                    Spacer()
                }

                if showSheet {
                    Color.black.opacity(0.62)
                        .ignoresSafeArea()
                        .onTapGesture { showSheet = false }
                    V4RoomPrivacySheet(
                        privacy: $privacy,
                        roomCode: "K7X2QF",
                        onDone: { showSheet = false }
                    )
                    .transition(.move(edge: .bottom))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showSheet)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(V4.canvas)
        }
    }
    return Demo()
}
