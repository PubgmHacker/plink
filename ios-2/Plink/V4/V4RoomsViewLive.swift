// Plink/V4/V4RoomsViewLive.swift
// Пересобрано 02.08.2026 под новый макет вкладки «Комнаты»:
// два крупных действия сверху, лента «Друзья в эфире», карточка текущей сессии,
// один блок «Все комнаты» с сегментами «Открытые / Мои / По коду» и списком
// широких карточек вместо сетки 2×2.

import SwiftUI
import UIKit
import Foundation

enum V4RoomsSegment: String, CaseIterable, Identifiable {
    case open
    case mine
    case byCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: return "Открытые"
        case .mine: return "Мои"
        case .byCode: return "По коду"
        }
    }
}

struct V4RoomsViewLive: View {
    let theme: V4Theme
    var roomsStore: V4RoomsStore?
    let openRoom: (Room) -> Void
    let createRoom: () -> Void
    let joinByCode: () -> Void

    @State private var searchQuery = ""
    @State private var searchExpanded = false
    @State private var segment: V4RoomsSegment = .open
    @Namespace private var segmentNamespace

    private var currentUserID: String? {
        AuthService.shared.currentUserValue?.id
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if searchExpanded {
                    searchField
                }

                actionTiles
                    .padding(.horizontal, 18)
                    .padding(.bottom, 22)

                content
            }
            .padding(.bottom, 96)
        }
        .foregroundStyle(V4.ink)
        .refreshable { await roomsStore?.load() }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            V4Heading(eyebrow: "ВМЕСТЕ СЕЙЧАС", title: "Комнаты")
                .accessibilityIdentifier("screen.rooms")
            Spacer()
            Button {
                HapticManager.selection()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    searchExpanded.toggle()
                    if !searchExpanded { searchQuery = "" }
                }
            } label: {
                V4GlyphIcon(glyph: searchExpanded ? .close : .search, size: 15, weight: .regular)
                    .foregroundStyle(V4.ink)
                    .frame(width: 44, height: 44)
                    .background(V4.roundBG, in: Circle())
                    .overlay(Circle().stroke(V4.line))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(searchExpanded ? "Закрыть поиск" : "Найти комнату")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.accentColor)
                .font(.system(size: 14, weight: .semibold))
            TextField("Название комнаты или владелец", text: $searchQuery)
                .foregroundStyle(V4.ink)
                .font(.system(size: 14, weight: .medium))
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(V4.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(minHeight: 50)
        .background(V4.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.accentColor.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Два крупных действия

    private var actionTiles: some View {
        HStack(spacing: 11) {
            actionTile(
                icon: "plus",
                title: "Создать комнату",
                subtitle: "Выбрать фильм и позвать друзей",
                accent: true
            ) {
                HapticManager.impact(.medium)
                createRoom()
            }
            actionTile(
                icon: "keyboard",
                title: "Войти по коду",
                subtitle: "6 символов от друга",
                accent: false
            ) {
                HapticManager.selection()
                segment = .byCode
                joinByCode()
            }
        }
    }

    private func actionTile(
        icon: String,
        title: String,
        subtitle: String,
        accent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(accent ? theme.buttonTextColor : V4.ink)
                    .frame(width: 34, height: 34)
                    .background(
                        accent ? AnyShapeStyle(theme.buttonTextColor.opacity(0.18))
                               : AnyShapeStyle(V4.raised),
                        in: Circle()
                    )
                Text(title)
                    .font(.system(size: 14.5, weight: .heavy))
                    .foregroundStyle(accent ? theme.buttonTextColor : V4.ink)
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent ? theme.buttonTextColor.opacity(0.72) : V4.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                accent ? AnyShapeStyle(theme.accentColor) : AnyShapeStyle(V4.surface),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(accent ? Color.clear : V4.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: - Контент

    @ViewBuilder
    private var content: some View {
        if let rs = roomsStore {
            switch rs.state {
            case .loading:
                RoundedRectangle(cornerRadius: 29)
                    .fill(V4.cardBG)
                    .frame(height: 235)
                    .padding(.horizontal, 18)
                    .overlay { ProgressView().tint(theme.accentColor) }
            case .loaded:
                loadedContent(rs)
            case .empty:
                emptyState
            case .failed(let error):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(V4.amber)
                    Text(error).font(.subheadline).foregroundStyle(V4.muted)
                    Button("Повторить") { Task { await roomsStore?.load() } }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accentColor)
                        .foregroundStyle(theme.buttonTextColor)
                        .frame(minHeight: 44)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
            case .idle:
                Color.clear.frame(height: 100)
            }
        } else {
            ProgressView()
                .tint(theme.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        }
    }

    @ViewBuilder
    private func loadedContent(_ rs: V4RoomsStore) -> some View {
        let all = filtered(rs.rooms)
        let hero: Room? = searchQuery.isEmpty ? (rs.heroRoom ?? all.first) : all.first
        let live = liveFriends(rs.rooms)

        if all.isEmpty && searchQuery.isEmpty {
            emptyState
        } else if all.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(V4.muted)
                Text("Ничего не найдено").font(.headline)
                Text("Проверь название комнаты или имя владельца")
                    .font(.subheadline)
                    .foregroundStyle(V4.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
        } else {
            if !live.isEmpty {
                sectionTitle("Друзья в эфире")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 13) {
                        ForEach(live, id: \.person.id) { entry in
                            liveFriendBubble(entry)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 2)
                }
                .padding(.bottom, 20)
            }

            if let hero {
                roomFeatureCard(hero)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
            }

            sectionTitle("Все комнаты")
            segmentControl
                .padding(.horizontal, 18)
                .padding(.bottom, 14)

            switch segment {
            case .open:
                roomList(all.filter { $0.privacy == .publicRoom || $0.privacy == .friendsRoom })
            case .mine:
                roomList(all.filter { room in
                    guard let uid = currentUserID else { return false }
                    return room.isHost(userId: uid)
                })
            case .byCode:
                byCodePanel(all)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "popcorn.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(theme.accentColor)
            Text("Пока никто не смотрит").font(.headline)
            Text("Создай комнату и позови друзей или войди по коду")
                .font(.subheadline)
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.vertical, 46)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .black))
            .tracking(-0.35)
            .foregroundStyle(V4.ink)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
    }

    // MARK: - Сегменты

    private var segmentControl: some View {
        HStack(spacing: 4) {
            ForEach(V4RoomsSegment.allCases) { item in
                let isOn = item == segment
                Button {
                    HapticManager.selection()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        segment = item
                    }
                } label: {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .heavy))
                        .foregroundStyle(isOn ? theme.buttonTextColor : V4.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if isOn {
                                Capsule()
                                    .fill(theme.accentColor)
                                    .matchedGeometryEffect(id: "selected-rooms-segment", in: segmentNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(V4.raised, in: Capsule())
        .overlay(Capsule().stroke(V4.line, lineWidth: 1))
    }

    // MARK: - Список комнат

    @ViewBuilder
    private func roomList(_ rooms: [Room]) -> some View {
        if rooms.isEmpty {
            Text(segment == .mine
                 ? "У вас нет своих комнат. Создайте первую — она появится здесь."
                 : "Открытых комнат сейчас нет.")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(V4.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
        } else {
            VStack(spacing: 10) {
                ForEach(rooms) { room in
                    roomRow(room)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func roomRow(_ room: Room) -> some View {
        Button {
            HapticManager.impact(.light)
            openRoom(room)
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .topLeading) {
                    roomArtwork(room)
                        .frame(width: 72, height: 72)
                        .clipped()
                    if room.isLocked {
                        ZStack {
                            Color.black.opacity(0.45)
                            V4GlyphIcon(glyph: .lock, size: 18, filled: true, weight: .regular)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    } else if room.isActive {
                        Text("LIVE")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(V4.danger, in: Capsule())
                            .padding(6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(room.name)
                        .font(.system(size: 13.5, weight: .heavy))
                        .foregroundStyle(V4.ink)
                        .lineLimit(1)
                    Text(subtitle(for: room))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(V4.muted)
                        .lineLimit(1)
                    HStack(spacing: 9) {
                        facesStack(room.participants)
                        Text("\(room.participantCount)/\(room.maxParticipants)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(V4.muted)
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: room.isFull ? "person.slash" : "arrow.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(room.isFull ? V4.muted : theme.buttonTextColor)
                    .frame(width: 34, height: 34)
                    .background(
                        room.isFull ? AnyShapeStyle(V4.raised) : AnyShapeStyle(theme.accentColor),
                        in: Circle()
                    )
            }
            .padding(10)
            .background(V4.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(V4.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Комната \(room.name), \(room.participantCount) участников")
    }

    private func subtitle(for room: Room) -> String {
        if let title = room.mediaItem?.title, !title.isEmpty {
            return "Сейчас: \(title)"
        }
        return "\(room.hostName) ещё выбирает фильм"
    }

    // MARK: - По коду

    private func byCodePanel(_ rooms: [Room]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                HapticManager.impact(.medium)
                joinByCode()
            } label: {
                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(V4.raised)
                            .frame(height: 46)
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(index == 0 ? theme.accentColor : V4.line, lineWidth: 1)
                            )
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ввести код комнаты")

            Text("Код из шести символов даёт хост. Приватные комнаты не видны в списке — только по коду.")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(V4.muted)
                .fixedSize(horizontal: false, vertical: true)

            let locked = rooms.filter { $0.privacy == .privateRoom || $0.privacy == .byLink || $0.isLocked }
            if !locked.isEmpty {
                Text("ВЫ УЖЕ ЗАХОДИЛИ")
                    .font(.system(size: 9.5, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(V4.muted)
                VStack(spacing: 10) {
                    ForEach(locked) { room in
                        roomRow(room)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Друзья в эфире

    private struct LiveFriendEntry {
        let person: UserPreview
        let room: Room
    }

    private func liveFriends(_ rooms: [Room]) -> [LiveFriendEntry] {
        var seen = Set<String>()
        var result: [LiveFriendEntry] = []
        for room in rooms where room.isActive {
            for person in room.participants where !seen.contains(person.id) {
                seen.insert(person.id)
                result.append(LiveFriendEntry(person: person, room: room))
            }
        }
        return result
    }

    private func liveFriendBubble(_ entry: LiveFriendEntry) -> some View {
        Button {
            HapticManager.impact(.light)
            openRoom(entry.room)
        } label: {
            VStack(spacing: 7) {
                avatarCircle(entry.person, size: 54)
                    .padding(3)
                    .overlay(
                        Circle().stroke(
                            AngularGradient(
                                colors: [theme.accentColor, V4.danger, theme.accentColor],
                                center: .center
                            ),
                            lineWidth: 2
                        )
                    )
                Text(entry.person.username)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(V4.muted)
                    .lineLimit(1)
                    .frame(width: 62)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.person.username) смотрит в комнате \(entry.room.name)")
    }

    private func facesStack(_ people: [UserPreview]) -> some View {
        HStack(spacing: -7) {
            ForEach(people.prefix(4), id: \.id) { person in
                avatarCircle(person, size: 20)
                    .overlay(Circle().stroke(V4.surface, lineWidth: 1.5))
            }
        }
    }

    @ViewBuilder
    private func avatarCircle(_ person: UserPreview, size: CGFloat) -> some View {
        let initial = String(person.username.prefix(1)).uppercased()
        let hue = Double(abs(person.id.hashValue) % 300)
        ZStack {
            Circle().fill(Color.oklch(0.42, 0.14, hue))
            if let raw = person.avatarURL, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Text(initial)
                            .font(.system(size: size * 0.42, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(Circle())
            } else {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .black))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    // MARK: - Карточка текущей сессии

    private func roomFeatureCard(_ room: Room) -> some View {
        Button {
            HapticManager.impact(.medium)
            openRoom(room)
        } label: {
            ZStack(alignment: .bottomLeading) {
                roomArtwork(room)
                    .frame(maxWidth: .infinity)
                    .frame(height: 268)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.22), .black.opacity(0.94)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        if room.isActive {
                            HStack(spacing: 6) {
                                Circle().fill(.white).frame(width: 5, height: 5)
                                Text("LIVE")
                            }
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(V4.danger, in: Capsule())
                        }
                        Text("\(room.participantCount) смотрят")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .plinkGlass(.control, in: Capsule(style: .continuous))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(theme.buttonTextColor)
                            .frame(width: 40, height: 40)
                            .background(theme.accentColor, in: Circle())
                    }

                    Spacer(minLength: 24)

                    Text(room.mediaItem?.title ?? room.name)
                        .font(.system(size: 25, weight: .black))
                        .tracking(-0.55)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: 9) {
                        facesStack(room.participants)
                        Text("\(room.name) · \(room.hostName)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.74))
                            .lineLimit(1)
                    }
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [theme.accentColor.opacity(0.34), .white.opacity(0.10), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.42), radius: 28, y: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Обложки

    private func filtered(_ rooms: [Room]) -> [Room] {
        guard !searchQuery.isEmpty else { return rooms }
        return rooms.filter { room in
            room.name.localizedCaseInsensitiveContains(searchQuery) ||
            room.hostName.localizedCaseInsensitiveContains(searchQuery) ||
            (room.mediaItem?.title.localizedCaseInsensitiveContains(searchQuery) ?? false)
        }
    }

    @ViewBuilder
    private func roomArtwork(_ room: Room) -> some View {
        if let raw = room.mediaItem?.thumbnailURL, let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                default: roomArtworkFallback(room)
                }
            }
        } else {
            roomArtworkFallback(room)
        }
    }

    private func roomArtworkFallback(_ room: Room) -> some View {
        let seed = abs(room.id.hashValue)
        let hue = Double(seed % 70) + 225
        return ZStack {
            LinearGradient(
                colors: [
                    Color.oklch(0.58, 0.22, hue),
                    Color.oklch(0.26, 0.14, hue + 35),
                    Color.oklch(0.07, 0.03, 250)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.11))
                .frame(width: 190, height: 190)
                .blur(radius: 10)
                .offset(x: 110, y: -64)
        }
    }
}
