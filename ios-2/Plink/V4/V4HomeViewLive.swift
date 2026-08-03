// Plink/V4/V4HomeViewLive.swift
// 02.08.2026: «Главная» пересобрана под новый макет.
//
// Что изменилось и почему:
// 1) Убрана лента LIVE-комнат «Смотрят сейчас». Именно она делала «Главную»
//    неотличимой от вкладки «Комнаты». Главная отвечает на вопрос «что посмотреть»,
//    Комнаты — «с кем и когда».
// 2) Поиск и карточка «Спросить ИИ-ассистента» — точки входа в чат с ИИ
//    (.plinkOpenAIChat). ИИ работает там, где ищут фильм, а не отдельной вкладкой.
// 3) Вместо автокарусели огромных квадратов — лента компактных постеров
//    и нумерованный топ-3. Автопрокрутка ещё и спорила с жестами пользователя.
// 4) Удалён мёртвый код: promoBanner, releaseNotesCard/releaseNoteRow, showScheduleSheet
//    — ни одного вызова в теле экрана.

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

// MARK: - Главная

struct V4HomeViewLive: View {
    let theme: V4Theme
    @Bindable var searchStore: V4SearchStore
    var roomsStore: V4RoomsStore?
    let openRoom: () -> Void
    var liveThemeIndex: Int = 0
    /// Переключить на вкладку «Комнаты».
    var openRoomsTab: (() -> Void)? = nil

    @ObservedObject private var historyMgr = WatchHistoryManager.shared
    @ObservedObject private var watchlist = WatchlistService.shared
    @ObservedObject private var dmInbox = DMChatService.shared
    @ObservedObject private var groupInbox = GroupChatService.shared

    @State private var showUnifiedSearch = false
    @State private var showReleaseNotes = false
    @State private var showInbox = false
    @State private var isRefreshing = false
    @State private var previewItem: V4SearchResult?

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

    private var timeOfDayGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "ДОБРОЕ УТРО"
        case 12..<17: return "ДОБРЫЙ ДЕНЬ"
        case 17..<22: return "ДОБРЫЙ ВЕЧЕР"
        default: return "ПОЗДНЯЯ НОЧЬ"
        }
    }

    private var avatarLetter: String {
        let name = AuthService.shared.currentUserValue?.username ?? "П"
        let clean = name.hasPrefix("@") ? String(name.dropFirst()) : name
        return String(clean.prefix(1)).uppercased()
    }

    // MARK: Тело

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                topBar

                V4Heading(eyebrow: timeOfDayGreeting, title: "Что посмотрим?")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 19)
                    .padding(.bottom, 16)

                searchRow
                    .padding(.horizontal, 19)
                    .padding(.bottom, 14)

                askAICard
                    .padding(.horizontal, 19)
                    .padding(.bottom, 20)

                if searchStore.trending.isEmpty {
                    if isRefreshing {
                        HomeSkeletonView().transition(.opacity)
                    } else {
                        HomeFallbackPlaceholder(theme: theme, openRoom: { showUnifiedSearch = true })
                            .padding(.bottom, 20)
                    }
                }

                if !searchStore.trending.isEmpty {
                    heroCarousel
                }

                if let resumeItem = resumeCandidate {
                    sectionTitle(L.string(.homeContinueWatching))
                    continueWatchingCard(resumeItem)
                        .padding(.horizontal, 19)
                        .padding(.bottom, 22)
                }

                if !searchStore.trending.isEmpty {
                    sectionTitle(L.string(.homePopular))
                    posterRail
                        .padding(.bottom, 24)
                }

                if searchStore.trending.count >= 3 {
                    sectionTitle("Топ недели")
                    topThree
                        .padding(.horizontal, 19)
                        .padding(.bottom, 24)
                }

                if !watchlist.entries.isEmpty {
                    sectionTitle(L.string(.homeWatchLaterLabel))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(watchlist.entries) { entry in
                                watchlistCard(entry)
                            }
                        }
                        .padding(.horizontal, 19)
                    }
                    .padding(.bottom, 24)
                }

                if searchStore.trending.count > 5 {
                    sectionTitle(L.string(.homeRecommendations))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(searchStore.trending.suffix(8)) { item in
                                recommendationCard(item)
                            }
                        }
                        .padding(.horizontal, 19)
                    }
                    .padding(.bottom, 20)
                }

                // Комнаты живут на своей вкладке. Здесь — одна строка-переход,
                // а не вторая копия того же экрана.
                roomsHandoff
                    .padding(.horizontal, 19)
            }
            .padding(.bottom, 96)
        }
        .foregroundStyle(V4.ink)
        .refreshable {
            isRefreshing = true
            await searchStore.loadTrending()
            isRefreshing = false
        }
        .sheet(item: $previewItem) { item in
            TrendingPreviewSheet(item: item, theme: theme) {
                previewItem = nil
                Task { await createRoomFromTrending(item) }
            }
            .presentationDetents([.large])
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
        }
        .sheet(isPresented: $showReleaseNotes) {
            ReleaseNotesSheet()
                .preferredColorScheme(.dark)
        }
    }

    // MARK: Шапка

    private var topBar: some View {
        HStack(spacing: 10) {
            V4Avatar(
                letter: avatarLetter,
                theme: theme,
                isPremium: PremiumStatusManager.shared.isPremium,
                imageURL: PlinkAvatarURL.resolve(userId: AuthService.shared.currentUserValue?.id, stored: nil)
            )
            Spacer()
            Button { showReleaseNotes = true } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(activeAccent)
                    .frame(width: 40, height: 40)
                    .background(activeAccent.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Новое в Plink")
            NotificationInboxButton(
                unreadCount: dmInbox.totalUnread + groupInbox.unreadTotal,
                action: { showInbox = true }
            )
        }
        .accessibilityIdentifier("screen.home")
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    // MARK: Поиск + вход в ИИ

    private var searchRow: some View {
        HStack(spacing: 10) {
            Button {
                HapticManager.impact(.light)
                showUnifiedSearch = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(V4.muted)
                    Text("Фильм, сериал или ссылка")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(V4.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(V4.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(V4.line, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Найти видео, сервис или комнату")

            Button {
                HapticManager.impact(.light)
                AnalyticsService.shared.track("ai_chat_used", parameters: ["source": "home_search"])
                NotificationCenter.default.post(name: .plinkOpenAIChat, object: nil)
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(activeBtnText)
                    .frame(width: 52, height: 52)
                    .background(activeAccent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Спросить ИИ-ассистента")
        }
    }

    private var askAICard: some View {
        Button {
            HapticManager.impact(.light)
            AnalyticsService.shared.track("ai_chat_used", parameters: ["source": "home_card"])
            NotificationCenter.default.post(name: .plinkOpenAIChat, object: nil)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(activeAccent.opacity(0.14))
                    Image(systemName: "sparkles")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(activeAccent)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Спросить ИИ-ассистента")
                        .font(.system(size: 15.5, weight: .heavy))
                        .foregroundStyle(V4.ink)
                    Text("Подберёт фильм и сразу соберёт комнату")
                        .font(.system(size: 11.5, weight: .medium))
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
    }

    // MARK: Герой

    private var heroCarousel: some View {
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
                        previewItem = item
                    },
                    liveThemeIndex: liveThemeIndex
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
            HStack(spacing: 12) {
                ForEach(searchStore.trending.prefix(10)) { item in
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
                ZStack(alignment: .bottomLeading) {
                    artwork(item)
                        .frame(width: 124, height: 168)
                        .clipped()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.62)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 26, height: 26)
                        .background(.white, in: Circle())
                        .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(item.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(V4.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 124, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Топ-3

    private var topThree: some View {
        VStack(spacing: 10) {
            ForEach(Array(searchStore.trending.prefix(3).enumerated()), id: \.element.id) { index, item in
                Button {
                    HapticManager.impact(.light)
                    previewItem = item
                } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 26, weight: .black))
                            .foregroundStyle(activeAccent.opacity(0.55))
                            .frame(width: 26)

                        artwork(item)
                            .frame(width: 62, height: 62)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 13.5, weight: .heavy))
                                .foregroundStyle(V4.ink)
                                .lineLimit(1)
                            Text(item.subtitle)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(V4.muted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("Смотреть")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(activeBtnText)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(activeAccent, in: Capsule())
                    }
                    .padding(10)
                    .background(V4.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(V4.line, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Переход в комнаты

    private var roomsHandoff: some View {
        Button {
            HapticManager.selection()
            openRoomsTab?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(activeAccent)
                    .frame(width: 40, height: 40)
                    .background(activeAccent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Смотреть с друзьями")
                        .font(.system(size: 14.5, weight: .heavy))
                        .foregroundStyle(V4.ink)
                    Text(roomsHandoffSubtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(V4.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(V4.muted)
            }
            .padding(13)
            .background(V4.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(V4.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Открыть вкладку Комнаты")
    }

    private var roomsHandoffSubtitle: String {
        let count = roomsStore?.rooms.count ?? 0
        if count == 0 { return "Создать комнату или войти по коду" }
        return "Сейчас открыто комнат: \(count)"
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
    private func artwork(_ item: V4SearchResult) -> some View {
        if let url = item.artworkURL {
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

    private struct ReleaseNotesSheet: View {
        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Новое в Plink")
                            .font(.system(size: 28, weight: .black))
                        VStack(alignment: .leading, spacing: 12) {
                            note(icon: "sparkles", title: "ИИ-ассистент везде", subtitle: "Чат с ассистентом открывается прямо с Главной, а вкладка «ИИ» — это голос.")
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

    private func recommendationCard(_ item: V4SearchResult) -> some View {
        Button {
            HapticManager.impact(.light)
            previewItem = item
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .bottomTrailing) {
                    artwork(item)
                        .frame(width: 180, height: 108)
                        .clipped()
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
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
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
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
        AnalyticsService.shared.track("room_create_from_trending")
        if APIClient.shared.authToken == nil {
            APIClient.shared.authToken = AuthTokenStore.shared.token
        }
        guard APIClient.shared.authToken != nil else {
            await MainActor.run { HapticManager.errorOccurred() }
            return
        }

        let videoId = item.id
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
