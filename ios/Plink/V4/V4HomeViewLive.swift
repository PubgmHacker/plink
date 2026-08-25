// Plink/V4/V4HomeViewLive.swift
// 02.08.2026: «Главная» пересобрана под новый макет.
// 03.08.2026: приведена в соответствие с HTML-превью (экран data-view="home").
//
// Что изменилось и почему:
// 1) Убрана лента LIVE-комнат «Смотрят сейчас». Именно она делала «Главную»
//    неотличимой от вкладки «Комнаты». Главная отвечает на вопрос «что посмотреть»,
//    Комнаты — «с кем и когда».
// 2) Вход в ИИ ровно один — строка поиска. Раньше их было три (искра в шапке,
//    синий квадрат у поиска и карточка «Спросить ИИ-ассистента»), и это
//    расходилось с макетом: там .searchbar единственная точка входа.
// 3) Приветствие сведено в одну строку с аватаром (.greet в макете), а не
//    висит отдельной надписью капсом над заголовком.
// 4) Добавлен ряд чипов жанров (.chiprow).
// 5) В шапке единственный колокольчик — по решению владельца от 03.08.2026
//    центр уведомлений в приложении один.
// 6) Удалён мёртвый код: promoBanner, releaseNotesCard/releaseNoteRow, showScheduleSheet
//    — ни одного вызова в теле экрана.
// 7) 07.08.2026: экран сам грузит свои тренды в .task. Раньше это делал
//    bootstrap() корневого экрана шестым последовательным запросом, и до
//    появления баннеров проходило около десяти секунд.
// 8) 21.08.2026: главная расчищена от объяснялок и дублей. Снята подпись
//    под чипами («чипы ищут по жанрам» — и так очевидно), кружки play и
//    градиенты с карточек «Популярно» и «Рекомендаций» (вся карточка — кнопка,
//    значок поверх постера только глушил артворк), контейнер-коробка
//    «Рекомендаций», строка «Смотреть с друзьями» внизу (дубль вкладки
//    «Комнаты») и невызываемый ReleaseNotesSheet. Герой получил кадр контента.
// 9) 22.08.2026: контент переориентирован с YouTube-чарта на кино. Чипы
//    стали полками кинокаталога (HomeCinemaCatalog + V4SearchStore.loadShelf):
//    «Фильмы», «Сериалы», «Мультфильмы», жанры — у каждой полки свои запросы
//    к /api/media/search вместо фильтра подстрокой по общему чарту с музыкой.
//    Поиск и чипы переведены с плоского V4.surface на настоящий Liquid Glass
//    (.plinkGlass) — до этого стеклом они только назывались.

import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif
import Foundation

// MARK: - AutoScrollCarousel — оставлен для других экранов

struct AutoScrollCarousel<T: Identifiable, Content: View>: View {
    let items: [T]
    let cardWidth: CGFloat
    @ViewBuilder let content: (T) -> Content

    @State private var offset: CGFloat = 0
    @State private var displayLink: Timer?
    @State private var userDragging = false
    @State private var pauseUntil: Date = .distantPast
    @State private var dragStartOffset: CGFloat = 0
    @State private var lastTick: Date = .distantPast

    private let spacing: CGFloat = 11
    private let sidePadding: CGFloat = 19
    private let speed: CGFloat = 22
    private let pauseAfterUserDrag: TimeInterval = 4.0

    private var contentWidth: CGFloat {
        CGFloat(items.count) * cardWidth + CGFloat(max(0, items.count - 1)) * spacing + sidePadding * 2
    }

    var body: some View {
        GeometryReader { geo in
            let w = contentWidth
            HStack(spacing: spacing) {
                Color.clear.frame(width: sidePadding, height: 1)
                ForEach(items) { item in content(item).id(item.id) }
                Color.clear.frame(width: sidePadding, height: 1)
            }
            .frame(width: w, alignment: .leading)
            .offset(x: offset)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        userDragging = true
                        offset = dragStartOffset + value.translation.width
                        pauseUntil = Date().addingTimeInterval(pauseAfterUserDrag)
                    }
                    .onEnded { _ in
                        userDragging = false
                        if w > 0 { while offset <= -w { offset += w }; while offset > 0 { offset -= w } }
                        dragStartOffset = offset
                        pauseUntil = Date().addingTimeInterval(pauseAfterUserDrag)
                    }
            )
            .frame(width: geo.size.width, height: nil, alignment: .leading)
            .clipped()
        }
        .frame(height: 256)
        .onAppear { startAutoScroll() }
        .onDisappear { displayLink?.invalidate() }
    }

    private func startAutoScroll() {
        displayLink?.invalidate()
        lastTick = Date()
        displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            guard !userDragging else { lastTick = Date(); return }
            guard Date() > pauseUntil else { lastTick = Date(); return }
            let now = Date()
            let dt = CGFloat(now.timeIntervalSince(lastTick))
            lastTick = now
            offset -= speed * dt
            let w = contentWidth
            if w > 0 { while offset <= -w { offset += w }; while offset > 0 { offset -= w } }
            dragStartOffset = offset
        }
    }
}

// MARK: - Нажатие контентных карточек

/// Микроанимация нажатия карточек витрины: лёгкое сжатие с приглушением,
/// как у постеров Apple TV. Прежний .plain оставлял карточки немыми — палец
/// не получал ответа до самого хаптика. Уважает «Уменьшение движения».
struct V4PressableCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72),
                       value: configuration.isPressed)
    }
}

// MARK: - Главная

struct V4HomeViewLive: View {
    let theme: V4Theme
    @Bindable var searchStore: V4SearchStore
    var roomsStore: V4RoomsStore?
    let openRoom: () -> Void
    var liveThemeIndex: Int = 0
    @ObservedObject private var historyMgr = WatchHistoryManager.shared
    @ObservedObject private var watchlist = WatchlistService.shared
    @ObservedObject private var dmInbox = DMChatService.shared
    @ObservedObject private var groupInbox = GroupChatService.shared

    @State private var showUnifiedSearch = false
    @State private var showInbox = false
    @State private var isRefreshing = false
    @State private var previewItem: V4SearchResult?
    // Дизайн-превью: `-plink.designchip <чип>` открывает Главную сразу на
    // нужной полке — скриншоты чипов без ручных тапов. Только DEBUG,
    // тот же приём, что -plink.designtab в PlinkApprovedV4Root.
    @State private var selectedGenre: String = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-plink.designchip"), args.indices.contains(i + 1),
           V4HomeViewLive.genres.contains(args[i + 1]) {
            return args[i + 1]
        }
        #endif
        return V4HomeViewLive.genres[0]
    }()
    @Environment(\.scenePhase) private var scenePhase

    /// Автообновление витрины (22.08.2026): раз в 15 минут полки старше TTL
    /// перезапрашиваются — подборки следят за трендами сами, пока экран жив.
    private let autoRefreshTick = Timer.publish(every: 15 * 60, on: .main, in: .common).autoconnect()

    /// Ряд чипов из макета (.chiprow) — полки кинокаталога.
    static let genres = HomeCinemaCatalog.chips

    // MARK: Цвета темы

    private var activeAccent: Color {
        if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) { return live.accentColor }
        return theme.accentColor
    }
    private var activeSecondary: Color {
        if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) { return live.secondaryAccent }
        return theme.secondaryAccent
    }
    private var activeBtnText: Color {
        if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) { return live.buttonTextColor }
        return theme.buttonTextColor
    }

    /// «Добрый вечер, Андрей» — одной строкой, как в макете.
    private var greetingLine: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part: String
        switch h {
        case 5..<12: part = "Доброе утро"
        case 12..<17: part = "Добрый день"
        case 17..<22: part = "Добрый вечер"
        default: part = "Поздняя ночь"
        }
        guard let name = AuthService.shared.currentUserValue?.username, !name.isEmpty else {
            return part
        }
        let clean = name.hasPrefix("@") ? String(name.dropFirst()) : name
        return "\(part), \(clean)"
    }

    private var avatarLetter: String {
        let name = AuthService.shared.currentUserValue?.username ?? "П"
        let clean = name.hasPrefix("@") ? String(name.dropFirst()) : name
        return String(clean.prefix(1)).uppercased()
    }

    /// Полка выбранного чипа. Каждый чип — собственная кино-подборка
    /// (см. HomeCinemaCatalog), а не фильтр подстрокой по общему чарту.
    private var visibleTrending: [V4SearchResult] {
        searchStore.shelf(for: selectedGenre)
    }

    // Непересекающиеся срезы (22.08.2026): раньше герой, «Популярно», «Топ
    // недели» и «Рекомендации» резали prefix/suffix ОДНОГО массива, и одни
    // и те же карточки шли по экрану до трёх раз подряд. Теперь полка чипа
    // делится по диапазонам без наложений, а «Топ недели» кормит собственная
    // полка каталога — с отсевом уже показанного.

    /// Герой-карусель: первые пять карточек полки.
    private var heroItems: [V4SearchResult] { Array(visibleTrending.prefix(5)) }
    /// «Популярно» — следующие десять, после героя.
    private var popularItems: [V4SearchResult] { Array(visibleTrending.dropFirst(5).prefix(10)) }
    /// «Рекомендации» — хвост полки за «Популярно».
    private var recommendationItems: [V4SearchResult] { Array(visibleTrending.dropFirst(15).prefix(8)) }
    /// «Топ недели» — отдельная полка; что уже стоит выше, сюда не попадает.
    private var topWeekItems: [V4SearchResult] {
        let shown = Set((heroItems + popularItems + recommendationItems).map(\.id))
        return Array(
            searchStore.shelf(for: HomeCinemaCatalog.topWeekShelf)
                .filter { !shown.contains($0.id) }
                .prefix(6)
        )
    }

    // MARK: Тело

    var body: some View {
        // ScrollViewReader — только ради DEBUG-аргумента -plink.designsection:
        // он подматывает Главную к нужной секции для скриншотов нижних полок
        // (см. .task). Прод-скролл прокси не использует.
        ScrollViewReader { proxy in
            homeScroll(proxy)
        }
    }

    private func homeScroll(_ scrollProxy: ScrollViewProxy) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                topBar

                Text("Что посмотрим?")
                    .font(.system(size: 30, weight: .black))
                    .tracking(-0.8)
                    .foregroundStyle(V4.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 19)
                    .padding(.bottom, 14)

                searchRow
                    .padding(.horizontal, 19)
                    .padding(.bottom, 12)

                genreChips
                    .padding(.bottom, 18)

                if visibleTrending.isEmpty {
                    // Пустая полка при незавершённой загрузке — «ещё грузим»,
                    // скелетон. Заглушка «пусто» — только после попытки.
                    if isRefreshing || !searchStore.hasAttemptedShelf(selectedGenre) {
                        HomeSkeletonView().transition(.opacity)
                    } else if selectedGenre != HomeCinemaCatalog.allChip {
                        VStack(spacing: 12) {
                            Text("Полка пока пустая")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(V4.ink)
                                .multilineTextAlignment(.center)
                            Button {
                                selectedGenre = HomeCinemaCatalog.allChip
                            } label: {
                                Text("Показать «Для вас»")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(V4.accentInk)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 40)
                                    .background(V4.accent, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 19)
                    } else {
                        HomeFallbackPlaceholder(theme: theme, openRoom: { showUnifiedSearch = true })
                            .padding(.bottom, 20)
                    }
                }

                if !visibleTrending.isEmpty {
                    heroCarousel
                }

                if let resumeItem = resumeCandidate {
                    sectionTitle(L.string(.homeContinueWatching))
                    continueWatchingCard(resumeItem)
                        .padding(.horizontal, 19)
                        .padding(.bottom, 22)
                }

                if !popularItems.isEmpty {
                    // id секций — якоря для -plink.designsection (см. .task).
                    sectionTitle(L.string(.homePopular))
                        .id("sec.popular")
                    posterRail
                        .padding(.bottom, 24)
                }

                if topWeekItems.count >= 3 {
                    sectionTitle("Топ недели")
                        .id("sec.top")
                    topWeekRail
                        .padding(.bottom, 24)
                }

                if !watchlist.entries.isEmpty {
                    sectionTitle(L.string(.homeWatchLaterLabel))
                        .id("sec.watchlist")
                    ScrollView(.horizontal, showsIndicators: false) {
                        // .top — как у «Популярно»: центрирование по умолчанию
                        // роняло карточки с короткой подписью ниже соседних.
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(watchlist.entries) { entry in
                                watchlistCard(entry)
                            }
                        }
                        .padding(.horizontal, 19)
                    }
                    .padding(.bottom, 24)
                }

                if !recommendationItems.isEmpty {
                    sectionTitle(L.string(.homeRecommendations))
                        .id("sec.recs")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            // Тот же posterCard, что в «Популярно»: своя
                            // 16:9-карточка 192×108 была вдвое ниже соседних
                            // постеров — ряд выглядел довеском, а не секцией,
                            // и ломал единый постерный язык витрины.
                            ForEach(recommendationItems) { item in
                                posterCard(item)
                            }
                        }
                        .padding(.horizontal, 19)
                    }
                    .padding(.bottom, 20)
                }
            }
            .padding(.bottom, 96)
        }
        .foregroundStyle(V4.ink)
        .refreshable {
            isRefreshing = true
            async let shelf: Void = searchStore.loadShelf(selectedGenre, force: true)
            async let week: Void = searchStore.loadShelf(HomeCinemaCatalog.topWeekShelf, force: true)
            _ = await (shelf, week)
            isRefreshing = false
        }
        .sheet(item: $previewItem) { item in
            TrendingPreviewSheet(item: item, theme: theme) { target in
                previewItem = nil
                Task { await createRoomFromTrending(item, target: target) }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showInbox) {
            PlinkInboxView()
                .preferredColorScheme(.dark)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showUnifiedSearch) {
            UnifiedSearchView(searchStore: searchStore, roomsStore: roomsStore, openRoom: {
                showUnifiedSearch = false
                openRoom()
            })
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // 07.08.2026: «Главная» грузит витрину сама и сразу — эндпоинт
        // публичный, ждать гидрации сессии незачем. 22.08.2026: грузится
        // полка активного чипа; повторный вход в .task безвреден — loadShelf
        // не перезапрашивает уже наполненную полку.
        .task {
            // Полка чипа и «Топ недели» — параллельно: секции независимы.
            async let shelf: Void = searchStore.loadShelf(selectedGenre)
            async let week: Void = searchStore.loadShelf(HomeCinemaCatalog.topWeekShelf)
            _ = await (shelf, week)
            #if DEBUG
            // Дизайн-превью шита: `-plink.designpreview` открывает превью
            // первой карточки загруженной полки — скриншот шита без ручных
            // тапов по симулятору. Тот же приём, что -plink.designchip выше.
            if ProcessInfo.processInfo.arguments.contains("-plink.designpreview"),
               previewItem == nil {
                previewItem = visibleTrending.first
            }
            // Дизайн-скролл: «-plink.designsection popular|top|watchlist|recs»
            // подматывает Главную к секции — скриншоты нижних полок без
            // ручных свайпов. Пауза даёт полкам встать после загрузки.
            let dbgArgs = ProcessInfo.processInfo.arguments
            if let flag = dbgArgs.firstIndex(of: "-plink.designsection"),
               dbgArgs.indices.contains(flag + 1) {
                try? await Task.sleep(nanoseconds: 700_000_000)
                scrollProxy.scrollTo("sec.\(dbgArgs[flag + 1])", anchor: .top)
            }
            #endif
        }
        .onChange(of: selectedGenre) { _, chip in
            Task { await searchStore.loadShelf(chip) }
        }
        // Автообновление: тик таймера и возврат приложения из фона будят
        // только протухшие полки (refreshIfStale сам решает по TTL), а
        // loadShelf не перерисовывает полку, чей состав не изменился —
        // карусели под пальцем не прыгают.
        .onReceive(autoRefreshTick) { _ in
            Task { await refreshStaleShelves() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshStaleShelves() }
        }
    }

    private func refreshStaleShelves() async {
        async let shelf: Void = searchStore.refreshIfStale(selectedGenre)
        async let week: Void = searchStore.refreshIfStale(HomeCinemaCatalog.topWeekShelf)
        _ = await (shelf, week)
    }

    // MARK: Шапка — аватар, приветствие, единственный колокольчик

    private var topBar: some View {
        HStack(spacing: 10) {
            V4Avatar(
                letter: avatarLetter,
                theme: theme,
                isPremium: PremiumStatusManager.shared.isPremium,
                imageURL: PlinkAvatarURL.resolve(userId: AuthService.shared.currentUserValue?.id, stored: nil)
            )

            Text(greetingLine)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(V4.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 6)

            NotificationInboxButton(
                unreadCount: dmInbox.totalUnread + groupInbox.unreadTotal,
                theme: theme,
                action: { showInbox = true }
            )
        }
        .accessibilityIdentifier("screen.home")
        .padding(.horizontal, 18)
        // 18, не 10: шапки всех вкладок отодвинуты от статус-бара на общий
        // «вдох» — контент не липнет ко времени и батарее (правка 22.08.2026).
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: Поиск — единственный вход в ИИ

    private var searchRow: some View {
        Button {
            HapticManager.impact(.light)
            AnalyticsService.shared.track("ai_chat_used", parameters: ["source": "home_search"])
            showUnifiedSearch = true
        } label: {
            HStack(spacing: 10) {
                V4GlyphIcon(glyph: .search, size: 15, weight: .regular)
                    .foregroundStyle(V4.muted)
                Text("Фильм, ссылка или вопрос ИИ")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(V4.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .plinkGlass(.control, cornerRadius: 20, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Найти фильм, вставить ссылку или спросить ИИ")
        .accessibilityIdentifier("home.searchEntry")
    }

    // MARK: Чипы жанров

    private var genreChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(V4HomeViewLive.genres, id: \.self) { genre in
                    let active = genre == selectedGenre

                    Button {
                        HapticManager.selection()
                        withAnimation(.easeOut(duration: 0.16)) { selectedGenre = genre }
                        AnalyticsService.shared.track(
                            "home_genre_chip",
                            parameters: ["genre": genre]
                        )
                    } label: {
                        let title = Text(genre)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(active ? activeBtnText : V4.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                        // Активный чип — плотная акцентная капсула, остальные —
                        // то же стекло, что и строка поиска над ними.
                        if active {
                            title
                                .background(activeAccent, in: Capsule())
                                .contentShape(Capsule())
                        } else {
                            title
                                .plinkGlass(.control, interactive: true)
                                .contentShape(Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 19)
        }
    }

    // MARK: Герой

    private var heroCarousel: some View {
        TabView {
            ForEach(heroItems) { item in
                // У кино subtitle уже собран каталогом («Иви · 2023 ·
                // Фильм · ★ 7,3»), у трендов Netflix источник тоже назван
                // («Netflix · В трендах недели · №1») — приставка YouTube
                // остаётся только у обычных роликов, где subtitle = канал.
                let raw = item.origin == .youtube && !item.subtitle.hasPrefix("Netflix")
                    ? "YouTube · \(item.subtitle)" : item.subtitle
                // Первый сегмент меты — сервис: уходит из мелкой строки в
                // крупный бейдж героя. Год или рейтинг первым сегментом
                // (кино без источника) бейджем не притворяются.
                let parts = raw.components(separatedBy: " · ")
                let first = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
                let hasProvider = parts.count > 1 && !first.isEmpty
                    && first.first?.isNumber != true && !first.contains("★")
                V4Hero(
                    title: item.title,
                    meta: hasProvider ? parts.dropFirst().joined(separator: " · ") : raw,
                    button: "Смотреть вместе",
                    height: 260,
                    theme: theme,
                    action: {
                        HapticManager.impact(.medium)
                        previewItem = item
                    },
                    liveThemeIndex: liveThemeIndex,
                    provider: hasProvider ? first : nil,
                    artworkURL: item.artworkURL
                )
                .padding(.horizontal, 13)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 280)
        .padding(.bottom, 22)
    }

    // MARK: Лента компактных постеров

    private var posterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // .top — обязательно: HStack по умолчанию центрует, и карточки с
            // подписью в одну строку «всплывали» относительно двухстрочных —
            // постеры сидели на разных высотах и ряд скакал.
            HStack(alignment: .top, spacing: 12) {
                ForEach(popularItems) { item in
                    posterCard(item)
                }
            }
            .padding(.horizontal, 19)
        }
    }

    private func posterCard(_ item: V4SearchResult) -> some View {
        Button {
            HapticManager.impact(.light)
            previewItem = item
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Кадр без затемнения и без кружка play: вся карточка — кнопка,
                // дубль-значок поверх каждого постера съедал яркость артворка.
                // Рейтинг и «Бесплатно» — прямо на постере (см. ratingBadge).
                // 128×192 — настоящий 2:3, единый для всех постерных рядов
                // Главной: прежние 124×168 (≈3:4) срезали у постеров Иви
                // верх и низ, а карточки выглядели мельче артворка героя.
                artwork(item, poster: true)
                    .frame(width: Self.railPosterW, height: Self.railPosterH)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .topTrailing) { ratingBadge(item) }
                    .overlay(alignment: .bottomLeading) { freeBadge(item) }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(V4.line, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(V4.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let meta = cardMeta(item) {
                        Text(meta)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(V4.muted)
                            .lineLimit(1)
                    }
                }
                // Высота фиксированная (2 строки + мета): без неё карточка
                // с коротким названием ниже соседней, ряд «дышит» при
                // прокрутке и секции под ним прыгают по вертикали.
                .frame(width: Self.railPosterW, height: 45, alignment: .topLeading)
            }
        }
        .buttonStyle(V4PressableCardStyle())
        // Первый шаг пути «выбрал контент → создал комнату». Идентификатор
        // нужен UI-смоуку: прямой кнопки «Создать комнату» в продукте нет.
        .accessibilityIdentifier("home.poster")
        .accessibilityLabel(cardA11yLabel(item))
    }

    // MARK: Топ недели — паттерн «Netflix Top 10»

    // Референс: ряд Top 10 Netflix (2020) — цифра ранга высотой с постер,
    // частично перекрытая артворком; тот же приём у Кинопоиска и Apple TV.
    // Прежняя версия была вертикальным списком «номер + мелкая картинка +
    // капсула Смотреть» — единственная секция экрана со своей, ни на что не
    // похожей вёрсткой. Теперь это горизонтальная лента, как «Популярно»
    // и «Рекомендации», а ранг несёт сама графика, а не подпись.

    // Один размер постера на все постерные ряды Главной («Популярно»,
    // «Топ недели», «Рекомендации») — 2:3, как у физического постера и в
    // рядах Netflix/Кинопоиска. Секции различаются графикой (ранг-цифра),
    // а не масштабом карточек: разноразмерные ряды читались как разнобой.
    private static let railPosterW: CGFloat = 128
    private static let railPosterH: CGFloat = 192
    private static let topRankPosterW: CGFloat = railPosterW
    private static let topRankPosterH: CGFloat = railPosterH
    /// Кегль ранг-цифры — по высоте постера (та же пропорция, что была
    /// у 122 pt при постере 166 pt).
    private static let topRankDigitSize: CGFloat = 140
    /// Насколько опустить line box цифры, чтобы её базовая линия легла на низ
    /// постера. Ниже baseline у цифр пусто — этот зазор (~0.2 кегля в SF,
    /// сверено по скриншоту симулятора) заставлял прижатую «по рамке» цифру
    /// висеть в воздухе.
    private static let topRankBaselineDrop: CGFloat = 28

    private var topWeekRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(Array(topWeekItems.enumerated()), id: \.element.id) { index, item in
                    topWeekCard(item, rank: index + 1)
                }
            }
            .padding(.horizontal, 19)
            // Тень постера мягкая и широкая — без запаса сверху и снизу
            // ScrollView срезал бы её по границе контента.
            .padding(.vertical, 6)
        }
    }

    private func topWeekCard(_ item: V4SearchResult, rank: Int) -> some View {
        Button {
            HapticManager.impact(.light)
            previewItem = item
        } label: {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .bottom, spacing: -18) {
                    Text("\(rank)")
                        .font(.system(size: Self.topRankDigitSize, weight: .black))
                        .kerning(-6)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [V4.ink.opacity(0.50), V4.ink.opacity(0.09)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: Self.topRankPosterH, alignment: .bottom)
                        .offset(y: Self.topRankBaselineDrop)
                        .accessibilityHidden(true)

                    artwork(item, poster: true)
                        .frame(width: Self.topRankPosterW, height: Self.topRankPosterH)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        // Только рейтинг: ранг-цифра — герой карточки, второй
                        // бейдж снизу превращал флагманскую секцию в ёлку.
                        .overlay(alignment: .topTrailing) { ratingBadge(item) }
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(V4.line, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.32), radius: 12, y: 6)
                }

                // Подпись — строго под постером (VStack выровнен по trailing),
                // а не под цифрой: колонка текста начинается там же, где артворк.
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(V4.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let meta = cardMeta(item) {
                        Text(meta)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(V4.muted)
                            .lineLimit(1)
                    }
                }
                // Та же фикс-высота, что у карточек «Популярно»: одинаковые
                // подписи держат постеры топа на одной линии.
                .frame(width: Self.topRankPosterW, height: 45, alignment: .topLeading)
            }
        }
        .buttonStyle(V4PressableCardStyle())
        .accessibilityLabel("Место \(rank): \(cardA11yLabel(item))")
    }

    // MARK: Общие элементы

    private func sectionTitle(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 20, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(V4.ink)
            Spacer()
        }
        .padding(.horizontal, 19)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func artwork(_ item: V4SearchResult, poster: Bool = false) -> some View {
        // Вертикальные карточки просят настоящий постер (есть у кино из
        // каталога); широкий кадр — запасной путь и для YouTube, и для героя.
        if let url = (poster ? item.posterURL : nil) ?? item.artworkURL {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(V4.cardBG)
            }
        } else {
            Rectangle().fill(V4.cardBG)
                .overlay(Image(systemName: "film").foregroundStyle(V4.muted))
        }
    }

    // Бейджи на артворке (22.08.2026). Референс — мобильные кинотеки 2026:
    // рейтинг и ценовой признак живут прямо на постере, а не только в превью.
    // Раньше карточка была «постер + название», и чтобы узнать, стоит ли
    // фильм внимания, приходилось открывать превью каждого.

    /// Рейтинг в верхнем углу постера: янтарная звезда на тёмном скриме.
    @ViewBuilder
    private func ratingBadge(_ item: V4SearchResult) -> some View {
        if let rating = item.ratingText {
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(rating)
                    .font(.system(size: 11, weight: .heavy))
                    .monospacedDigit()
            }
            .foregroundStyle(V4.amber)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(6)
            .accessibilityHidden(true)
        }
    }

    /// «Бесплатно» в нижнем углу — главный аргумент выбрать тайтл сейчас.
    @ViewBuilder
    private func freeBadge(_ item: V4SearchResult) -> some View {
        if item.isFreeOnService {
            Text("Бесплатно")
                .font(.system(size: 9.5, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(V4.free, in: Capsule())
                .padding(6)
                .accessibilityHidden(true)
        }
    }

    /// Мета под названием карточки: «2023 · Фильм» у кино, канал — у ролика.
    /// Название без контекста заставляло гадать, фильм это или трейлер.
    private func cardMeta(_ item: V4SearchResult) -> String? {
        if item.origin == .youtube {
            let channel = item.subtitle.trimmingCharacters(in: .whitespaces)
            return channel.isEmpty ? nil : channel
        }
        var parts: [String] = []
        if let year = item.year { parts.append(String(year)) }
        if let kind = item.kindLabel { parts.append(kind) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// VoiceOver-описание карточки целиком: бейджи скрыты от чтения
    /// по одному, всё существенное собрано в одну фразу.
    private func cardA11yLabel(_ item: V4SearchResult) -> String {
        var parts = [item.title]
        if let meta = cardMeta(item) { parts.append(meta) }
        if let rating = item.ratingText { parts.append("рейтинг \(rating)") }
        if item.isFreeOnService { parts.append("бесплатно") }
        return parts.joined(separator: ", ")
    }

    // MARK: Продолжить смотреть / список

    private var resumeCandidate: WatchHistoryItem? {
        historyMgr.history.first(where: {
            let p = $0.progress ?? 0
            return p > 0.02 && p < 0.95
        })
    }

    private func remainingText(_ item: WatchHistoryItem) -> String {
        guard let total = item.totalDuration else { return "немного" }
        let left = max(0, total - item.watchedDuration)
        let mins = Int(left / 60)
        return mins > 0 ? "\(mins) мин" : "меньше минуты"
    }

    @ViewBuilder
    private func continueWatchingCard(_ item: WatchHistoryItem) -> some View {
        Button {
            HapticManager.impact(.medium)
            Task { await resumeWatching(item) }
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if let thumb = item.thumbnailURL, let url = URL(string: thumb) {
                            AsyncImage(url: url) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle().fill(V4.cardBG)
                            }
                        } else {
                            Rectangle().fill(V4.cardBG)
                                .overlay(Image(systemName: "film").foregroundStyle(V4.muted))
                        }
                    }
                    if let progress = item.progress {
                        Rectangle().fill(activeAccent)
                            .frame(width: 116 * progress, height: 3)
                    }
                }
                .frame(width: 116, height: 65)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(V4.ink)
                        .lineLimit(2)
                    Text("\(L.string(.homeTimeLeft)) \(remainingText(item))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(V4.muted)
                }
                Spacer()
                V4GlyphIcon(glyph: .play, size: 14, filled: true, weight: .regular)
                    .foregroundStyle(activeBtnText)
                    .frame(width: 36, height: 36)
                    .background(activeAccent, in: Circle())
            }
            .padding(12)
            .background(V4.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(V4.line, lineWidth: 1)
            )
        }
        .buttonStyle(V4PressableCardStyle())
        .contextMenu {
            Button(role: .destructive) {
                historyMgr.remove(item)
            } label: {
                Label("Убрать", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func watchlistCard(_ entry: WatchlistService.Entry) -> some View {
        Button {
            HapticManager.impact(.medium)
            Task { await createRoom(from: entry.mediaItem, title: entry.mediaItem.title) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let thumb = entry.mediaItem.thumbnailURL, let url = URL(string: thumb) {
                        AsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(V4.cardBG)
                        }
                    } else {
                        Rectangle().fill(V4.cardBG)
                            .overlay(Image(systemName: "bookmark.fill").foregroundStyle(V4.muted))
                    }
                }
                // 172×97 — 16:9 (у закладок YouTube-миниатюры, вертикального
                // постера нет). Прежние 150×84 на фоне укрупнённых постеров
                // 128×192 превращали ряд в самый мелкий на экране.
                .frame(width: 172, height: 97)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(V4.line, lineWidth: 1)
                )
                Text(entry.mediaItem.title)
                    // Тот же вес заголовка, что у постерных карточек: полуряд
                    // semibold рядом с bold-подписями читался как «бледнее».
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(V4.ink)
                    .lineLimit(2)
                    // Две строки зарезервированы: карточки одной высоты,
                    // ряд не проседает на коротких названиях.
                    .frame(width: 172, height: 30, alignment: .topLeading)
            }
        }
        .buttonStyle(V4PressableCardStyle())
        .contextMenu {
            Button(role: .destructive) {
                watchlist.remove(entry.id)
            } label: {
                Label("Убрать из списка", systemImage: "bookmark.slash")
            }
        }
    }

    private func resumeWatching(_ item: WatchHistoryItem) async {
        PlinkPendingResume.set(mediaId: item.mediaItemId, seconds: item.watchedDuration)
        await createRoom(from: item.mediaItem, title: item.title)
    }

    /// Общий путь создания комнаты из готового MediaItem (история / watchlist).
    private func createRoom(from mediaItem: MediaItem, title: String) async {
        if APIClient.shared.authToken == nil {
            APIClient.shared.authToken = AuthTokenStore.shared.token
        }
        guard APIClient.shared.authToken != nil else {
            await MainActor.run { HapticManager.errorOccurred() }
            return
        }
        let request = CreateRoomRequest(
            name: String(title.prefix(80)),
            maxParticipants: 10,
            mediaItem: mediaItem,
            privacy: .publicRoom,
            password: nil,
            hostName: AuthService.shared.currentUserValue?.username
        )
        do {
            var room = try await RoomService(api: APIClient.shared).createRoom(request)
            if room.mediaItem == nil {
                room = Room(
                    id: room.id, name: room.name, hostID: room.hostID, hostName: room.hostName,
                    code: room.code, participants: room.participants, mediaItem: mediaItem,
                    isActive: room.isActive, maxParticipants: room.maxParticipants,
                    hostIsPremium: room.hostIsPremium, createdAt: room.createdAt,
                    privacy: room.privacy, password: room.password
                )
            }
            await MainActor.run {
                HapticManager.roomJoined()
                UIPasteboard.general.string = "Код комнаты Plink: \(room.code)"
                NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
            }
        } catch {
            await MainActor.run { HapticManager.errorOccurred() }
        }
    }

    private func createRoomFromTrending(
        _ item: V4SearchResult, target: V4WatchTarget = .native
    ) async {
        if APIClient.shared.authToken == nil {
            APIClient.shared.authToken = AuthTokenStore.shared.token
        }
        guard APIClient.shared.authToken != nil else {
            await MainActor.run { HapticManager.errorOccurred() }
            return
        }

        // Кинотеатры в приоритете (22.08.2026): у карточки три пути в комнату.
        // Ролик YouTube — прежний прямой синх; тайтл из каталога — страница
        // просмотра кинотеатра; чип «Где ещё смотреть» — страница поиска
        // выбранного кинотеатра по названию. Кино открывается в WebView,
        // хост входит в свой аккаунт — Plink не обходит защиту.
        let mediaItem: MediaItem
        let analyticsSource: String
        switch (target, item.origin) {
        case (.native, .youtube):
            let videoId = item.id
            mediaItem = MediaItem(
                id: videoId,
                title: item.title,
                artist: nil,
                thumbnailURL: item.artworkURL?.absoluteString,
                streamURL: item.watchURL,
                duration: nil,
                mediaType: .video,
                source: .youtube,
                videoId: videoId
            )
            analyticsSource = "youtube"
        case (.native, .cinema(let service)):
            mediaItem = MediaItem(
                id: item.id,
                title: item.title,
                artist: nil,
                thumbnailURL: (item.artworkURL ?? item.posterURL)?.absoluteString,
                streamURL: item.watchURL,
                duration: nil,
                mediaType: item.isSeries ? .series : .movie,
                source: .url,
                videoId: nil
            )
            analyticsSource = service.rawValue
        case (.cinema(let service, let url), _):
            mediaItem = MediaItem(
                id: "\(service.rawValue)-\(item.id)",
                title: item.title,
                artist: nil,
                thumbnailURL: (item.artworkURL ?? item.posterURL)?.absoluteString,
                streamURL: url,
                duration: nil,
                mediaType: item.isSeries ? .series : .movie,
                source: .url,
                videoId: nil
            )
            analyticsSource = "bridge_\(service.rawValue)"
        }
        AnalyticsService.shared.track(
            "room_create_from_trending",
            parameters: ["source": analyticsSource]
        )
        let request = CreateRoomRequest(
            name: String(item.title.prefix(80)),
            maxParticipants: 10,
            mediaItem: mediaItem,
            privacy: .publicRoom,
            password: nil,
            hostName: AuthService.shared.currentUserValue?.username
        )
        do {
            var room = try await RoomService(api: APIClient.shared).createRoom(request)
            if room.mediaItem == nil {
                room = Room(
                    id: room.id,
                    name: room.name,
                    hostID: room.hostID,
                    hostName: room.hostName,
                    code: room.code,
                    participants: room.participants,
                    mediaItem: mediaItem,
                    isActive: room.isActive,
                    maxParticipants: room.maxParticipants,
                    hostIsPremium: room.hostIsPremium,
                    createdAt: room.createdAt,
                    privacy: room.privacy,
                    password: room.password
                )
            }
            await MainActor.run {
                HapticManager.roomJoined()
                PlinkAppDelegate.requestNotificationPermission()
                UIPasteboard.general.string = "Код комнаты Plink: \(room.code)"
                NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
            }
        } catch {
            await MainActor.run { HapticManager.errorOccurred() }
        }
    }
}
