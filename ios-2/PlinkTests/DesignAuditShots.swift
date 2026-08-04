// PlinkTests/DesignAuditShots.swift — офскрин-рендер экранов для дизайн-аудита.
//
// Это НЕ регрессионный тест: ничего не проверяется пиксельно. Кейс собирает
// живые продуктовые экраны с моковыми данными и складывает PNG на диск, чтобы
// оценивать дизайн глазами, не проходя всё приложение руками (создание
// комнаты, поиск сервисов, настройки, пейволл, онбординг и админку иначе
// пришлось бы открывать через живой бэкенд и платный аккаунт).
//
// Устройство и ограничения скопированы с MarketingShots.swift — там же
// объяснено, почему флаг лежит в /tmp, а не в ~/Desktop (TCC подвешивает
// тест на системном запросе доступа).
//
// Запуск:
//   cd ios-2 && xcodegen generate
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
            "Кадры аудита снимаются по требованию: DESIGN_AUDIT=1 или файл /tmp/plink-design-audit."
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

    // MARK: - Экраны

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

    /// Второй и третий экраны онбординга. Свайп в офскрин-рендере не
    /// воспроизвести, поэтому сцены снимаются напрямую.
    func testOnboardingScenesShot() throws {
        try requireEnabled()
        try shoot(OnboardingScenePreview(page: 1), named: "04b-onboarding-reels")
        try shoot(OnboardingScenePreview(page: 2), named: "04c-onboarding-ai")
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

    /// «Главная» целиком — единственный способ посмотреть её без живого
    /// бэкенда: UI-тест воронки сначала проходит регистрацию, а она требует
    /// базу данных.
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

    // MARK: - Вход и первый запуск
    //
    // Эти кадры нужны, чтобы судить о редизайне глазами: UI-тест воронки до
    // экранов входа доходит, но дальше требует живую базу данных.

    /// Вход — режим по умолчанию единого экрана.
    func testAuthSignInShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(onAuthenticated: {})
                .environmentObject(APIClient.shared),
            named: "10-auth-signin"
        )
    }

    /// Регистрация — тот же экран с переключателем в другом положении.
    func testAuthSignUpShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(initialMode: .signUp, onAuthenticated: {})
                .environmentObject(APIClient.shared),
            named: "11-auth-signup"
        )
    }

    /// Заполненный вход — активная главная кнопка. Пустую форму видно на
    /// 10-auth-signin, но пользователь бо́льшую часть времени смотрит на
    /// заполненную, и судить о контрасте кнопки надо по ней.
    func testAuthFilledShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(
                prefilledEmail: "kira@plink.app",
                prefilledPassword: "sunset42",
                onAuthenticated: {}
            )
            .environmentObject(APIClient.shared),
            named: "12-auth-filled"
        )
    }

    /// Экран входа с сообщением об истёкшей сессии.
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

    // MARK: Доступность
    //
    // Фон входа собран из шести слоёв (мозаика кадров, луч, зерно), и каждый
    // из них при Reduce Transparency / Reduce Motion обязан отключиться. Это
    // ровно тот код, который ломается молча: обычные кадры выглядят
    // нормально, а человек с включённой настройкой получает либо кашу, либо
    // пустой чёрный экран. Поэтому оба состояния снимаются отдельно.

    /// Reduce Transparency: мозаика, луч и зерно должны уйти, база и виньетка
    /// остаться. Экран обязан быть НЕ пустым и НЕ прозрачным.
    func testAuthReduceTransparencyShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(
                prefilledEmail: "kira@plink.app",
                prefilledPassword: "sunset42",
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

    /// Reduce Motion: мозаика встаёт статичным кадром (без TimelineView),
    /// но остаётся на месте — движение убирается, картинка нет.
    func testAuthReduceMotionShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(
                prefilledEmail: "kira@plink.app",
                prefilledPassword: "sunset42",
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

    /// Крупный Dynamic Type: у полей и кнопки minHeight вместо фиксированной
    /// высоты — проверяем, что подписи не обрезаются.
    func testAuthLargeTypeShot() throws {
        try requireEnabled()
        try shoot(
            PlinkAuthScreen(
                prefilledEmail: "kira@plink.app",
                prefilledPassword: "sunset42",
                onAuthenticated: {}
            )
            .environmentObject(APIClient.shared)
            .environment(\.dynamicTypeSize, .accessibility2),
            named: "16-auth-large-type"
        )
    }

    // MARK: - Инфраструктура


    /// Витрина уровней: кольца, бейджи и чипы рядом, чтобы видеть систему
    /// целиком, а не по одному экрану.
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

    /// `V4AppearanceView` требует биндингов — оборачиваем в держатель состояния.
    private struct AppearanceHost: View {
        @State private var theme: V4Theme = .electric
        @State private var presented = true
        var body: some View {
            V4AppearanceView(theme: $theme, presented: $presented)
        }
    }

    private func shoot<V: View>(_ view: V, named name: String) throws {
        let window: UIWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
            .map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(origin: .zero, size: Self.canvas))

        window.frame = CGRect(origin: .zero, size: Self.canvas)
        window.backgroundColor = .black
        window.overrideUserInterfaceStyle = .dark
        window.windowLevel = .normal + 10

        let host = UIHostingController(
            rootView: view
                .frame(width: Self.canvas.width, height: Self.canvas.height)
                .preferredColorScheme(.dark)
                .environment(\.colorScheme, .dark)
        )
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .black
        window.rootViewController = host

        window.isHidden = false
        window.makeKeyAndVisible()
        host.view.frame = window.bounds

        let ambient = host.view.safeAreaInsets
        host.additionalSafeAreaInsets = UIEdgeInsets(
            top: max(0, Self.screenSafeArea.top - ambient.top),
            left: 0,
            bottom: max(0, Self.screenSafeArea.bottom - ambient.bottom),
            right: 0
        )
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Даём SwiftUI прогнать .task/.onAppear. Вложенный RunLoop здесь не
        // подходит — он держит главный поток (см. MarketingShots).
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        CATransaction.flush()

        let format = UIGraphicsImageRendererFormat()
        format.scale = Self.scale
        format.opaque = true
        let bounds = CGRect(origin: .zero, size: Self.canvas)
        let image = UIGraphicsImageRenderer(size: Self.canvas, format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(bounds)
            host.view.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }

        guard let data = image.pngData() else {
            XCTFail("Не удалось закодировать PNG для \(name)")
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
