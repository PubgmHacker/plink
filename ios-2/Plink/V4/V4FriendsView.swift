// Plink/V4/V4FriendsView.swift
// Three segments: Друзья · Чаты/Общение · Недавние комнаты (with whom / what).

import SwiftUI
import PhotosUI
import UIKit
import Foundation

// Аудит 26.07.2026: здесь был статический макет V4FriendsView с захардкоженными
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
        case .rooms: return "Комнаты"
        }
    }

    var icon: String {
        switch self {
        case .friends: return "person.2.fill"
        case .chats: return "bubble.left.and.bubble.right.fill"
        case .rooms: return "play.rectangle.fill"
        }
    }
}


// MARK: - Live friends

struct V4FriendsViewLive: View {
    // M16: групповые беседы (мессенджер внутри приложения)
    // M21/M22: unified inbox — беседы встроены прямо в чаты
    @ObservedObject private var groupService = GroupChatService.shared
    @ObservedObject private var muteStore = ChatMuteStore.shared
    @State private var openGroup: GroupChatDTO? = nil
    let theme: V4Theme
    var store: V4FriendsStore?
    /// M14: активные комнаты — для «Друг сейчас смотрит».
    var roomsStore: V4RoomsStore?
    /// When false (other tab), pause polling. Root passes tab == friends.
    var isActive: Bool = true
    /// Default: Друзья (not chats) — full friend list / carousel first.
    @State private var segment: FriendsHubSegment = .friends
    @State private var dmFriend: Friend?
    @State private var profileFriend: Friend?
    @State private var showCreateRoom = false
    @State private var watchWithFriend: Friend?
    @State private var showAddFriend = false
    @State private var showCreateGroupSheet = false  // M34: CTA «Создать беседу»
    @State private var showRequests = false
    @State private var toast: String?
    @State private var recentRooms: [Room] = []
    @State private var recentLoading = false
    @State private var roomToOpen: Room?
    @Environment(\.scenePhase) private var scenePhase
    /// Shared so unread badges survive sheet open/close.
    @ObservedObject private var dmService = DMChatService.shared
    @ObservedObject private var inviteService = RoomInviteService.shared
    /// Forces avatar AsyncImage reload when session bust changes
    @State private var avatarBust = PlinkAvatarURL.sessionBust

    private var requestBadge: Int { store?.requests.count ?? 0 }

    /// Pin order — shared store (not a private stored prop so memberwise init stays public).
    private var pinStore: FriendPinStore { FriendPinStore.shared }

    @ObservedObject private var blockManager = UserBlockManager.shared

    /// Alphabetical / online-first friends list (no chat previews). Blocked hidden.
    private var peopleFriends: [Friend] {
        let list = (store?.friends ?? []).filter { !blockManager.isBlocked($0.id) }
        return list.sorted { a, b in
            if a.isOnline != b.isOnline { return a.isOnline && !b.isOnline }
            return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedAscending
        }
    }

    private var onlineFriends: [Friend] {
        // Deleted accounts never appear as online (Telegram).
        peopleFriends.filter { $0.isOnline && !$0.deleted }
    }

    /// M14: друзья, которые прямо сейчас хостят активную комнату.
    private var friendsWatchingNow: [(friend: Friend, room: Room)] {
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
    private var orderedFriends: [Friend] {
        let list = (store?.friends ?? []).filter { !blockManager.isBlocked($0.id) && !dmService.isArchived($0.id) }
        return pinStore.sortedChats(
            friends: list,
            lastActivity: { dmService.lastActivityAt(for: $0) },
            unread: { dmService.unreadCount(for: $0) }
        )
    }

    private var totalUnread: Int { dmService.totalUnread }

    var body: some View {
        // No NavigationStack — keep living theme visible
        VStack(spacing: 0) {
            header
                .accessibilityIdentifier("screen.friends")
                .padding(.horizontal, 18)
                .padding(.top, 10)
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

                    switch segment {
                    case .friends:
                        friendsPeopleBlock
                    case .chats:
                        chatsBlock
                    case .rooms:
                        recentBlock
                    }
                }
                .padding(.bottom, 100)
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                await store?.load()
                await loadRecentRooms()
                await dmService.refreshUnread()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(V4.ink)
        .background(Color.clear)
        .sheet(item: $dmFriend, onDismiss: {
            Task { await dmService.refreshUnread() }
        }) { friend in
            NavigationStack {
                DMChatView(friend: friend)
                    .environmentObject(dmService)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Закрыть") { dmFriend = nil }
                        }
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
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Закрыть") { profileFriend = nil }
                    }
                }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
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
        }
        .sheet(isPresented: $showCreateGroupSheet) {
            CreateGroupSheet(friends: store?.friends ?? [])
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
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkRoomsDidChange)) { _ in
            Task { await loadRecentRooms() }
        }
        // Friends list (presence + avatars) while tab visible.
        // Аудит 26.07.2026 P2: было 1 с — три параллельных цикла давали ~3 запроса
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
                        .frame(height: 40)
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
                        .frame(height: 40)
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
                    HapticManager.selection()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        segment = seg
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: seg.icon)
                            .font(.system(size: 12, weight: .bold))
                        Text(seg.title)
                            .font(.system(size: 13, weight: .bold))
                        // Badges
                        if seg == .chats, totalUnread > 0 {
                            Text(totalUnread > 99 ? "99+" : "\(totalUnread)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(theme.accentColor, in: Capsule())
                        }
                        if seg == .friends, let n = store?.friends.count, n > 0 {
                            Text("\(n)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(segment == seg ? theme.buttonTextColor.opacity(0.8) : V4.muted)
                        }
                        if seg == .rooms, !recentRooms.isEmpty {
                            Text("\(recentRooms.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(segment == seg ? theme.buttonTextColor.opacity(0.8) : V4.muted)
                        }
                    }
                    .foregroundStyle(segment == seg ? theme.buttonTextColor : V4.ink.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(segment == seg ? theme.accentColor : V4.surface.opacity(0.45))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(segment == seg ? Color.clear : V4.line.opacity(0.55), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(V4.surface.opacity(0.28))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(V4.line.opacity(0.4), lineWidth: 0.8)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            V4Heading(
                eyebrow: "ВМЕСТЕ",
                title: segment == .friends ? "Друзья"
                    : segment == .chats ? "Общение"
                    : "Комнаты"
            )
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
                        .background(V4.surface.opacity(0.5))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(V4.line.opacity(0.8)))

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
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.accentColor)
                    .frame(width: 40, height: 40)
                    .background(V4.surface.opacity(0.5))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(V4.line.opacity(0.8)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Добавить друга")
        }
    }

    // MARK: - Section chrome

    private func sectionHeader(title: String, icon: String, count: Int?, actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.accentColor)
                .frame(width: 28, height: 28)
                .background(theme.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(V4.ink)

            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(V4.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(V4.surface.opacity(0.55), in: Capsule())
                    .overlay(Capsule().stroke(V4.line.opacity(0.6)))
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

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(V4.surface.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(V4.line.opacity(0.65), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func emptyInside(icon: String, title: String, subtitle: String, cta: String? = nil, action: (() -> Void)? = nil) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(theme.accentColor.opacity(0.85))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            if let cta, let action {
                Button(action: action) {
                    Text(cta)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.buttonTextColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(theme.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 12)
    }

    // MARK: - Друзья (people only — no chat previews)

    @ViewBuilder
    /// M14: карточка «друг смотрит» с кнопкой присоединения.
    private func friendWatchingCard(_ friend: Friend, _ room: Room) -> some View {
        Button {
            HapticManager.impact(.medium)
            NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
        } label: {
            HStack(spacing: 12) {
                V4Avatar(letter: String(friend.displayTitle.prefix(1)).uppercased(), theme: theme, size: 40)
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

    private var friendsPeopleBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            // M14: «Друг сейчас смотрит — присоединиться»
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

            // Online carousel
            if !onlineFriends.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(
                        title: LocalizationManager.shared.string(.frOnline),
                        icon: "circle.fill",
                        count: onlineFriends.count,
                        actionTitle: nil,
                        action: nil
                    )
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(onlineFriends) { friend in
                                onlineFriendChip(friend)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 4)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: LocalizationManager.shared.string(.frAllFriends),
                    icon: "person.2.fill",
                    count: store?.friends.count,
                    actionTitle: LocalizationManager.shared.string(.frAdd),
                    action: { showAddFriend = true }
                )

                if let s = store {
                    switch s.state {
                    case .loading:
                        sectionCard {
                            ProgressView().tint(theme.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 36)
                                .accessibilityLabel("Загрузка друзей")
                        }
                    case .failed(let err):
                        sectionCard {
                            emptyInside(
                                icon: "wifi.exclamationmark",
                                title: "Не удалось загрузить друзей",
                                subtitle: err,
                                cta: "Повторить"
                            ) { Task { await store?.load() } }
                        }
                    case .idle:
                        Color.clear.frame(height: 1)
                    case .loaded, .empty:
                        if s.friends.isEmpty {
                            sectionCard {
                                VStack(spacing: 4) {
                                    emptyInside(
                                        icon: "person.badge.plus",
                                        title: LocalizationManager.shared.string(.frEmptyTitle),
                                        subtitle: LocalizationManager.shared.string(.frEmptySub),
                                        cta: LocalizationManager.shared.string(.frFind)
                                    ) { showAddFriend = true }
                                    // M26 UX: инвайт-ссылка прямо из пустого состояния
                                    if let myId = AuthService.shared.currentUserValue?.id,
                                       let inviteURL = URL(string: "https://plink.app/u/\(myId)") {
                                        ShareLink(item: inviteURL) {
                                            Label(LocalizationManager.shared.string(.frInviteLink), systemImage: "square.and.arrow.up")
                                                .font(.system(size: 13.5, weight: .semibold))
                                                .foregroundStyle(theme.accentColor)
                                                .padding(.vertical, 8)
                                        }
                                    }
                                }
                                .padding(.bottom, 10)
                            }
                        } else {
                            // 2-column grid of friend cards
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ],
                                spacing: 12
                            ) {
                                ForEach(peopleFriends) { friend in
                                    friendPersonCard(friend)
                                }
                            }
                            .padding(.horizontal, 16)
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

    private func onlineFriendChip(_ friend: Friend) -> some View {
        Button {
            HapticManager.selection()
            profileFriend = friend
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    friendAvatar(friend, size: 64)
                    if !friend.deleted {
                        Circle()
                            .fill(Color(red: 0.3, green: 0.9, blue: 0.55))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(V4.surface.opacity(0.95), lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                }
                Text(friend.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(V4.ink)
                    .lineLimit(1)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
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
    private func friendAvatar(_ friend: Friend, size: CGFloat) -> some View {
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

    private func friendPersonCard(_ friend: Friend) -> some View {
        VStack(spacing: 10) {
            Button {
                HapticManager.selection()
                profileFriend = friend
            } label: {
                VStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        friendAvatar(friend, size: 56)
                        if friend.isOnline && !friend.deleted {
                            Circle()
                                .fill(Color(red: 0.3, green: 0.9, blue: 0.55))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(V4.surface.opacity(0.95), lineWidth: 2))
                                .offset(x: 1, y: 1)
                        }
                    }
                    Text(friend.displayTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(V4.ink)
                        .lineLimit(1)
                    Text(friend.presenceText)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            friend.isOnline && !friend.deleted
                            ? Color(red: 0.3, green: 0.9, blue: 0.55)
                            : V4.muted
                        )
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if friend.deleted {
                Text(LocalizationManager.shared.string(.frCantMessage))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(V4.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(V4.raised.opacity(0.4), in: Capsule())
            } else {
                HStack(spacing: 8) {
                    Button {
                        HapticManager.selection()
                        dmFriend = friend
                    } label: {
                        Image(systemName: "message.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(V4.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(V4.raised.opacity(0.75), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Чат с \(friend.displayTitle)")

                    Button {
                        HapticManager.impact(.light)
                        watchWithFriend = friend
                        showCreateRoom = true
                    } label: {
                        Image(systemName: "film.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.buttonTextColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(theme.accentColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Смотреть вместе с \(friend.displayTitle)")
                }
            }
        }
        .padding(12)
        .background(V4.surface.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(V4.line.opacity(0.55), lineWidth: 1)
        )
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
                    Label("��мотреть вместе", systemImage: "film.fill")
                }
            }
        }
    }

    // MARK: - Чаты / Общение

    // MARK: - M21/M22 Unified Inbox helpers

    // Аудит 26.07.2026: вложенный тип не наследует MainActor-изоляцию View,
    // а его геттеры дёргают DMChatService и FriendPinStore — оба @MainActor.
    @MainActor
    private enum InboxItem: Identifiable {
        case dm(Friend)
        case group(GroupChatDTO)
        var id: String {
            switch self { case .dm(let f): return "dm-\(f.id)"; case .group(let g): return "grp-\(g.id)" }
        }
        var lastActivity: Date {
            switch self {
            case .dm(let f): return DMChatService.shared.lastActivityAt(for: f.id) ?? .distantPast
            case .group(let g): return g.lastMessageDate ?? .distantPast
            }
        }
        var isPinned: Bool {
            switch self {
            case .dm(let f): return FriendPinStore.shared.isPinned(f.id)
            case .group: return false
            }
        }
    }

    private var unifiedInbox: [InboxItem] {
        let _ = dmService.inboxEpoch
        let _ = pinStore.orderedPinnedIds
        let dms = orderedFriends.map { InboxItem.dm($0) }
        let groups = groupService.groups
            .sorted { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }
            .map { InboxItem.group($0) }
        let pinned  = dms.filter(\.isPinned)
        let unpinned = (dms.filter { !$0.isPinned } + groups)
            .sorted { $0.lastActivity > $1.lastActivity }
        return pinned + unpinned
    }

    private var chatsBlock: some View {
        let totalCount = (store?.friends.count ?? 0) + groupService.groups.count
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Чаты",
                icon: "bubble.left.and.bubble.right.fill",
                count: totalCount > 0 ? totalCount : nil,
                actionTitle: LocalizationManager.shared.string(.frAdd),
                action: { showAddFriend = true }
            )

            // M34: быстрое создание групповой беседы
            Button {
                HapticManager.impact(.light)
                showCreateGroupSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                    Text("Создать беседу")
                    Spacer()
                    Image(systemName: "plus")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.accentColor)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(theme.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.accentColor.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Создать групповую беседу")

            if unifiedInbox.isEmpty {
                sectionCard {
                    emptyInside(
                        icon: "bubble.left.and.bubble.right",
                        title: "Пока нет чатов",
                        subtitle: "Добавь друга или создай беседу — всё появится здесь",
                        cta: "Найти друга"
                    ) { showAddFriend = true }
                }
            } else {
                sectionCard {
                    ForEach(unifiedInbox) { item in
                        switch item {
                        case .dm(let friend):   friendChatRow(friend)
                        case .group(let group): groupChatRow(group)
                        }
                    }
                }
            }
        }
        // M21: открыть беседу из unified inbox
        .sheet(item: $openGroup) { group in
            NavigationStack {
                GroupsListView(friends: store?.friends ?? [], meId: dmService.currentUserId)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Закрыть") { openGroup = nil }
                        }
                    }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// M21/M22: Telegram-style group chat row (unified inbox)
    @ViewBuilder
    private func groupChatRow(_ group: GroupChatDTO) -> some View {
        let unread  = group.unreadCount ?? 0
        let muteKey = "grp-\(group.id)"
        let muted   = muteStore.isMuted(muteKey)
        Button {
            HapticManager.selection()
            openGroup = group
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [theme.accentColor.opacity(0.85), theme.accentColor.opacity(0.42)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 48, height: 48)
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.buttonTextColor)
                    }
                    // 👥 group marker
                    Circle().fill(V4.surface)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Image(systemName: muted ? "bell.slash.fill" : "person.3.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(muted ? .orange : theme.accentColor)
                        }
                        .offset(x: 2, y: 2)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(group.title)
                            .font(.system(size: 15.5, weight: unread > 0 ? .heavy : .semibold))
                            .foregroundStyle(V4.ink)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        if let lastAt = group.lastMessageDate {
                            Text(Self.chatListTime(lastAt))
                                .font(.system(size: 12, weight: unread > 0 ? .semibold : .regular))
                                .foregroundStyle(unread > 0 ? theme.accentColor : V4.muted)
                        }
                    }
                    HStack(spacing: 6) {
                        if let last = group.lastMessageText, !last.isEmpty {
                            Text(last)
                                .font(.system(size: 13, weight: unread > 0 ? .medium : .regular))
                                .foregroundStyle(unread > 0 ? V4.ink.opacity(0.85) : V4.muted)
                                .lineLimit(1)
                        } else {
                            Text("\(group.memberCount ?? 0) участника")
                                .font(.system(size: 13))
                                .foregroundStyle(V4.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if muted {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                        if unread > 0 {
                            Text(unread > 99 ? "99+" : "\(unread)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(muted ? Color.gray : theme.accentColor, in: Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(unread > 0 && !muted ? theme.accentColor.opacity(0.05) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V4.line.opacity(0.45)).frame(height: 0.5).padding(.leading, 74)
        }
        // Аудит 26.07.2026 P1: swipeActions удалены — работают только в List,
        // строки лежат в VStack/ScrollView (свайпы не срабатывали). Действия — в contextMenu.
        // M22: контекстное меню (долгий тап)
        .contextMenu {
            Button { openGroup = group } label: {
                Label("Открыть беседу", systemImage: "person.3.fill")
            }
            Button {
                Task { await groupService.markRead(groupId: group.id) }
                toast = "Отмечено как прочитанное"
            } label: { Label("Отметить как прочитанное", systemImage: "checkmark.message.fill") }
            Button {
                muteStore.toggle(muteKey)
                toast = muteStore.isMuted(muteKey) ? "Беседа заглушена" : "Уведомления включены"
            } label: {
                Label(muted ? "Включить уведомления" : "Выключить уведомления",
                      systemImage: muted ? "bell.fill" : "bell.slash.fill")
            }
            Divider()
            Button(role: .destructive) {
                Task { await groupService.leave(groupId: group.id) }
                toast = "Беседа удалена"
            } label: { Label("Удалить беседу", systemImage: "trash") }
        }
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
                        icon: "play.rectangle.fill",
                        title: "Пока пусто",
                        subtitle: "Создай комнату с другом — здесь появит��я история «с кем и что»",
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

    private func friendChatRow(_ friend: Friend) -> some View {
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
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 9, weight: .bold))
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
                Image(systemName: "film.fill")
                    .font(.system(size: 13, weight: .semibold))
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
                // M22: Telegram-July-2026-style context menu
        .contextMenu {
            // — Primary —
            Button { dmFriend = friend } label: {
                Label("Открыть чат", systemImage: "message.fill")
            }
            Button {
                // Аудит 26.07.2026 P1: раньше тут звали chatDidOpen — чат «висел
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
        // Аудит 26.07.2026 P1: swipeActions удалены — они работают только в List,
        // а строки лежат в VStack/ScrollView (мёртвый код, свайпы не срабатывали).
        // Все действия доступны через contextMenu выше.
    }

    private func togglePin(_ friend: Friend) {
        HapticManager.impact(.medium)
        let willPin = !pinStore.isPinned(friend.id)
        Task {
            // Аудит 26.07.2026 P2: различаем «сервер подтвердил», «лимит» и
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
    private static func chatListTime(_ date: Date) -> String {
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
                        Text("Хост: \(room.hostName)")
                            .font(.system(size: 11))
                            .foregroundStyle(V4.muted.opacity(0.85))
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
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
                LinearGradient(
                    colors: [Color(hex: 0x0B1018), Color(hex: 0x0A0D12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if store.requests.isEmpty && store.outgoing.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "tray")
                                    .font(.system(size: 36))
                                    .foregroundStyle(theme.accentColor)
                                Text(LocalizationManager.shared.string(.frNoRequests))
                                    .font(.headline)
                                    .foregroundStyle(V4.ink)
                                Text(LocalizationManager.shared.string(.frNoRequestsSub))
                                    .font(.subheadline)
                                    .foregroundStyle(V4.muted)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                            .padding(.horizontal, 24)
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
                                .background(V4.surface.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(V4.line))
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
                                            Text("⏳")
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .overlay(alignment: .bottom) {
                                            Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 66)
                                        }
                                    }
                                }
                                .background(V4.surface.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(V4.line))
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
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
                    .frame(height: 34)
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
                    .frame(height: 34)
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
                            .frame(height: 48)
                            .background(V4.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(V4.line))

                        Button {
                            Task { await sendByUsername() }
                        } label: {
                            if isSending {
                                ProgressView().tint(theme.buttonTextColor).frame(width: 48, height: 48)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 16, weight: .semibold))
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
                                                .frame(height: 34)
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
            .background(V4.canvas.ignoresSafeArea())
            .navigationTitle("Добавить друга")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
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
