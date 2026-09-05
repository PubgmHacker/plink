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

/// Дизайн-режим: `-plink.designempty` показывает экран-приглашение даже на
/// аккаунте с друзьями. Нужен только чтобы снимать это состояние вживую —
/// в релизной сборке флаг не существует.
enum V4FriendsEmptyDesign {
    static let forced: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-plink.designempty")
        #else
        return false
        #endif
    }()
}

/// Ряд мест у экрана: своё занято, соседние — свободны. Это подпись пустой
/// вкладки, а не иконка-заглушка: Плинк — совместный просмотр, и пустота здесь
/// значит «рядом никто не сидит», а не «раздел пуст». Кольца дышат по очереди
/// слева направо — взгляд идёт к ним, а под ними стоит поле ввода.
private struct PlinkSeatRow: View {
    let letter: String
    let seed: String
    let imageURL: URL?

    var body: some View {
        // Ряд, а не стопка аватарок: наложение требует непрозрачной заливки,
        // и свободные места превращались в чёрные кружки поверх подсветки.
        // Раздвинутые кольца видно насквозь — место читается пустым.
        HStack(spacing: 11) {
            V4Avatar(letter: letter.isEmpty ? "П" : letter, seed: seed, size: 64, imageURL: imageURL)
            EmptySeat(index: 0, size: 58)
            EmptySeat(index: 1, size: 51)
            EmptySeat(index: 2, size: 44)
        }
        .accessibilityHidden(true)
    }

    /// Свободное место: тонкое кольцо, которое медленно светлеет и гаснет.
    /// Кольцо белое, а не акцентное — акцент здесь совпал бы с подсветкой
    /// темы и пропал. Плюса внутри нет: он изображал кнопку, которой не был,
    /// и спорил с настоящей «+» в шапке.
    private struct EmptySeat: View {
        let index: Int
        let size: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var lit = false

        private var base: Double { 1.0 - Double(index) * 0.26 }

        var body: some View {
            ZStack {
                Circle().fill(.white.opacity(0.05 * base))
                // Сплошное кольцо, а не пунктир: пунктирная окружность —
                // язык вайрфрейма, и вся сцена читалась недорисованной.
                Circle().strokeBorder(.white.opacity((lit ? 0.34 : 0.15) * base), lineWidth: 1)
            }
            .frame(width: size, height: size)
            .onAppear {
                guard !reduceMotion else { lit = true; return }
                withAnimation(
                    .easeInOut(duration: 2.1)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.42)
                ) { lit = true }
            }
        }
    }
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
            // Stories rail — what friends watched this week and their
            // statuses, Telegram-style rings. Own tile first.
            if let s = store {
                V4FriendStoriesRail(
                    theme: theme,
                    store: s,
                    onOpen: { storyPresentation = $0 },
                    onMine: { mine in
                        if let mine {
                            storyPresentation = PlinkStoryPresentation(owners: [mine], start: 0)
                        } else {
                            showStatusEditor = true
                        }
                    }
                )
                .padding(.top, 2)
            }

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
                if let s = store {
                    let settled = s.state.isSettled
                    let isEmpty = V4FriendsEmptyDesign.forced || (settled && s.friends.isEmpty)

                    // Заголовок «Все друзья» — только над списком. Над
                    // приглашением он пересчитывал нули и объявлял пустоту
                    // разделом.
                    if !isEmpty {
                        // Без текстового «Добавить»: вход один — «+» в шапке
                        // хаба, дубль в заголовке секции путал.
                        // Заголовок обязан описывать то, что под ним. Он брал
                        // общее число друзей мимо чипа и поиска: включённый
                        // «В сети» при нуле онлайн оставлял «Все друзья 3»
                        // прямо над плашкой «Сейчас никого нет в сети».
                        // Теперь и подпись, и счёт идут за фильтром — заодно
                        // исчез дубль числа с чипом «Все» (ниже).
                        sectionHeader(
                            title: friendsFilter == .online
                                ? LocalizationManager.shared.string(.frOnline)
                                : LocalizationManager.shared.string(.frAllFriends),
                            icon: "person.2.fill",
                            count: filteredPeople.count,
                            actionTitle: nil,
                            action: nil
                        )
                    }

                    if isEmpty {
                        friendsEmptyInvite
                    } else {
                        switch s.state {
                        // idle — миг до старта загрузки (bootstrap запускает её
                        // сразу после создания стора); раньше idle рисовал
                        // прозрачную заглушку, и заголовок висел над пустотой.
                        case .loading, .idle:
                            friendsLoadingSkeleton
                        case .failed:
                            // Сырой текст ошибки (NSURLErrorDomain и т.п.) наружу
                            // не выходит — офлайн-состояние говорит человеческим
                            // языком и даёт одно действие.
                            sectionCard {
                                emptyInside(
                                    icon: "wifi.exclamationmark",
                                    title: "Друзья не загрузились",
                                    subtitle: "Похоже, нет соединения. Проверьте интернет — и попробуйте ещё раз.",
                                    ctaIcon: "arrow.clockwise",
                                    cta: "Повторить",
                                    style: .plain
                                ) { Task { await store?.load() } }
                            }
                        case .loaded, .empty:
                            friendsPeopleList
                        }
                    }
                } else {
                    sectionHeader(
                        title: LocalizationManager.shared.string(.frAllFriends),
                        icon: "person.2.fill",
                        count: nil,
                        actionTitle: nil,
                        action: nil
                    )
                    friendsLoadingSkeleton
                }
            }
        }
    }

    // MARK: - Скелет загрузки

    /// Загрузка рисует будущие строки, а не спиннер по центру карточки:
    /// геометрия совпадает со списком, поэтому появление данных не дёргает
    /// экран. Ширины разной длины — иначе четыре одинаковые полосы читаются
    /// как таблица, а не как имена.
    var friendsLoadingSkeleton: some View {
        let widths: [(CGFloat, CGFloat)] = [(148, 84), (116, 104), (172, 70), (132, 92)]
        return VStack(spacing: 0) {
            ForEach(Array(widths.enumerated()), id: \.offset) { idx, w in
                HStack(spacing: 12) {
                    SkeletonCircle(size: 52)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonRect(width: w.0, height: 13, cornerRadius: 6)
                        SkeletonRect(width: w.1, height: 10, cornerRadius: 5)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 11)
                if idx < widths.count - 1 {
                    Rectangle().fill(V4.line.opacity(0.5)).frame(height: 0.5)
                        .padding(.leading, 64)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .plinkGlass(.control, cornerRadius: 18)
        .padding(.horizontal, 16)
        .accessibilityElement()
        .accessibilityLabel("Загрузка друзей")
    }

    // MARK: - Пусто: экран-приглашение

    /// Друзей нет. Референсы (Telegram «Контакты», WhatsApp «Пригласить»,
    /// Discord «Add Friend») сходятся в одном: пустой экран — это НЕ баннер с
    /// картинкой и кнопкой, открывающей ещё один экран, а сама форма
    /// добавления. Поэтому здесь: ряд мест у экрана → заголовок → поле «@ник»
    /// с отправкой прямо отсюда → два канала строками. Старый вариант
    /// (медальон + две кнопки в стеклянной коробке) стоил двух тапов до
    /// первого поля ввода.
    var friendsEmptyInvite: some View {
        VStack(spacing: 0) {
            // Заявки идут выше приглашения: человека уже позвали — звать
            // кого-то ещё бессмысленно, пока это не разобрано.
            if requestBadge > 0 {
                emptyRequestsCallout
                    .padding(.bottom, 18)
            }

            PlinkSeatRow(
                letter: meLetter,
                seed: AuthService.shared.currentUserValue?.id ?? "",
                imageURL: meAvatarURL
            )
            .padding(.bottom, 22)

            Text(LocalizationManager.shared.string(.frEmptyTitle))
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(V4.ink)
                .multilineTextAlignment(.center)

            Text(LocalizationManager.shared.string(.frEmptySub))
                .font(.system(size: 14))
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 14)
                .padding(.top, 8)

            emptyUsernameField
                .padding(.top, 22)

            // Подсказка и ошибка занимают одну и ту же строку: место
            // зарезервировано всегда, поэтому неудачная отправка не сдвигает
            // кнопки под пальцем.
            Text(inviteError ?? LocalizationManager.shared.string(.frEmptyHint))
                .font(.system(size: 12))
                .foregroundStyle(inviteError == nil ? V4.muted.opacity(0.85) : V4.danger)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
                .frame(minHeight: 30, alignment: .top)
                .padding(.horizontal, 10)
                .padding(.top, 9)
                .animation(.easeOut(duration: 0.2), value: inviteError)

            emptyChannelRows
                .padding(.top, 6)
        }
        .padding(.horizontal, 16)
        // Приглашение живёт по центру свободной полосы, а не под шапкой:
        // прижатый к верху блок оставлял полэкрана пустоты — ровно то, что
        // и делало старое состояние «деревенским».
        // −100: столько скролл держит под таб-баром.
        .frame(maxWidth: .infinity, minHeight: max(hubViewport - 100, 520), alignment: .center)
    }

    /// Буква своего кресла — из имени, как в остальных списках.
    private var meLetter: String {
        let me = AuthService.shared.currentUserValue
        let name = me?.displayName?.isEmpty == false ? (me?.displayName ?? "") : (me?.username ?? "")
        return String(name.prefix(1)).uppercased()
    }

    private var meAvatarURL: URL? {
        guard let me = AuthService.shared.currentUserValue else { return nil }
        return PlinkAvatarURL.resolve(userId: me.id, stored: me.avatarURL)
    }

    /// Ник без «@» и пробелов — единственный источник правды для кнопки и submit.
    private var inviteUsernameClean: String {
        inviteUsername
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
    }

    /// Поле «@ник» с отправкой: главное действие экрана стоит прямо здесь.
    private var emptyUsernameField: some View {
        let ready = !inviteUsernameClean.isEmpty && !inviteSending
        return HStack(spacing: 6) {
            Text("@")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(V4.muted)
                .padding(.leading, 16)

            TextField(
                "",
                text: $inviteUsername,
                prompt: Text(LocalizationManager.shared.string(.frEmptyPlaceholder))
                    .foregroundColor(V4.muted.opacity(0.75))
            )
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(V4.ink)
            .tint(theme.accentColor)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.username)
            .submitLabel(.send)
            .onSubmit { sendInviteRequest() }
            .onChange(of: inviteUsername) { _, _ in
                if inviteError != nil { inviteError = nil }
            }
            .accessibilityLabel("Ник друга")

            Button {
                sendInviteRequest()
            } label: {
                ZStack {
                    Circle()
                        .fill(ready ? theme.accentColor : V4.muted.opacity(0.22))
                        .frame(width: 42, height: 42)
                    if inviteSending {
                        ProgressView()
                            .tint(theme.buttonTextColor)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(ready ? theme.buttonTextColor : V4.muted)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!ready)
            .padding(.trailing, 7)
            .animation(.easeOut(duration: 0.18), value: ready)
            .accessibilityLabel(LocalizationManager.shared.string(.frAdd))
        }
        .frame(height: 56)
        .plinkGlass(.control, cornerRadius: 18)
    }

    /// Два вторых канала — строками мессенджера, а не парой кнопок: список
    /// каналов растёт, кнопки в ряд — нет.
    private var emptyChannelRows: some View {
        VStack(spacing: 0) {
            Button {
                HapticManager.selection()
                showAddFriend = true
            } label: {
                emptyChannelLabel(
                    icon: "magnifyingglass",
                    title: LocalizationManager.shared.string(.frEmptyFindTitle),
                    subtitle: LocalizationManager.shared.string(.frEmptyFindSub)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("friends.emptyFind")

            Rectangle().fill(V4.line.opacity(0.55)).frame(height: 0.5)
                .padding(.leading, 62)

            // Инвайт-ссылка — по нику (так же, как «Поделиться» на профиле);
            // id в /u/ не вёл на публичную страницу.
            if let me = AuthService.shared.currentUserValue,
               let inviteURL = PlinkURLs.profileLink(me.username.isEmpty ? me.id : me.username) {
                ShareLink(item: inviteURL) {
                    emptyChannelLabel(
                        icon: "link",
                        title: LocalizationManager.shared.string(.frInviteLink),
                        subtitle: LocalizationManager.shared.string(.frEmptyLinkSub)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("friends.emptyInvite")
            }
        }
        .plinkGlass(.control, cornerRadius: 18)
    }

    private func emptyChannelLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 13) {
            // Нейтрально: тёплая тема красит и подложку экрана, и такой
            // кружок — иконка растворялась в собственном фоне.
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(V4.ink)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(V4.ink)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(V4.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(V4.muted.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    /// Входящие заявки на пустом экране: цифра + один тап до разбора.
    private var emptyRequestsCallout: some View {
        Button {
            HapticManager.impact(.light)
            showRequests = true
        } label: {
            HStack(spacing: 12) {
                // То же лицо, что у карточки заявок в хабе: нейтральный
                // глиф и красная метка — акцент остаётся фону и заливкам.
                V4GlyphIcon(glyph: .requests, size: 16, filled: true, weight: .regular)
                    .foregroundStyle(V4.ink)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(alignment: .topTrailing) {
                        V4CountBadge(count: requestBadge)
                            .offset(x: 5, y: -3)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizationManager.shared.string(.frEmptyRequests))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(V4.ink)
                    Text(LocalizationManager.shared.string(.frEmptyRequestsSub))
                        .font(.system(size: 12.5))
                        .foregroundStyle(V4.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(V4.muted.opacity(0.7))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .plinkGlass(.control, cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(LocalizationManager.shared.string(.frEmptyRequests)), \(requestBadge)")
    }

    /// Отправка заявки прямо с пустого экрана. Успех = тост и очистка поля
    /// (список сам подтянется), отказ = строка под полем, а не модалка.
    func sendInviteRequest() {
        let clean = inviteUsernameClean
        guard !clean.isEmpty, !inviteSending, let manager = store?.friendManager else { return }
        HapticManager.impact(.light)
        inviteSending = true
        inviteError = nil
        Task { @MainActor in
            let ok = await manager.sendRequestByUsername(clean)
            inviteSending = false
            if ok {
                inviteUsername = ""
                HapticManager.notification(.success)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    toast = manager.lastSuccessMessage ?? LocalizationManager.shared.string(.frSent)
                }
                await store?.load()
            } else {
                HapticManager.errorOccurred()
                inviteError = manager.errorMessage ?? LocalizationManager.shared.string(.frEmptySendFailed)
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
                            subtitle: "Проверьте написание или поищите по нику.",
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
                // Без счётчика: при активном «Все» это ровно то же число,
                // что стоит в заголовке секции в 90 pt выше — «Все друзья 3»
                // и «Все 3» читались как две разные цифры.
                peopleChip(
                    title: "Все",
                    count: nil,
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
                            // Глиф и подпись — нейтральные, счётчик — красный:
                            // акцент красит живую подложку, и на тёплой теме
                            // оранжевый чип на оранжевом свечении сливался.
                            V4GlyphIcon(glyph: .requests, size: 12, filled: true, weight: .semibold)
                            Text("Заявки")
                                .font(.system(size: 13.5, weight: .semibold))
                            V4CountBadge(count: requests, fontSize: 10, ringed: false)
                        }
                        .foregroundStyle(V4.ink)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background {
                            Capsule().fill(V4.raised.opacity(0.6))
                                .overlay(Capsule().stroke(V4.line.opacity(0.6), lineWidth: 0.8))
                        }
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
        /// `nil` — «счётчика у чипа нет» (у «Все» его держит заголовок секции).
        /// Ноль — «есть, но пусто»: он тоже не рисуется, чтобы «В сети 0» не
        /// выглядел ошибкой рядом с зелёной точкой.
        count: Int?,
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
                if let count, count > 0 {
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
                .plinkHitTarget(36)
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
