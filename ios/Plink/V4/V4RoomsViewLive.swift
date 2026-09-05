// Plink/V4/V4RoomsViewLive.swift
// Пересобрано 02.08.2026 под новый макет вкладки «Комнаты»:
// два крупных действия сверху, лента «Друзья в эфире», карточка текущей сессии,
// один блок «Все комнаты» с сегментами «Открытые / Мои / По коду» и списком
// широких карточек вместо сетки 2×2.
//
// 25.08.2026. Вкладка забрала историю «с кем и что смотрели» из хаба
// «Вместе»: прошлые просмотры — это про кино, а не про людей, и им место
// рядом с живыми комнатами.
//
// 26.08.2026. Имя вкладки вернулось к «Комнатам»: «Вечера» обещали вечер,
// а смотрят в любое время дня — и «комната» это то самое слово, которым
// зовёт кнопка, код приглашения и пуш.

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
    // Друзья нужны истории: «с кем смотрели» собирается сопоставлением
    // участников прошлых комнат со списком друзей.
    var friendsStore: V4FriendsStore? = nil
    let openRoom: (Room) -> Void
    let createRoom: () -> Void
    let joinByCode: () -> Void

    @State private var searchQuery = ""
    @State private var searchExpanded = false
    @State private var segment: V4RoomsSegment = .open
    @Namespace private var segmentNamespace

    // История «с кем и что смотрели» — только завершённые вечера:
    // живые комнаты уже стоят в основном списке вкладки.
    @State private var recentRooms: [Room] = []

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

                recentBlock
            }
            .padding(.bottom, 96)
        }
        .foregroundStyle(V4.ink)
        .refreshable {
            await roomsStore?.load()
            await loadRecentRooms()
        }
        // Вкладка смонтирована всегда (ZStack с opacity в корне),
        // так что .task срабатывает один раз на старте; свежесть дальше
        // держат refreshable и уведомление об изменении комнат.
        .task { await loadRecentRooms() }
        .onReceive(NotificationCenter.default.publisher(for: .plinkRoomsDidChange)) { _ in
            Task { await loadRecentRooms() }
        }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            V4Heading(eyebrow: "КИНО ВМЕСТЕ", title: "Комнаты")
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
        // Единый «вдох» шапок от статус-бара (см. topBar Главной).
        .padding(.top, 18)
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

    // Пара равных по весу карточек. Раньше левая была сплошной ярко-синей
    // плитой (растянутый btn-primary), а правая почти сливалась с фоном —
    // пара читалась как «кричащая + мёртвая». Теперь обе на одном каркасе:
    // акцентная — заливка с бликом и мягким свечением, вторая — живое стекло
    // поверх фона; чипы иконок одного размера, высоты выровнены, текст
    // прижат к низу, чтобы базовые линии пары совпадали.
    private var actionTiles: some View {
        HStack(spacing: 12) {
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
                icon: "number",
                title: "Войти по коду",
                subtitle: "6 символов от друга",
                accent: false
            ) {
                HapticManager.selection()
                segment = .byCode
                joinByCode()
            }
        }
        // Обе плитки тянутся до высоты соседа — без жёстких констант.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func actionTile(
        icon: String,
        title: String,
        subtitle: String,
        accent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let content = VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(accent ? theme.buttonTextColor : theme.accentColor)
                .frame(width: 36, height: 36)
                .background(
                    accent ? AnyShapeStyle(theme.buttonTextColor.opacity(0.16))
                           : AnyShapeStyle(theme.accentColor.opacity(0.14)),
                    in: Circle()
                )
                .overlay(
                    Circle().stroke(
                        accent ? theme.buttonTextColor.opacity(0.24)
                               : theme.accentColor.opacity(0.22),
                        lineWidth: 1
                    )
                )

            Spacer(minLength: 6)

            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(accent ? theme.buttonTextColor : V4.ink)
            Text(subtitle)
                .font(.system(size: 11.5, weight: .semibold))
                .lineSpacing(2)
                .foregroundStyle(accent ? theme.buttonTextColor.opacity(0.76) : V4.muted)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)

        return Button(action: action) {
            Group {
                if accent {
                    content
                        .background {
                            ZStack {
                                shape.fill(theme.accentColor)
                                // Блик сверху + затемнение к низу: объём вместо
                                // плоской заливки, тем же приёмом, что кнопки
                                // PlinkProminentButtonStyle.
                                shape.fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.20), .clear, .black.opacity(0.16)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            }
                        }
                        .overlay(
                            shape.stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.32), .white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                        )
                        .shadow(color: theme.accentColor.opacity(0.30), radius: 16, y: 8)
                } else {
                    // Стекло приносит свой кант и тень — дополнительных не надо.
                    content.plinkGlass(.control, in: shape)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    // MARK: - Контент

    @ViewBuilder
    private var content: some View {
        if let rs = roomsStore {
            switch rs.state {
            case .loading:
                roomsSkeleton
            case .loaded:
                loadedContent(rs)
            case .empty:
                emptyState
            case .failed(let error):
                // Раньше: голый жёлтый треугольник, серая строка и системный
                // .borderedProminent посреди пустого экрана — читалось как
                // алерт из туториала. Теперь ошибка — собранная карточка в
                // языке приложения, с понятным следующим шагом.
                stateCard(
                    icon: "wifi.exclamationmark",
                    iconTint: V4.amber,
                    title: error,
                    message: "Проверьте соединение — и попробуем ещё раз.",
                    buttonTitle: "Повторить"
                ) {
                    Task { await roomsStore?.load() }
                }
            case .idle:
                // idle — миг до старта загрузки (bootstrap запускает её сразу
                // после создания стора); прозрачная дыра на этом кадре
                // выглядела как сломанный экран — показываем тот же скелет.
                roomsSkeleton
            }
        } else {
            roomsSkeleton
        }
    }

    /// Скелет реального макета (герой + два ряда) с мягкой пульсацией —
    /// вместо пустого прямоугольника со спиннером, который выглядел дырой.
    private var roomsSkeleton: some View {
        VStack(spacing: 12) {
            ghost(height: 208, radius: 30)
            ghost(height: 92, radius: 20)
            ghost(height: 92, radius: 20)
        }
        .padding(.horizontal, 18)
        .modifier(V4RoomsGhostPulse())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Загружаем комнаты")
    }

    private func ghost(height: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(V4.cardBG)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(V4.line, lineWidth: 1)
            )
            .frame(height: height)
    }

    /// Единый каркас пустых и ошибочных состояний: иконка в мягком круге,
    /// заголовок, одна строка объяснения и кнопка следующего шага — стиль
    /// кнопки общий с остальным приложением (PlinkProminentButtonStyle).
    private func stateCard(
        icon: String,
        iconTint: Color,
        title: String,
        message: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(iconTint.opacity(0.13))
                Circle().stroke(iconTint.opacity(0.22), lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            .frame(width: 58, height: 58)
            .padding(.bottom, 14)

            Text(title)
                .font(.system(size: 16.5, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(V4.ink)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)

            Text(message)
                .font(.system(size: 12.5, weight: .semibold))
                .lineSpacing(2)
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)

            Button(buttonTitle) {
                HapticManager.impact(.light)
                action()
            }
            .buttonStyle(
                PlinkProminentButtonStyle(
                    tint: theme.accentColor,
                    textColor: theme.buttonTextColor,
                    height: 46,
                    cornerRadius: 23,
                    fillsWidth: false
                )
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
        .background(V4.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(V4.line, lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    @ViewBuilder
    private func loadedContent(_ rs: V4RoomsStore) -> some View {
        let all = filtered(rs.rooms)
        let hero: Room? = searchQuery.isEmpty ? (rs.heroRoom ?? all.first) : all.first
        let live = liveFriends(rs.rooms)

        if all.isEmpty && searchQuery.isEmpty {
            emptyState
        } else if all.isEmpty {
            // Пустой поиск — транзитное состояние, без сцены с проектором:
            // луч зарезервирован за «в мире пусто», здесь достаточно типографики.
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(V4.muted)
                Text("Ничего не найдено")
                    .font(.system(size: 17, weight: .heavy))
                    .tracking(-0.3)
                    .foregroundStyle(V4.ink)
                Text("Проверьте название комнаты или имя владельца")
                    .font(.system(size: 13))
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

    // Пустой экран приглашает к действию: сцена с лучом проектора (общий
    // язык пустых состояний V4EmptyState) и кнопка «Создать комнату» прямо
    // в состоянии — не заставляем взгляд возвращаться к плиткам наверху.
    // stateCard с кружком остаётся языком ошибок — у пустоты и сбоя
    // намеренно разные знаки.
    private var emptyState: some View {
        V4EmptyState(
            icon: "popcorn.fill",
            title: "Пока никто не смотрит",
            subtitle: "Создайте комнату и позовите друзей — или войдите по коду из шести символов.",
            accent: theme.accentColor,
            accentInk: theme.buttonTextColor,
            primary: .init(title: "Создать комнату", icon: "plus",
                           a11yID: "rooms.emptyCreate", run: createRoom)
        )
        .padding(.vertical, 30)
        .padding(.horizontal, 16)
        .background(V4.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(V4.line, lineWidth: 1)
        )
        .padding(.horizontal, 18)
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
                        // minHeight, а не height: при Dynamic Type XXL текст
                        // сегмента переставал влезать в 38 pt и обрезался.
                        .frame(minHeight: 38)
                        .padding(.vertical, 2)
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
                            .frame(minHeight: 16)
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
                // roomArtwork отдаёт .aspectRatio(contentMode: .fill). Чтобы закрыть
                // рамку высотой 268 pt, кадр 16:9 сообщает наверх ширину ~476 pt —
                // это шире экрана. .frame(maxWidth: .infinity) здесь не помогает:
                // он задаёт нижнюю границу ширины, а не верхнюю. .clipped() тоже не
                // спасал — он обрезает отрисовку по уже раздутым границам, а не сам
                // размер. Поэтому вкладка «Комнаты» ехала по горизонтали.
                //
                // Теперь размер задаёт Color.clear, а картинка живёт в overlay:
                // overlay никогда не влияет на размер родителя, поэтому лишнее по
                // бокам честно обрезается. В roomRow обложка уже стоит в жёстком
                // .frame(width: 72, height: 72) — там этой проблемы не было.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 268)
                    .overlay { roomArtwork(room) }
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
                            .frame(minHeight: 28)
                            .background(V4.danger, in: Capsule())
                        }
                        Text("\(room.participantCount) смотрят")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 28)
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

    // MARK: - Прошлые вечера (история из хаба «Вместе», 25.08.2026)

    // Пустая история молчит: у вкладки уже есть плитка «Создать комнату»
    // и пустое состояние списка — третий призыв к действию был бы шумом.
    // Секция появляется вместе с первым завершённым вечером.
    @ViewBuilder
    private var recentBlock: some View {
        if !recentRooms.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("Что смотрели")
                    .padding(.top, 26)

                Text(LocalizationManager.shared.string(.frHistorySub))
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineSpacing(2)
                    .foregroundStyle(V4.muted)
                    .padding(.horizontal, 18)
                    .padding(.top, -6)
                    .padding(.bottom, 12)

                VStack(spacing: 0) {
                    ForEach(Array(recentRooms.enumerated()), id: \.element.id) { index, room in
                        recentRoomRow(room)
                        if index < recentRooms.count - 1 {
                            Rectangle()
                                .fill(V4.line.opacity(0.45))
                                .frame(height: 0.5)
                                .padding(.leading, 86)
                        }
                    }
                }
                .background(V4.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(V4.line, lineWidth: 1)
                )
                .padding(.horizontal, 18)
            }
        }
    }

    private func recentRoomRow(_ room: Room) -> some View {
        let mediaTitle = room.mediaItem?.title ?? room.name
        let withFriends = coWatchFriends(in: room)
        let othersCount = max(0, room.participantCount - 1)

        return Button {
            HapticManager.impact(.light)
            openRoom(room)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    roomArtwork(room)
                        .frame(width: 60, height: 60)
                        .clipped()
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(V4.line.opacity(0.6), lineWidth: 0.8)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(mediaTitle)
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(-0.2)
                        .foregroundStyle(V4.ink)
                        .lineLimit(1)

                    if !withFriends.isEmpty {
                        HStack(spacing: 6) {
                            overlappingFriendAvatars(withFriends)
                            Text(withFriendsLine(withFriends, others: othersCount))
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(V4.muted)
                                .lineLimit(1)
                        }
                    } else if othersCount > 0 {
                        Text("\(othersCount) участник(ов) · код \(room.code)")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(V4.muted)
                            .lineLimit(1)
                    } else {
                        Text("Только вы · код \(room.code)")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(V4.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(V4.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Смотрели: \(mediaTitle)")
    }

    /// Друзья, бывшие в комнате, — сверка участников со списком друзей.
    private func coWatchFriends(in room: Room) -> [Friend] {
        let friends = friendsStore?.friends ?? []
        guard !friends.isEmpty else { return [] }
        let me = currentUserID ?? UserDefaults.standard.string(forKey: "plink_current_user_id") ?? ""
        var result: [Friend] = []
        for p in room.participants where p.id != me {
            if let f = friends.first(where: { $0.id == p.id }) {
                result.append(f)
            }
        }
        if room.hostID != me,
           !result.contains(where: { $0.id == room.hostID }),
           let f = friends.first(where: { $0.id == room.hostID }) {
            result.insert(f, at: 0)
        }
        return result
    }

    private func withFriendsLine(_ friends: [Friend], others: Int) -> String {
        let names = friends.prefix(2).map(\.displayTitle)
        var s = "с " + names.joined(separator: ", ")
        let extra = friends.count - names.count
        if extra > 0 {
            s += " +\(extra)"
        } else if others > friends.count {
            s += " · ещё \(others - friends.count)"
        }
        return s
    }

    private func overlappingFriendAvatars(_ friends: [Friend]) -> some View {
        HStack(spacing: -8) {
            ForEach(Array(friends.prefix(3).enumerated()), id: \.element.id) { idx, f in
                avatarCircle(f.asUserPreview, size: 22)
                    .overlay(Circle().stroke(V4.surface.opacity(0.9), lineWidth: 1.5))
                    .zIndex(Double(3 - idx))
            }
        }
    }

    private func loadRecentRooms() async {
        let svc = RoomService(api: APIClient.shared)
        guard let history = try? await svc.fetchMyRoomHistory() else { return }
        var seen = Set<String>()
        var merged: [Room] = []
        for r in history where !r.isActive && !seen.contains(r.id) {
            seen.insert(r.id)
            merged.append(r)
        }
        recentRooms = Array(merged.prefix(12))
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

/// Пульс скелета загрузки: 0.55 ↔ 1.0. При включённом Reduce Motion
/// анимации нет — скелет стоит на постоянных 0.8.
private struct V4RoomsGhostPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 0.8 : (dim ? 0.55 : 1))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: dim
            )
            .onAppear { if !reduceMotion { dim = true } }
    }
}
