// Plink/V4/V4ReelsView.swift — Лента трейлеров во вкладке «ИИ»
//
// 03.08.2026, вторая редакция. Первая была буквальным портом HTML-макета:
// карточка 430 pt посреди экрана и две стрелки справа. Это старомодно:
// лента коротких роликов листается пальцем и занимает весь экран, иначе она
// не читается как лента.
//
// Сейчас: вертикальный пейджинг на всю высоту, свайп пальцем, фон — размытый
// постер текущего трейлера, сам ролик — чёткое окно 16:9.
//
// ЮРИДИЧЕСКОЕ ОГРАНИЧЕНИЕ, НЕ НАРУШАТЬ:
// условия YouTube API запрещают перекрывать плеер собственными элементами
// управления. Поэтому колонка действий и подпись живут НИЖЕ окна плеера,
// в свободной части экрана, а не поверх видео. При переводе на настоящий
// плеер геометрию менять нельзя.
//
// Лента на заглушках: подключение каталога ждёт решения по коммерческой
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
    /// Кадр тайтла. Пока не загрузился — виден градиент art.
    var artworkURL: URL?
    /// Идентификатор ролика для официального плеера. Пока не заполняется.
    var youtubeID: String?

    init(
        id: String,
        title: String,
        subtitle: String,
        art: V4ReelArt,
        artworkURL: URL? = nil,
        youtubeID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.art = art
        self.artworkURL = artworkURL
        self.youtubeID = youtubeID
    }

    static func == (lhs: V4ReelItem, rhs: V4ReelItem) -> Bool { lhs.id == rhs.id }

    /// Карточка ленты из живого каталога.
    ///
    /// 26.08.2026: здесь лежали четыре вписанных тайтла («Дюна: Часть
    /// третья», «Проект Аве», «Периферия, сезон 2», «Тихий рассвет») —
    /// двух последних не существует. Придуманный каталог в отгруженном
    /// разделе снят: лента берёт полку «Новинки» того же стора, что кормит
    /// Главную, и показывает настоящие названия с настоящими кадрами.
    init(from result: V4SearchResult) {
        self.id = result.id
        self.title = result.title
        self.subtitle = result.subtitle
        self.art = Self.art(forSeed: result.id)
        self.artworkURL = result.artworkURL ?? result.posterURL
        self.youtubeID = result.origin == .youtube ? result.id : nil
    }

    /// Градиент под кадром — от идентификатора, а не по кругу: у одного
    /// тайтла всегда один и тот же фон, и он не скачет между запусками.
    private static func art(forSeed seed: String) -> V4ReelArt {
        var hash: UInt32 = 2_166_136_261
        for byte in seed.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        switch hash % 4 {
        case 0: return .indigo
        case 1: return .rose
        case 2: return .teal
        default: return .amber
        }
    }
}

// MARK: - Лента

/// Полноэкранная лента трейлеров: один трейлер — один экран,
/// листается вертикальным свайпом. Никаких стрелок.
struct V4ReelsPanel: View {
    let theme: V4Theme
    var items: [V4ReelItem] = []

    /// Каталог ещё не подключён: карточки — витрина будущей ленты.
    /// Раньше поверх ленты лежал полноэкранный дизмер с плашкой «Будет
    /// доступно скоро», а под ним оставались все кнопки — текст плашки
    /// наезжал на «Смотреть вместе», и экран выглядел сломанным. Теперь
    /// в превью просто нет ни одного мёртвого контрола: ни play, ни пилюли,
    /// ни колонки действий — только кадр, название и тихий бейдж «Скоро».
    var isPreview: Bool = false

    /// Место сверху под плавающую шапку экрана.
    var topInset: CGFloat = 84
    /// Место снизу под док и таб-бар.
    var bottomInset: CGFloat = 150

    /// «Смотреть вместе» — собрать комнату по этому трейлеру.
    var onWatchTogether: (V4ReelItem) -> Void = { _ in }
    /// «В очередь».
    var onEnqueue: (V4ReelItem) -> Void = { _ in }
    /// «Поделиться».
    var onShare: (V4ReelItem) -> Void = { _ in }
    /// «Ещё» — контекстное меню.
    var onMore: (V4ReelItem) -> Void = { _ in }

    @State private var visibleID: String?
    @State private var playingID: String?
    @State private var hintBob = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentArt: V4ReelArt {
        items.first(where: { $0.id == visibleID })?.art ?? items.first?.art ?? .indigo
    }

    /// Текущая карточка для индикатора позиции: до первого свайпа
    /// scrollPosition ещё nil — считаем первой.
    private var currentID: String? { visibleID ?? items.first?.id }

    var body: some View {
        if items.isEmpty {
            empty
        } else {
            feed
        }
    }

    private var feed: some View {
        ZStack {
            // Фон — тот же постер, сильно размытый: даёт глубину и связывает
            // окно плеера с чёрным экраном.
            V4ReelArtView(art: currentArt)
                .blur(radius: 60)
                .opacity(0.55)
                .overlay(Color.black.opacity(0.45))
                // Верхний скрим — часть фона ленты, а не шапки. Когда полоса
                // затемнения принадлежала шапке, она обрывалась на своей
                // высоте и читалась отдельным слоем «другого экрана».
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.55), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 150)
                }
                .animation(.easeInOut(duration: 0.45), value: visibleID)
                .ignoresSafeArea()

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(items) { reel in
                        page(reel)
                            .containerRelativeFrame(.vertical)
                            .id(reel.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $visibleID)
            .onChange(of: visibleID) { oldValue, newValue in
                guard oldValue != newValue else { return }
                HapticManager.selection()
                playingID = nil
                AnalyticsService.shared.track(
                    "reel_swiped",
                    parameters: ["direction": "next"]
                )
            }
        }
        .background(Color.black)
        // Вертикальные точки позиции у правого края: единственный намёк,
        // что лента листается и сколько в ней трейлеров. Скролл-индикатор
        // скрыт намеренно — системная полоса на пейджере читается как
        // недокрученный список, а не как лента.
        .overlay(alignment: .trailing) {
            if items.count > 1 {
                VStack(spacing: 7) {
                    ForEach(items) { it in
                        Capsule()
                            .fill(it.id == currentID
                                  ? theme.accentColor
                                  : Color.white.opacity(0.22))
                            .frame(width: 3.5, height: it.id == currentID ? 22 : 8)
                    }
                }
                .padding(.trailing, 8)
                .animation(reduceMotion ? nil : .bouncy(duration: 0.4), value: visibleID)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("reels.feed")
    }

    // MARK: Один экран ленты

    private func page(_ reel: V4ReelItem) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)

            player(reel)

            // Всё управление — ниже плеера, в свободной части экрана.
            HStack(alignment: .top, spacing: 14) {
                info(reel)
                Spacer(minLength: 4)
                if !isPreview { actions(reel) }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            Spacer(minLength: 0)

            // Хинт свайпа — только на первой карточке: без него нижняя
            // половина экрана в превью читалась мёртвой пустотой, а сам
            // факт вертикальной ленты оставался невидимым.
            if reel.id == items.first?.id && items.count > 1 {
                VStack(spacing: 5) {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .offset(y: hintBob ? -3 : 2)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                            value: hintBob
                        )
                        .onAppear { hintBob = true }
                    Text("Свайп вверх — следующий трейлер")
                        .font(.system(size: 11.5, weight: .semibold))
                        .tracking(0.2)
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                // 64, не 16: док «Спроси про фильмы» на вкладке ИИ выступает
                // над bottomInset примерно на 40 pt — хинт должен жить выше.
                .padding(.bottom, 64)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            Color.clear.frame(height: bottomInset)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reels.card")
    }

    /// Окно плеера 16:9. Единственные элементы поверх видео — кнопка
    /// воспроизведения самого плеера и его метка. Больше сюда ничего не класть.
    private func player(_ reel: V4ReelItem) -> some View {
        ZStack(alignment: .topLeading) {
            V4ReelArtView(art: reel.art)

            // Настоящий кадр поверх градиента. Градиент остаётся подложкой:
            // пока кадр летит по сети, окно плеера не мигает чёрным.
            if let artworkURL = reel.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    }
                }
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            // Мелкий бейдж «СКОРО» в превью снят: про состояние раздела
            // теперь говорит крупный онбординг-слой вкладки ИИ, а подпись
            // в углу кадра дублировала его и читалась дешёвой. В живом
            // режиме бейджа нет тем более — раньше тут висел «ОФИЦИАЛЬНЫЙ
            // ПЛЕЕР», внутренний жаргон без пользы для пользователя.

            // В превью кадр пуст (одни градиенты) — тихий водяной знак
            // хлопушки даёт кадру предмет, не изображая кнопку: у него нет
            // ни подложки, ни рамки, ничего кликабельного.
            if isPreview {
                Image(systemName: "movieclapper")
                    .font(.system(size: 58, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.16))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            // Play-глиф без ролика — фейковый переключатель; в превью его нет.
            if !isPreview {
                V4GlyphButton(
                    glyph: playingID == reel.id ? .pause : .play,
                    theme: theme,
                    kind: .onMedia,
                    diameter: 62,
                    iconSize: 20,
                    accessibility: playingID == reel.id ? "Пауза" : "Смотреть трейлер"
                ) {
                    HapticManager.impact(.medium)
                    playingID = (playingID == reel.id) ? nil : reel.id
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.10))
        )
        .padding(.horizontal, 12)
        .shadow(color: .black.opacity(0.55), radius: 26, y: 14)
    }

    private func info(_ reel: V4ReelItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(reel.title)
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(V4.ink)
                .lineLimit(2)

            Text(reel.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(2)

            if !isPreview {
                V4ReelPill(title: "Смотреть вместе", accent: true, theme: theme) {
                    onWatchTogether(reel)
                }
                .padding(.top, 8)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 8)
    }

    /// Колонка круглых иконок. Живёт ниже плеера, не поверх него.
    private func actions(_ reel: V4ReelItem) -> some View {
        VStack(spacing: 14) {
            V4GlyphAction(glyph: .queue, caption: "В очередь", theme: theme) {
                onEnqueue(reel)
            }
            V4GlyphAction(glyph: .share, caption: "Отправить", theme: theme) {
                onShare(reel)
            }
            V4GlyphAction(glyph: .more, caption: "Ещё", theme: theme) {
                onMore(reel)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            V4GlyphIcon(glyph: .play, size: 26, weight: .regular)
                .foregroundStyle(V4.muted)
            Text("Каталог загружается")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Кнопка-капсула

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
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(accent ? theme.buttonTextColor : V4.ink)
                .padding(.horizontal, 16)
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
