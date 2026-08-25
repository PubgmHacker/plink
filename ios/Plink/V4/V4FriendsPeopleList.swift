// Plink/V4/V4FriendsPeopleList.swift
//
// 03.08.2026. V4FriendsView.swift разросся до 2007 строк: один тип держал
// три сегмента, строки чатов, строки людей, недавние комнаты и два шита.
// Разрезано на extension'ы — блоки опираются на приватные члены
// V4FriendsViewLive, поэтому вынести их в отдельные типы нельзя без
// протаскивания десятка зависимостей через инициализатор.
//
// 25.08.2026. Карточная сетка 2×N заменена мессенджер-строками (модель
// ТГ/ВК): сетка не масштабировалась дальше пары десятков друзей и дублировала
// кнопки «чат/кино» в каждой карточке. Теперь: чипы «Все / В сети / Заявки»
// вместо отдельной карусели онлайна, строка = аватар + имя + статус + чат,
// поиск появляется от 12 друзей, алфавитные секции — от 50.

import SwiftUI
import PhotosUI
import UIKit
import Foundation

/// Фильтр списка друзей (чипы над списком).
enum FriendsPeopleFilter {
    case all
    case online
}

extension V4FriendsViewLive {
    // MARK: - Друзья (people only — no chat previews)

    @ViewBuilder
    /// Карточка «друг смотрит» с кнопкой присоединения.
    private func friendWatchingCard(_ friend: Friend, _ room: Room) -> some View {
        Button {
            HapticManager.impact(.medium)
            NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
        } label: {
            HStack(spacing: 12) {
                V4Avatar(letter: String(friend.displayTitle.prefix(1)).uppercased(), seed: friend.id, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(friend.displayTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(V4.ink)
                        .lineLimit(1)
                    Text("смотрит «\(room.name)»")
                        .font(.system(size: 12))
                        .foregroundStyle(V4.muted)
                        .lineLimit(1)
                }
                Spacer()
                Text(LocalizationManager.shared.string(.frJoin))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(Capsule().stroke(theme.accentColor.opacity(0.6), lineWidth: 1))
            }
            .padding(12)
            .background(V4.cardBG.opacity(0.55))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    var friendsPeopleBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            // «Друг сейчас смотрит — присоединиться»
            if !friendsWatchingNow.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(
                        title: LocalizationManager.shared.string(.frWatchingNow),
                        icon: "play.tv.fill",
                        count: friendsWatchingNow.count,
                        actionTitle: nil,
                        action: nil
                    )
                    VStack(spacing: 8) {
                        ForEach(friendsWatchingNow, id: \.room.id) { pair in
                            friendWatchingCard(pair.friend, pair.room)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                // Без текстового «Добавить»: вход один — «+» в шапке хаба,
                // дубль в заголовке секции путал и выглядел старомодно.
                sectionHeader(
                    title: LocalizationManager.shared.string(.frAllFriends),
                    icon: "person.2.fill",
                    count: store?.friends.count,
                    actionTitle: nil,
                    action: nil
                )

                if let s = store {
                    switch s.state {
                    // idle — миг до старта загрузки (bootstrap запускает её
                    // сразу после создания стора); раньше idle рисовал
                    // прозрачную заглушку, и заголовок висел над пустотой.
                    case .loading, .idle:
                        sectionCard {
                            ProgressView().tint(theme.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 36)
                                .accessibilityLabel("Загрузка друзей")
                        }
                    case .failed:
                        // Сырой текст ошибки (NSURLErrorDomain и т.п.) наружу
                        // не выходит — офлайн-состояние говорит человеческим
                        // языком и даёт одно действие.
                        sectionCard {
                            emptyInside(
                                icon: "wifi.exclamationmark",
                                title: "Друзья не загрузились",
                                subtitle: "Похоже, нет соединения. Проверь интернет — и попробуй ещё раз.",
                                ctaIcon: "arrow.clockwise",
                                cta: "Повторить",
                                style: .plain
                            ) { Task { await store?.load() } }
                        }
                    case .loaded, .empty:
                        if s.friends.isEmpty {
                            // Формула из референсов инвайт-экранов: медальон →
                            // заголовок → выгода → «Найти друга» + второй канал
                            // «Пригласить по ссылке» тем же парным рядом кнопок,
                            // что и на лице профиля.
                            sectionCard {
                                V4EmptyState(
                                    icon: "person.2.fill",
                                    title: LocalizationManager.shared.string(.frEmptyTitle),
                                    subtitle: LocalizationManager.shared.string(.frEmptySub),
                                    accent: theme.accentColor,
                                    accentInk: theme.buttonTextColor,
                                    // Мир людей — своя сцена-орбита, луч
                                    // проектора остаётся кино-экранам.
                                    style: .orbit,
                                    primary: .init(
                                        title: LocalizationManager.shared.string(.frFind),
                                        icon: "magnifyingglass",
                                        a11yID: "friends.emptyFind"
                                    ) { showAddFriend = true }
                                ) {
                                    // Инвайт-ссылка — по нику (так же, как
                                    // «Поделиться» на профиле); id в /u/ не вёл
                                    // на публичную страницу.
                                    if let me = AuthService.shared.currentUserValue,
                                       let inviteURL = PlinkURLs.profileLink(
                                        me.username.isEmpty ? me.id : me.username
                                       ) {
                                        ShareLink(item: inviteURL) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "square.and.arrow.up")
                                                    .font(.system(size: 13, weight: .bold))
                                                Text(LocalizationManager.shared.string(.frInviteLink))
                                                    .font(.system(size: 14, weight: .semibold))
                                            }
                                            .padding(.horizontal, 18)
                                        }
                                        // Без tint: на нативном стекле tint
                                        // красит кнопку почти в заливку, и
                                        // вторичный канал спорил с primary.
                                        // Геометрия — один в один с primary
                                        // (высота 48, радиус 16): разнокали-
                                        // берные кнопки читались криво.
                                        // Полоса до 300 pt — та же, что у
                                        // primary в V4EmptyState: по-контентная
                                        // ширина делала вторичную кнопку шире
                                        // главной, иерархия переворачивалась.
                                        .buttonStyle(PlinkGlassButtonStyle(
                                            tint: nil,
                                            height: 48, cornerRadius: 16, fillsWidth: true
                                        ))
                                        .frame(maxWidth: 300)
                                        .padding(.top, 10)
                                    }
                                }
                                .padding(.vertical, 30)
                                .padding(.horizontal, 12)
                            }
                        } else {
                            friendsPeopleList
                        }
                    }
                } else {
                    sectionCard {
                        ProgressView().tint(theme.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                    }
                }
            }
        }
    }

    // MARK: - Список людей: чипы → поиск → строки

    /// Кто из друзей прямо сейчас хостит комнату — для статуса в строке.
    private var watchingRoomByFriendId: [String: Room] {
        var map: [String: Room] = [:]
        for pair in friendsWatchingNow { map[pair.friend.id] = pair.room }
        return map
    }

    /// Список после чипа и поиска.
    private var filteredPeople: [Friend] {
        var list = friendsFilter == .online ? onlineFriends : peopleFriends
        let q = friendsQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.displayTitle.lowercased().contains(q) || $0.username.lowercased().contains(q)
            }
        }
        return list
    }

    private var friendsPeopleList: some View {
        let list = filteredPeople
        return VStack(alignment: .leading, spacing: 12) {
            peopleFilterChips

            // Поиск не нужен, пока друзей мало — до дюжины список читается глазами.
            if peopleFriends.count >= 12 {
                peopleSearchField
                    .padding(.horizontal, 16)
            }

            if list.isEmpty {
                sectionCard {
                    if !friendsQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        emptyInside(
                            icon: "magnifyingglass",
                            title: "Никого не нашли",
                            subtitle: "Проверь написание или поищи по нику.",
                            style: .plain
                        )
                    } else {
                        emptyInside(
                            icon: "moon.zzz.fill",
                            title: "Сейчас никого нет в сети",
                            subtitle: "Загляни позже — или напиши первым, сообщение дождётся.",
                            style: .plain
                        )
                    }
                }
            } else if list.count >= 50 {
                // На большом списке — алфавитные секции: скроллом по 100+
                // строкам без ориентиров не пользуются.
                ForEach(letterGroups(from: list), id: \.letter) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.letter)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(V4.muted)
                            .padding(.horizontal, 24)
                        sectionCard {
                            ForEach(group.friends) { friend in
                                friendPersonRow(friend, showsDivider: friend.id != group.friends.last?.id)
                            }
                        }
                    }
                }
            } else {
                sectionCard {
                    ForEach(list) { friend in
                        friendPersonRow(friend, showsDivider: friend.id != list.last?.id)
                    }
                }
            }
        }
    }

    private var peopleFilterChips: some View {
        let requests = store?.requests.count ?? 0
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                peopleChip(
                    title: "Все",
                    count: peopleFriends.count,
                    isOn: friendsFilter == .all
                ) { friendsFilter = .all }

                peopleChip(
                    title: "В сети",
                    count: onlineFriends.count,
                    isOn: friendsFilter == .online,
                    dot: true
                ) { friendsFilter = .online }

                // «Заявки» — не фильтр, а вход в тот же шит, что и трей в
                // шапке; чип появляется только когда есть что разобрать.
                if requests > 0 {
                    Button {
                        HapticManager.impact(.light)
                        showRequests = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.clock.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Заявки")
                                .font(.system(size: 13.5, weight: .semibold))
                            Text("\(requests)")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(theme.buttonTextColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(theme.accentColor, in: Capsule())
                        }
                        .foregroundStyle(theme.accentColor)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .overlay(Capsule().stroke(theme.accentColor.opacity(0.45), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Заявки, \(requests)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    private func peopleChip(
        title: String,
        count: Int,
        isOn: Bool,
        dot: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { action() }
        } label: {
            HStack(spacing: 6) {
                if dot {
                    Circle()
                        .fill(Color(red: 0.3, green: 0.9, blue: 0.55))
                        .frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(isOn ? theme.buttonTextColor : V4.ink)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background {
                if isOn {
                    Capsule().fill(theme.accentColor)
                } else {
                    Capsule().fill(V4.raised.opacity(0.6))
                        .overlay(Capsule().stroke(V4.line.opacity(0.6), lineWidth: 0.8))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var peopleSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(V4.muted)
            TextField("Поиск по друзьям", text: $friendsQuery)
                .font(.system(size: 15))
                .foregroundStyle(V4.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !friendsQuery.isEmpty {
                Button {
                    friendsQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(V4.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .plinkGlass(.control, in: Capsule())
    }

    /// Алфавитные группы для больших списков (≥50 строк на экране).
    private func letterGroups(from list: [Friend]) -> [(letter: String, friends: [Friend])] {
        let sorted = list.sorted {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
        var groups: [(letter: String, friends: [Friend])] = []
        for friend in sorted {
            let first = friend.displayTitle
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(1)
                .uppercased()
            let letter = (first.rangeOfCharacter(from: .letters) != nil) ? first : "#"
            if let lastIndex = groups.indices.last, groups[lastIndex].letter == letter {
                groups[lastIndex].friends.append(friend)
            } else {
                groups.append((letter: letter, friends: [friend]))
            }
        }
        return groups
    }

    // MARK: - Строка друга (мессенджер-стиль)

    private func friendPersonRow(_ friend: Friend, showsDivider: Bool) -> some View {
        let watchingRoom = watchingRoomByFriendId[friend.id]
        return HStack(spacing: 10) {
            Button {
                HapticManager.selection()
                profileFriend = friend
            } label: {
                HStack(spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        friendAvatar(friend, size: 52)
                        if friend.isOnline && !friend.deleted {
                            Circle()
                                .fill(Color(red: 0.3, green: 0.9, blue: 0.55))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(V4.surface.opacity(0.95), lineWidth: 2))
                                .offset(x: 1, y: 1)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(friend.displayTitle)
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(V4.ink)
                            .lineLimit(1)

                        // Статус по убыванию интереса: смотрит сейчас →
                        // просто в сети → «был(а) …». Здесь presence уместен —
                        // это список людей, а не переписок.
                        if let watchingRoom {
                            HStack(spacing: 5) {
                                Image(systemName: "play.tv.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("смотрит «\(watchingRoom.name)»")
                                    .lineLimit(1)
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.accentColor)
                        } else {
                            Text(friend.presenceText)
                                .font(.system(size: 13))
                                .foregroundStyle(
                                    friend.isOnline && !friend.deleted
                                    ? Color(red: 0.3, green: 0.9, blue: 0.55)
                                    : V4.muted
                                )
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !friend.deleted {
                Button {
                    HapticManager.selection()
                    dmFriend = friend
                } label: {
                    V4GlyphIcon(glyph: .chat, size: 14, filled: true, weight: .regular)
                        .foregroundStyle(V4.ink)
                        .frame(width: 36, height: 36)
                        .background(V4.raised.opacity(0.75), in: Circle())
                        .overlay(Circle().stroke(V4.line.opacity(0.55), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Чат с \(friend.displayTitle)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(V4.line.opacity(0.45))
                    .frame(height: 0.5)
                    .padding(.leading, 78) // под текст, мимо аватара
            }
        }
        .contextMenu {
            Button { profileFriend = friend } label: {
                Label("Профиль", systemImage: "person.crop.circle")
            }
            if !friend.deleted {
                Button { dmFriend = friend } label: {
                    Label("Написать", systemImage: "message.fill")
                }
                Button {
                    watchWithFriend = friend
                    showCreateRoom = true
                } label: {
                    Label("Смотреть вместе", systemImage: "film.fill")
                }
            }
        }
    }

    @ViewBuilder
    func friendAvatar(_ friend: Friend, size: CGFloat) -> some View {
        if friend.deleted {
            PlinkDeletedAvatar(size: size)
        } else {
            PlinkStableAvatar(
                url: PlinkAvatarURL.stable(userId: friend.id, stored: friend.avatarURL),
                letter: friend.initials,
                size: size,
                userId: friend.id
            )
        }
    }

}
