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
    // Дизайн-превью: `-plink.designtab N` открывает оболочку сразу на нужной
    // вкладке — скриншоты экранов в симуляторе без ручных тапов. Только DEBUG.
    @State private var tab: Int = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-plink.designtab"), args.indices.contains(i + 1),
           let t = Int(args[i + 1]), (0...4).contains(t) {
            return t
        }
        #endif
        return 0
    }()
    // Стартуем с последней сохранённой темы, а не с жёсткой .electric:
    // иначе первый кадр всегда синий, а через секунды серверная гидрация
    // (hydrateFromBackendAndApplyToV4 → .plinkV4ThemeRestored) резко
    // перекидывала на выбранную тему — «синяя вспышка» при каждом входе.
    // Ключ plink.v4ThemeName пишется при каждой смене и при гидрации.
    @State private var theme: V4Theme =
        V4Theme(rawValue: UserDefaults.standard.string(forKey: "plink.v4ThemeName") ?? "") ?? .electric
    @State private var appearance=false
    @State private var liveThemeIndex: Int = UserDefaults.standard.integer(forKey: "plink.liveTheme")
    @State private var highContrast: Bool = PlinkAppearancePrefs.highContrast

    // Показ комнаты идёт через roomToPresent + .fullScreenCover ниже.
    // @State roomCoordinator не читался ни разу (единственное
    // упоминание во всём проекте — эта строка), вместе с ним удалён и мёртвый
    // V5/PlinkRoomPresentation.swift.
    @State private var roomToPresent: Room?

    // Backend-backed stores — no mock data in this tree.
    @State private var roomsStore: V4RoomsStore?
    @State private var searchStore = V4SearchStore()
    @State private var friendsStore: V4FriendsStore?
    @State private var aiStore = V4AIStore()
    @State private var profileStore: V4ProfileStore?
    @State private var showCreateRoom = false
    @State private var showJoinByCode = false
    // 26.08.2026, откат по замечанию владельца: вкладка «ИИ» — это раздел
    // (лента трейлеров, сфера ассистента и крупное «Скоро»), а не голый чат.
    // Накануне вкладку подменили разговором, и вместе с ним из приложения
    // исчезли рилсы и сфера. Раздел вернулся, разговор снова живёт отдельной
    // поверхностью поверх вкладок: у ленты и у чата разные роли.
    @State private var showAIChat = false
    /// «Спросить голосом» — тот же чат, но с сразу включённым микрофоном.
    @State private var aiChatAutoVoice = false
    @State private var lastSharedRoomCode: String?
    @State private var joinErrorMessage: String?
    @State private var showJoinError = false
    @State private var joinPrefillCode = ""
    @State private var joinStartWithPassword = false

    // Единственный консьюмер deep-link'ов (раньше
    // pendingLink никто не читал — комната джойнилась на сервере, UI молчал).
    @State private var pendingFriendInvite: V4FriendInvite?

    // Жизненный цикл фоновых сервисов. Раньше
    // stopUnreadPolling() не звали нигде — DM-опрос и presence-пинги жили вечно.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // let-разрез: ~25 модификаторов одной цепью тип-чекер уже не осиливал
        // (приёмник plinkOpenFriendsTab 25.08.2026 стал каплей — «unable to
        // type-check in reasonable time»). Две половины он проверяет отдельно.
        let core = ZStack(alignment:.bottom){
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
            // 07.08.2026: жёсткая рамка вокруг вкладок.
            //
            // Все шесть экранов живут здесь одновременно и гасятся через
            // .opacity — вкладки не пересоздаются при переключении. Побочный
            // эффект: ZStack принимает ширину самого широкого ребёнка, поэтому
            // одна секция на одном экране, вылезшая за границу (ряд с
            // фиксированными по ширине карточками вне горизонтального
            // ScrollView, строка без переноса, карусель), растягивала по
            // горизонтали ВСЁ приложение вместе с таб-баром — и сразу на всех
            // вкладках, а не только на виноватой.
            //
            // GeometryReader сообщает наверх ровно предложенный размер и
            // никогда не размер своих детей, поэтому содержимое вкладок
            // физически не может раздуть оболочку. Явный .frame + маска по
            // ширине экрана обрезают вылезающее вбок: промах в вёрстке теперь
            // выглядит как обрезанная карточка на одном экране, а не как
            // поехавший интерфейс.
            //
            // Внимание: .frame(maxWidth: .infinity) здесь НЕ работает — он
            // задаёт нижнюю границу, а не верхнюю, и ребёнка шире предложенного
            // размера не ужимает.
            GeometryReader { geo in
                Group {
                    // ZStack with opacity — keeps all tabs alive, no recreation lag
                    V4HomeViewLive(
                        theme: theme,
                        searchStore: searchStore,
                        roomsStore: roomsStore,
                        openRoom: { openFirstRoom() },
                        liveThemeIndex: liveThemeIndex
                    )
                        .opacity(tab == 0 ? 1 : 0).allowsHitTesting(tab == 0)
                    V4RoomsViewLive(theme:theme, roomsStore:roomsStore, friendsStore:friendsStore, openRoom:{ room in openRoom(room) }, createRoom:{showCreateRoom=true}, joinByCode:{showJoinByCode=true})
                        .opacity(tab == 1 ? 1 : 0).allowsHitTesting(tab == 1)
                    V4FriendsViewLive(theme:theme, store:friendsStore, roomsStore: roomsStore, isActive: tab == 2)
                        .opacity(tab == 2 ? 1 : 0).allowsHitTesting(tab == 2)
                    // Вкладка «ИИ» — раздел целиком: лента трейлеров в
                    // превью-режиме, поверх неё онбординг со сферой и «Скоро»,
                    // и два рабочих входа — чат и голос. Разговор поднимается
                    // отдельным экраном (fullScreenCover ниже).
                    V4AIViewLive(theme: theme, store: aiStore, searchStore: searchStore, isActive: tab == 3)
                        .opacity(tab == 3 ? 1 : 0).allowsHitTesting(tab == 3)
                    // Настройки — не вкладка: шесть кнопок теснили таббар, а
                    // маршрут не ежедневный. Вход — строка «Общие настройки»
                    // на лице профиля, шитом (правка 22.08.2026).
                    V4ProfileViewLive(theme:theme, store:profileStore, showAppearance:$appearance)
                        .opacity(tab == 4 ? 1 : 0).allowsHitTesting(tab == 4)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                // Маска вместо .clipped(): гард всё так же срезает
                // горизонтальные вылеты (ширина маски = ширине экрана), но
                // не отрезает легальный полноэкранный фон вкладки под
                // статус-баром и home-индикатором. .clipped() упирался в
                // safe area, и у ленты «ИИ» фон обрывался ровно по линии
                // статус-бара — сверху просвечивал синий LivingBackground
                // жёсткой полосой «другого экрана».
                .mask {
                    Rectangle()
                        .frame(width: geo.size.width, height: geo.size.height + 400)
                }
                .animation(.easeInOut(duration: 0.15), value: tab)
            }
            VStack(spacing: 8) {
                // 25.08.2026 (T5): пока идёт вечер, над баром живёт капсула
                // «Сейчас смотрят» — вернуться в комнату одним тапом с любой
                // вкладки (модель мини-плеера Spotify/iOS 26 bottom accessory).
                // Прячется, когда комната уже открыта на весь экран.
                if let ongoing = ongoingRoom, roomToPresent == nil {
                    PlinkOngoingRoomCapsule(room: ongoing, theme: theme) {
                        openRoom(ongoing)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                PlinkLiquidTabBar(
                    selection: $tab,
                    theme: theme,
                    friendsUnread: DMChatService.shared.totalUnread
                )
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: ongoingRoom?.id)
            // Единый контракт нижней навигации: контент всех вкладок имеет
            // одинаковый резерв под floating tab bar + home indicator.
            // Раньше экраны вручную гадали 90/92/100 pt и расходились.
            .padding(.bottom, 2)
            if appearance { V4AppearanceView(theme:$theme,presented:$appearance).zIndex(25).transition(.opacity) }
        }.preferredColorScheme(.dark).tint(currentAccent)
        .task {
            if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) { theme = live.closestStandardTheme }
            // Комната читает акцент активной темы — единый стиль без прыжка дизайнов
            UserDefaults.standard.set(theme.rawValue, forKey: "plink.v4ThemeName")
            await bootstrap()
        }
        .onChange(of: theme) { _, newTheme in
            UserDefaults.standard.set(newTheme.rawValue, forKey: "plink.v4ThemeName")
            // Выбор темы уезжает PUT /api/profile/appearance
            // (кросс-девайс). Дедупликация и офлайн-деградация — внутри стора.
            AppearanceStore.shared.syncV4Theme(
                themeName: newTheme.rawValue,
                liveIndex: UserDefaults.standard.integer(forKey: "plink.liveTheme")
            )
        }
        // В фоне гасим DM-опрос / realtime и presence-пинги,
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
                // смена/сброс живой темы тоже уезжает на
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
        // Статическая тема, гидрированная с сервера при
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
        // 25.08.2026: карточка «Друзья» на лице профиля ведёт на вкладку
        // «Друзья» (VK-модель: счётчик друзей — это дверь, не цифра).
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("plinkOpenFriendsTab"))) { _ in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { tab = 2 }
        }
        // Разговор с ассистентом — поверхность над вкладками: его зовут и с
        // ленты «ИИ», и из поиска на «Главной».
        .onReceive(NotificationCenter.default.publisher(for: .plinkOpenAIChat)) { _ in
            aiChatAutoVoice = false
            showAIChat = true
        }
        // 03.08.2026: «спросить голосом» больше не отдельный экран — это тот же
        // чат с включённым микрофоном.
        .onReceive(NotificationCenter.default.publisher(for: .plinkOpenAIVoice)) { _ in
            aiChatAutoVoice = true
            showAIChat = true
        }

        core
        .fullScreenCover(isPresented: $showAIChat, onDismiss: { aiChatAutoVoice = false }) {
            V4AIChatView(theme: theme, store: aiStore, autoStartVoice: aiChatAutoVoice)
        }
        .sheet(isPresented: $showCreateRoom) {
            RoomCreationView(onRoomCreated: handleRoomCreated)
                .environmentObject(APIClient.shared)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showJoinByCode) {
            JoinRoomSheet(
                onJoined: { room in
                    showJoinByCode = false
                    roomToPresent = room
                },
                initialCode: joinPrefillCode,
                startWithPassword: joinStartWithPassword
            )
            .environmentObject(APIClient.shared)
            .preferredColorScheme(.dark)
            .onDisappear {
                joinPrefillCode = ""
                joinStartWithPassword = false
            }
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
            Text("Отправь другу код: \(lastSharedRoomCode ?? "")\n\nДруг: вкладка «Комнаты» → «Войти по коду» → ввести код.\nКод уже в буфере обмена.")
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
        // Deep links — комната открывается, заявка в друзья
        // подтверждается алертом. @Published отдаёт текущее значение при подписке,
        // так что ссылка, пришедшая до появления экрана, тоже обработается.
        .onReceive(DeepLinkRouter.shared.$pendingLink) { link in
            handleDeepLink(link)
        }
        .onReceive(DeepLinkRouter.shared.$pendingChat) { target in
            guard target != nil else { return }
            tab = 2
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
        .alert("Не удалось войти", isPresented: $showJoinError) {
            Button("ОК", role: .cancel) {
                showJoinError = false
                joinErrorMessage = nil
            }
        } message: {
            Text(joinErrorMessage ?? "")
        }
    }

    // MARK: - Deep Links

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
                    await MainActor.run {
                        HapticManager.errorOccurred()
                        if JoinRoomErrorCopy.isPasswordRequired(error) {
                            joinPrefillCode = code
                            joinStartWithPassword = true
                            showJoinByCode = true
                        } else {
                            joinErrorMessage = JoinRoomErrorCopy.message(for: error)
                            showJoinError = true
                        }
                    }
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

    /// Open the exact room the person selected, then join it for live presence.
    private func openRoom(_ room: Room) {
        Task {
            do {
                let joined = try await RoomService(api: APIClient.shared).joinRoom(code: room.code)
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

    /// Мой идущий вечер — источник капсулы над таббаром. Именно myRooms
    /// (fetchMyActiveRooms), а не heroRoom: героем может быть чужая комната,
    /// а капсула зовёт вернуться только в свою сессию.
    private var ongoingRoom: Room? {
        roomsStore?.myRooms.first(where: { $0.isActive && $0.participantCount > 0 })
    }

    /// Комната создана — общий финал для обоих входов в мастер.
    private func handleRoomCreated(_ newRoom: Room) {
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

    /// Quick Room — one-tap create from first trending video.
    // Здесь были quickCreateRoom() и вторая копия
    // createRoomFromTrending() — обе без единого вызова (живая копия — в
    // V4HomeViewLive). Удалены.


    private var currentAccent: Color {
        PlinkPlusLiveTheme.resolve(liveThemeIndex)?.accentColor ?? theme.accentColor
    }

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

        // 25.08.2026: загрузка сторов стартует СРАЗУ после их создания —
        // параллельно прелюдии ниже (профиль/тема/presence/бейджи), а не
        // после неё. Раньше «Вечера» и «Друзья» ждали всю серийную цепочку:
        // повисший fetchCurrentUser или presence-пинг держал вкладки в .idle
        // без единого пикселя контента, а на здоровой сети — тормозил их
        // на секунды. Токен уже восстановлен выше, так что этим запросам
        // прелюдия не нужна.
        let roomsTask = Task { await roomsStore?.load() }
        let friendsTask = Task { await friendsStore?.load() }
        let profileTask = Task { await profileStore?.load() }

        // Server is authority for isPremium + ADMIN role (e.g. koslakandrej@gmail.com)
        if api.authToken != nil {
            do {
                // Здесь был второй вызов syncFromServer с
                // expiry: nil. Теперь fetchCurrentUser() сам синхронизирует премиум
                // с серверной датой premiumUntil, и дубль только затирал бы её.
                let user = try await as_.fetchCurrentUser()
                profileStore?.applyUser(user)
            } catch {
                Logger.api.warn("[bootstrap] fetchCurrentUser: \(error.localizedDescription)")
            }
            // Гидрация оформления с сервера — тема/бабл
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
            // Заявки в друзья метят вкладку «Друзья» так же, как сообщения,
            // поэтому читаются в фоне всей оболочкой, а не самой вкладкой.
            FriendManager.shared.startRequestsPolling()
        }

        // 07.08.2026: раньше здесь стояли четыре последовательных await, и
        // searchStore.loadTrending() был шестым сетевым вызовом подряд —
        // баннеры на «Главной» ждали профиль, тему, presence, бейджи и
        // комнаты, около десяти секунд на живом устройстве.
        // Тренды переехали в .task самой «Главной» (грузятся сразу при
        // появлении экрана); загрузки сторов запущены выше, здесь только
        // дожидаемся их перед сбросом кэша аватарок.
        _ = await roomsTask.value
        _ = await friendsTask.value
        _ = await profileTask.value
        PlinkAvatarURL.bumpSessionBust()
    }
}

// MARK: - Friend Invite (deep link /u/<id>)

private struct V4FriendInvite: Identifiable {
    let id = UUID()
    let userId: String
    let username: String
}

// MARK: - Ongoing Room Capsule (T5)

/// Мини-плеер над таббаром: «вечер идёт — вернись одним тапом».
/// Слой, а не вкладка: виден с любого экрана, пока комната живая.
struct PlinkOngoingRoomCapsule: View {
    let room: Room
    var theme: V4Theme = .electric
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.impact(.medium)
            action()
        } label: {
            HStack(spacing: 11) {
                thumb
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(room.mediaItem?.title ?? room.name)
                        .font(.system(size: 12.5, weight: .heavy))
                        .foregroundStyle(V4.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(V4.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(theme.buttonTextColor)
                    .frame(width: 30, height: 30)
                    .background(theme.accentColor, in: Circle())
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 48)
            .plinkGlass(.navigation, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 26)
        .accessibilityLabel("Вернуться в комнату \(room.name)")
        .accessibilityHint(subtitle)
    }

    private var subtitle: String {
        let n = room.participantCount
        let word: String
        switch n % 100 {
        case 11...14: word = "человек"
        default:
            switch n % 10 {
            case 1: word = "человек"
            case 2...4: word = "человека"
            default: word = "человек"
            }
        }
        return "\(room.name) · \(n) \(word)"
    }

    private var thumb: some View {
        ZStack {
            let hue = Double(abs(room.id.hashValue) % 70) + 225
            LinearGradient(
                colors: [Color.oklch(0.58, 0.22, hue), Color.oklch(0.26, 0.14, hue + 35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let raw = room.mediaItem?.thumbnailURL, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
            }
            // Живой маркер поверх обложки — капсула сигналит «идёт сейчас».
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.5), radius: 3)
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

// MARK: - Liquid Glass Tab Bar

struct PlinkLiquidTabBar: View {
    @Binding var selection: Int
    var theme: V4Theme = .electric
    /// Unread DMs — red badge on «Друзья» tab when user is not in that chat.
    var friendsUnread: Int = 0
    @ObservedObject private var dmService = DMChatService.shared
    @ObservedObject private var friendManager = FriendManager.shared
    /// Ширина ряда вкладок — для пересчёта позиции пальца в индекс при ведении.
    @State private var barWidth: CGFloat = 0
    /// X пальца, пока он прижат к бару (nil — отпущен). Пока палец держит
    /// бар, пилюля выделения не перескакивает по слотам, а непрерывно едет
    /// за пальцем и слегка «приподнимается» — как ведение по бару в Telegram.
    /// Отпустил — пилюля пружиной садится в центр ближайшего слота.
    @State private var dragX: CGFloat? = nil
    private var activeSecondary: Color { let (_, c1, _, _) = theme.colors; return c1 }

    // M25 i18n: подписи через LocalizationManager (RU/EN/ZH).
    // 25.08.2026: вкладок пять. «Комнаты» = живые комнаты + история, «ИИ» — раздел
    // ленты с ассистентом. Друзья остаются на индексе 2:
    // plinkOpenFriendsTab/pendingChat шлют tab=2; ассистент — 3, профиль — 4.
    private var items: [(String, String)] {
        let l = LocalizationManager.shared
        return [
            ("house.fill", l.string(.tabHome)),
            ("play.rectangle.fill", l.string(.tabRooms)),
            ("person.2.fill", l.string(.tabFriends)),
            ("sparkles", l.string(.tabAI)),
            ("person.crop.circle.fill", l.string(.tabProfile))
        ]
    }

    /// Метка вкладки «Друзья» = непрочитанные личные + входящие заявки.
    /// friendsUnread и totalUnread — одно и то же число из двух рук, поэтому
    /// они берутся по максимуму, а заявки прибавляются: это отдельное
    /// событие, и без слагаемого о нём в баре не узнать.
    private var friendsBadge: Int {
        max(friendsUnread, dmService.totalUnread) + friendManager.incomingRequests.count
    }

    var body: some View {
        // Контейнер нужен, чтобы пилюля выделения на iOS 26 перетекала между
        // вкладками как единая масса стекла, а не гасла и зажигалась заново.
        PlinkGlassGroup(spacing: 16) {
            content
                .padding(.horizontal, 6)
                .frame(height: 64)
                .plinkGlass(.navigation, in: Capsule(style: .continuous))
        }
        .padding(.horizontal, 14)
        // ZStack уже учитывает bottom safe area. Дополнительные 8 pt
        // создавали риск наложения material на home indicator.
        .padding(.bottom, 2)
        .accessibilityElement(children: .contain)
    }

    private var content: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                Button {
                    select(index)
                } label: {
                    tabLabel(index)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("tab.\(index)")
                .accessibilityLabel(items[index].1)
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
        .background {
            // Пилюля выделения — ОДНА на весь бар, позиционируется числом,
            // а не matchedGeometryEffect по слотам: только так она может
            // встать между вкладками и непрерывно следовать за пальцем.
            GeometryReader { g in
                let W = g.size.width
                Capsule(style: .continuous)
                    .fill(activeSecondary.opacity(dragX == nil ? 0.20 : 0.28))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                activeSecondary.opacity(dragX == nil ? 0.30 : 0.44),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: activeSecondary.opacity(dragX == nil ? 0 : 0.26),
                        radius: 10, y: 3
                    )
                    .frame(width: slotWidth(W), height: 50)
                    // «Подъём» при зажатии: чуть крупнее, ярче и с тенью —
                    // палец чувствует, что схватил пилюлю.
                    .scaleEffect(dragX == nil ? 1 : 1.07)
                    .position(x: pillX(W), y: g.size.height / 2)
                    .onAppear { barWidth = W }
                    .onChange(of: W) { _, w in barWidth = w }
            }
        }
        // Ведение пальцем по бару (как в Telegram): зажал — пилюля
        // приподнялась и едет за пальцем, вкладки переключаются на лету при
        // пересечении слотов; отпустил — пилюля садится в ближайший слот.
        // Тап продолжает работать через Button (и остаётся доступным для
        // VoiceOver). simultaneousGesture: при обычном тапе жест выбирает ту
        // же вкладку, что и кнопка, — конфликт исключён.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragX == nil {
                        HapticManager.impact(.light)
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                            dragX = value.location.x
                        }
                    } else {
                        withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.88)) {
                            dragX = value.location.x
                        }
                    }
                    select(at: value.location.x)
                }
                .onEnded { value in
                    select(at: value.location.x)
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                        dragX = nil
                    }
                }
        )
    }

    // MARK: слот-геометрия (равные слоты по числу вкладок, spacing 2)

    private var slotSpacing: CGFloat { 2 }

    private func slotWidth(_ W: CGFloat) -> CGFloat {
        (W - slotSpacing * CGFloat(items.count - 1)) / CGFloat(items.count)
    }

    private func slotCenter(_ index: Int, in W: CGFloat) -> CGFloat {
        CGFloat(index) * (slotWidth(W) + slotSpacing) + slotWidth(W) / 2
    }

    /// Центр пилюли: под пальцем (с зажимом до краёв бара), иначе — центр
    /// выбранного слота.
    private func pillX(_ W: CGFloat) -> CGFloat {
        let half = slotWidth(W) / 2
        if let x = dragX { return min(max(x, half), W - half) }
        return slotCenter(selection, in: W)
    }

    /// Индекс из горизонтальной позиции пальца: слоты вкладок равной ширины.
    private func select(at x: CGFloat) {
        guard barWidth > 0 else { return }
        let span = slotWidth(barWidth) + slotSpacing
        select(min(items.count - 1, max(0, Int(x / span))))
    }

    private func select(_ index: Int) {
        guard index != selection else { return }
        HapticManager.selection()
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.26)) {
            selection = index
        }
    }

    @ViewBuilder
    private func tabLabel(_ index: Int) -> some View {
        let isSelected = selection == index

        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: items[index].0)
                    .font(.system(size: 17, weight: .semibold))
                    // Иконка выбранной вкладки слегка крупнее — вес выделения
                    // распределён между размером, цветом и подложкой, а не
                    // держится на одной заливке.
                    .scaleEffect(isSelected ? 1.06 : 1)
                // Tab 2 = Друзья — unread DM badge
                if index == 2, friendsBadge > 0 {
                    // Тот же V4CountBadge, что в шапках и строках: красный
                    // сигнал в приложении один и не зависит от темы.
                    V4CountBadge(count: friendsBadge, fontSize: 9)
                        .offset(x: 9, y: -6)
                }
            }
            Text(items[index].1)
                .font(.system(size: 9.5, weight: .semibold))
                .lineLimit(1)
                // Шесть слотов: «Настройки» на узких экранах ужимается,
                // а не обрезается многоточием.
                .minimumScaleFactor(0.8)
        }
        // 26.08.2026: активная вкладка белая, а не цвета темы. На тёплых
        // палитрах акцентная иконка ложилась на акцентную пилюлю поверх
        // акцентного фона — три оттенка одного цвета, выделение исчезало.
        // Тема остаётся пилюле (это фон), иконка и подпись — тот же белый,
        // что у главных кнопок приложения.
        .foregroundStyle(isSelected ? V4.ink : V4.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityIdentifier("tab.\(index).content")
    }
}

// MARK: - Notification Bell

struct NotificationInboxButton: View {
    let unreadCount: Int
    var theme: V4Theme = .electric
    let action: () -> Void

    var body: some View {
        // Единый набор вместо ручной сборки: раньше здесь были свои
        // Image(systemName:), своя подложка V4.roundBG и свой бейдж на
        // Color.accentColor — системном синем, не совпадающем с акцентом темы.
        V4GlyphButton(
            glyph: .bell,
            theme: theme,
            kind: .glass,
            diameter: 44,
            iconSize: 17,
            filled: unreadCount > 0,
            badge: unreadCount > 0 ? unreadCount : nil,
            accessibility: "Уведомления",
            action: action
        )
        .accessibilityValue(unreadCount == 0 ? "Нет новых" : "Новых: \(unreadCount)")
    }
}
