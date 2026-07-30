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

    // Показ комнаты идёт через roomToPresent + .fullScreenCover ниже.
    // Аудит 26.07.2026: @State roomCoordinator не читался ни разу (единственное
    // упоминание во всём проекте — эта строка), вместе с ним удалён и мёртвый
    // V5/PlinkRoomPresentation.swift.
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

    // Аудит 26.07.2026 P1: единственный консьюмер deep-link'ов (раньше
    // pendingLink никто не читал — комната джойнилась на сервере, UI молчал).
    @State private var pendingFriendInvite: V4FriendInvite?

    // Аудит 26.07.2026 P2: жизненный цикл фоновых сервисов. Раньше
    // stopUnreadPolling() не звали нигде — DM-опрос и presence-пинги жили вечно.
    @Environment(\.scenePhase) private var scenePhase

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
            // Аудит 26.07.2026: выбор темы уезжает PUT /api/profile/appearance
            // (кросс-девайс). Дедупликация и офлайн-деградация — внутри стора.
            AppearanceStore.shared.syncV4Theme(
                themeName: newTheme.rawValue,
                liveIndex: UserDefaults.standard.integer(forKey: "plink.liveTheme")
            )
        }
        // Аудит 26.07.2026 P2: в фоне гасим DM-опрос / realtime и presence-пинги,
        // при возврате поднимаем и сразу подтягиваем свежие бейджи.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                guard APIClient.shared.authToken != nil else { return }
                PresenceHeartbeat.start()
                DMChatService.shared.startUnreadPolling()
                Task { await DMChatService.shared.refreshUnread() }
            case .background:
                DMChatService.shared.stopUnreadPolling()
                PresenceHeartbeat.stop()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkLiveThemeChanged)) { n in
            if let i = n.object as? Int {
                liveThemeIndex = i
                if let l = PlinkPlusLiveTheme.resolve(i) { theme = l.closestStandardTheme }
                // Аудит 26.07.2026: смена/сброс живой темы тоже уезжает на
                // сервер (onChange(of: theme) не сработает, если ближайшая
                // статическая тема совпала с текущей). Имя темы берём из
                // plink.v4ThemeName — он пишется ДО поста нотификации, а
                // @State theme в этот момент может быть ещё старым (эхо
                // гидрации иначе перетёрло бы серверный выбор).
                AppearanceStore.shared.syncV4Theme(
                    themeName: UserDefaults.standard.string(forKey: "plink.v4ThemeName") ?? theme.rawValue,
                    liveIndex: i
                )
            }
        }
        // Аудит 26.07.2026: статическая тема, гидрированная с сервера при
        // старте, — .plinkLiveThemeChanged(0) сам по себе тему не меняет.
        .onReceive(NotificationCenter.default.publisher(for: .plinkV4ThemeRestored)) { n in
            if let raw = n.object as? String, let restored = V4Theme(rawValue: raw) {
                theme = restored
            }
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
        // Аудит 26.07.2026 P1: deep links — комната открывается, заявка в друзья
        // подтверждается алертом. @Published отдаёт текущее значение при подписке,
        // так что ссылка, пришедшая до появления экрана, тоже обработается.
        .onReceive(DeepLinkRouter.shared.$pendingLink) { link in
            handleDeepLink(link)
        }
        .alert(
            "Заявка в друзья",
            isPresented: Binding(
                get: { pendingFriendInvite != nil },
                set: { if !$0 { pendingFriendInvite = nil } }
            ),
            presenting: pendingFriendInvite
        ) { invite in
            Button("Добавить") {
                pendingFriendInvite = nil
                Task { @MainActor in
                    await FriendManager.shared.sendRequest(to: invite.userId, username: invite.username)
                }
            }
            Button("Отмена", role: .cancel) { pendingFriendInvite = nil }
        } message: { invite in
            Text("Отправить заявку в друзья пользователю @\(invite.username)?")
        }
    }

    // MARK: - Deep Links (Аудит 26.07.2026 P1)

    @MainActor
    private func handleDeepLink(_ link: DeepLinkType) {
        switch link {
        case .none:
            return
        case .room(let code):
            DeepLinkRouter.shared.clear()
            Task {
                do {
                    let joined = try await RoomService(api: APIClient.shared).joinRoom(code: code)
                    await MainActor.run {
                        HapticManager.roomJoined()
                        roomToPresent = joined
                        Task { await roomsStore?.load() }
                    }
                } catch {
                    await MainActor.run { HapticManager.errorOccurred() }
                }
            }
        case .friendInvite(let userId):
            DeepLinkRouter.shared.clear()
            Task {
                let username = await Self.fetchUsername(userId: userId)
                await MainActor.run {
                    pendingFriendInvite = V4FriendInvite(userId: userId, username: username)
                }
            }
        }
    }

    /// Имя пользователя для алерта-приглашения (фолбэк — «Пользователь»).
    private static func fetchUsername(userId: String) async -> String {
        struct UserDTO: Decodable { let username: String? }
        let user: UserDTO? = try? await APIClient.shared.request("users/\(userId)")
        return user?.username ?? "Пользователь"
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
    // Аудит 26.07.2026: здесь были quickCreateRoom() и вторая копия
    // createRoomFromTrending() — обе без единого вызова (живая копия — в
    // V4HomeViewLive). Удалены.


    private func bootstrap() async {
        let api = APIClient.shared
        // Hydrate shared session first — fixes empty currentUser after ISO8601 cache
        AuthService.shared.rebindSessionFromStorage()
        if api.authToken == nil {
            api.authToken = AuthService.shared.authToken
                ?? AuthTokenStore.shared.token
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
                // Аудит 26.07.2026 (P2): здесь был второй вызов syncFromServer с
                // expiry: nil. Теперь fetchCurrentUser() сам синхронизирует премиум
                // с серверной датой premiumUntil, и дубль только затирал бы её.
                let user = try await as_.fetchCurrentUser()
                profileStore?.applyUser(user)
            } catch {
                Logger.api.warn("[bootstrap] fetchCurrentUser: \(error.localizedDescription)")
            }
            // Аудит 26.07.2026: гидрация оформления с сервера — тема/бабл
            // подтягиваются на iPhone без открытия экрана «Оформление»
            // (смена устройства восстанавливает выбор). Заодно создаётся
            // AppearanceStore.shared → AppearanceStore.live перестаёт быть
            // nil, и откат платных тем при истечении Plink+ реально работает.
            await AppearanceStore.shared.hydrateFromBackendAndApplyToV4()
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

// MARK: - Friend Invite (deep link /u/<id>) — Аудит 26.07.2026 P1

private struct V4FriendInvite: Identifiable {
    let id = UUID()
    let userId: String
    let username: String
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


