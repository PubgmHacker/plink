//
//  UnifiedSearchView.swift
//  Plink
//
//  P0.3: Unified search with chips (Видео / Сервисы / Комнаты).
//  Mixed results by default, chip filters output.
//

import SwiftUI

struct UnifiedSearchView: View {
    @Bindable var searchStore: V4SearchStore
    var roomsStore: V4RoomsStore?
    let openRoom: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var selectedChip: SearchChip = .all
    @State private var showRoomCreation = false
    @State private var actionError: String?
    // «Посмотреть позже»
    @ObservedObject private var watchlist = WatchlistService.shared
    private let theme = V4Theme.saved

    enum SearchChip: String, CaseIterable {
        case all = "Всё"
        case videos = "Видео"
        case services = "Сервисы"
        case rooms = "Комнаты"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                V4.canvas
                RadialGradient(
                    colors: [theme.accentColor.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.5, y: 0),
                    startRadius: 0,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 0) {
                    // Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SearchChip.allCases, id: \.self) { chip in
                                Button {
                                    HapticManager.selection()
                                    selectedChip = chip
                                } label: {
                                    Text(chip.rawValue)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(selectedChip == chip ? theme.buttonTextColor : Cinema2026.text)
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: 32)
                                        .background(selectedChip == chip ? theme.accentColor : Cinema2026.surface, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }

                    // Results
                    if query.isEmpty {
                        emptyState
                    } else {
                        resultsList
                    }
                }
            }
            .navigationTitle("Поиск")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Видео, сервис или комната")
            .onChange(of: query) { _, new in
                searchStore.search(new)
            }
            .toolbar {
                V4SheetCloseToolbarItem { dismiss() }
            }
            .alert("Не удалось открыть видео", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("Понятно", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "Попробуйте ещё раз.")
            }
            .sheet(isPresented: $showRoomCreation) {
                RoomCreationView(
                    onRoomCreated: { _ in
                        showRoomCreation = false
                        dismiss()
                    }
                )
                .environmentObject(APIClient.shared)
                .preferredColorScheme(.dark)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Cinema2026.secondary)
            Text(LocalizationManager.shared.string(.usPrompt))
                .font(.headline)
                .foregroundStyle(Cinema2026.text)
            Text(LocalizationManager.shared.string(.usPromptSub))
                .font(.subheadline)
                .foregroundStyle(Cinema2026.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                // Videos section
                if selectedChip == .all || selectedChip == .videos {
                    if !filteredVideos.isEmpty {
                        sectionHeader("Видео")
                        ForEach(filteredVideos) { item in
                            videoRow(item)
                        }
                    }
                }

                // Services section
                if selectedChip == .all || selectedChip == .services {
                    if !filteredServices.isEmpty {
                        sectionHeader("Сервисы")
                        ForEach(filteredServices, id: \.self) { svc in
                            serviceRow(svc)
                        }
                    }
                }

                // Rooms section
                if selectedChip == .all || selectedChip == .rooms {
                    if roomsStore != nil && !filteredRooms.isEmpty {
                        sectionHeader("Комнаты")
                        ForEach(filteredRooms) { room in
                            roomRow(room)
                        }
                    }
                }

                if filteredVideos.isEmpty && filteredServices.isEmpty && filteredRooms.isEmpty {
                    Text(LocalizationManager.shared.string(.nothingFound))
                        .font(.subheadline)
                        .foregroundStyle(Cinema2026.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    private var filteredVideos: [V4SearchResult] {
        guard !query.isEmpty else { return [] }
        // Use search results from state if loaded, otherwise filter trending
        if case .loaded(let results) = searchStore.state {
            return results.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.subtitle.localizedCaseInsensitiveContains(query)
            }
        }
        return searchStore.trending.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredServices: [VideoService] {
        let allServices: [VideoService] = [.youtube, .vk, .rutube, .netflix, .disney, .kinopoisk, .ivi, .okko, .wink, .start, .premier, .smotrim, .kion, .browser, .customURL]
        guard !query.isEmpty else { return allServices }
        return allServices.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredRooms: [Room] {
        guard let rs = roomsStore, !query.isEmpty else { return [] }
        return rs.rooms.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.hostName.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Rows

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .heavy))
            .tracking(1.1)
            .foregroundStyle(Cinema2026.secondary)
            .padding(.top, 8)
    }

    /// MediaItem для watchlist из результата поиска. Пустой запрос падает
    /// на полку Главной, где теперь стоят и карточки кинотеатров, — у них
    /// источник .url и страница просмотра вместо youtube.com/watch.
    private func watchlistItem(_ item: V4SearchResult) -> MediaItem {
        let isYouTube = item.origin == .youtube
        return MediaItem(
            id: item.id, title: item.title, artist: nil,
            thumbnailURL: item.artworkURL?.absoluteString,
            streamURL: item.watchURL,
            duration: nil,
            mediaType: item.origin.isClip ? .video : (item.isSeries ? .series : .movie),
            source: isYouTube ? .youtube : .url,
            videoId: isYouTube ? item.id : nil
        )
    }

    /// В beta комнату создаём только для двух источников с проверенным
    /// официальным embed-плеером. Карточка кинотеатра/будущего провайдера
    /// должна открыть его страницу, а не отправлять пользователя в пустую
    /// комнату с обычным каталогом внутри WebView.
    private func canCreateRoom(for item: V4SearchResult) -> Bool {
        item.origin.isClip && item.origin.service.isAvailableInBeta
    }

    private func openOfficialPage(for item: V4SearchResult) {
        guard let url = URL(string: item.watchURL) else {
            actionError = "У этого результата нет корректной ссылки."
            return
        }
        HapticManager.impact(.light)
        openURL(url)
        dismiss()
    }

    @MainActor
    private func createRoom(for item: V4SearchResult) async {
        guard canCreateRoom(for: item) else {
            openOfficialPage(for: item)
            return
        }
        if APIClient.shared.authToken == nil {
            APIClient.shared.authToken = AuthTokenStore.shared.token
        }
        guard APIClient.shared.authToken != nil else {
            actionError = "Войдите в Plink, чтобы создать комнату."
            return
        }

        let mediaItem = watchlistItem(item)
        let request = CreateRoomRequest(
            name: String(item.title.prefix(80)),
            maxParticipants: 10,
            mediaItem: mediaItem,
            privacy: .publicRoom,
            password: nil,
            hostName: AuthService.shared.currentUserValue?.username
        )
        do {
            let room = try await RoomService(api: APIClient.shared).createRoom(request)
            HapticManager.roomJoined()
            UIPasteboard.general.string = "Код комнаты Plink: \(room.code)"
            NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
            dismiss()
        } catch {
            HapticManager.errorOccurred()
            actionError = "Не удалось создать комнату. Проверьте соединение и попробуйте ещё раз."
        }
    }

    private func videoRow(_ item: V4SearchResult) -> some View {
        HStack(spacing: 10) {
            // Отдельная кнопка результата. Раньше закладка была вложена в
            // эту кнопку: SwiftUI выбирал внешний hit-test, поэтому тап по
            // bookmark иногда создавал комнату, а на iOS 26 жесты мерцали.
            Button {
                if canCreateRoom(for: item) {
                    Task { await createRoom(for: item) }
                } else {
                    openOfficialPage(for: item)
                }
            } label: {
                HStack(spacing: 12) {
                // Ветки «нет кадра» и «кадр не дошёл» раньше выглядели
                // по-разному (глиф против пустой плашки) и обе одинаково
                // для всех находок — список читался решёткой серых плиток.
                Group {
                    if let url = item.artworkURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            case .empty:
                                // Ждём картинку — показываем только тон. Монограмма во весь
                                // кадр, мигающая на каждой быстрой загрузке, читается сбоем,
                                // а не ожиданием; её место — состояние «постера не будет».
                                PlinkArtlessPoster(seed: item.title, glyph: "play.fill", showsMonogram: false)
                            default:
                                PlinkArtlessPoster(seed: item.title, glyph: "play.fill")
                            }
                        }
                    } else {
                        PlinkArtlessPoster(seed: item.title, glyph: "play.fill")
                    }
                }
                .frame(width: 80, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Cinema2026.text)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        ServiceLogoView(service: item.origin.service, size: 14)
                        Text(item.origin.service.brandName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Cinema2026.secondary)
                        if !item.subtitle.isEmpty {
                            Text("·")
                                .foregroundStyle(Cinema2026.secondary.opacity(0.6))
                            Text(item.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Cinema2026.secondary)
                                .lineLimit(1)
                        }
                        if let dur = item.duration {
                            Text("· \(dur)")
                                .font(.system(size: 12))
                                .foregroundStyle(Cinema2026.secondary)
                        }
                    }
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.title), \(item.origin.service.brandName)")
            .accessibilityHint(canCreateRoom(for: item)
                               ? "Создать комнату для совместного просмотра"
                               : "Открыть официальную страницу сервиса")

            // Отложить в «Посмотреть позже» — самостоятельная hit-area.
            Button {
                HapticManager.selection()
                watchlist.toggle(watchlistItem(item))
            } label: {
                Image(systemName: watchlist.contains(item.id) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(watchlist.contains(item.id) ? Cinema2026.accent : Cinema2026.secondary)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(watchlist.contains(item.id) ? "Убрать из списка позже" : "Посмотреть позже")

            Image(systemName: canCreateRoom(for: item) ? "person.2.fill" : "arrow.up.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Cinema2026.secondary)
                .frame(width: 22)
        }
        .padding(10)
        .background(Cinema2026.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func serviceRow(_ svc: VideoService) -> some View {
        Button {
            showRoomCreation = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: svc.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(svc.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(svc.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Cinema2026.text)
                    Text(svc.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Cinema2026.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Cinema2026.secondary)
            }
            .padding(10)
            .background(Cinema2026.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func roomRow(_ room: Room) -> some View {
        Button {
            dismiss()
            openRoom()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Cinema2026.accent)
                    .frame(width: 40, height: 40)
                    .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Cinema2026.text)
                    Text("\(room.participantCount) участников · \(room.hostName)")
                        .font(.system(size: 12))
                        .foregroundStyle(Cinema2026.secondary)
                }
                Spacer()
                if room.isActive {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Cinema2026.danger, in: Capsule())
                }
            }
            .padding(10)
            .background(Cinema2026.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
