// Plink/Features/Auth2026/AuthLaunchGate.swift — MVP: skip + notifications + deferred deep links
// Сплэш — лок-ап бренда на фоне шелла (PlinkSplashView ниже); палитра PlinkShell.

import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

enum LaunchDestination: Equatable {
    case restoringSession
    case authentication
    case onboarding
    case app

    /// После входа или регистрации: новый человек видит онбординг, повторный — сразу приложение.
    static func afterAuthentication(needsOnboarding: Bool) -> LaunchDestination {
        needsOnboarding ? .onboarding : .app
    }
}

struct AuthLaunchGate: View {
    @State private var destination: LaunchDestination = .restoringSession
    @State private var authNotice: String?
    @State private var authTransitionNonce = 0
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter

    let dependencies: AppDependencies
    let onboardingStore: OnboardingStoring

    var body: some View {
        ZStack {
            switch destination {
            case .restoringSession:
                PlinkSplashView()
                    .transition(.opacity)

            case .authentication:
                authFlow
                    .transition(.opacity)

            case .onboarding:
                OnboardingFlow(
                    onFinish: {
                        // Capture via MainActor so @State destination always updates
                        Task { @MainActor in
                            completeOnboarding()
                        }
                    },
                    onSkip: {
                        Task { @MainActor in
                            skipOnboarding()
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(2)

            case .app:
                PlinkAppShell(dependencies: dependencies)
                    .accessibilityElement(children: .contain)
                    .id(authTransitionNonce)
                    .transition(.opacity)
                    .onAppear { flushPendingDeepLink() }
                    .accessibilityIdentifier("app.shell")
            }
        }
        .task { await restoreSession() }
        .animation(.easeOut(duration: 0.32), value: destination)
        .onReceive(NotificationCenter.default.publisher(for: .plinkSignedOut)) { notification in
            authNotice = notification.object as? String
            withAnimation(.easeOut(duration: 0.3)) {
                destination = .authentication
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkSessionExpired)) { _ in
            AuthService.shared.signOutLocally(postNotification: false)
            authNotice = L10n.text(.sessionExpiredSecure)
            withAnimation(.easeOut(duration: 0.3)) {
                destination = .authentication
            }
        }
        .onOpenURL { url in
            if destination == .app {
                deepLinkRouter.handle(url)
            } else {
                storePendingDeepLink(url)
            }
        }
        .onChange(of: destination) { _, newValue in
            if newValue == .app { flushPendingDeepLink() }
        }
    }

    /// Вход и регистрация — один экран с переключателем режима, а не два
    /// маршрута. Раньше здесь был switch по authRoute, и переход между входом
    /// и регистрацией менял всю страницу целиком.
    @ViewBuilder
    private var authFlow: some View {
        PlinkAuthScreen(
            sessionMessage: authNotice,
            onAuthenticated: handleAuthenticated
        )
    }

    private func restoreSession() async {
        #if DEBUG
        // Дизайн-превью: `-plink.designpreview` открывает оболочку приложения
        // без сети и без валидного токена, чтобы снимать таб-бар и экраны в
        // симуляторе. В релизной сборке флага не существует.
        if ProcessInfo.processInfo.arguments.contains("-plink.designpreview") {
            setupMocksForPreview()
            authNotice = nil
            destination = .app
            return
        }
        #endif

        #if DEBUG && targetEnvironment(simulator)
        // Симуляторный автологин НАСТОЯЩИМ аккаунтом:
        //   SIMCTL_CHILD_PLINK_SIM_LOGIN="email:пароль[:username]" xcrun simctl launch …
        // Вход (или регистрация, если аккаунта ещё нет) на реальном бэкенде,
        // онбординг пропускается. В отличие от -plink.designpreview данные
        // живые: витрина, комнаты, друзья и чаты работают по-настоящему.
        // Ветка существует только в Debug-сборке под симулятор.
        if let raw = ProcessInfo.processInfo.environment["PLINK_SIM_LOGIN"] {
            let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            if parts.count >= 2 {
                let email = parts[0]
                let password = parts[1]
                let username = parts.count > 2 && !parts[2].isEmpty
                    ? parts[2]
                    : String(email.prefix(while: { $0 != "@" }))
                do {
                    _ = try await AuthService.shared.signIn(email: email, password: password)
                } catch {
                    do {
                        _ = try await AuthService.shared.signUp(email: email, password: password, username: username)
                    } catch {
                        Logger.app.error("[AuthGate] sim autologin failed: \(error.localizedDescription)")
                    }
                }
                if AuthService.shared.authToken != nil {
                    onboardingStore.markCompleted(version: OnboardingVersion.current)
                    handleAuthenticated()
                    // `-plink.designurl plink://r/CODE` — открыть диплинк сразу после
                    // автологина. `simctl openurl` вешает на SpringBoard системный
                    // диалог «Открыть в приложении „Плинк“?», который без тапа не
                    // закрыть, а тапов у симулятора на чужом Space нет. Пауза даёт
                    // оболочке смонтироваться и подписаться на pendingLink.
                    let args = ProcessInfo.processInfo.arguments
                    if let i = args.firstIndex(of: "-plink.designurl"),
                       args.indices.contains(i + 1),
                       let url = URL(string: args[i + 1]) {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(2500))
                            DeepLinkRouter.shared.handle(url)
                        }
                    }
                    // `-plink.designcreate <service>` — open the room creation
                    // wizard right after autologin (RoomCreationView.debugStart
                    // reads the step and service). Same delay as the deep link.
                    if args.contains("-plink.designcreate") {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(2500))
                            NotificationCenter.default.post(
                                name: Notification.Name("plinkOpenCreateRoom"),
                                object: nil
                            )
                        }
                    }
                    return
                }
                // Не вышло (нет сети, занят username) — обычный путь на экран входа.
            }
        }
        #endif

        async let minimumSplash: Void = Task.sleep(for: .milliseconds(650))
        // 10 с, а не 6: окно cold start бэкенда + bcrypt-скан refresh-токенов
        // на сервере укладывается в него, поэтому обычный старт не уходит
        // в оффлайн-режим со старым access-токеном.
        let result = await restoreWithTimeout(seconds: 10)
        _ = try? await minimumSplash

        switch result {
        case .authenticated:
            authNotice = nil
            destination = onboardingStore.needsCurrentOnboarding ? .onboarding : .app
        case .offlineAuthenticated:
            authNotice = nil
            destination = onboardingStore.needsCurrentOnboarding ? .onboarding : .app
        case .expired:
            authNotice = L10n.text(.sessionExpiredKept)
            destination = .authentication
        case .unauthenticated:
            authNotice = nil
            destination = .authentication
        }
    }

    /// У сплэша не было своего таймаута.
    /// restoreAndValidateSession упирается в дефолтные 60 с URLSession, поэтому
    /// на висящем соединении (плохой Wi-Fi, captive portal) заставка держалась
    /// почти минуту. Ждём не дольше `seconds`: с кэшированным пользователем
    /// уходим в оффлайн-режим (APIClient пришлёт .plinkSessionExpired, если
    /// токен всё же мёртв), без кэша — на экран входа.
    ///
    /// ВАЖНО: по таймауту мы перестаём ЖДАТЬ восстановление, но НЕ отменяем его.
    /// /auth/refresh ротирует refresh-токен на сервере (старый помечается
    /// revokedAt до отправки ответа), а новый сохраняется только после успешного
    /// ответа в AuthService.refreshJWT. Отмена запроса стоила бы пользователю
    /// сессии: в Keychain остался бы отозванный токен, и сервер на следующем
    /// старте счёл бы это переиспользованием и отозвал ВСЕ токены аккаунта.
    /// Поэтому задача живёт в неструктурированном Task и докручивается сама.
    private func restoreWithTimeout(seconds: Double) async -> AuthRestoreResult {
        let authService = dependencies.authService
        let race = AsyncStream<AuthRestoreResult?> { continuation in
            Task {
                let value = await authService.restoreAndValidateSession()
                continuation.yield(value)
                continuation.finish()
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                // yield после finish() — no-op, поэтому гонка безопасна.
                continuation.yield(nil)
                continuation.finish()
            }
        }
        var iterator = race.makeAsyncIterator()
        let first: AuthRestoreResult? = await iterator.next() ?? nil
        if let first {
            return first
        }
        let cachedUser = authService.currentUserValue
        return cachedUser == nil ? .unauthenticated : .offlineAuthenticated
    }

    @MainActor
    private func handleAuthenticated() {
        Logger.app.info("[AuthGate] handleAuthenticated begin token=\(AuthService.shared.authToken != nil)")
        authNotice = nil
        // Rebind from storage as a defensive fallback, then publish the token
        // before replacing the auth view with the app shell.
        AuthService.shared.rebindSessionFromStorage()
        APIClient.shared.authToken = AuthService.shared.authToken
            ?? AuthTokenStore.shared.token
        authTransitionNonce += 1
        withAnimation(.easeOut(duration: 0.32)) {
            destination = LaunchDestination.afterAuthentication(
                needsOnboarding: onboardingStore.needsCurrentOnboarding
            )
        }
        Logger.app.info("[AuthGate] destination set to \(String(describing: destination)) token=\(APIClient.shared.authToken != nil)")
        if destination == .app {
            flushPendingDeepLink()
        }
    }

    // Разрешение на уведомления больше не запрашивается отсюда. Раньше обе
    // ветки — «прошёл» и «пропустил» — молча показывали системный диалог, то
    // есть человек, который только что нажал «Пропустить», всё равно получал
    // запрос без объяснения. Теперь про уведомления спрашивает последний экран
    // онбординга, объяснив зачем, и только если пользователь согласился.

    @MainActor
    private func completeOnboarding() {
        onboardingStore.markCompleted(version: OnboardingVersion.current)
        withAnimation(.easeOut(duration: 0.32)) {
            destination = .app
        }
        flushPendingDeepLink()
    }

    @MainActor
    private func skipOnboarding() {
        onboardingStore.markCompleted(version: OnboardingVersion.current)
        withAnimation(.easeOut(duration: 0.32)) {
            destination = .app
        }
        flushPendingDeepLink()
    }

    // MARK: - Отложенные диплинки
    //
    // Ссылка ждала входа в @State pendingURL и терялась,
    // если пользователь уходил регистрироваться и приложение выгружали.
    // Теперь она живёт в UserDefaults — переживает kill приложения (мёртвый
    // DeepLinkRouter.storePending, писавший в тот же слот, удалён).
    // Храним полный URL (а не разобранный Destination): handle() понимает и
    // легаси-схему raveclone://, и /join/<code>, и /r?code=.

    private static let pendingDeepLinkKey = "plink.pendingDeepLink"
    private static let pendingDeepLinkDateKey = "plink.pendingDeepLink.savedAt"
    /// Приглашение старше часа применять уже поздно — комнаты давно нет.
    private static let pendingDeepLinkTTL: TimeInterval = 3600

    private func storePendingDeepLink(_ url: URL) {
        let defaults = UserDefaults.standard
        defaults.set(url.absoluteString, forKey: Self.pendingDeepLinkKey)
        defaults.set(Date().timeIntervalSince1970, forKey: Self.pendingDeepLinkDateKey)
    }

    private func flushPendingDeepLink() {
        let defaults = UserDefaults.standard
        // Слот чистим ДО разбора: неразбираемая строка (в т.ч. оставленная
        // сторонним кодом) иначе оставалась бы в UserDefaults навсегда.
        let raw = defaults.string(forKey: Self.pendingDeepLinkKey)
        let savedAt = defaults.double(forKey: Self.pendingDeepLinkDateKey)
        clearPendingDeepLink()
        guard let raw, let url = URL(string: raw) else { return }
        // savedAt == 0 — ссылку положила старая версия без метки времени.
        if savedAt > 0, Date().timeIntervalSince1970 - savedAt > Self.pendingDeepLinkTTL {
            return
        }
        deepLinkRouter.handle(url)
    }

    /// Ссылка не привязана к аккаунту, поэтому при выходе её надо снимать —
    /// иначе приглашение, полученное пользователем A, применилось бы к B,
    /// который вошёл на том же устройстве.
    private func clearPendingDeepLink() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.pendingDeepLinkKey)
        defaults.removeObject(forKey: Self.pendingDeepLinkDateKey)
    }

    // MARK: - Дизайн-превью

    #if DEBUG
    /// Подставляет локальную сессию для флага `-plink.designpreview`, чтобы
    /// снимать экраны в симуляторе без сети. Только Debug: в релизной сборке
    /// этого кода нет.
    private func setupMocksForPreview() {
        // Создаём мокового пользователя
        let mockUser = User(
            id: "mock_user_001",
            username: "mock_alex",
            email: "alex@mock.com",
            avatarURL: nil,
            avatarData: nil,
            displayName: "Alex Mock",
            coverURL: nil,
            isOnline: true,
            isPremium: false,
            premiumUntil: nil,
            role: "USER",
            createdAt: Date()
        )

        // Кодируем и сохраняем через стандартный механизм AuthService
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(mockUser) {
            UserDefaults.standard.set(data, forKey: "rave_saved_user")
        }
        AuthTokenStore.shared.save("mock_token_12345")
        APIClient.shared.authToken = "mock_token_12345"
        // Перечитываем сессию из хранилища
        AuthService.shared.rebindSessionFromStorage()

        Logger.app.info("[AuthGate] design-preview session: \(mockUser.displayTitle)")
    }
    #endif
}

// MARK: - Сплэш («restoring session»)

/// Сплэш — тот же лок-ап, что на иконке и на экране входа: знак, вордмарк и
/// теглайн эталона на фоне шелла. Сплэш и вход показываются друг за другом,
/// поэтому фон и палитра у них одни (PlinkShellBackground / PlinkShell), и
/// переход между ними — только появление формы, а не смена сцены.
///
/// Здесь стояла третья палитра проекта — «бархат кинозала» с лучом
/// проектора и teal-акцентом. Ушла вместе с AnimatedPosterMosaic.swift.
struct PlinkSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.plinkFreezeAnimations) private var frozen
    @Environment(\.plinkAccessibilityOverride) private var override
    @State private var appeared = false
    @State private var pulsing = false

    private var reduceMotion: Bool { systemReduceMotion || override.reduceMotion || frozen }

    var body: some View {
        ZStack {
            // Сияние чуть ниже, чем на входе: там оно стоит над формой, здесь
            // — ровно за знаком, который висит по центру.
            PlinkShellBackground(glowCenter: UnitPoint(x: 0.5, y: 0.42))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Дышит только знак: вордмарк и теглайн под ним стоят на
                // месте, иначе весь блок «плывёт» и читается как лаг.
                PlinkBrandMark(size: 96)
                    .scaleEffect(pulsing ? 1.03 : 1.0)

                PlinkWordmark(size: 36)
                    .padding(.top, 22)

                PlinkTagline(size: 12)
                    .padding(.top, 12)

                Spacer()

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(PlinkShell.accentSoft)
                    .scaleEffect(0.9)
                    .opacity(0.85)
                    .padding(.bottom, 48)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: (appeared || reduceMotion) ? 0 : 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.text(.launchA11y))
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.25 : 0.6)) {
                appeared = true
            }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

extension Notification.Name {
    static let plinkSignedOut = Notification.Name("plinkSignedOut")
    static let plinkSessionExpired = Notification.Name("plinkSessionExpired")
    static let plinkRoomCreated = Notification.Name("plinkRoomCreated")
    /// Posted after leave/end so Home/Friends/Rooms re-sync active vs history lists.
    static let plinkRoomsDidChange = Notification.Name("plinkRoomsDidChange")
    static let plinkProfileDidUpdate = Notification.Name("plinkProfileDidUpdate")
    static let plinkOpenChat = Notification.Name("plinkOpenChat")
}
