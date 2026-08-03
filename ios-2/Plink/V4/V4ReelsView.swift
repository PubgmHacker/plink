// Plink/V4/V4ReelsView.swift — Рилсы: лента трейлеров во вкладке «ИИ»
//
// 03.08.2026. Порт из HTML-макета (панель data-mpanel="reels").
// До этого рилсы существовали только в превью, в Swift их не было вообще.
//
// ЮРИДИЧЕСКОЕ ОГРАНИЧЕНИЕ, НЕ НАРУШАТЬ:
// условия YouTube API запрещают перекрывать плеер собственными элементами
// управления. Поэтому кнопки действий вынесены в отдельную полосу ПОД
// плеером (.bar в макете), а не поверх видео. Не переносите их на плеер.
//
// Лента пока на заглушках: подключение каталога ждёт решения по коммерческой
// лицензии TMDB. Точка входа для реальных данных — V4ReelsPanel(items:).

import SwiftUI

// MARK: - Палитра постеров

/// Градиенты повторяют .art / .art.b / .art.c / .art.d из макета.
enum V4ReelArt {
    case indigo
    case rose
    case teal
    case amber

    /// Верхний правый блик.
    var highlight: Color {
        switch self {
        case .indigo: return Color(red: 120 / 255, green: 150 / 255, blue: 255 / 255).opacity(0.55)
        case .rose:   return Color(red: 255 / 255, green: 120 / 255, blue: 180 / 255).opacity(0.50)
        case .teal:   return Color(red: 110 / 255, green: 255 / 255, blue: 215 / 255).opacity(0.40)
        case .amber:  return Color(red: 255 / 255, green: 205 / 255, blue: 130 / 255).opacity(0.45)
        }
    }

    /// Нижнее левое свечение.
    var glow: Color {
        switch self {
        case .indigo: return Color(red: 40 / 255, green: 60 / 255, blue: 160 / 255).opacity(0.75)
        case .rose:   return Color(red: 150 / 255, green: 25 / 255, blue: 80 / 255).opacity(0.70)
        case .teal:   return Color(red: 15 / 255, green: 110 / 255, blue: 90 / 255).opacity(0.70)
        case .amber:  return Color(red: 150 / 255, green: 85 / 255, blue: 20 / 255).opacity(0.70)
        }
    }

    /// Базовая заливка: три остановки на 0 / 44 / 100 %.
    var ramp: [Color] {
        switch self {
        case .indigo:
            return [
                Color(red: 0x33 / 255, green: 0x40 / 255, blue: 0x9a / 255),
                Color(red: 0x18 / 255, green: 0x20 / 255, blue: 0x55 / 255),
                Color(red: 0x08 / 255, green: 0x0b / 255, blue: 0x18 / 255),
            ]
        case .rose:
            return [
                Color(red: 0x8e / 255, green: 0x2f / 255, blue: 0x5e / 255),
                Color(red: 0x3d / 255, green: 0x12 / 255, blue: 0x30 / 255),
                Color(red: 0x0b / 255, green: 0x05 / 255, blue: 0x10 / 255),
            ]
        case .teal:
            return [
                Color(red: 0x1f / 255, green: 0x7a / 255, blue: 0x63 / 255),
                Color(red: 0x0f / 255, green: 0x2f / 255, blue: 0x28 / 255),
                Color(red: 0x05 / 255, green: 0x0d / 255, blue: 0x0c / 255),
            ]
        case .amber:
            return [
                Color(red: 0x9c / 255, green: 0x65 / 255, blue: 0x22 / 255),
                Color(red: 0x3a / 255, green: 0x24 / 255, blue: 0x10 / 255),
                Color(red: 0x0c / 255, green: 0x08 / 255, blue: 0x05 / 255),
            ]
        }
    }
}

/// Постер-заглушка. Повторяет .art со всеми слоями, включая косой блик и виньетку.
struct V4ReelArtView: View {
    let art: V4ReelArt

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: art.ramp[0], location: 0.0),
                        .init(color: art.ramp[1], location: 0.44),
                        .init(color: art.ramp[2], location: 1.0),
                    ],
                    startPoint: UnitPoint(x: 0.6, y: 0),
                    endPoint: UnitPoint(x: 0.4, y: 1)
                )

                RadialGradient(
                    colors: [art.highlight, .clear],
                    center: UnitPoint(x: 0.78, y: 0.08),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.62
                )

                RadialGradient(
                    colors: [art.glow, .clear],
                    center: UnitPoint(x: 0.12, y: 0.92),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.58
                )

                // Косой блик (.art:before)
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.16), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: w * 0.9, height: h * 1.2)
                .rotationEffect(.degrees(18))
                .blur(radius: 16)
                .offset(x: -w * 0.2, y: -h * 0.3)

                // Виньетка (.art:after)
                RadialGradient(
                    stops: [
                        .init(color: .clear, location: 0.40),
                        .init(color: Color.black.opacity(0.55), location: 1.0),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.3),
                    startRadius: 0,
                    endRadius: max(w, h) * 1.1
                )
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Модель ленты

struct V4ReelItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let art: V4ReelArt
    /// Идентификатор ролика для официального плеера. Пока не заполняется.
    var youtubeID: String?

    init(
        id: String,
        title: String,
        subtitle: String,
        art: V4ReelArt,
        youtubeID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.art = art
        self.youtubeID = youtubeID
    }

    static func == (lhs: V4ReelItem, rhs: V4ReelItem) -> Bool { lhs.id == rhs.id }

    /// Те же четыре карточки, что в макете.
    static let placeholders: [V4ReelItem] = [
        V4ReelItem(
            id: "dune-3",
            title: "Дюна: Часть третья",
            subtitle: "Трейлер · 2026 · фантастика · 2 ч 41 мин",
            art: .rose
        ),
        V4ReelItem(
            id: "project-ave",
            title: "Проект Аве",
            subtitle: "Трейлер · 2026 · триллер · 1 ч 58 мин",
            art: .teal
        ),
        V4ReelItem(
            id: "periphery-2",
            title: "Периферия, сезон 2",
            subtitle: "Тизер · 2026 · сериал · 8 серий",
            art: .amber
        ),
        V4ReelItem(
            id: "quiet-dawn",
            title: "Тихий рассвет",
            subtitle: "Трейлер · 2026 · драма · 2 ч 06 мин",
            art: .indigo
        ),
    ]
}

// MARK: - Сегмент «Рилсы / Голос»

/// Повторяет .seg из макета: капсула с подложкой, активная кнопка залита акцентом.
///
/// Перебор идёт по индексам, а не через id: \.value — KeyPath к элементу кортежа
/// в Swift невозможен: кортеж не номинальный тип и свойств у него нет.
struct V4SegmentedBar<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    let theme: V4Theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.indices), id: \.self) { i in
                let option = options[i]
                let active = option.value == selection

                Button {
                    guard !active else { return }
                    HapticManager.selection()
                    withAnimation(.easeOut(duration: 0.18)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(active ? theme.buttonTextColor : V4.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if active {
                                Capsule().fill(theme.accentColor)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(V4.surface, in: Capsule())
        .overlay(Capsule().stroke(V4.line))
    }
}

// MARK: - Кнопка в полосе действий

struct V4ReelPill: View {
    let title: String
    var accent: Bool = false
    var theme: V4Theme
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.impact(.light)
            action()
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(accent ? theme.buttonTextColor : V4.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background {
                    if accent {
                        Capsule().fill(theme.accentColor)
                    } else {
                        Capsule().fill(V4.raised)
                    }
                }
                .overlay {
                    if !accent { Capsule().stroke(V4.line) }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Панель рилсов

struct V4ReelsPanel: View {
    let theme: V4Theme
    var items: [V4ReelItem] = V4ReelItem.placeholders

    /// «Смотреть вместе» — собрать комнату по этому трейлеру.
    var onWatchTogether: (V4ReelItem) -> Void = { _ in }
    /// «В очередь».
    var onEnqueue: (V4ReelItem) -> Void = { _ in }
    /// «Ещё» — контекстное меню.
    var onMore: (V4ReelItem) -> Void = { _ in }

    @State private var index: Int = 0
    @State private var isPlaying = false

    private var current: V4ReelItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let reel = current {
                card(reel)
                legalNote
            } else {
                empty
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Карточка

    private func card(_ reel: V4ReelItem) -> some View {
        ZStack(alignment: .bottom) {
            // Плеер. Занимает всё, кроме нижних 96 pt под полосу действий.
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    V4ReelArtView(art: reel.art)
                        .id(reel.id)
                        .transition(.opacity)

                    Text("ОФИЦИАЛЬНЫЙ ПЛЕЕР")
                        .font(.system(size: 9.5, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(V4.ink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.2))
                        )
                        .padding(12)

                    playButton

                    swipeControls

                    info(reel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                Color.clear.frame(height: 96)
            }

            actionBar(reel)
        }
        .frame(height: 430)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(V4.line)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.height < -40 {
                        advance(by: 1)
                    } else if value.translation.height > 40 {
                        advance(by: -1)
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reels.card")
    }

    // MARK: Слои поверх плеера

    /// Единственный элемент поверх видео — кнопка воспроизведения самого плеера.
    /// Никаких других органов управления здесь быть не должно.
    private var playButton: some View {
        GeometryReader { geo in
            Button {
                HapticManager.impact(.medium)
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(V4.ink)
                    .frame(width: 56, height: 56)
                    .background(Color.black.opacity(0.4), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.26)))
            }
            .buttonStyle(.plain)
            .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
            .accessibilityLabel(isPlaying ? "Пауза" : "Смотреть трейлер")
        }
    }

    private var swipeControls: some View {
        VStack(spacing: 14) {
            arrow("chevron.up", label: "Предыдущий трейлер") { advance(by: -1) }
            arrow("chevron.down", label: "Следующий трейлер") { advance(by: 1) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 12)
        .padding(.bottom, 40)
    }

    private func arrow(_ icon: String, label: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(V4.ink)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 40, height: 40)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2))
                        .frame(width: 40, height: 40)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func info(_ reel: V4ReelItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reel.title)
                .font(.system(size: 18, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(V4.ink)

            Text(reel.subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(14)
        .background(
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
        )
    }

    // MARK: Полоса действий — ПОД плеером

    private func actionBar(_ reel: V4ReelItem) -> some View {
        HStack(spacing: 8) {
            V4ReelPill(title: "Смотреть вместе", accent: true, theme: theme) {
                onWatchTogether(reel)
            }
            V4ReelPill(title: "В очередь", theme: theme) {
                onEnqueue(reel)
            }
            V4ReelPill(title: "Ещё", theme: theme) {
                onMore(reel)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0x0a / 255, green: 0x0a / 255, blue: 0x0b / 255))
        .overlay(alignment: .top) {
            Rectangle().fill(V4.line).frame(height: 1)
        }
    }

    private var legalNote: some View {
        Text("Управление вынесено под плеер: YouTube API запрещает перекрывать плеер своими кнопками. Лента ждёт решения по коммерческой лицензии TMDB.")
            .font(.system(size: 10.5))
            .lineSpacing(3)
            .foregroundStyle(V4.muted)
            .padding(.leading, 9)
            .overlay(alignment: .leading) {
                Rectangle().fill(theme.accentColor).frame(width: 2)
            }
            .padding(.top, 11)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(V4.muted)
            Text("Трейлеры появятся, когда подключим каталог")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 430)
    }

    // MARK: Переключение

    private func advance(by delta: Int) {
        guard !items.isEmpty else { return }
        HapticManager.selection()
        isPlaying = false
        withAnimation(.easeOut(duration: 0.22)) {
            index = (index + delta + items.count) % items.count
        }
        AnalyticsService.shared.track(
            "reel_swiped",
            parameters: ["direction": delta > 0 ? "next" : "prev"]
        )
    }
}
