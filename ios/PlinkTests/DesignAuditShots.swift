// PlinkTests/DesignAuditShots.swift — offscreen renders of real screens for design review.
//
// This is NOT a regression test: nothing is compared pixel by pixel. The case builds
// live product screens with mock data and writes PNGs to disk, so the design can be
// judged by eye without driving the whole app by hand — room creation, service
// search, settings, the paywall, onboarding and the admin panel would otherwise each
// need a live backend and a paid account to reach.
//
// The mechanism and its limits are copied from MarketingShots.swift, which explains
// why the flag file lives in /tmp rather than ~/Desktop: under ~/Desktop, macOS TCC
// hangs the test on a system permission prompt that no one is there to answer.
//
// To run, from `ios/`:
//   xcodegen generate
//   echo /tmp/plink-audit-output > /tmp/plink-design-audit
//   xcodebuild test -scheme Plink \
//     -destination 'platform=iOS Simulator,name=iPhone 17' \
//     -only-testing:PlinkTests/DesignAuditShots
//   rm /tmp/plink-design-audit

import XCTest
import SwiftUI
import UIKit
@testable import Plink

@MainActor
final class DesignAuditShots: XCTestCase {

    private static let canvas = CGSize(width: 393, height: 852)
    private static let scale: CGFloat = 2
    private static let screenSafeArea = UIEdgeInsets(top: 44, left: 0, bottom: 20, right: 0)

    private static let flagFile = URL(fileURLWithPath: "/tmp/plink-design-audit")

    private static var flagContents: String? {
        guard let raw = try? String(contentsOf: flagFile, encoding: .utf8) else { return nil }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["DESIGN_AUDIT"] == "1" { return true }
        return flagContents != nil
    }

    private func requireEnabled() throws {
        try XCTSkipUnless(
            Self.isEnabled,
            "Audit frames are captured on demand: set DESIGN_AUDIT=1 or create the file /tmp/plink-design-audit."
        )
    }

    private var outputDirectory: URL {
        if let env = ProcessInfo.processInfo.environment["DESIGN_AUDIT_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        if let flag = Self.flagContents, !flag.isEmpty {
            return URL(fileURLWithPath: flag, isDirectory: true)
        }
        return URL(fileURLWithPath: "/tmp/plink-audit-output", isDirectory: true)
    }

    override func setUp() async throws {
        try await super.setUp()
        guard Self.isEnabled else { return }
        LocalizationManager.shared.currentLanguage = .russian
    }

    // MARK: - Screens

    func testRoomCreationShot() throws {
        try requireEnabled()
        try shoot(RoomCreationView(), named: "01-room-creation")
    }

    func testServiceBrowserShot() throws {
        try requireEnabled()
        try shoot(
            ServiceBrowserView(service: .youtube, onCreateRoom: { _, _ in }),
            named: "02-service-browser"
        )
    }

    func testPaywallShot() throws {
        try requireEnabled()
        try shoot(PlinkPlusPaywall(trigger: .theme), named: "03-paywall")
    }

    func testOnboardingShot() throws {
        try requireEnabled()
        try shoot(OnboardingFlow(onFinish: {}, onSkip: {}), named: "04-onboarding")
    }

    /// The second and third onboarding screens. A swipe cannot be reproduced in an
    /// offscreen render, so the scenes are captured directly.
    func testOnboardingScenesShot() throws {
        try requireEnabled()
        try shoot(OnboardingScene(page: .rooms), named: "04b-onboarding-rooms")
        try shoot(OnboardingScene(page: .chats), named: "04c-onboarding-chats")
    }

    /// Стена первого экрана с настоящими постерами. В симуляторе под VPN без
    /// DNS URLSession не резолвит api.ivi.ru, поэтому постеры для кадра
    /// скачивает хост в каталог из DESIGN_AUDIT_POSTERS (по умолчанию
    /// /tmp/plink-posters), а стена получает их как file://-ссылки через
    /// `OnboardingCatalogWall.posterSource`. Вёрстка и AsyncImage — те же, что
    /// в проде; отличается только транспорт.
    func testOnboardingWallPostersShot() throws {
        try requireEnabled()
        let env = ProcessInfo.processInfo.environment["DESIGN_AUDIT_POSTERS"] ?? ""
        let directory = URL(fileURLWithPath: env.isEmpty ? "/tmp/plink-posters" : env, isDirectory: true)
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try XCTSkipIf(files.isEmpty, "No posters in \(directory.path): download them on the host first.")

        let live = OnboardingCatalogWall.posterSource
        OnboardingCatalogWall.posterSource = { files }
        defer { OnboardingCatalogWall.posterSource = live }
        try shoot(OnboardingScene(page: .catalog), named: "04a-onboarding-wall-posters")
    }

    func testAppearanceShot() throws {
        try requireEnabled()
        try shoot(
            AppearanceHost(),
            named: "05-appearance"
        )
    }


    func testIdentityRingsShot() throws {
        try requireEnabled()
        try shoot(IdentityRingsBoard(), named: "06-identity-rings")
    }


    func testFriendsShot() throws {
        try requireEnabled()
        try shoot(
            V4FriendsViewLive(theme: .electric, store: nil, roomsStore: nil, isActive: true),
            named: "07-friends"
        )
    }

    /// The whole Home screen — the only way to see it without a live backend: the
    /// funnel UI test signs up first, and signup needs a database.
    func testHomeShot() throws {
        try requireEnabled()
        try shoot(
            V4HomeViewLive(
                theme: .electric,
                searchStore: V4SearchStore(),
                roomsStore: nil,
                openRoom: {}
            ),
            named: "08-home"
        )
    }

    /// Два класса устройств рядом. На реальном 17 Pro `displayScale` равен 3
    /// и классику иначе не увидеть: снимок принуждает класс через окружение.
    ///
    /// Кадр судит ФОН: слева два размытия по 0,6 радиуса и 20 кадров в
    /// секунду, справа три полных размытия и 30. Стекло чипов на этом
    /// снимке одинаковое, и так и должно быть — симулятор идёт по нативному
    /// пути iOS 26, а плотность подложки и кромка правятся только в ручной
    /// аппроксимации для iOS 17–25 (её знобы проверены в ThemeRegressionTests).
    func testDeviceTierShot() throws {
        try requireEnabled()
        try shoot(
            HStack(spacing: 0) {
                ForEach([PlinkDeviceTier.classic, .modern], id: \.self) { tier in
                    ZStack {
                        PlinkShellBackground(glowCenter: UnitPoint(x: 0.5, y: 0.34))
                        VStack(spacing: 18) {
                            Text(tier == .classic ? "classic · 2× LCD" : "modern · 3× OLED")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                            PlinkBrandMark(size: 56)
                            Text("Смотреть вместе")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .plinkGlass(.navigation)
                            Text("Панель поверх кадра")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .padding(12)
                                .plinkGlass(.overlay, cornerRadius: 16)
                        }
                        .padding(.horizontal, 10)
                    }
                    .environment(\.plinkDeviceTierOverride, tier)
                }
            },
            named: "21-device-tier"
        )
    }

    /// Сплэш целиком — первый кадр продукта. Виден живьём меньше секунды,
    /// поэтому судить его по глазам без офскрин-рендера нечем.
    func testSplashShot() throws {
        try requireEnabled()
        try shoot(PlinkSplashView(), named: "18-splash")
    }

    /// Марка сервиса на герое — крупным планом, три случая сразу: кинотеатр
    /// с абстрактным знаком (PREMIER), кинотеатр со словесным знаком, где
    /// подпись обязана исчезнуть (Netflix), и ролик, где подпись несёт имя
    /// канала, а не бренда (YouTube). Судить бейдж по общему кадру витрины
    /// нечем: он там 24 pt высотой.
    func testHeroProviderBadgeShot() throws {
        try requireEnabled()
        try shoot(
            VStack(spacing: 12) {
                V4Hero(title: "Ронин", meta: "2020 · Шоу", button: "Смотреть вместе",
                       height: 250, theme: .electric, action: {},
                       provider: "PREMIER", service: .premier)
                V4Hero(title: "Очень странные дела", meta: "2016 · Сериал · ★ 8,4",
                       button: "Смотреть вместе", height: 250, theme: .electric,
                       action: {}, provider: "Netflix", service: .netflix)
                V4Hero(title: "Как устроен объектив", meta: "18:04", button: "Смотреть вместе",
                       height: 250, theme: .electric, action: {},
                       provider: "Кинематограф", service: .youtube)
            }
            .padding(.horizontal, 13),
            named: "19-hero-badge"
        )
    }

    /// Марка сервиса на светлом кадре. Бейдж лишился плашки, и читаемость
    /// подписи теперь держит ореол из теней — а проверить его можно только
    /// над белым: на градиенте-заглушке героя фон и так тёмный. Скрим 0,43 —
    /// значение градиента героя на той высоте, где стоит марка.
    func testProviderMarkOnBrightFrameShot() throws {
        try requireEnabled()
        let cases: [(String, Color, Double)] = [
            ("белый кадр без скрима", .white, 0.0),
            ("белый кадр под скримом героя", .white, 0.43),
            ("светло-серый под скримом", Color(white: 0.72), 0.43),
            ("тёмный кадр под скримом", Color(white: 0.18), 0.43)
        ]
        try shoot(
            VStack(spacing: 0) {
                ForEach(Array(cases.enumerated()), id: \.offset) { _, c in
                    ZStack(alignment: .leading) {
                        c.1
                        Color.black.opacity(c.2)
                        HStack(spacing: 18) {
                            V4ProviderMark(provider: "PREMIER", service: .premier)
                            V4ProviderMark(provider: "Netflix", service: .netflix)
                            V4ProviderMark(provider: "Кинематограф", service: .youtube)
                        }
                        .padding(.horizontal, 19)
                    }
                    .frame(height: 106)
                }
            },
            named: "20-provider-mark-bright"
        )
    }

    // MARK: - Sign-in and first launch
    //
    // These frames exist so a redesign can be judged by eye: the funnel UI test does
    // reach the sign-in screens, but going past them needs a live database.

    /// Sign-in — the default mode of the combined screen.
    func testAuthSignInShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(onAuthenticated: {})
                .environmentObject(APIClient.shared),
            named: "10-auth-signin"
        )
    }

    /// Sign-up — the same screen with the toggle in the other position.
    func testAuthSignUpShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(initialMode: .signUp, onAuthenticated: {})
                .environmentObject(APIClient.shared),
            named: "11-auth-signup"
        )
    }

    /// Sign-up, filled — the frame where the username field, the live password rule
    /// and the «Регистрация через Apple» caption can all be judged at once. The empty
    /// sign-up frame shows none of them in their satisfied state.
    func testAuthSignUpFilledShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(
                initialMode: .signUp,
                prefilledEmail: "kira@plink.app",
                prefilledPassword: "sunset42",
                revealPassword: true,
                prefilledUsername: "kiravolkova",
                onAuthenticated: {}
            )
            .environmentObject(APIClient.shared),
            named: "11b-auth-signup-filled"
        )
    }

    /// Sign-in, filled — the primary button in its active state. The empty form is
    /// visible in 10-auth-signin, but a user spends most of their time looking at the
    /// filled one, so button contrast has to be judged on this frame.
    func testAuthFilledShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(
                prefilledEmail: "kira@plink.app",
                prefilledPassword: "sunset42",
                revealPassword: true,
                onAuthenticated: {}
            )
            .environmentObject(APIClient.shared),
            named: "12-auth-filled"
        )
    }

    /// The sign-in screen carrying an expired-session notice.
    func testAuthSessionNoticeShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(
                sessionMessage: "Сессия истекла. Войдите заново — это защищает ваш аккаунт.",
                onAuthenticated: {}
            )
            .environmentObject(APIClient.shared),
            named: "13-auth-session-notice"
        )
    }

    // MARK: Accessibility
    //
    // The sign-in background is six layers (a mosaic of frames, a light beam, grain),
    // and every one of them must switch off under Reduce Transparency / Reduce Motion.
    // This is exactly the kind of code that breaks silently: the ordinary frames look
    // fine, while somebody with the setting enabled gets either mush or an empty black
    // screen. Hence both states are captured separately.

    /// Reduce Transparency: the mosaic, beam and grain must go; the base and vignette
    /// must stay. The screen must be neither empty nor transparent.
    func testAuthReduceTransparencyShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(
                prefilledEmail: "kira@plink.app",
                prefilledPassword: "sunset42",
                revealPassword: true,
                onAuthenticated: {}
            )
            .environmentObject(APIClient.shared)
            .environment(
                \.plinkAccessibilityOverride,
                PlinkAccessibilityOverride(reduceTransparency: true)
            ),
            named: "14-auth-reduce-transparency"
        )
    }

    /// Reduce Motion: the mosaic becomes a static frame (no TimelineView) but stays
    /// where it is — the movement goes away, the picture does not.
    func testAuthReduceMotionShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(
                prefilledEmail: "kira@plink.app",
                prefilledPassword: "sunset42",
                revealPassword: true,
                onAuthenticated: {}
            )
            .environmentObject(APIClient.shared)
            .environment(
                \.plinkAccessibilityOverride,
                PlinkAccessibilityOverride(reduceMotion: true)
            ),
            named: "15-auth-reduce-motion"
        )
    }

    /// Large Dynamic Type: the fields and the button use minHeight rather than a
    /// fixed height — this checks that labels are not clipped.
    func testAuthLargeTypeShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(
                prefilledEmail: "kira@plink.app",
                prefilledPassword: "sunset42",
                revealPassword: true,
                onAuthenticated: {}
            )
            .environmentObject(APIClient.shared)
            .environment(\.dynamicTypeSize, .accessibility2),
            named: "16-auth-large-type"
        )
    }

    /// Хром плеера в обоих вариантах. Кадр нужен именно оффскрином: в
    /// симуляторе комната не доезжает до первого пикселя видео (VPN режет
    /// хосты потоков), а перевернуть его в ландшафт из командной строки
    /// нечем — то есть глазами эту раскладку иначе не увидеть.
    func testPlayerChromeShot() throws {
        try requireEnabled()
        try shoot(
            PlayerChromeBoard(variant: .portrait, model: makePlayerModel()),
            named: "17-player-chrome-portrait",
            canvas: CGSize(width: 393, height: 221),
            safeArea: .zero
        )
        try shoot(
            PlayerChromeBoard(variant: .landscape, model: makePlayerModel(),
                              safeArea: Self.landscapeSafeArea),
            named: "17b-player-chrome-landscape",
            canvas: CGSize(width: 852, height: 393),
            safeArea: UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59)
        )
        // Тот же ландшафт с открытым ящиком чата. Именно здесь ломалось:
        // полоса перемотки и кнопки звука/полного экрана уходили под ящик.
        try shoot(
            PlayerChromeBoard(variant: .landscape, model: makePlayerModel(),
                              drawerVisible: true, safeArea: Self.landscapeSafeArea),
            named: "17c-player-chrome-landscape-drawer",
            canvas: CGSize(width: 852, height: 393),
            safeArea: UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59)
        )
    }

    // MARK: - Очередь и голосования (пункты 11, 12, 20)

    /// Панель очереди комнаты — на снимке оба её состояния. Отзыв говорил
    /// «окно очереди максимально дешёвое», правка заменила системный `List`
    /// с серыми ячейками на карточки, и проверить это можно было только
    /// глазами: живая комната требует бэкенда, двух устройств и роли хоста.
    func testRoomQueueShot() throws {
        try requireEnabled()
        let host = makePlayerModel()
        host.designSeed(queue: Self.auditQueue)
        try shoot(RoomQueueSheet(model: host), named: "22-room-queue-host")

        // Гостю не показываем ни ручек перетаскивания, ни «включить» — те же
        // права на сервере, поэтому кнопки не должны даже появляться.
        let guest = makeGuestModel()
        guest.designSeed(queue: Self.auditQueue)
        try shoot(RoomQueueSheet(model: guest), named: "22b-room-queue-guest")

        // Пустое состояние: три призрачных слота вместо надписи в пустоте.
        try shoot(RoomQueueSheet(model: makePlayerModel()), named: "22c-room-queue-empty")
    }

    /// Карточка голосования поверх кадра: открытая (свой голос отдан),
    /// открытая без голоса и закрытая с победителем. Раньше это была серая
    /// полоска на 18 % белого — «дешёвое и несовременное» окно из отзыва.
    func testRoomPollShot() throws {
        try requireEnabled()
        try shoot(
            PollBoard(polls: [Self.auditPoll(voted: true), Self.auditPoll(voted: false)]),
            named: "23-room-poll-open",
            canvas: CGSize(width: 393, height: 620),
            safeArea: .zero
        )
        try shoot(
            PollBoard(polls: [Self.auditPoll(voted: true, closed: true)]),
            named: "23b-room-poll-closed",
            canvas: CGSize(width: 393, height: 340),
            safeArea: .zero
        )
    }

    /// Конструктор опроса — лист, который открывается кнопкой «Голосование».
    func testPollComposerShot() throws {
        try requireEnabled()
        try shoot(PollComposerSheet(onCreate: { _, _ in }), named: "24-poll-composer")
    }

    /// Очередь из шести элементов: один играет, дальше разные сервисы и
    /// приоритетный элемент Plink+ — чтобы на снимке было видно все значки.
    private static let auditQueue: [RoomQueueWire.Item] = {
        let base: Double = 1_756_000_000_000
        let rows: [(String, String, String, String, Bool)] = [
            ("q1", "Большой кролик Бак", "youtube", "Аня", false),
            ("q2", "Слёзы стали", "vk", "Я", false),
            ("q3", "Сквозь снег — первый сезон", "rutube", "Марк", true),
            ("q4", "Интерстеллар", "ivi", "Аня", false),
            ("q5", "Кто подставил кролика Роджера", "youtube", "Лёша", false),
            ("q6", "Догвилль", "vk", "Марк", false)
        ]
        return rows.enumerated().map { index, row in
            RoomQueueWire.Item(
                id: row.0,
                title: row.1,
                streamURL: "https://example.invalid/\(row.0)",
                source: row.2,
                addedBy: row.3,
                addedAtMs: base + Double(index) * 60_000,
                priority: row.4 ? true : nil
            )
        }
    }()

    private static func auditPoll(voted: Bool, closed: Bool = false) -> RoomPollState {
        var poll = RoomPollState(
            id: "poll-audit",
            question: "Что смотрим дальше?",
            options: ["Сквозь снег", "Интерстеллар", "Ещё один эпизод"],
            createdBy: "u-anya",
            createdByName: "Аня"
        )
        poll.votes = ["u-anya": 1, "u-mark": 1, "u-lesha": 0]
        if voted { poll.votes["u-me"] = 1 }
        poll.isClosed = closed
        return poll
    }

    /// Тот же гость, что и хост, только без роли: права в панели очереди
    /// решает `isHost`, и снимок обязан показать оба варианта.
    private func makeGuestModel() -> WatchRoomModel {
        let model = WatchRoomModel(
            roomId: "room-audit",
            currentUserId: "u-me",
            currentUsername: "Я",
            baseEndpoint: URL(string: "ws://127.0.0.1:9/ws")!,
            ticketProvider: { _ in throw URLError(.cannotConnectToHost) },
            roomCode: "PLNK42",
            mediaTitle: "Большой кролик Бак",
            roomHostId: "u-anya"
        )
        model.sessionDidConnect(role: .viewer)
        return model
    }

    /// Карточки голосования лежат на светлом кадре: они обязаны читаться
    /// поверх картинки, а не только на чёрном фоне листа.
    private struct PollBoard: View {
        let polls: [RoomPollState]

        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.34, green: 0.30, blue: 0.42),
                             Color(red: 0.68, green: 0.62, blue: 0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 18) {
                    ForEach(Array(polls.enumerated()), id: \.offset) { _, poll in
                        RoomPollCard(
                            poll: poll,
                            myUserId: "u-me",
                            canClose: true,
                            onVote: { _ in },
                            onClose: {},
                            onDismiss: {}
                        )
                    }
                }
                .padding(20)
            }
            .ignoresSafeArea()
        }
    }

    /// Числа отступов хрома — из продакшн-хелпера, тем же вызовом, что и в
    /// `LandscapeWatchLayout`. Картинка показывает результат, этот тест
    /// фиксирует правило.
    /// Вырез iPhone 17 Pro в ландшафте и домашняя полоса.
    private static let landscapeSafeArea = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)

    func testLandscapeChromeInsetsClearNotchAndDrawer() {
        let safe = Self.landscapeSafeArea

        let closed = WatchLandscapeMetrics.chromeInsets(
            canvasWidth: 852, safeArea: safe, drawerVisible: false
        )
        XCTAssertEqual(closed.leading, 59)
        XCTAssertEqual(closed.trailing, 59)
        XCTAssertEqual(closed.bottom, 21)

        let opened = WatchLandscapeMetrics.chromeInsets(
            canvasWidth: 852, safeArea: safe, drawerVisible: true
        )
        XCTAssertEqual(opened.leading, 59)
        XCTAssertEqual(opened.bottom, 21)
        // Ящик ПЛЮС вырез: ящик доходит до физического края и накрывает
        // вырез своей полосой, поэтому хром отступает на сумму.
        XCTAssertEqual(opened.trailing,
                       WatchLandscapeMetrics.drawerWidth(for: 852) + safe.trailing)
        XCTAssertGreaterThanOrEqual(opened.trailing, 59)
    }

    private func makePlayerModel() -> WatchRoomModel {
        let model = WatchRoomModel(
            roomId: "room-audit",
            currentUserId: "u-me",
            currentUsername: "Я",
            baseEndpoint: URL(string: "ws://127.0.0.1:9/ws")!,
            ticketProvider: { _ in throw URLError(.cannotConnectToHost) },
            roomCode: "PLNK42",
            mediaTitle: "Большой кролик Бак",
            roomHostId: "u-me"
        )
        model.sessionDidConnect(role: .host)
        return model
    }

    /// Сам кадр видео подменён ровной заливкой: проверяется расстановка хрома,
    /// а не декодер.
    private struct PlayerChromeBoard: View {
        let variant: WatchRoomLayoutState.Variant
        let model: WatchRoomModel
        var drawerVisible = false
        /// Вырез и домашняя полоса приходят числом: корневой `.frame()` в
        /// `shoot` съедает `additionalSafeAreaInsets`, и GeometryReader внутри
        /// кадра увидел бы нули. На устройстве их читает сам
        /// `LandscapeWatchLayout` — здесь важна геометрия результата.
        var safeArea = EdgeInsets()
        @State private var ui: WatchRoomUIState

        init(variant: WatchRoomLayoutState.Variant,
             model: WatchRoomModel,
             drawerVisible: Bool = false,
             safeArea: EdgeInsets = EdgeInsets()) {
            self.variant = variant
            self.model = model
            self.drawerVisible = drawerVisible
            self.safeArea = safeArea
            // Состояние ящика должно совпадать с тем, что рисуем: иначе
            // переключатель чата в нижней панели показывает не тот значок.
            var state = WatchRoomUIState()
            state.chatDrawerVisible = drawerVisible
            _ui = State(initialValue: state)
        }

        var body: some View {
            GeometryReader { proxy in
                // Композиция как в LandscapeWatchLayout: кадр во весь экран,
                // хром — с отступами из того же продакшн-хелпера, ящик чата
                // поверх справа.
                let insets = variant == .landscape
                    ? WatchLandscapeMetrics.chromeInsets(
                        canvasWidth: proxy.size.width,
                        safeArea: safeArea,
                        drawerVisible: drawerVisible
                    )
                    : EdgeInsets()
                ZStack(alignment: .trailing) {
                    LinearGradient(
                        colors: [Color(red: 0.16, green: 0.10, blue: 0.28), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    PlayerTopChrome(model: model, variant: variant,
                                    mediaTitle: model.mediaTitle, chromeInsets: insets)
                    PlinkPlayerControls(model: model, ui: $ui, variant: variant,
                                        chromeInsets: insets)
                    if drawerVisible {
                        LandscapeChatDrawer(
                            model: model,
                            isVisible: .constant(true),
                            containerWidth: proxy.size.width,
                            safeArea: safeArea
                        )
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Infrastructure


    /// A showcase of the tiers: rings, badges and chips side by side, so the system
    /// can be seen whole rather than one screen at a time.
    ///
    /// The labels below stay Russian on purpose — they are rendered into the frame,
    /// and these screenshots are reviewed as the Russian-language product.
    private struct IdentityRingsBoard: View {
        private let levels: [(Bool, Bool, String)] = [
            (false, false, "Обычный"),
            (true, false, "Админ"),
            (false, true, "Plink+"),
            (true, true, "Админ + Plink+")
        ]

        var body: some View {
            VStack(spacing: 30) {
                Text("Кольца и бейджи")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(V4.ink)

                HStack(spacing: 20) {
                    ForEach(levels, id: \.2) { admin, plus, label in
                        VStack(spacing: 10) {
                            PlinkIdentityAvatar(
                                diameter: 64,
                                isAdmin: admin,
                                isPremium: plus,
                                isOnline: true
                            ) {
                                Circle().fill(V4.raised).overlay(
                                    Text("А").font(.system(size: 24, weight: .bold))
                                        .foregroundStyle(V4.ink)
                                )
                            }
                            Text(label)
                                .font(.system(size: 10))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(V4.muted)
                                .frame(width: 76)
                        }
                    }
                }

                HStack(spacing: 10) {
                    PlinkIdentityChip(kind: .admin)
                    PlinkIdentityChip(kind: .plus)
                    PlinkIdentityChip(kind: .verified)
                    LiveBadge()
                }

                HStack(spacing: 18) {
                    ForEach([28.0, 40.0, 56.0], id: \.self) { d in
                        PlinkIdentityAvatar(
                            diameter: d,
                            isAdmin: false,
                            isPremium: true
                        ) {
                            Circle().fill(V4.raised)
                        }
                    }
                }

                Spacer()
            }
            .padding(.top, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(V4.canvas)
        }
    }

    /// `V4AppearanceView` needs bindings, so wrap it in a state holder.
    private struct AppearanceHost: View {
        @State private var theme: V4Theme = .electric
        @State private var presented = true
        var body: some View {
            V4AppearanceView(theme: $theme, presented: $presented)
        }
    }

    private func shoot<V: View>(_ view: V, named name: String) throws {
        try shoot(view, named: name, canvas: Self.canvas, safeArea: Self.screenSafeArea)
    }

    private func shoot<V: View>(
        _ view: V,
        named name: String,
        canvas: CGSize,
        safeArea: UIEdgeInsets
    ) throws {
        let window: UIWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
            .map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(origin: .zero, size: canvas))

        window.frame = CGRect(origin: .zero, size: canvas)
        window.backgroundColor = .black
        window.overrideUserInterfaceStyle = .dark
        window.windowLevel = .normal + 10

        // РАЗМЕР ЗАДАЁТ ОКНО, А НЕ .frame НА КОРНЕ (правка 04.09.2026).
        //
        // Было `.frame(width:height:)` на rootView — и это глушило безопасную
        // зону: проба внутри стенда печатала `height=852, insets top=21,
        // bottom=0` вместо заданных 44/20. То есть КАЖДЫЙ кадр аудита рисовался
        // на холсте на 64 pt щедрее настоящего экрана, а зазор под домашним
        // индикатором не проверялся ни разу — при том что футер экрана входа
        // уже один раз обрезался именно там.
        //
        // Теперь размер приходит от `host.view.frame = window.bounds` (ниже),
        // а `additionalSafeAreaInsets` доводит вставки до 44/20. Кадры стали
        // строже: то, что раньше «влезало», теперь обязано влезать честно.
        let host = UIHostingController(
            rootView: view
                .preferredColorScheme(.dark)
                .environment(\.colorScheme, .dark)
                // Animations off: the render has to be deterministic.
                .environment(\.plinkFreezeAnimations, true)
                .transaction { $0.disablesAnimations = true }
        )
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .black
        window.rootViewController = host

        window.isHidden = false
        window.makeKeyAndVisible()
        host.view.frame = window.bounds

        let ambient = host.view.safeAreaInsets
        host.additionalSafeAreaInsets = UIEdgeInsets(
            top: max(0, safeArea.top - ambient.top),
            left: max(0, safeArea.left - ambient.left),
            bottom: max(0, safeArea.bottom - ambient.bottom),
            right: max(0, safeArea.right - ambient.right)
        )
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Let SwiftUI run .task/.onAppear. A nested RunLoop is wrong here — it holds
        // the main thread (see MarketingShots).
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        CATransaction.flush()

        let format = UIGraphicsImageRendererFormat()
        format.scale = Self.scale
        format.opaque = true
        let bounds = CGRect(origin: .zero, size: canvas)

        func render() -> UIImage {
            UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
                UIColor.black.setFill()
                ctx.fill(bounds)
                host.view.drawHierarchy(in: bounds, afterScreenUpdates: false)
            }
        }

        // One render, with no "wait for it to settle" loop. Both alternatives were
        // tried here and both were worse, which is why this looks too simple:
        //
        //   - A fixed 1.2s pause. The screen animates in on a 0.62s spring, and roughly
        //     every third frame captured mid-transition. It read as a real regression —
        //     "the button went dark, the logo faded" — when nothing had changed.
        //   - A "render until two frames match" loop. Worse: the background animates
        //     FOREVER, so the frames never converge, the loop ran to its ceiling, and
        //     repeated `drawHierarchy` calls in one pass sometimes returned an empty
        //     image — a frame with no form and no logo at all.
        //
        // The answer is not to outwait the animations but to switch them off:
        // `plinkFreezeAnimations` puts the scene straight into its final state. One
        // render is then enough, and the result is reproducible byte for byte.
        let image = render()

        guard let data = image.pngData() else {
            XCTFail("Could not encode PNG for \(name)")
            return
        }
        let directory = outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(name).png")
        try data.write(to: file, options: .atomic)
        print("AUDIT_SHOT \(file.path) \(data.count) bytes")

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
