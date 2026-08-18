// iPad/Mac sidebar shell. Uses AppSection enum (home/rooms/ai/friends/profile).
//
// Детали .home/.ai/.friends/.profile показывали старое
// поколение (DiscoveryHomeView с фейковым каталогом, AIAssistantView,
// FriendsView, ProfileView). Теперь все пять секций — живые V4-экраны,
// те же, что на iPhone в PlinkApprovedV4Root, с теми же сторами.

import SwiftUI

struct PlinkSidebarShell: View {
    @Binding var selection: AppSection
    @Binding var createPresented: Bool
    let dependencies: AppDependencies

    // Реальный список комнат вместо заглушки «Комнаты».
    @State private var roomsStore: V4RoomsStore?
    @State private var roomToPresent: Room?
    // На iPad кнопка «войти по коду» рисовалась всегда, но
    // joinByCode в V4RoomsViewLive не передавался (параметр опционален) — тап
    // не делал ничего. На iPhone тот же экран получает обработчик.
    @State private var showJoinByCode = false

    // Живые V4-сторы по образцу PlinkApprovedV4Root.bootstrap().
    @State private var searchStore = V4SearchStore()
    @State private var friendsStore: V4FriendsStore?
    @State private var aiStore = V4AIStore()
    @State private var profileStore: V4ProfileStore?
    @State private var showAppearance = false
    // Тема восстанавливается из того же ключа, куда её пишет iPhone-корень.
    @State private var theme: V4Theme = V4Theme(
        rawValue: UserDefaults.standard.string(forKey: "plink.v4ThemeName") ?? ""
    ) ?? .electric

    var body: some View {
        NavigationSplitView {
            // List был без selection — value-based
            // NavigationLink не менял Binding, detail вечно показывал .home.
            // Оптиональный прокси-биндинг: List(selection:) требует Optional.
            List(selection: Binding<AppSection?>(
                get: { selection },
                set: { if let newValue = $0 { selection = newValue } }
            )) {
                Section {
                    Label("Plink", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(Cinema2026.text)
                        .listRowBackground(Color.clear)
                }

                Section("Смотреть") {
                    nav(.home)
                    nav(.rooms)
                    nav(.ai)
                    nav(.friends)
                }

                Section {
                    Button {
                        createPresented = true
                    } label: {
                        Label("Создать комнату", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Cinema2026.accent)
                }

                Section {
                    nav(.profile)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 300)
            .scrollContentBackground(.hidden)
            .background(Cinema2026.background)
        } detail: {
            ZStack {
                // V4-экраны рисуются поверх живого фона, как на iPhone.
                V4LivingBackground(theme: theme)
                    .ignoresSafeArea()
                detail(for: selection)
                // Оверлей «Оформление» — как в PlinkApprovedV4Root.
                if showAppearance {
                    V4AppearanceView(theme: $theme, presented: $showAppearance)
                        .zIndex(25)
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
        }
        .onReceive(DeepLinkRouter.shared.$pendingChat) { target in
            guard target != nil else { return }
            selection = .friends
        }
        .navigationSplitViewStyle(.balanced)
        .environmentObject(dependencies.apiClient)
        .task { await bootstrap() }
        .onChange(of: theme) { _, newTheme in
            // Комната читает акцент активной темы — единый стиль.
            UserDefaults.standard.set(newTheme.rawValue, forKey: "plink.v4ThemeName")
        }
        // Презентация комнаты из детали «Комнаты»
        .fullScreenCover(item: $roomToPresent) { room in
            WatchRoomContainer(room: room)
        }
        .onReceive(DeepLinkRouter.shared.$pendingChat) { target in
            guard target != nil else { return }
            selection = .friends
        }
    }

    private func nav(_ section: AppSection) -> some View {
        NavigationLink(value: section) {
            Label(section.title, systemImage: section.symbol)
        }
        // Tag дублирует value — selection обновляется
        // и через List(selection:), и через NavigationLink.
        .tag(section)
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .home:
            V4HomeViewLive(
                theme: theme,
                searchStore: searchStore,
                roomsStore: roomsStore,
                openRoom: { openFirstRoom() },
                openRoomsTab: { selection = .rooms }
            )
        case .rooms:
            // Заглушка VStack{Text("Комнаты")} заменена
            // живым списком комнат (тот же модуль, что и на iPhone).
            V4RoomsViewLive(
                theme: theme,
                roomsStore: roomsStore,
                openRoom: { room in openRoom(room) },
                createRoom: { createPresented = true },
                joinByCode: { showJoinByCode = true }
            )
            .sheet(isPresented: $showJoinByCode) {
                JoinRoomSheet { room in
                    showJoinByCode = false
                    roomToPresent = room
                }
                .environmentObject(dependencies.apiClient)
            }
            .task { await roomsStore?.load() }
        case .ai:
            V4AIViewLive(theme: theme, store: aiStore)
        case .friends:
            V4FriendsViewLive(
                theme: theme,
                store: friendsStore,
                roomsStore: roomsStore,
                isActive: selection == .friends
            )
        case .profile:
            V4ProfileViewLive(
                theme: theme,
                store: profileStore,
                showAppearance: $showAppearance
            )
        }
    }

    // MARK: - Bootstrap

    /// Упрощённая копия PlinkApprovedV4Root.bootstrap(): те же сторы и
    /// та же гидратация токена, чтобы данные на iPad были живыми.
    private func bootstrap() async {
        let api = dependencies.apiClient
        AuthService.shared.rebindSessionFromStorage()
        if api.authToken == nil {
            api.authToken = AuthService.shared.authToken
                ?? AuthTokenStore.shared.token
        }
        if roomsStore == nil {
            roomsStore = V4RoomsStore(roomService: RoomService(api: api))
        }
        if friendsStore == nil {
            friendsStore = V4FriendsStore(friendManager: FriendManager.shared)
        }
        if profileStore == nil {
            profileStore = V4ProfileStore(authService: dependencies.authService)
        }

        if api.authToken != nil {
            do {
                let user = try await dependencies.authService.fetchCurrentUser()
                profileStore?.applyUser(user)
            } catch {
                Logger.api.warn("[bootstrap] fetchCurrentUser: \(error.localizedDescription)")
            }
            // Presence + бейджи непрочитанных — как на iPhone.
            PresenceHeartbeat.start()
            await PresenceHeartbeat.ping()
            DMChatService.shared.startUnreadPolling()
            await DMChatService.shared.refreshUnread()
        }

        await roomsStore?.load()
        await searchStore.loadTrending()
        await friendsStore?.load()
        await profileStore?.load()
        PlinkAvatarURL.bumpSessionBust()
    }

    private func openRoom(_ room: Room) {
        Task {
            do {
                let joined = try await RoomService(api: dependencies.apiClient).joinRoom(code: room.code)
                await MainActor.run { roomToPresent = joined }
            } catch {
                await MainActor.run { roomToPresent = room }
            }
        }
    }

    private func openFirstRoom() {
        guard let room = roomsStore?.heroRoom ?? roomsStore?.railRooms.first else { return }
        openRoom(room)
    }
}
