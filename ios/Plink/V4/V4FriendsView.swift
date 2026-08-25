// Plink/V4/V4FriendsView.swift
// Three segments: Друзья · Чаты/Общение · Недавние комнаты (with whom / what).

import SwiftUI
import PhotosUI
import UIKit
import Foundation

// Здесь был статический макет V4FriendsView с захардкоженными
// данными (0 инстанцирований) — удалён; enum сегментов оставлен, он живой.

// MARK: - Friends hub segments

private enum FriendsHubSegment: Int, CaseIterable, Identifiable {
    case friends = 0
    case chats = 1
    case rooms = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .friends: return "Друзья"
        case .chats: return "Чаты"
        // «Вечера», не «Комнаты»: сегмент показывает историю совместных
        // просмотров, а «Комнаты» уже есть в таб-баре — два одинаковых
        // слова вели в разные места.
        case .rooms: return "Вечера"
        }
    }

    var icon: String {
        switch self {
        case .friends: return "person.2.fill"
        case .chats: return "bubble.left.and.bubble.right.fill"
        case .rooms: return "play.rectangle.fill"
        }
    }

    /// Иконка из общего набора — вместо своего Image(systemName:).
    var glyph: V4Glyph {
        switch self {
        case .friends: return .people
        case .chats:   return .chat
        case .rooms:   return .room
        }
    }

    /// Дизайн-превью: `-plink.designsegment <0|1|2>` открывает хаб сразу на
    /// нужном сегменте — скриншоты «Чатов»/«Комнат» без тапов по симулятору.
    /// Тот же приём, что -plink.designchip на Главной.
    static var launchDefault: FriendsHubSegment {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-plink.designsegment"),
           args.indices.contains(i + 1),
           let raw = Int(args[i + 1]),
           let seg = FriendsHubSegment(rawValue: raw) {
            return seg
        }
        #endif
        return .friends
    }
}


// MARK: - Live friends

struct V4FriendsViewLive: View {
    // Групповые беседы (мессенджер внутри приложения)
    // Unified inbox — беседы встроены прямо в чаты
    @ObservedObject var groupService = GroupChatService.shared
    @ObservedObject var muteStore = ChatMuteStore.shared
    @State var openGroup: GroupChatDTO? = nil
    let theme: V4Theme
    var store: V4FriendsStore?
    /// Активные комнаты — для «Друг сейчас смотрит».
    var roomsStore: V4RoomsStore?
    /// When false (other tab), pause polling. Root passes tab == friends.
    var isActive: Bool = true
    /// Default: Друзья (not chats) — full friend list / carousel first.
    /// В DEBUG стартовый сегмент можно задать -plink.designsegment.
    @State private var segment: FriendsHubSegment = .launchDefault
    /// Для переезда пилюли выделения между сегментами.
    @Namespace private var segmentNS
    /// Куда толкать контент при смене сегмента: вправо по порядку —
    /// новый экран въезжает справа, назад — слева. Ставится в момент
    /// тапа, до анимируемой смены `segment`.
    @State private var segPush: Edge = .trailing
    @State var dmFriend: Friend?
    @State var profileFriend: Friend?
    @State var showCreateRoom = false
    @State var watchWithFriend: Friend?
    @State var showAddFriend = false
    @State var showCreateGroupSheet = false  // CTA «Создать беседу»
    @State private var showRequests = false
    @State var toast: String?
    @State private var recentRooms: [Room] = []
    @State private var recentLoading = false
    @State private var roomToOpen: Room?
    @Environment(\.scenePhase) private var scenePhase
    /// Shared so unread badges survive sheet open/close.
    @ObservedObject var dmService = DMChatService.shared
    @ObservedObject private var inviteService = RoomInviteService.shared
    /// Forces avatar AsyncImage reload when session bust changes
    @State private var avatarBust = PlinkAvatarURL.sessionBust

    private var requestBadge: Int { store?.requests.count ?? 0 }

    /// Pin order — shared store (not a private stored prop so memberwise init stays public).
    var pinStore: FriendPinStore { FriendPinStore.shared }

    @ObservedObject private var blockManager = UserBlockManager.shared

    /// Alphabetical / online-first friends list (no chat previews). Blocked hidden.
    var peopleFriends: [Friend] {
        let list = (store?.friends ?? []).filter { !blockManager.isBlocked($0.id) }
        return list.sorted { a, b in
            if a.isOnline != b.isOnline { return a.isOnline && !b.isOnline }
            return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedAscending
        }
    }

    var onlineFriends: [Friend] {
        // Deleted accounts never appear as online (Telegram).
        peopleFriends.filter { $0.isOnline && !$0.deleted }
    }

    /// Друзья, которые прямо сейчас хостят активную комнату.
    var friendsWatchingNow: [(friend: Friend, room: Room)] {
        guard let rooms = roomsStore?.rooms, !rooms.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [(friend: Friend, room: Room)] = []
        for friend in peopleFriends where !friend.deleted {
            if let room = rooms.first(where: {
                $0.isActive && $0.hostName.caseInsensitiveCompare(friend.username) == .orderedSame
            }), !seen.contains(room.id) {
                seen.insert(room.id)
                result.append((friend, room))
            }
        }
        return result
    }

    /// Telegram order: pinned (stable) → unpinned by last message time. Blocked hidden.
    var orderedFriends: [Friend] {
        let list = (store?.friends ?? []).filter { !blockManager.isBlocked($0.id) && !dmService.isArchived($0.id) }
        return pinStore.sortedChats(
            friends: list,
            lastActivity: { dmService.lastActivityAt(for: $0) },
            unread: { dmService.unreadCount(for: $0) }
        )
    }

    private var totalUnread: Int { dmService.totalUnread }

    private func consumePendingChat(_ target: PlinkChatTarget) {
        if segment != .chats {
            // Диплинк в чат — тот же направленный переход, что и тап по
            // сегменту, а не мгновенная подмена контента.
            segPush = FriendsHubSegment.chats.rawValue > segment.rawValue ? .trailing : .leading
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                segment = .chats
            }
        }
        switch target {
        case .dm(let friendId):
            Task { await presentDM(friendId: friendId) }
        case .group(let groupId):
            Task { await presentGroup(groupId: groupId) }
        }
        DeepLinkRouter.shared.clearPendingChat()
    }

    private func presentDM(friendId: String) async {
        if let existing = store?.friends.first(where: { $0.id == friendId })
            ?? FriendManager.shared.friends.first(where: { $0.id == friendId }) {
            dmFriend = existing
            return
        }
        struct UserDTO: Decodable {
            let username: String?
            let avatarURL: String?
        }
        let user: UserDTO? = try? await APIClient.shared.request("users/\(friendId)")
        dmFriend = Friend(
            id: friendId,
            username: user?.username ?? "Пользователь",
            avatarURL: user?.avatarURL,
            isOnline: false,
            friendsSince: Date()
        )
    }

    private func presentGroup(groupId: String) async {
        if groupService.groups.isEmpty {
            await groupService.loadGroups()
        }
        if let group = groupService.groups.first(where: { $0.id == groupId }) {
            openGroup = group
        }
    }

    var body: some View {
        // No NavigationStack — keep living theme visible
        VStack(spacing: 0) {
            header
                .accessibilityIdentifier("screen.friends")
                .padding(.horizontal, 18)
                // Единый «вдох» шапок от статус-бара (см. topBar Главной).
                .padding(.top, 18)
                .padding(.bottom, 10)

            segmentPicker
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Invites always visible above content (actionable)
                    if !inviteService.pendingInvites.isEmpty {
                        roomInvitesBlock
                    }

                    // Один VStack на весь сменяемый контент: id(segment)
                    // перерождает поддерево целиком, и оно уходит/приходит
                    // направленным толчком (вперёд — справа, назад — слева).
                    // ZStack обязателен: во время перехода старый и новый
                    // экраны существуют одновременно, и в VStack они бы
                    // выстроились столбиком — здесь они накладываются.
                    ZStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 20) {
                            switch segment {
                            case .friends:
                                friendsPeopleBlock
                            case .chats:
                                // Прототип 03.08.2026: во вкладке «Чаты» вместо
                                // колокольчика — явная карточка заявок. Иконка в шапке
                                // одна на все сегменты и легко теряется.
                                if requestBadge > 0 {
                                    friendRequestsCard
                                }
                                chatsBlock
                            case .rooms:
                                recentBlock
                            }
                        }
                        .id(segment)
                        .transition(.asymmetric(
                            insertion: .move(edge: segPush).combined(with: .opacity),
                            removal: .move(edge: segPush == .trailing ? .leading : .trailing)
                                .combined(with: .opacity)
                        ))
                    }
                }
                .padding(.bottom, 100)
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                await store?.load()
                await loadRecentRooms()
                await dmService.refreshUnread()
                await groupService.loadGroups()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(V4.ink)
        .background(Color.clear)
        .onAppear {
            if let target = DeepLinkRouter.shared.pendingChat {
                consumePendingChat(target)
            }
        }
        .onReceive(DeepLinkRouter.shared.$pendingChat) { target in
            guard let target else { return }
            consumePendingChat(target)
        }
        .sheet(item: $dmFriend, onDismiss: {
            Task { await dmService.refreshUnread() }
        }) { friend in
            NavigationStack {
                DMChatView(friend: friend)
                    .environmentObject(dmService)
                    .toolbar {
                        V4SheetCloseToolbarItem { dmFriend = nil }
                    }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $profileFriend) { friend in
            NavigationStack {
                FriendProfileView(userId: friend.id, usernameHint: friend.username) {
                    watchWithFriend = friend
                    profileFriend = nil
                    showCreateRoom = true
                }
                .toolbar {
                    V4SheetCloseToolbarItem { profileFriend = nil }
                }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCreateRoom, onDismiss: {
            // Keep watchWithFriend until create finishes if still creating; clear if cancelled
            if roomToOpen == nil { watchWithFriend = nil }
        }) {
            RoomCreationView(
                onRoomCreated: { room in
                    let friend = watchWithFriend
                    showCreateRoom = false
                    Task {
                        if let friend {
                            await RoomInviteService.shared.sendInvite(
                                to: friend,
                                room: room,
                                mediaTitle: room.mediaItem?.title
                            )
                        }
                        await MainActor.run {
                            HapticManager.roomJoined()
                            UIPasteboard.general.string = "Код комнаты Plink: \(room.code)"
                            roomToOpen = room
                            if friend != nil {
                                toast = "Комната создана · приглашение отправлено"
                            } else {
                                toast = "Комната создана · код \(room.code)"
                            }
                            watchWithFriend = nil
                        }
                    }
                }
            )
            .environmentObject(APIClient.shared)
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCreateGroupSheet) {
            CreateGroupSheet(friends: store?.friends ?? [])
                .preferredColorScheme(.dark)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddFriend) {
            if let store {
                AddFriendSheet(store: store, theme: theme) { message in
                    // Delay slightly so toast appears after sheet dismisses
                    Task { @MainActor in
                        await store.load()
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            toast = message
                        }
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            } else {
                Text(LocalizationManager.shared.string(.loading)).padding()
            }
        }
        .sheet(isPresented: $showRequests) {
            if let store {
                FriendRequestsSheet(theme: theme, store: store) { message in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        toast = message
                    }
                }
            }
        }
        .fullScreenCover(item: $roomToOpen) { room in
            WatchRoomContainer(room: room)
                .preferredColorScheme(.dark)
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(V4.surface.opacity(0.95), in: Capsule())
                    .padding(.top, 12)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_400_000_000)
                            withAnimation { self.toast = nil }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast)
        .task {
            await store?.load()
            await loadRecentRooms()
            await dmService.refreshUnread()
            await inviteService.refreshFromServer()
            await UserBlockManager.shared.refreshBlocksFromServer()
        }
        // Tabs stay mounted (opacity switch) — re-fetch when this tab is shown
        .onChange(of: isActive) { _, active in
            guard active else { return }
            Task {
                await store?.refreshQuietly()
                await loadRecentRooms()
                await dmService.refreshUnread()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, isActive else { return }
            Task {
                await store?.refreshQuietly()
                await loadRecentRooms()
                await dmService.refreshUnread()
                await groupService.loadGroups()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkRoomsDidChange)) { _ in
            Task { await loadRecentRooms() }
        }
        // Friends list (presence + avatars) while tab visible.
        // Было 1 с — три параллельных цикла давали ~3 запроса
        // в секунду и жгли батарею/трафик. Мгновенные события идут по realtime,
        // поллинг оставлен fallback-ом и только для активной вкладки на переднем плане.
        .task(id: isActive) {
            guard isActive else { return }
            await store?.refreshQuietly()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000) // 20s fallback
                guard !Task.isCancelled, isActive else { break }
                // scenePhase внутри долгоживущего .task «залипает» на значении момента
                // старта, поэтому спрашиваем состояние приложения напрямую.
                let foreground = await MainActor.run { UIApplication.shared.applicationState == .active }
                guard foreground else { continue }
                await store?.refreshQuietly()
                // Бесед нет в realtime-доставке: добавленный в беседу узнаёт
                // о ней только перечитыванием списка — обновляем тем же тактом.
                await groupService.loadGroups()
            }
        }
        // Unread DMs: realtime + редкий fallback-опрос внутри сервиса
        .task {
            dmService.startUnreadPolling()
            await inviteService.refreshFromServer()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { break }
                let foreground = await MainActor.run { UIApplication.shared.applicationState == .active }
                if foreground {
                    await inviteService.refreshFromServer()
                }
            }
        }
        .onAppear {
            dmService.startUnreadPolling()
            Task {
                await dmService.refreshUnread()
                await store?.refreshQuietly()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkAvatarsDidChange)) { n in
            if let b = n.object as? Int {
                avatarBust = b
            } else {
                avatarBust = PlinkAvatarURL.sessionBust
            }
        }
    }

    // MARK: - Incoming room invites

    @ViewBuilder
    private var roomInvitesBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Приглашения смотреть",
                icon: "envelope.open.fill",
                count: inviteService.pendingInvites.count,
                actionTitle: nil,
                action: nil
            )
            sectionCard {
                ForEach(inviteService.pendingInvites) { invite in
                    roomInviteRow(invite)
                }
            }
        }
        .padding(.horizontal, 0)
    }

    private func roomInviteRow(_ invite: RoomInvite) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                V4Avatar(
                    letter: PlinkAvatarURL.letter(from: invite.fromUsername),
                    theme: theme,
                    size: 44,
                    imageURL: PlinkAvatarURL.resolve(userId: invite.fromUserID, stored: invite.fromAvatarURL)
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(invite.fromUsername)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(V4.ink)
                    Text("Приглашает в «\(invite.roomName)»")
                        .font(.system(size: 13))
                        .foregroundStyle(V4.muted)
                        .lineLimit(2)
                    Text("Код \(invite.roomCode)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accentColor)
                }
                Spacer(minLength: 4)
            }
            HStack(spacing: 10) {
                Button {
                    // Remove card immediately, then join
                    Task {
                        if let room = await inviteService.acceptInvite(invite) {
                            await MainActor.run {
                                roomToOpen = room
                                toast = "Вы в комнате «\(room.name)»"
                            }
                        } else {
                            await MainActor.run {
                                toast = "Не удалось войти. Комната могла закрыться."
                            }
                        }
                    }
                } label: {
                    Text(LocalizationManager.shared.string(.frAccept))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.buttonTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    inviteService.declineInvite(invite)
                } label: {
                    Text(LocalizationManager.shared.string(.frDecline))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(V4.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .background(V4.raised.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V4.line.opacity(0.55)).frame(height: 1)
        }
    }

    // MARK: - Segment picker

    private var segmentPicker: some View {
        HStack(spacing: 6) {
            ForEach(FriendsHubSegment.allCases) { seg in
                Button {
                    guard seg != segment else { return }
                    HapticManager.selection()
                    // Направление до смены сегмента: вперёд по порядку —
                    // новый контент въезжает справа, назад — слева.
                    segPush = seg.rawValue > segment.rawValue ? .trailing : .leading
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        segment = seg
                    }
                } label: {
                    HStack(spacing: 6) {
                        V4GlyphIcon(glyph: seg.glyph, size: 13, filled: segment == seg, weight: .regular)
                        Text(seg.title)
                            // Вес постоянный: раньше выбранный сегмент не менял
                            // вес, но иконка была залитой всегда — теперь
                            // заливка и есть признак выбора.
                            .font(.system(size: 13, weight: .semibold))
                        // Badges
                        if seg == .chats, totalUnread > 0 {
                            Text(totalUnread > 99 ? "99+" : "\(totalUnread)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(V4.danger, in: Capsule())
                        }
                        if seg == .friends, let n = store?.friends.count, n > 0 {
                            Text("\(n)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(segment == seg ? Color.black.opacity(0.45) : V4.muted)
                        }
                        if seg == .rooms, !recentRooms.isEmpty {
                            Text("\(recentRooms.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(segment == seg ? Color.black.opacity(0.45) : V4.muted)
                        }
                    }
                    // Активный сегмент — белая пилюля с чёрным текстом, как
                    // главные CTA приложения; цвет темы из пилюль убран —
                    // сегменты не должны спорить с акцентными кнопками экрана.
                    .foregroundStyle(segment == seg ? Color.black.opacity(0.92) : V4.ink.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        // Пилюля переезжает между сегментами как одна масса,
                        // а не гаснет и зажигается заново на новом месте.
                        if segment == seg {
                            Capsule(style: .continuous)
                                .fill(.white)
                                .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
                                .matchedGeometryEffect(id: "friends.segment", in: segmentNS)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .plinkGlass(.control, in: Capsule(style: .continuous))
    }

    // MARK: - Header

    /// Карточка входящих заявок для вкладки «Чаты».
    /// Ведёт в тот же экран, что и иконка в шапке.
    private var friendRequestsCard: some View {
        Button {
            HapticManager.impact(.light)
            showRequests = true
        } label: {
            HStack(spacing: 12) {
                V4GlyphIcon(glyph: .requests, size: 17, filled: true, weight: .regular)
                    .foregroundStyle(theme.accentColor)
                    .frame(width: 40, height: 40)
                    .background(theme.accentColor.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(requestsCardTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(V4.ink)
                    Text("Посмотреть и ответить")
                        .font(.system(size: 12.5))
                        .foregroundStyle(V4.muted)
                }

                Spacer(minLength: 8)

                V4GlyphIcon(glyph: .chevronRight, size: 13, weight: .regular)
                    .foregroundStyle(V4.muted)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 64)
            .plinkGlass(.control, cornerRadius: 18, tint: theme.accentColor)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(requestsCardTitle)
        .accessibilityHint("Открывает список заявок в друзья")
    }

    /// «2 заявки в друзья» — с правильным падежом для 1/2-4/5+.
    private var requestsCardTitle: String {
        let n = requestBadge
        let form: String
        switch (n % 100, n % 10) {
        case (11...14, _): form = "заявок"
        case (_, 1):       form = "заявка"
        case (_, 2...4):   form = "заявки"
        default:           form = "заявок"
        }
        return "\(n) \(form) в друзья"
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            V4Heading(
                eyebrow: "ВМЕСТЕ",
                title: segment == .friends ? "Друзья"
                    : segment == .chats ? "Общение"
                    : "Вечера"
            )
            // Заголовок меняется вместе с сегментом — мягким кроссфейдом,
            // а не мгновенной подменой строки.
            .id(segment)
            .transition(.opacity)
            Spacer(minLength: 8)

            // Заявки — icon only, badge if incoming
            Button {
                HapticManager.impact(.light)
                showRequests = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: requestBadge > 0 ? "person.badge.clock.fill" : "tray.full")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(requestBadge > 0 ? theme.accentColor : V4.ink)
                        .frame(width: 40, height: 40)
                        .plinkGlass(.control, in: Circle())

                    if requestBadge > 0 {
                        Text(requestBadge > 9 ? "9+" : "\(requestBadge)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(theme.buttonTextColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(theme.accentColor, in: Capsule())
                            .offset(x: 4, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(requestBadge > 0 ? "Заявки, \(requestBadge)" : "Заявки")

            // Добавить друга
            Button {
                HapticManager.impact(.light)
                showAddFriend = true
            } label: {
                V4GlyphIcon(glyph: .plus, size: 17, weight: .regular)
                    .foregroundStyle(theme.accentColor)
                    .frame(width: 40, height: 40)
                    .plinkGlass(.control, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Добавить друга")
        }
    }

    // MARK: - Section chrome

    // Заголовок секции — чистая типографика без цветных плашек: акцентный
    // квадратик с иконкой и капсула-счётчик выглядели дешёвыми виджетами
    // и тянули цвет темы в каждый заголовок. Иконка остаётся в сигнатуре
    // (вызовы не трогаем), но не рисуется; счётчик — тихая цифра рядом.
    func sectionHeader(title: String, icon: String, count: Int?, actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(V4.ink)

            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(V4.muted)
            }

            Spacer()

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
    }

    func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        // Корпус хаба — на стекле, как карточки настроек и поиска: плоская
        // заливка V4.surface на живом фоне читалась вырезанным прямоугольником.
        .plinkGlass(.control, cornerRadius: 18)
        .padding(.horizontal, 16)
    }

    /// Все пустые состояния хаба — через общий V4EmptyState: одна формула
    /// «сцена → заголовок → пояснение → действие» на всё приложение.
    /// Для ошибок передаётся `style: .plain` — луч проектора зарезервирован
    /// за «в мире пусто», сбой получает компактный кружок.
    func emptyInside(icon: String, title: String, subtitle: String, ctaIcon: String = "plus", cta: String? = nil, style: V4EmptyStyle = .scene, action: (() -> Void)? = nil) -> some View {
        V4EmptyState(
            icon: icon,
            title: title,
            subtitle: subtitle,
            accent: theme.accentColor,
            accentInk: theme.buttonTextColor,
            style: style,
            primary: (cta != nil && action != nil)
                ? .init(title: cta!, icon: ctaIcon, run: action!)
                : nil
        )
        .padding(.vertical, 30)
        .padding(.horizontal, 12)
    }

    // MARK: - Недавние комнаты (с кем / что смотрели)

    @ViewBuilder
    private var recentBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "С друзьями",
                icon: "clock.arrow.circlepath",
                count: recentRooms.isEmpty ? nil : recentRooms.count,
                actionTitle: "Создать",
                action: { showCreateRoom = true }
            )

            Text(LocalizationManager.shared.string(.frHistorySub))
                .font(.system(size: 13))
                .foregroundStyle(V4.muted)
                .padding(.horizontal, 18)
                .padding(.top, -4)

            sectionCard {
                if recentLoading && recentRooms.isEmpty {
                    ProgressView().tint(theme.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                } else if recentRooms.isEmpty {
                    emptyInside(
                        icon: "play.rectangle.on.rectangle.fill",
                        title: "Здесь будут ваши вечера",
                        subtitle: "Создай комнату с другом — история «с кем и что смотрели» соберётся сама.",
                        ctaIcon: "plus",
                        cta: "Создать комнату"
                    ) { showCreateRoom = true }
                } else {
                    ForEach(recentRooms) { room in
                        recentRoomRow(room)
                    }
                }
            }
        }
    }

    // MARK: - Rows

    func friendChatRow(_ friend: Friend) -> some View {
        let unread = dmService.unreadCount(for: friend.id)
        let preview = dmService.lastPreviewByFriend[friend.id]
        let pinned = pinStore.isPinned(friend.id)
        let lastAt = dmService.lastActivityAt(for: friend.id)

        // Flat Telegram-style row inside shared sectionCard (no nested capsules / extra gaps)
        return HStack(spacing: 10) {
            Button {
                HapticManager.selection()
                dmFriend = friend
            } label: {
                HStack(spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        friendAvatar(friend, size: 48)
                        if friend.isOnline && !friend.deleted {
                            Circle()
                                .fill(Color(red: 0.3, green: 0.9, blue: 0.55))
                                .frame(width: 11, height: 11)
                                .overlay(Circle().stroke(V4.surface.opacity(0.95), lineWidth: 2))
                                .offset(x: 1, y: 1)
                        }
                    }
                    .onTapGesture { profileFriend = friend }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            if pinned {
                                V4GlyphIcon(glyph: .pin, size: 9, filled: true, weight: .regular)
                                    .foregroundStyle(theme.accentColor)
                            }
                            Text(friend.displayTitle)
                                .font(.system(size: 15.5, weight: unread > 0 ? .heavy : .semibold))
                                .foregroundStyle(V4.ink)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            if let lastAt {
                                Text(Self.chatListTime(lastAt))
                                    .font(.system(size: 12, weight: unread > 0 ? .semibold : .regular))
                                    .foregroundStyle(unread > 0 ? theme.accentColor : V4.muted)
                            }
                        }
                        HStack(spacing: 6) {
                            if let preview, !preview.isEmpty {
                                Text(preview)
                                    .font(.system(size: 13, weight: unread > 0 ? .medium : .regular))
                                    .foregroundStyle(unread > 0 ? V4.ink.opacity(0.85) : V4.muted)
                                    .lineLimit(1)
                            } else {
                                Text(friend.presenceText)
                                    .font(.system(size: 13))
                                    .foregroundStyle(
                                        friend.isOnline
                                        ? Color(red: 0.3, green: 0.9, blue: 0.55)
                                        : V4.muted
                                    )
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if unread > 0 {
                                Text(unread > 99 ? "99+" : "\(unread)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(theme.accentColor, in: Capsule())
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Compact watch-together control (icon only)
            Button {
                HapticManager.impact(.light)
                watchWithFriend = friend
                showCreateRoom = true
            } label: {
                V4GlyphIcon(glyph: .film, size: 13, filled: true, weight: .regular)
                    .foregroundStyle(theme.accentColor)
                    .frame(width: 34, height: 34)
                    .background(theme.accentColor.opacity(0.14), in: Circle())
                    .overlay(Circle().stroke(theme.accentColor.opacity(0.28), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Смотреть вместе с \(friend.displayTitle)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(unread > 0 ? theme.accentColor.opacity(0.05) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(V4.line.opacity(0.45))
                .frame(height: 0.5)
                .padding(.leading, 74) // align under text, past avatar
        }
                // Telegram-July-2026-style context menu
        .contextMenu {
            // — Primary —
            Button { dmFriend = friend } label: {
                Label("Открыть чат", systemImage: "message.fill")
            }
            Button {
                // Раньше тут звали chatDidOpen — чат «висел
                // открытым» (openFriendId), бейдж молчал, всё входящее авточиталось.
                Task { await dmService.markChatRead(friendId: friend.id) }
                toast = "Отмечено как прочитанное"
            } label: {
                Label("Отметить как прочитанное", systemImage: "checkmark.message.fill")
            }
            Button {
                HapticManager.impact(.light)
                let muted = muteStore.isMuted(friend.id)
                muteStore.setMuted(friend.id, muted: !muted)
                toast = muted ? "Уведомления включены" : "\(friend.displayTitle) заглушён"
            } label: {
                let muted = muteStore.isMuted(friend.id)
                Label(muted ? "Включить уведомления" : "Выключить уведомления",
                      systemImage: muted ? "bell.fill" : "bell.slash.fill")
            }
            Button { togglePin(friend) } label: {
                Label(pinned ? "Открепить" : "Закрепить",
                      systemImage: pinned ? "pin.slash.fill" : "pin.fill")
            }
            Button {
                Task { await dmService.archiveChat(with: friend) }
                toast = "\(friend.displayTitle) архивирован"
            } label: {
                Label("Архивировать", systemImage: "archivebox.fill")
            }
            Divider()
            Button { profileFriend = friend } label: {
                Label("Профиль", systemImage: "person.crop.circle")
            }
            Button {
                watchWithFriend = friend; showCreateRoom = true
            } label: {
                Label("Смотреть вместе", systemImage: "film.fill")
            }
            Divider()
            Button(role: .destructive) {
                Task { await dmService.deleteChat(with: friend); toast = "Чат удалён" }
            } label: { Label("Удалить чат", systemImage: "trash") }
            Button(role: .destructive) {
                Task {
                    await UserBlockManager.shared.blockAndDeleteChat(userId: friend.id, friend: friend)
                    toast = "\(friend.displayTitle) заблокирован"
                }
            } label: { Label("Заблокировать", systemImage: "hand.raised.fill") }
        }
        // swipeActions удалены — они работают только в List,
        // а строки лежат в VStack/ScrollView (мёртвый код, свайпы не срабатывали).
        // Все действия доступны через contextMenu выше.
    }

    private func togglePin(_ friend: Friend) {
        HapticManager.impact(.medium)
        let willPin = !pinStore.isPinned(friend.id)
        Task {
            // Различаем «сервер подтвердил», «лимит» и
            // «сеть не ответила» — раньше любой сбой показывался как успех.
            let result = await store?.friendManager.setPinned(friendId: friend.id, pinned: willPin)
                ?? .syncFailed
            await MainActor.run {
                switch result {
                case .limitReached:
                    toast = "Максимум 10 закреплений"
                case .syncFailed:
                    toast = willPin
                        ? "Закреплено локально · синхронизируем позже"
                        : "Откреплено локально · синхронизируем позже"
                case .synced:
                    toast = willPin
                        ? "\(friend.displayTitle) закреплён"
                        : "\(friend.displayTitle) откреплён"
                }
            }
        }
    }

    /// Compact time for chat list (Telegram-like).
    static func chatListTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            return "вчера"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            f.dateFormat = "d MMM"
        } else {
            f.dateFormat = "dd.MM.yy"
        }
        return f.string(from: date)
    }

    private func recentRoomRow(_ room: Room) -> some View {
        let mediaTitle = room.mediaItem?.title ?? room.name
        let withFriends = coWatchFriends(in: room)
        let othersCount = max(0, room.participantCount - 1)

        return Button {
            HapticManager.impact(.light)
            roomToOpen = room
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail / media poster
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [theme.accentColor.opacity(0.4), Color.purple.opacity(0.35), V4.raised],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    if let thumb = room.mediaItem?.thumbnailURL,
                       let url = URL(string: thumb) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(theme.accentColor)
                            }
                        }
                    } else {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(theme.accentColor)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(V4.line.opacity(0.5), lineWidth: 0.8)
                )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        if room.isActive {
                            Text("LIVE")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.85), in: Capsule())
                        }
                        Text(mediaTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(V4.ink)
                            .lineLimit(2)
                    }

                    // Who you watched with
                    if !withFriends.isEmpty {
                        HStack(spacing: 6) {
                            overlappingFriendAvatars(withFriends)
                            Text(withFriendsLine(withFriends, others: othersCount))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(V4.muted)
                                .lineLimit(1)
                        }
                    } else if othersCount > 0 {
                        Text("\(othersCount) участник(ов) · код \(room.code)")
                            .font(.system(size: 12))
                            .foregroundStyle(V4.muted)
                    } else {
                        Text(room.isActive ? "Ты один · код \(room.code)" : "История · \(room.code)")
                            .font(.system(size: 12))
                            .foregroundStyle(V4.muted)
                    }

                    if !room.hostName.isEmpty, room.hostName != "Unknown" {
                        Text("Владелец: \(room.hostName)")
                            .font(.system(size: 11))
                            .foregroundStyle(V4.muted.opacity(0.85))
                    }
                }
                Spacer(minLength: 4)
                V4GlyphIcon(glyph: .chevronRight, size: 12, weight: .regular)
                    .foregroundStyle(V4.muted)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V4.line.opacity(0.45)).frame(height: 0.5).padding(.leading, 90)
        }
    }

    /// Friends who were in this room (match against local friends list).
    private func coWatchFriends(in room: Room) -> [Friend] {
        let friendIds = Set((store?.friends ?? []).map(\.id))
        let me = UserDefaults.standard.string(forKey: "plink_current_user_id") ?? ""
        // Map participants that are friends
        var result: [Friend] = []
        for p in room.participants where p.id != me && friendIds.contains(p.id) {
            if let f = store?.friends.first(where: { $0.id == p.id }) {
                result.append(f)
            }
        }
        // Host if friend and not already listed
        if room.hostID != me, friendIds.contains(room.hostID),
           !result.contains(where: { $0.id == room.hostID }),
           let f = store?.friends.first(where: { $0.id == room.hostID }) {
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
                friendAvatar(f, size: 22)
                    .overlay(Circle().stroke(V4.surface.opacity(0.9), lineWidth: 1.5))
                    .zIndex(Double(3 - idx))
            }
        }
    }

    private func loadRecentRooms() async {
        recentLoading = true
        defer { recentLoading = false }
        do {
            let svc = RoomService(api: APIClient.shared)
            // Active first (can rejoin), then closed history for "recent"
            let active = try await svc.fetchMyActiveRooms()
            let history = (try? await svc.fetchMyRoomHistory()) ?? []
            // Dedup: show live rooms first, then history (no double entries)
            var seen = Set(active.map(\.id))
            var merged = active
            for r in history where !seen.contains(r.id) {
                seen.insert(r.id)
                merged.append(r)
            }
            recentRooms = Array(merged.prefix(20))
        } catch {
            // keep previous
        }
    }
}

// MARK: - Friend requests sheet (from header icon)

private struct FriendRequestsSheet: View {
    let theme: V4Theme
    let store: V4FriendsStore
    var onToast: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                V4.canvas.ignoresSafeArea()
                RadialGradient(
                    colors: [theme.accentColor.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.5, y: 0),
                    startRadius: 0,
                    endRadius: 420
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if store.requests.isEmpty && store.outgoing.isEmpty {
                            VStack(spacing: 14) {
                                ZStack {
                                    Circle().fill(theme.accentColor.opacity(0.13))
                                    Circle().stroke(theme.accentColor.opacity(0.22), lineWidth: 1)
                                    Image(systemName: "tray")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(theme.accentColor)
                                }
                                .frame(width: 58, height: 58)
                                Text(LocalizationManager.shared.string(.frNoRequests))
                                    .font(.system(size: 16.5, weight: .heavy))
                                    .tracking(-0.3)
                                    .foregroundStyle(V4.ink)
                                Text(LocalizationManager.shared.string(.frNoRequestsSub))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .lineSpacing(2)
                                    .foregroundStyle(V4.muted)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .plinkGlass(.control, cornerRadius: 20)
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                        } else {
                            if !store.requests.isEmpty {
                                Text(LocalizationManager.shared.string(.frIncoming))
                                    .font(.system(size: 11, weight: .heavy))
                                    .tracking(0.9)
                                    .foregroundStyle(theme.accentColor)
                                    .padding(.horizontal, 18)

                                VStack(spacing: 0) {
                                    ForEach(store.requests) { req in
                                        incomingRow(req)
                                    }
                                }
                                .plinkGlass(.control, cornerRadius: 16)
                                .padding(.horizontal, 16)
                            }

                            if !store.outgoing.isEmpty {
                                Text(LocalizationManager.shared.string(.frOutgoing))
                                    .font(.system(size: 11, weight: .heavy))
                                    .tracking(0.9)
                                    .foregroundStyle(V4.muted)
                                    .padding(.horizontal, 18)
                                    .padding(.top, 8)

                                VStack(spacing: 0) {
                                    ForEach(store.outgoing) { req in
                                        HStack(spacing: 12) {
                                            V4Avatar(letter: String(req.toUser.username.prefix(1)), theme: theme, size: 40)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(req.toUser.username)
                                                    .font(.system(size: 15, weight: .bold))
                                                    .foregroundStyle(V4.ink)
                                                Text(LocalizationManager.shared.string(.frPending))
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(V4.muted)
                                            }
                                            Spacer()
                                            Image(systemName: "hourglass")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(V4.muted)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .overlay(alignment: .bottom) {
                                            Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 66)
                                        }
                                    }
                                }
                                .plinkGlass(.control, cornerRadius: 16)
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Заявки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                V4SheetCloseToolbarItem { dismiss() }
            }
            .task { await store.load() }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func incomingRow(_ req: FriendRequest) -> some View {
        HStack(spacing: 12) {
            V4Avatar(letter: String(req.fromUser.username.prefix(1)), theme: theme, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(req.fromUser.username)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(V4.ink)
                Text(LocalizationManager.shared.string(.frWantsToAdd))
                    .font(.system(size: 12))
                    .foregroundStyle(V4.muted)
            }
            Spacer()
            Button {
                HapticManager.impact(.medium)
                Task {
                    await store.accept(req)
                    onToast("\(req.fromUser.username) в друзьях")
                }
            } label: {
                Text(LocalizationManager.shared.string(.frAccept))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.buttonTextColor)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 34)
                    .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Button {
                HapticManager.impact(.light)
                Task {
                    await store.decline(req)
                    onToast("Заявка отклонена")
                }
            } label: {
                Text(LocalizationManager.shared.string(.frNo))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(V4.ink)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 34)
                    .background(V4.raised.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(V4.line))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 66)
        }
    }
}

// MARK: - Add Friend Sheet

private struct AddFriendSheet: View {
    let store: V4FriendsStore
    let theme: V4Theme
    var onDone: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var directUsername = ""
    @State private var isSending = false
    @State private var localError: String?
    @State private var searchTask: Task<Void, Never>?

    private var manager: FriendManager { store.friendManager }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(LocalizationManager.shared.string(.frAddByUsername))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(V4.muted)

                    HStack(spacing: 10) {
                        TextField("@ник друга", text: $directUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(V4.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .background(V4.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(V4.line))

                        Button {
                            Task { await sendByUsername() }
                        } label: {
                            if isSending {
                                ProgressView().tint(theme.buttonTextColor).frame(width: 48, height: 48)
                            } else {
                                V4GlyphIcon(glyph: .send, size: 16, filled: true, weight: .regular)
                                    .foregroundStyle(theme.buttonTextColor)
                                    .frame(width: 48, height: 48)
                                    .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isSending || directUsername.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    Text(LocalizationManager.shared.string(.frAddHint))
                        .font(.system(size: 12))
                        .foregroundStyle(V4.muted)
                }
                .padding(18)

                Divider().overlay(V4.line)

                VStack(alignment: .leading, spacing: 10) {
                    Text(LocalizationManager.shared.string(.frOrSearch))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(V4.muted)
                        .padding(.horizontal, 18)
                        .padding(.top, 14)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(V4.muted)
                        TextField("Поиск по нику…", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(V4.ink)
                            .onChange(of: query) { _, new in
                                searchTask?.cancel()
                                searchTask = Task {
                                    try? await Task.sleep(nanoseconds: 350_000_000)
                                    guard !Task.isCancelled else { return }
                                    await manager.searchUsers(query: new)
                                }
                            }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(V4.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(V4.line))
                    .padding(.horizontal, 18)

                    if let localError {
                        Text(localError)
                            .font(.caption)
                            .foregroundStyle(V4.danger)
                            .padding(.horizontal, 18)
                    }

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(manager.searchResults) { user in
                                HStack(spacing: 12) {
                                    Group {
                                        if let url = PlinkAvatarURL.resolve(userId: user.id, stored: user.avatarURL) {
                                            AsyncImage(url: url) { phase in
                                                if let img = phase.image {
                                                    img.resizable().scaledToFill()
                                                } else {
                                                    Circle().fill(theme.accentColor.opacity(0.25))
                                                        .overlay(
                                                            Text(String(user.username.prefix(1)).uppercased())
                                                                .font(.system(size: 15, weight: .bold))
                                                                .foregroundStyle(.white)
                                                        )
                                                }
                                            }
                                        } else {
                                            Circle().fill(theme.accentColor.opacity(0.25))
                                                .overlay(
                                                    Text(String(user.username.prefix(1)).uppercased())
                                                        .font(.system(size: 15, weight: .bold))
                                                        .foregroundStyle(.white)
                                                )
                                        }
                                    }
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.username)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(V4.ink)
                                        Text(user.isOnline ? "в сети" : "не в сети")
                                            .font(.system(size: 12))
                                            .foregroundStyle(V4.muted)
                                    }
                                    Spacer()
                                    if manager.isFriend(user.id) {
                                        Text(LocalizationManager.shared.string(.frFriendBadge)).font(.system(size: 12, weight: .semibold)).foregroundStyle(V4.muted)
                                    } else if manager.hasOutgoingRequest(to: user.id) {
                                        Text(LocalizationManager.shared.string(.frSent)).font(.system(size: 12, weight: .semibold)).foregroundStyle(V4.amber)
                                    } else {
                                        Button {
                                            Task { await sendToUser(user) }
                                        } label: {
                                            Text(LocalizationManager.shared.string(.frAdd))
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(theme.buttonTextColor)
                                                .padding(.horizontal, 12)
                                                .frame(minHeight: 34)
                                                .background(theme.accentColor, in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 70)
                                }
                            }
                            if manager.searchResults.isEmpty && !query.isEmpty && !manager.isLoading {
                                Text(LocalizationManager.shared.string(.frNobodyFound))
                                    .font(.subheadline)
                                    .foregroundStyle(V4.muted)
                                    .padding(.top, 24)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                }
            }
            .background {
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
            }
            .navigationTitle("Добавить друга")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                V4SheetCloseToolbarItem { dismiss() }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sendByUsername() async {
        isSending = true
        localError = nil
        defer { isSending = false }
        let ok = await manager.sendRequestByUsername(directUsername)
        if ok {
            // Sheet dismisses so parent top toast is visible
            onDone(manager.lastSuccessMessage ?? "Заявка отправлена")
            dismiss()
        } else {
            localError = manager.errorMessage ?? "Не удалось отправить"
        }
    }

    private func sendToUser(_ user: UserPreview) async {
        isSending = true
        localError = nil
        defer { isSending = false }
        let ok = await manager.sendRequest(to: user.id, username: user.username)
        if ok {
            onDone(manager.lastSuccessMessage ?? "Заявка отправлена")
            dismiss()
        } else {
            localError = manager.errorMessage ?? "Не удалось отправить"
        }
    }
}
