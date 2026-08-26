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
    @State private var query = ""
    @State private var selectedChip: SearchChip = .all
    @State private var showRoomCreation = false
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

    private func videoRow(_ item: V4SearchResult) -> some View {
        Button {
            HapticManager.impact(.light)
            dismiss()
            // Create room from this video. Карточка кинотеатра (полка
            // Главной при пустом запросе) открывает страницу просмотра,
            // ролик YouTube — прежний embed.
            Task {
                let mediaItem: MediaItem
                if item.origin == .youtube {
                    let videoId = item.id
                    mediaItem = MediaItem(
                        id: "https://www.youtube.com/embed/\(videoId)",
                        title: item.title, artist: nil,
                        thumbnailURL: item.artworkURL?.absoluteString,
                        streamURL: "https://www.youtube.com/embed/\(videoId)",
                        duration: nil, mediaType: .video, source: .youtube, videoId: videoId
                    )
                } else {
                    mediaItem = watchlistItem(item)
                }
                let request = CreateRoomRequest(
                    name: item.title, maxParticipants: 4, mediaItem: mediaItem,
                    privacy: .publicRoom, password: nil,
                    hostName: AuthService.shared.currentUserValue?.username
                )
                do {
                    let api = APIClient(baseURL: PlinkConfig.apiURLString)
                    let room = try await RoomService(api: api).createRoom(request)
                    await MainActor.run {
                        HapticManager.roomJoined()
                        UIPasteboard.general.string = "Код комнаты Plink: \(room.code)"
                        NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
                    }
                } catch {}
            }
        } label: {
            HStack(spacing: 12) {
                if let url = item.artworkURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Cinema2026.surface)
                    }
                    .frame(width: 80, height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Cinema2026.surface)
                        .frame(width: 80, height: 45)
                        .overlay(
                            Image(systemName: "play.rectangle.fill")
                                .foregroundStyle(Cinema2026.accent)
                        )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Cinema2026.text)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Text(item.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Cinema2026.secondary)
                        if let dur = item.duration {
                            Text("· \(dur)")
                                .font(.system(size: 12))
                                .foregroundStyle(Cinema2026.secondary)
                        }
                    }
                }
                Spacer()
                // Отложить в «Посмотреть позже»
                Button {
                    watchlist.toggle(watchlistItem(item))
                } label: {
                    Image(systemName: watchlist.contains(item.id) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 17))
                        .foregroundStyle(watchlist.contains(item.id) ? Cinema2026.accent : Cinema2026.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Посмотреть позже")
                Image(systemName: "plus.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Cinema2026.accent)
            }
            .padding(10)
            .background(Cinema2026.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
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
