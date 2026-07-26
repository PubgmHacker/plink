// Plink/V4/PlinkApprovedV4Root.swift — split from PlinkV4PixelPerfect (move-only, no logic change)
// Source of truth: V4 design module. Do not change visuals.

import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif
import Foundation



// MARK: - Section

struct PlinkApprovedV4Root: View {
    @State private var tab=0
    @State private var theme:V4Theme = .electric
    @State private var appearance=false
    @State private var liveThemeIndex: Int = UserDefaults.standard.integer(forKey: "plink.liveTheme")
    @State private var highContrast: Bool = PlinkAppearancePrefs.highContrast

    // P0.2b: Unified WatchRoom presentation — single coordinator, single fullScreenCover
    @State private var roomCoordinator = RoomPresentationCoordinator()
    @State private var roomToPresent: Room?

    // P0: Real backend stores
    @State private var roomsStore: V4RoomsStore?
    @State private var searchStore = V4SearchStore()
    @State private var friendsStore: V4FriendsStore?
    @State private var aiStore = V4AIStore()
    @State private var profileStore: V4ProfileStore?
    @State private var showCreateRoom = false
    @State private var showJoinByCode = false
    @State private var lastSharedRoomCode: String?

    var body: some View {
        ZStack(alignment:.bottom){
            // Plink+ video bg OR standard Canvas — mutually exclusive
            // .id() forces SwiftUI to recreate the view when theme changes
            if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) {
                if let vn = live.videoFileName {
                    MetalVideoBackground(videoName: vn, opacity: 0.55, overlayColor: .black, overlayOpacity: 0.45)
                        .id("bg-\(liveThemeIndex)")
                } else { PlinkPlusStaticGradient(theme: live) }
            } else {
                V4LivingBackground(theme:theme)
                    .id("bg-standard")
            }
            // High-contrast overlay (Оформление → Больше контраста)
            if highContrast {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            Group {
                // ZStack with opacity — keeps all tabs alive, no recreation lag
                V4HomeViewLive(theme:theme, searchStore:searchStore, roomsStore:roomsStore, openRoom:{ openFirstRoom() }, liveThemeIndex:liveThemeIndex, openRoomsTab:{ tab = 1 })
                    .opacity(tab == 0 ? 1 : 0).allowsHitTesting(tab == 0)
                V4RoomsViewLive(theme:theme, roomsStore:roomsStore, openRoom:{ openFirstRoom() }, createRoom:{showCreateRoom=true}, joinByCode:{showJoinByCode=true})
                    .opacity(tab == 1 ? 1 : 0).allowsHitTesting(tab == 1)
                V4FriendsViewLive(theme:theme, store:friendsStore, roomsStore: roomsStore, isActive: tab == 2)
                    .opacity(tab == 2 ? 1 : 0).allowsHitTesting(tab == 2)
                V4AIViewLive(theme:theme, store:aiStore)
                    .opacity(tab == 3 ? 1 : 0).allowsHitTesting(tab == 3)
                V4ProfileViewLive(theme:theme, store:profileStore, showAppearance:$appearance)
                    .opacity(tab == 4 ? 1 : 0).allowsHitTesting(tab == 4)
            }
            .animation(.easeInOut(duration: 0.15), value: tab)
            PlinkLiquidTabBar(
                selection: $tab,
                theme: theme,
                friendsUnread: DMChatService.shared.totalUnread
            )
            if appearance { V4AppearanceView(theme:$theme,presented:$appearance).zIndex(25).transition(.opacity) }
        }.preferredColorScheme(.dark).tint(V4.accent)
        .task {
            if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) { theme = live.closestStandardTheme }
            // M14: комната читает акцент активной темы — единый стиль без прыжка дизайнов
            UserDefaults.standard.set(theme.rawValue, forKey: "plink.v4ThemeName")
            await bootstrap()
        }
        .onChange(of: theme) { _, newTheme in
            UserDefaults.standard.set(newTheme.rawValue, forKey: "plink.v4ThemeName")
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkLiveThemeChanged)) { n in
            if let i = n.object as? Int { liveThemeIndex = i; if let l = PlinkPlusLiveTheme.resolve(i) { theme = l.closestStandardTheme } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkAppearancePrefsChanged)) { _ in
            highContrast = PlinkAppearancePrefs.highContrast
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("plinkOpenCreateRoom"))) { _ in
            showCreateRoom = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("plinkOpenJoinByCode"))) { _ in
            showJoinByCode = true
        }
        .sheet(isPresented: $showCreateRoom) {
            RoomCreationView(
                onRoomCreated: { newRoom in
                    showCreateRoom = false
                    HapticManager.roomJoined()
                    // Copy room code + surface alert so host always sees 6-char code
                    UIPasteboard.general.string = "Код комнаты Plink: \(newRoom.code)"
                    lastSharedRoomCode = newRoom.code
                    // P0.2b: room created → present WatchRoom after host dismisses code alert
                    Task { await roomsStore?.load() }
                    // Present room after brief moment so alert is readable
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        roomToPresent = newRoom
                    }
                }
            )
            .environmentObject(APIClient.shared)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showJoinByCode) {
            JoinRoomSheet(
                onJoined: { room in
                    showJoinByCode = false
                    roomToPresent = room
                }
            )
            .environmentObject(APIClient.shared)
            .preferredColorScheme(.dark)
        }
        .alert(
            "Код комнаты",
            isPresented: Binding(
                get: { lastSharedRoomCode != nil },
                set: { if !$0 { lastSharedRoomCode = nil } }
            )
        ) {
            Button("Скопировано — ОК") { lastSharedRoomCode = nil }
        } message: {
            Text("Отправь другу код: \(lastSharedRoomCode ?? "")\n\nДруг: вкладка «Комнаты» → иконка «человек+» → ввести код.\nКод уже в буфере обмена.")
        }
        // P0.2b: single fullScreenCover for WatchRoom — handles both join and create
        .fullScreenCover(item: $roomToPresent) { room in
            WatchRoomContainer(room: room)
        }
        .onChange(of: roomToPresent?.id) { _, newId in
            // After room closes — re-sync active rooms (empty shells disappear)
            if newId == nil {
                Task { await roomsStore?.load() }
            }
        }
        // Trending / home cards post .plinkRoomCreated with a Room object — present WatchRoom
        .onReceive(NotificationCenter.default.publisher(for: .plinkRoomCreated)) { note in
            guard let room = note.object as? Room else { return }
            // Avoid re-present churn if already showing the same room
            if roomToPresent?.id == room.id { return }
            HapticManager.roomJoined()
            roomToPresent = room
            Task { await roomsStore?.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkRoomsDidChange)) { _ in
            Task { await roomsStore?.load() }
        }
    }

    /// Open a room from the rooms store (join first so presence/sync work multi-device).
    private func openFirstRoom() {
        guard let rs = roomsStore else { return }
        let candidate = rs.heroRoom ?? rs.railRooms.first
        guard let room = candidate else { return }
        Task {
            do {
                let joined = try await RoomService(api: APIClient.shared).joinRoom(code: room.code)
                await MainActor.run {
                    roomToPresent = joined
                }
            } catch {
                // Fall back to presenting list snapshot if already a member / network blip
                await MainActor.run {
                    roomToPresent = room
                }
            }
        }
    }

    /// Quick Room — one-tap create from first trending video.
    private func quickCreateRoom() async {
        guard let trending = searchStore.trending.first else { return }
        guard KeychainHelper.read(for: "rave_auth_token") != nil else { return }
        let videoId = trending.id
        let mediaItem = MediaItem(
            id: "https://www.youtube.com/embed/\(videoId)",
            title: trending.title,
            artist: nil,
            thumbnailURL: trending.artworkURL?.absoluteString,
            streamURL: "https://www.youtube.com/embed/\(videoId)",
            duration: nil,
            mediaType: .video,
            source: .youtube,
            videoId: videoId
        )
        let request = CreateRoomRequest(
            name: "\(trending.title)",
            maxParticipants: 4,
            mediaItem: mediaItem,
            privacy: .publicRoom,
            password: nil,
            hostName: AuthService.shared.currentUserValue?.username
        )
        do {
            let api = APIClient.shared
            let room = try await RoomService(api: api).createRoom(request)
            await MainActor.run {
                HapticManager.roomJoined()
                PlinkAppDelegate.requestNotificationPermission()
                UIPasteboard.general.string = "Код комнаты Plink: \(room.code)"
                roomToPresent = room
                Task { await roomsStore?.load() }
            }
        } catch {}
    }

    /// Create room from a specific trending video.
    private func createRoomFromTrending(_ item: V4SearchResult) async {
        guard KeychainHelper.read(for: "rave_auth_token") != nil else { return }
        // Ensure APIClient.shared has the token (Keychain alone is not enough for RoomService)
        if APIClient.shared.authToken == nil {
            APIClient.shared.authToken = KeychainHelper.read(for: "rave_auth_token")
        }
        guard APIClient.shared.authToken != nil else {
            await MainActor.run { HapticManager.errorOccurred() }
            return
        }

        let videoId = item.id
        // Use watch URL — backend + client both extract videoId reliably
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
            let api = APIClient.shared
            var room = try await RoomService(api: api).createRoom(request)
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
                // Present WatchRoom (also mirrored via .plinkRoomCreated for home subviews)
                roomToPresent = room
                NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
                Task { await roomsStore?.load() }
            }
        } catch {
            await MainActor.run {
                HapticManager.errorOccurred()
            }
        }
    }

    private func bootstrap() async {
        let api = APIClient.shared
        // Hydrate shared session first — fixes empty currentUser after ISO8601 cache
        AuthService.shared.rebindSessionFromStorage()
        if api.authToken == nil {
            api.authToken = AuthService.shared.authToken
                ?? KeychainHelper.read(for: "rave_auth_token")
        }
        let rs = RoomService(api: api)
        // Shared FriendManager so friends list + open DM share avatar version updates
        let fm = FriendManager.shared
        // Always use shared AuthService so profile + WatchRoom share identity
        let as_ = AuthService.shared
        roomsStore = V4RoomsStore(roomService: rs)
        friendsStore = V4FriendsStore(friendManager: fm)
        profileStore = V4ProfileStore(authService: as_)

        // Server is authority for isPremium + ADMIN role (e.g. koslakandrej@gmail.com)
        if api.authToken != nil {
            do {
                let user = try await as_.fetchCurrentUser()
                PremiumStatusManager.shared.syncFromServer(
                    isPremium: user.isPremium,
                    expiry: nil
                )
                profileStore?.applyUser(user)
            } catch {
                Logger.api.warn("[bootstrap] fetchCurrentUser: \(error.localizedDescription)")
            }
            // Mark self online so friends list shows real presence
            PresenceHeartbeat.start()
            await PresenceHeartbeat.ping()
            // Instant unread badges app-wide
            DMChatService.shared.startUnreadPolling()
            await DMChatService.shared.refreshUnread()
        }

        await roomsStore?.load()
        await searchStore.loadTrending()
        await friendsStore?.load()
        await profileStore?.load()
        PlinkAvatarURL.bumpSessionBust()
    }
}

// MARK: - Liquid Glass Tab Bar (GPT-5.6 Post-V4)

struct PlinkLiquidTabBar: View {
    @Binding var selection: Int
    var theme: V4Theme = .electric
    /// Unread DMs — red badge on «Друзья» tab when user is not in that chat.
    var friendsUnread: Int = 0
    @ObservedObject private var dmService = DMChatService.shared
    @Namespace private var selectionNS
    private var activeSecondary: Color { let (_, c1, _, _) = theme.colors; return c1 }

    // M25 UX: Друзья — в центре (чаще всего используется), ИИ — 4-я позиция.
    // M25 i18n: подписи через LocalizationManager (RU/EN/ZH).
    private var items: [(String, String)] {
        let l = LocalizationManager.shared
        return [
            ("house.fill", l.string(.tabHome)),
            ("circle.grid.2x2.fill", l.string(.tabRooms)),
            ("person.2.fill", l.string(.tabFriends)),
            ("sparkles", l.string(.tabAI)),
            ("person.crop.circle.fill", l.string(.tabProfile))
        ]
    }

    private var friendsBadge: Int { max(friendsUnread, dmService.totalUnread) }

    var body: some View {
        content
            .padding(6)
            .background(.ultraThinMaterial)
            
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(V4.line, lineWidth: 0.75)
            )
            .frame(height: 72)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .accessibilityElement(children: .contain)
    }

    private var content: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                Button {
                    HapticManager.selection()
                    withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.26)) {
                        selection = index
                    }
                } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: items[index].0)
                                .font(.system(size: 18, weight: .semibold))
                            // M25: Tab 2 = Друзья — unread DM badge
                            if index == 2, friendsBadge > 0 {
                                Text(friendsBadge > 9 ? "9+" : "\(friendsBadge)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.red, in: Capsule())
                                    .offset(x: 10, y: -6)
                            }
                        }
                        Text(items[index].1)
                            .font(.system(size: 9.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == index ? activeSecondary : V4.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if selection == index {
                            Capsule(style: .continuous)
                                .fill(activeSecondary.opacity(0.15))
                                .matchedGeometryEffect(id: "selected-tab", in: selectionNS)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(items[index].1)
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
    }
}

// MARK: - Notification Bell (GPT-5.6 Post-V4)

struct NotificationInboxButton: View {
    let unreadCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: unreadCount > 0 ? "bell.fill" : "bell")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(V4.ink)
                .frame(width: 43, height: 43)
                .background(V4.roundBG)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(V4.line, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if unreadCount > 0 {
                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(V4.accentInk)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(V4.accent)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Уведомления")
        .accessibilityValue(unreadCount == 0 ? "Нет новых" : "Новых: \(unreadCount)")
    }
}


