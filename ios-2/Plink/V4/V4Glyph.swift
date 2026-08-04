// Plink/V4/V4Glyph.swift — единая иконочная система
//
// 03.08.2026. До этого файла каждый экран рисовал иконки сам: где-то 13 pt bold,
// где-то 17 pt semibold, где-то fill-вариант рядом с линейным. Интерфейс
// выглядел собранным из разных приложений.
//
// Правила, закреплённые здесь:
//   • только линейные начертания, тонкий штрих (.light / .regular);
//     заливка — только для активного состояния;
//   • иконка живёт в круге со стеклом и волосяной обводкой;
//   • видимый круг может быть меньше 44 pt, область касания — никогда;
//   • бейдж — точка или число в правом верхнем углу, всегда одинаковый.
//
// Новые экраны обязаны брать иконки отсюда, а не писать Image(systemName:) вручную.

import SwiftUI

// MARK: - Словарь иконок

enum V4Glyph {
    case chat
    case bell
    case bellOff
    case mic
    case send
    case plus
    case more
    case queue
    case share
    case play
    case pause
    case close
    case search
    case watchTogether
    case sparkle
    case check
    case copy
    case retry
    case trash
    case lock
    case people
    case globe
    case camera
    case heart
    // 03.08.2026: добавлено при переводе вкладок на общий набор. Раньше эти
    // символы жили как Image(systemName:) прямо в экранах — с разными
    // размерами и весами в каждом.
    case chevronRight
    case person
    case people3
    case film
    case room
    case pin
    case bookmark
    case appearance
    case shield
    case warning
    case inbox
    case photo
    case requests
    case leave

    var symbol: String {
        switch self {
        case .chat:          return "bubble.left.and.bubble.right"
        case .bell:          return "bell"
        case .bellOff:       return "bell.slash"
        case .mic:           return "mic"
        case .send:          return "paperplane"
        case .plus:          return "plus"
        case .more:          return "ellipsis"
        case .queue:         return "list.bullet"
        case .share:         return "square.and.arrow.up"
        case .play:          return "play.fill"
        case .pause:         return "pause.fill"
        case .close:         return "xmark"
        case .search:        return "magnifyingglass"
        case .watchTogether: return "play.rectangle.on.rectangle"
        case .sparkle:       return "sparkles"
        case .check:         return "checkmark"
        case .copy:          return "doc.on.doc"
        case .retry:         return "arrow.clockwise"
        case .trash:         return "trash"
        case .lock:          return "lock"
        case .people:        return "person.2"
        case .globe:         return "globe"
        case .camera:        return "video"
        case .heart:         return "heart"
        case .chevronRight:  return "chevron.right"
        case .person:        return "person"
        case .people3:       return "person.3"
        case .film:          return "film"
        case .room:          return "play.rectangle"
        case .pin:           return "pin"
        case .bookmark:      return "bookmark"
        case .appearance:    return "paintbrush.pointed"
        case .shield:        return "shield.lefthalf.filled"
        case .warning:       return "exclamationmark.triangle"
        case .inbox:         return "tray"
        case .photo:         return "photo.on.rectangle"
        case .requests:      return "person.badge.clock"
        case .leave:         return "rectangle.portrait.and.arrow.right"
        }
    }

    /// Залитый близнец для активного состояния. Где его нет — остаётся линейный.
    var filledSymbol: String {
        switch self {
        case .chat:       return "bubble.left.and.bubble.right.fill"
        case .bell:       return "bell.fill"
        case .bellOff:    return "bell.slash.fill"
        case .mic:        return "mic.fill"
        case .send:       return "paperplane.fill"
        case .lock:       return "lock.fill"
        case .people:     return "person.2.fill"
        case .camera:     return "video.fill"
        case .heart:      return "heart.fill"
        case .trash:      return "trash.fill"
        case .person:     return "person.fill"
        case .people3:    return "person.3.fill"
        case .film:       return "film.fill"
        case .room:       return "play.rectangle.fill"
        case .pin:        return "pin.fill"
        case .bookmark:   return "bookmark.fill"
        case .appearance: return "paintbrush.pointed.fill"
        case .requests:   return "person.badge.clock.fill"
        case .inbox:      return "tray.fill"
        default:          return symbol
        }
    }
}

// MARK: - Голая иконка

struct V4GlyphIcon: View {
    let glyph: V4Glyph
    var size: CGFloat = 19
    var filled: Bool = false
    /// Штрих намеренно тонкий — это главное отличие современного набора.
    var weight: Font.Weight = .light

    var body: some View {
        Image(systemName: filled ? glyph.filledSymbol : glyph.symbol)
            .font(.system(size: size, weight: weight))
            .symbolRenderingMode(.monochrome)
    }
}

// MARK: - Круглая кнопка

enum V4GlyphKind {
    /// Полупрозрачное стекло — базовый вариант для шапок и панелей.
    case glass
    /// Тёмное стекло — поверх видео и ярких постеров.
    case onMedia
    /// Залитый акцентом — главное действие экрана.
    case accent
    /// Без подложки — внутри строк и пузырей.
    case plain
}

struct V4GlyphButton: View {
    let glyph: V4Glyph
    var theme: V4Theme
    var kind: V4GlyphKind = .glass
    /// Диаметр видимого круга. Область касания всегда не меньше 44 pt.
    var diameter: CGFloat = 46
    var iconSize: CGFloat = 19
    var filled: Bool = false
    var active: Bool = false
    /// Число в бейдже. 0 или nil — бейджа нет.
    var badge: Int? = nil
    /// Точка без числа.
    var dot: Bool = false
    var accessibility: String
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            ZStack {
                shape

                V4GlyphIcon(glyph: glyph, size: iconSize, filled: filled || active)
                    .foregroundStyle(foreground)
            }
            .frame(width: diameter, height: diameter)
            .overlay(alignment: .topTrailing) { badgeView }
            .frame(width: max(diameter, 44), height: max(diameter, 44))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    @ViewBuilder
    private var shape: some View {
        switch kind {
        case .glass:
            Circle()
                .fill(active ? theme.accentColor.opacity(0.18) : Color.white.opacity(0.07))
                .overlay(
                    Circle().stroke(
                        active ? theme.accentColor.opacity(0.55) : Color.white.opacity(0.14),
                        lineWidth: 1
                    )
                )
        case .onMedia:
            Circle()
                .fill(Color.black.opacity(0.42))
                .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
        case .accent:
            Circle()
                .fill(theme.accentColor)
                .shadow(color: theme.accentColor.opacity(0.38), radius: 14, y: 6)
        case .plain:
            Color.clear
        }
    }

    private var foreground: Color {
        switch kind {
        case .accent:  return theme.buttonTextColor
        case .glass:   return active ? theme.accentColor : V4.ink
        case .onMedia: return V4.ink
        case .plain:   return active ? theme.accentColor : V4.muted
        }
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge, badge > 0 {
            Text(badge > 99 ? "99+" : "\(badge)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(V4.danger, in: Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.35), lineWidth: 1.5))
                .offset(x: 5, y: -3)
        } else if dot {
            Circle()
                .fill(V4.danger)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1.5))
                .offset(x: 2, y: 0)
        }
    }
}

// MARK: - Иконка с подписью (колонка действий в ленте)

struct V4GlyphAction: View {
    let glyph: V4Glyph
    let caption: String
    var theme: V4Theme
    var kind: V4GlyphKind = .onMedia
    var diameter: CGFloat = 48
    let action: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            V4GlyphButton(
                glyph: glyph,
                theme: theme,
                kind: kind,
                diameter: diameter,
                iconSize: 20,
                accessibility: caption,
                action: action
            )

            Text(caption)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .shadow(color: .black.opacity(0.5), radius: 4)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
