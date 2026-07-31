// Plink/V4/V4HomeViewLive.swift — split from PlinkV4PixelPerfect (move-only, no logic change)
// Source of truth: V4 design module. Do not change visuals.

import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif
import Foundation

// Аудит 26.07.2026: здесь была структура `V4HomeView` — макетный вариант
// главного экрана с ЗАХАРДКОЖЕННЫМИ демо-данными: герой «Afterglow»,
// «5 друзей уже смотрят», карточки «Кино без спойлеров · 5 друзей · LIVE»
// и аватар с буквой «П» вместо имени пользователя.
//
// Проверка по всему проекту показала НОЛЬ мест использования: экран нигде
// не открывался, приложение работает через `V4HomeViewLive` с настоящими
// данными. То есть пользователи выдуманных друзей не видели.
//
// Структура удалена, потому что оставлять её было ловушкой: любой, кто
// подключил бы её по ошибке (имена различаются одним словом «Live»),
// показал бы людям несуществующие комнаты. Доверие после такого
// не восстанавливается, а польза от макета — нулевая, он есть в истории git.

// MARK: - AutoScrollCarousel — continuous slow auto-scrolling horizontal carousel
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
        .frame(height: 220)
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

// MARK: - Live Screen Variants (P0: Real backend data)

// M30: фильтры главной
enum HomeFilter: String, CaseIterable {
    case all = "Всё"
    case popular = "Популярное"
    case watching = "Смотрят"
    case friends = "Друзья"
}

struct V4HomeViewLive: View {
    let theme: V4Theme
    @Bindable var searchStore: V4SearchStore
    var roomsStore: V4RoomsStore?
    let openRoom: () -> Void
    var liveThemeIndex: Int = 0
    /// M14: переключить на вкладку «Комнаты» (для «Все» в «Смотрят сейчас»).
    var openRoomsTab: (() -> Void)? = nil
    @ObservedObject private var historyMgr = WatchHistoryManager.shared
    @ObservedObject private var watchlist = WatchlistService.shared
    @State private var query = ""
    @State private var showUnifiedSearch = false
    @State private var showInbox = false
    // M17: живые бейджи непрочитанного для колокольчика
    @ObservedObject private var dmInbox = DMChatService.shared
    @ObservedObject private var groupInbox = GroupChatService.shared
    @State private var showScheduleSheet = false  // M12: планирование сеансов
    @State private var homeFilter: HomeFilter = .all  // M30
    @State private var isRefreshing = false            // M30
    @State private var previewItem: V4SearchResult?    // M34: превью перед созданием комнаты

    // M31: sticky search bar поверх контента
    // Аудит 26.07.2026: при разделении файла из PlinkV4PixelPerfect это свойство
    // ошибочно осталось в V4HomeView, хотя ссылается на showUnifiedSearch и
    // используется в body именно этой структуры (.safeAreaInset ниже).
    // Возвращено на место — чинит обе ошибки «cannot find ... in scope».
    private var stickySearchBar: some View {
        Button {
            showUnifiedSearch = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                Text(L.string(.homeVideoPlaceholder)).foregroundStyle(V4.muted)
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 13)
            .frame(height: 44)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(V4.line))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 19)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // M30: динамическое приветствие по времени суток
    private var timeOfDayGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "ДОБРОЕ УТРО"
        case 12..<17: return "ДОБРЫЙ ДЕНЬ"
        case 17..<22: return "ДОБРЫЙ ВЕЧЕР"
        default: return "ПОЗДНЯЯ НОЧЬ"
        }
    }

    /// M14: реальная буква имени пользователя вместо жёсткой «П».
    private var avatarLetter: String {
        let name = AuthService.shared.currentUserValue?.username ?? "П"
        let clean = name.hasPrefix("@") ? String(name.dropFirst()) : name
        return String(clean.prefix(1)).uppercased()
    }

    // Theme-aware colors — use Plink+ theme colors if active, else standard
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack { V4Avatar(letter: avatarLetter, theme: theme, isPremium: PremiumStatusManager.shared.isPremium, imageURL: PlinkAvatarURL.resolve(userId: AuthService.shared.currentUserValue?.id, stored: nil)); Spacer(); NotificationInboxButton(unreadCount: dmInbox.totalUnread + groupInbox.unreadTotal, action: { showInbox = true }) }
                    .accessibilityIdentifier("screen.home")
                    .padding(.horizontal,18).padding(.top,10).padding(.bottom,16)
                .sheet(isPresented: $showInbox) {
                    // M17: живой центр уведомлений вместо заглушки
                    PlinkInboxView()
                        .preferredColorScheme(.dark)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
                V4Heading(eyebrow: timeOfDayGreeting, title: "С кем смотрим?")
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.bottom,14)

                // M30/M31: фильтр-пилюли
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(HomeFilter.allCases, id: \.self) { f in
                            Button {
                                HapticManager.selection()
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) { homeFilter = f }
                            } label: {
                                Text(f.rawValue)
                                    .font(.system(size: 12, weight: homeFilter == f ? .bold : .medium))
                                    .foregroundStyle(homeFilter == f ? activeBtnText : V4.muted)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 44)
                                    .background(homeFilter == f ? activeAccent : V4.cardBG.opacity(0.5), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 19)
                }.padding(.bottom, 16)

                // M20: skeleton пока trending не загружен; M31: fallback если пусто
                if searchStore.trending.isEmpty {
                    if isRefreshing {
                        HomeSkeletonView()
                            .transition(.opacity)
                    } else {
                        HomeFallbackPlaceholder(theme: theme, openRoom: { showUnifiedSearch = true })
                            .padding(.bottom, 20)
                    }
                }

                // Hero — only live trending rooms/videos (no promo video banners)
                if !searchStore.trending.isEmpty && (homeFilter == .all || homeFilter == .popular) {
                    TabView {
                        ForEach(searchStore.trending.prefix(5)) { item in
                            V4Hero(
                                title: item.title,
                                meta: "YouTube · \(item.subtitle)",
                                button: "Смотреть вместе",
                                height: 260,
                                theme: theme,
                                action: {
                                    HapticManager.impact(.medium)
                                    previewItem = item  // M34: сначала превью, потом комната
                                },
                                liveThemeIndex: liveThemeIndex
                            )
                            .padding(.horizontal, 13)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .frame(height: 280)
                    .padding(.bottom, 20)
                }

                // "Популярное" — auto-scrolling carousel, bigger posters
                if !searchStore.trending.isEmpty && (homeFilter == .all || homeFilter == .popular) {
                    HStack { Text(L.string(.homePopular)).font(.system(size:24,weight:.heavy)).foregroundStyle(V4.ink); Spacer() }
                        .padding(.horizontal,19).padding(.bottom,14)
                    AutoScrollCarousel(items: Array(searchStore.trending.prefix(10)), cardWidth: 250) { item in
                        trendingCard(item)
                    }
                    .padding(.bottom, 22)
                }

                // AUDIT: Quick Room — premium liquid glass button
                if !searchStore.trending.isEmpty {
                    Button {
                        HapticManager.impact(.medium)
                        if let first = searchStore.trending.first {
                            Task { await createRoomFromTrending(first) }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text(L.string(.homeQuickRoom))
                                .font(.system(size: 15, weight: .bold))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(activeBtnText)
                        .padding(.horizontal, 18)
                        .frame(height: 50)
                        .background(
                            ZStack {
                                LinearGradient(
                                    colors: [activeAccent.opacity(0.9), activeSecondary.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                LinearGradient(
                                    colors: [.white.opacity(0.2), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(.white.opacity(0.15), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .shadow(color: activeAccent.opacity(0.3), radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 19)
                    .padding(.bottom, 10)

                    // M12: запланировать совместный сеанс с напоминанием
                    Button {
                        HapticManager.impact(.light)
                        showScheduleSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 15, weight: .semibold))
                            Text(L.string(.homeScheduleSession))
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(V4.ink.opacity(0.85))
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(V4.cardBG.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 19)
                    .padding(.bottom, 18)
                }

                // M14: «Продолжить просмотр» — вернуться к недосмотренному
                if let resumeItem = resumeCandidate {
                    continueWatchingCard(resumeItem)
                        .padding(.horizontal, 19)
                        .padding(.bottom, 18)
                }

                // M14: «Посмотреть позже» — watchlist
                if !watchlist.entries.isEmpty {
                    HStack { Text(L.string(.homeWatchLaterLabel)).font(.system(size:22,weight:.heavy)).foregroundStyle(V4.ink); Spacer() }
                        .padding(.horizontal,19).padding(.bottom,12)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(watchlist.entries) { entry in
                                watchlistCard(entry)
                            }
                        }
                        .padding(.horizontal, 19)
                    }
                    .padding(.bottom, 8)
                }

                // Рекомендации — bigger cards, more prominent
                if searchStore.trending.count > 5 && (homeFilter == .all || homeFilter == .popular) {
                    HStack { Text(L.string(.homeRecommendations)).font(.system(size:22,weight:.heavy)).foregroundStyle(V4.ink); Spacer() }
                        .padding(.horizontal,19).padding(.bottom,12)
                    ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:12) {
                        ForEach(searchStore.trending.suffix(8)) { item in
                            recommendationCard(item)
                        }
                    }.padding(.horizontal,19) }
                    .padding(.bottom, 8)
                }

                // "Смотрят сейчас" — poster-based cards: video thumbnail + viewer count + host
                HStack(spacing:8) {
                    Circle().fill(V4.danger).frame(width:8,height:8)
                        .shadow(color: V4.danger.opacity(0.6), radius: 4)
                    Text(L.string(.homeWatchingNow))
                        .font(.system(size:22,weight:.heavy))
                        .tracking(-0.4)
                    Spacer()
                    // M14: «Все» ведёт на вкладку «Комнаты» — больше не тупик
                    Button {
                        HapticManager.selection()
                        openRoomsTab?()
                    } label: {
                        Text(L.string(.homeAll))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(V4.accent)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(V4.ink)
                .padding(.horizontal,19).padding(.top,32).padding(.bottom,14)

                VStack(spacing:10) {
                    if let rs = roomsStore {
                        switch rs.state {
                        case .loading, .idle:
                            ForEach(0..<2, id: \.self) { _ in watchingNowSkeleton }
                        case .loaded where !rs.rooms.isEmpty:
                            ForEach(rs.rooms.prefix(5)) { room in watchingNowCard(room) }
                        case .failed:
                            compactRoomsState(
                                icon: "wifi.exclamationmark",
                                title: "Не удалось загрузить комнаты",
                                subtitle: "Проверь соединение и повтори",
                                actionTitle: "Повторить"
                            ) { Task { await roomsStore?.load() } }
                        case .loaded, .empty:
                            compactRoomsState(
                                icon: "person.3.sequence.fill",
                                title: "Пока тихо",
                                subtitle: "Найди видео или создай комнату — друзья смогут присоединиться",
                                actionTitle: "Найти видео"
                            ) { showUnifiedSearch = true }
                        }
                    } else {
                        ForEach(0..<2, id: \.self) { _ in watchingNowSkeleton }
                    }
                }
                .padding(.horizontal,19)

                // M31: друзья смотрят + новинки недели
                if homeFilter == .all || homeFilter == .friends {
                    FriendsWatchingSection(theme: theme, openRoom: { openRoomsTab?() })
                        .padding(.top, 10)
                        .padding(.bottom, 18)
                }
                if homeFilter == .all {
                    NewThisWeekSection(theme: theme)
                        .padding(.bottom, 10)
                }
            }.padding(.bottom,96)
        }.foregroundStyle(V4.ink)
        .safeAreaInset(edge: .top) { stickySearchBar }
        .refreshable {
            isRefreshing = true
            await searchStore.loadTrending()
            isRefreshing = false
        }
        .sheet(item: $previewItem) { item in
            // M34: превью перед созданием комнаты
            TrendingPreviewSheet(item: item, theme: theme) {
                previewItem = nil
                Task { await createRoomFromTrending(item) }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showUnifiedSearch) {
            UnifiedSearchView(searchStore: searchStore, roomsStore: roomsStore, openRoom: {
                showUnifiedSearch = false
                openRoom()
            })
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showScheduleSheet) {
            ScheduleSessionSheet()
                .preferredColorScheme(.dark)
        }
    }

    private var watchingNowSkeleton: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(V4.cardBG)
                .frame(width: 108, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(V4.cardBG).frame(width: 160, height: 13)
                RoundedRectangle(cornerRadius: 3).fill(V4.cardBG.opacity(0.6)).frame(width: 90, height: 10)
            }
            Spacer()
        }
        .padding(12)
        .frame(minHeight: 88)
        .background(V4.cardBG.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Загрузка активных комнат")
    }

    private func compactRoomsState(
        icon: String,
        title: String,
        subtitle: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(V4.muted)
            Text(title)
                .font(.system(size: 15, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(activeAccent)
                .foregroundStyle(activeBtnText)
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(V4.cardBG.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Create room from a specific trending video — used by hero + quick room.
    @ViewBuilder
    private func watchingNowCard(_ room: Room) -> some View {
        Button {
            HapticManager.impact(.light)
            NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
        } label: {
            ZStack(alignment: .bottomLeading) {
                // Full-bleed 16:9 media establishes the room before metadata.
                if let thumbStr = room.mediaItem?.thumbnailURL, let url = URL(string: thumbStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            roomArtworkFallback
                        }
                    }
                } else {
                    roomArtworkFallback
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.16), .black.opacity(0.94)],
                    startPoint: UnitPoint(x: 0.5, y: 0.18),
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        if room.isActive {
                            HStack(spacing: 5) {
                                Circle().fill(.white).frame(width: 5, height: 5)
                                Text(L.string(.homeLive))
                            }
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(V4.danger, in: Capsule())
                        }

                        Text("\(room.participantCount)/\(room.maxParticipants)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(.black.opacity(0.48), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.16)))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.black)
                            .frame(width: 34, height: 34)
                            .background(.white, in: Circle())
                    }

                    Spacer(minLength: 22)

                    Text(room.mediaItem?.title ?? room.name)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 7) {
                        Image(systemName: "person.crop.circle.fill")
                        Text("\(L.string(.homeHostLabel)) \(room.hostName)")
                            .lineLimit(1)
                        Spacer()
                        Text("Войти")
                            .fontWeight(.bold)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                }
                .padding(16)
            }
            .frame(height: 198)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.30), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
    }

    private var roomArtworkFallback: some View {
        ZStack {
            LinearGradient(
                colors: [theme.accentColor.opacity(0.42), theme.secondaryAccent.opacity(0.18), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.white.opacity(0.68))
        }
    }

    /// Promotional banner for hero carousel
    private func promoBanner(title: String, subtitle: String, icon: String, isPremium: Bool = false, action: @escaping () -> Void) -> some View {
        let bannerAccent = isPremium ? Color(hex: "#A855F7") : activeAccent
        let bannerSecondary = isPremium ? Color(hex: "#EC4899") : activeSecondary
        return Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Background gradient
                LinearGradient(
                    colors: [bannerAccent.opacity(0.3), Color.oklch(0.06, 0.01, 190)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // Glow accent
                RadialGradient(colors: [bannerSecondary.opacity(0.4), .clear], center: UnitPoint(x: 0.75, y: 0.25), startRadius: 0, endRadius: 180)
                // Dark fade at bottom for text readability
                LinearGradient(colors: [.clear, Color.oklch(0.06, 0.01, 190, alpha: 0.9)], startPoint: UnitPoint(x: 0.5, y: 0.3), endPoint: .bottom)

                VStack(alignment: .leading, spacing: 10) {
                    // Icon badge
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(bannerAccent.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                        if isPremium {
                            Text("Plink+")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: "#A855F7"), in: Capsule())
                        }
                    }
                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                    // CTA button
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                        Text(isPremium ? "Оформить" : "Создать")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    .foregroundStyle(activeBtnText)
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(
                        ZStack {
                            LinearGradient(colors: [bannerAccent.opacity(0.9), bannerSecondary.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .top, endPoint: .center)
                        }
                    )
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: bannerAccent.opacity(0.3), radius: 10, y: 4)
                }
                .padding(.horizontal, 19)
                .padding(.bottom, 18)
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
            .shadow(color: .black.opacity(0.40), radius: 27, y: 25)
        }
        .buttonStyle(.plain)
    }

    /// Trending card with thumbnail + title
    private func trendingCard(_ item: V4SearchResult) -> some View {
        let (_, _, _, accent) = theme.colors
        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                if let url = item.artworkURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 14).fill(V4.cardBG)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 14).fill(V4.cardBG)
                }
                RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.05))
                Text("YouTube")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(8)
            }
            .frame(width: 250, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(V4.ink)
                .lineLimit(2)
                .frame(width: 250, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.impact(.light)
            previewItem = item  // M34: превью по тапу на карточку
        }
    }

    /// Compact cinematic card for recommendations.
    private func recommendationCard(_ item: V4SearchResult) -> some View {
        Button {
            HapticManager.impact(.light)
            previewItem = item
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .bottomTrailing) {
                    if let url = item.artworkURL {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12).fill(V4.cardBG)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(V4.cardBG)
                    }
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(.white, in: Circle())
                        .padding(9)
                }
                .frame(width: 180, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(item.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(V4.ink)
                    .lineLimit(2)
                    .frame(width: 180, alignment: .leading)

                Text(item.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(V4.muted)
                    .lineLimit(1)
                    .frame(width: 180, alignment: .leading)
            }
            .frame(width: 196, alignment: .leading)
            .padding(8)
            .background(V4.cardBG.opacity(0.52), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(V4.line))
        }
        .buttonStyle(.plain)
    }

    /// Create room from a trending video — posts .plinkRoomCreated so
    /// PlinkApprovedV4Root picks it up and presents WatchRoom.
    // MARK: - M14: «Продолжить просмотр» + «Посмотреть позже»

    /// Недосмотренное видео (2–95% прогресса) — кандидат на «Продолжить».
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
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(L.string(.homeContinueWatching))
                        .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(activeAccent)
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(V4.ink)
                        .lineLimit(2)
                    Text("\(L.string(.homeTimeLeft)) \(remainingText(item))")
                        .font(.system(size: 11))
                        .foregroundStyle(V4.muted)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(activeAccent)
            }
            .padding(12)
            .background(V4.cardBG.opacity(0.55))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
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
            VStack(alignment: .leading, spacing: 6) {
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
                .frame(width: 150, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(entry.mediaItem.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(V4.ink)
                    .lineLimit(2)
                    .frame(width: 150, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                watchlist.remove(entry.id)
            } label: {
                Label("Убрать из списка", systemImage: "bookmark.slash")
            }
        }
    }

    private func resumeWatching(_ item: WatchHistoryItem) async {
        // Хост сделает синхронный seek к сохранённому таймкоду после подключения
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

    private func createRoomFromTrending(_ item: V4SearchResult) async {
        AnalyticsService.shared.track("room_create_from_trending")  // M35: funnel
        // Ensure API client has token (Keychain alone is not enough for RoomService)
        if APIClient.shared.authToken == nil {
            APIClient.shared.authToken = AuthTokenStore.shared.token
        }
        guard APIClient.shared.authToken != nil else {
            await MainActor.run {
                HapticManager.errorOccurred()
            }
            return
        }

        let videoId = item.id
        // Prefer watch URL — backend + client both extract videoId reliably
        let streamURL = "https://www.youtube.com/watch?v=\(videoId)"
        let mediaItem = MediaItem(
            id: videoId,
            title: item.title,
            artist: nil,
            thumbnailURL: item.artworkURL?.absoluteString,
            streamURL: streamURL,
            duration: nil,
            mediaType: .video,
            source: .youtube,
            videoId: videoId
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
            // If server stripped mediaItem, keep the local one for playback
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
            await MainActor.run {
                HapticManager.errorOccurred()
            }
        }
    }
}


