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
    @State private var showUnifiedSearch = false
    @State private var showReleaseNotes = false
    @State private var showInbox = false
    // M17: живые бейджи непрочитанного для колокольчика
    @ObservedObject private var dmInbox = DMChatService.shared
    @ObservedObject private var groupInbox = GroupChatService.shared
    @State private var showScheduleSheet = false  // M12: планирование сеансов
    @State private var homeFilter: HomeFilter = .all  // M30
    @State private var isRefreshing = false            // M30
    @State private var previewItem: V4SearchResult?    // M34: превью перед созданием комнаты

    // Discovery is an intentional action inside the content hierarchy. A sticky
    // search field at the top made Home feel like a utility screen and pushed the
    // social/product thesis below the fold.
    private var discoveryEntry: some View {
        Button {
            HapticManager.impact(.light)
            showUnifiedSearch = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(activeAccent.opacity(0.14))
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(activeAccent)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Что будем смотреть?")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(V4.ink)
                    Text("YouTube, Twitch, ссылка или код комнаты")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(V4.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(activeBtnText)
                    .frame(width: 38, height: 38)
                    .background(activeAccent, in: Circle())
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [V4.surface.opacity(0.94), activeAccent.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(activeAccent.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Найти видео, сервис или комнату")
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
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.bottom,18)

                discoveryEntry
                    .padding(.horizontal, 19)
                    .padding(.bottom, 20)

                // Home filters describe content after the product action is clear.
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

                // Updates live in a dedicated sheet. They must not interrupt the
                // content feed or appear as a permanent promotional card on Home.

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

                // Release notes / onboarding belongs in a dedicated surface, not as
                // a generic bottom appendage after recommendations.
                if showReleaseNotes {
                    releaseNotesCard
                        .padding(.horizontal, 19)
                        .padding(.bottom, 18)
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
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(activeAccent)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(V4.ink)
                .padding(.horizontal,19).padding(.top,32).padding(.bottom,14)

                Group {
                    if let rs = roomsStore {
                        switch rs.state {
                        case .loading, .idle:
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 14) {
                                    ForEach(0..<2, id: \.self) { _ in watchingNowSkeleton }
                                }
                                .padding(.horizontal, 19)
                            }
                        case .loaded where !rs.rooms.isEmpty:
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 14) {
                                    ForEach(rs.rooms.prefix(8)) { room in watchingNowCard(room) }
                                }
                                .padding(.horizontal, 19)
                            }
                            .scrollTargetBehavior(.viewAligned)
                        case .failed:
                            compactRoomsState(
                                icon: "wifi.exclamationmark",
                                title: "Не удалось загрузить комнаты",
                                subtitle: "Проверь соединение и повтори",
                                actionTitle: "Повторить"
                            ) { Task { await roomsStore?.load() } }
                            .padding(.horizontal, 19)
                        case .loaded, .empty:
                            compactRoomsState(
                                icon: "person.3.sequence.fill",
                                title: "Пока тихо",
                                subtitle: "Найди видео или создай комнату — друзья смогут присоединиться",
                                actionTitle: "Найти видео"
                            ) { showUnifiedSearch = true }
                            .padding(.horizontal, 19)
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(0..<2, id: \.self) { _ in watchingNowSkeleton }
                            }
                            .padding(.horizontal, 19)
                        }
                    }
                }
                .frame(height: 334)

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
        .sheet(isPresented: $showReleaseNotes) {
            ReleaseNotesSheet()
                .preferredColorScheme(.dark)
        }
    }

    private var watchingNowSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(V4.cardBG.opacity(0.82))
                .frame(height: 170)
                .overlay(alignment: .topLeading) {
                    Capsule().fill(V4.raised.opacity(0.9)).frame(width: 70, height: 24).padding(14)
                }
            RoundedRectangle(cornerRadius: 5).fill(V4.cardBG).frame(width: 190, height: 16)
            RoundedRectangle(cornerRadius: 4).fill(V4.cardBG.opacity(0.6)).frame(width: 126, height: 11)
        }
        .padding(10)
        .frame(width: 306, height: 308, alignment: .topLeading)
        .background(V4.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityLabel("Загрузка активных комнат")
    }

    private func compactRoomsState(
        icon: String,
        title: String,
        subtitle: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [activeAccent, activeSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(activeBtnText)
                }
                .frame(width: 58, height: 58)
                .shadow(color: activeAccent.opacity(0.34), radius: 18, y: 10)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(V4.ink)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(V4.muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                Text(actionTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(activeBtnText)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(
                        LinearGradient(
                            colors: [activeAccent, activeSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: activeAccent.opacity(0.28), radius: 12, y: 6)
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.black.opacity(0.72), V4.surface.opacity(0.92)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RadialGradient(
                        colors: [activeAccent.opacity(0.22), .clear],
                        center: .topLeading,
                        startRadius: 8,
                        endRadius: 240
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [activeAccent.opacity(0.30), .white.opacity(0.06), activeSecondary.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Cinematic live-room tile. The room is presented as a social scene rather
    /// than a settings row: media first, people second, metadata last.
    @ViewBuilder
    private func watchingNowCard(_ room: Room) -> some View {
        Button {
            HapticManager.impact(.light)
            NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    roomArtwork(room)
                        .frame(height: 220)
                        .clipped()

                    LinearGradient(
                        colors: [.black.opacity(0.24), .clear, .black.opacity(0.82)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    HStack(spacing: 7) {
                        if room.isActive {
                            HStack(spacing: 6) {
                                Circle().fill(.white).frame(width: 5, height: 5)
                                Text(L.string(.homeLive))
                            }
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(V4.danger, in: Capsule())
                            .shadow(color: V4.danger.opacity(0.42), radius: 10)
                        }

                        roomPrivacyBadge(room)
                        Spacer()

                        HStack(spacing: 5) {
                            Image(systemName: "person.2.fill")
                            Text("\(room.participantCount)")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(14)

                    VStack(alignment: .leading, spacing: 6) {
                        Spacer()
                        Text(room.mediaItem?.title ?? room.name)
                            .font(.system(size: 21, weight: .heavy))
                            .tracking(-0.35)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let artist = room.mediaItem?.artist, !artist.isEmpty {
                            Text(artist)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                    }
                    .padding(16)
                }

                HStack(spacing: 11) {
                    roomParticipantStack(room)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(room.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(V4.ink)
                            .lineLimit(1)
                        Text("Хост · \(room.hostName)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(V4.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(activeBtnText)
                        .frame(width: 40, height: 40)
                        .background(activeAccent, in: Circle())
                        .shadow(color: activeAccent.opacity(0.32), radius: 12, y: 6)
                }
                .padding(15)
                .background(
                    LinearGradient(
                        colors: [V4.surface.opacity(0.96), Color.black.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .frame(width: 320, height: 324)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.76), V4.surface.opacity(0.96)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [activeAccent.opacity(0.38), .white.opacity(0.10), activeSecondary.opacity(0.22)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.46), radius: 28, y: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(room.mediaItem?.title ?? room.name), хост \(room.hostName), \(room.participantCount) участников")
        .accessibilityHint("Открыть комнату")
    }

    @ViewBuilder
    private func roomArtwork(_ room: Room) -> some View {
        if let thumbStr = room.mediaItem?.thumbnailURL, let url = URL(string: thumbStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    roomArtworkFallback(room)
                }
            }
        } else {
            roomArtworkFallback(room)
        }
    }

    private func roomArtworkFallback(_ room: Room) -> some View {
        let seed = abs(room.id.hashValue)
        let angle = Double(seed % 240) + 80
        return ZStack {
            LinearGradient(
                colors: [
                    Color.oklch(0.54, 0.15, angle),
                    Color.oklch(0.22, 0.10, angle + 42),
                    Color.oklch(0.07, 0.025, 215),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.11))
                .frame(width: 170, height: 170)
                .blur(radius: 10)
                .offset(x: 118, y: -54)
            Image(systemName: room.mediaItem == nil ? "rectangle.stack.badge.play.fill" : "play.fill")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white.opacity(0.72))
                .shadow(color: .black.opacity(0.36), radius: 20)
        }
    }

    @ViewBuilder
    private func roomPrivacyBadge(_ room: Room) -> some View {
        if room.privacy != .publicRoom || room.isLocked {
            Image(systemName: room.isLocked ? "lock.fill" : room.privacy.icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private func roomParticipantStack(_ room: Room) -> some View {
        HStack(spacing: -8) {
            ForEach(Array(room.participants.prefix(3).enumerated()), id: \.element.id) { index, participant in
                Group {
                    if let url = PlinkAvatarURL.resolve(userId: participant.id, stored: participant.avatarURL) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            roomAvatarFallback(participant.username, index: index)
                        }
                    } else {
                        roomAvatarFallback(participant.username, index: index)
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(Circle())
                .overlay(Circle().stroke(V4.surface, lineWidth: 2))
            }
            if room.participants.isEmpty {
                roomAvatarFallback(room.hostName, index: 0)
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(V4.surface, lineWidth: 2))
            }
        }
    }

    private func roomAvatarFallback(_ name: String, index: Int) -> some View {
        let palette: [Color] = [activeAccent, activeSecondary, V4.danger]
        return ZStack {
            palette[index % palette.count]
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)
        }
    }

    private var releaseNotesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [activeAccent.opacity(0.28), activeSecondary.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(activeAccent)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Новое в Plink")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(V4.ink)
                    Text("Что нового после обновления")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(V4.muted)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                releaseNoteRow(icon: "sparkles", title: "Умные подсказки ИИ", subtitle: "Ассистент предлагает контекстно, без лишнего шума")
                releaseNoteRow(icon: "qrcode.viewfinder", title: "Вход по коду", subtitle: "Шесть символов — и ты внутри, без поиска и ссылок")
                releaseNoteRow(icon: "clock.arrow.circlepath", title: "История просмотров", subtitle: "Что вы смотрели вместе — теперь собрано в профиле")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [V4.surface.opacity(0.96), Color.black.opacity(0.64)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(activeAccent.opacity(0.16), lineWidth: 1)
        )
    }

    private func releaseNoteRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(activeAccent.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(activeAccent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(V4.ink)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(V4.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(V4.cardBG.opacity(0.34), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }


    private struct ReleaseNotesSheet: View {
        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Новое в Plink")
                            .font(.system(size: 28, weight: .black))
                        VStack(alignment: .leading, spacing: 12) {
                            note(icon: "sparkles", title: "Умные подсказки ИИ", subtitle: "Ассистент теперь предлагает, что посмотреть, когда уместно.")
                            note(icon: "qrcode.viewfinder", title: "Вход по коду", subtitle: "Шестизначный код — быстрый способ войти в комнату.")
                            note(icon: "clock.arrow.circlepath", title: "История просмотров", subtitle: "Что вы смотрели вместе теперь видно в профиле и истории.")
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
                .navigationTitle("Новое в Plink")
                .navigationBarTitleDisplayMode(.inline)
            }
        }

        @ViewBuilder
        private func note(icon: String, title: String, subtitle: String) -> some View {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 16, weight: .bold))
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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


