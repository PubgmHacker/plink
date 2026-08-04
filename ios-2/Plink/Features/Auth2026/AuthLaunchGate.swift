// Plink/Features/Auth2026/AuthLaunchGate.swift — MVP: skip + notifications + deferred deep links
// Splash redesign: кинозал — луч проектора + слоёный play-кадр (CinematicSplashView ниже).

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
                CinematicSplashView()
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
            authNotice = "Сессия истекла. Войдите заново — это защищает ваш аккаунт."
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
            authNotice = nil
            destination = .app
            return
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
            authNotice = "Сессия истекла. Войдите заново — мы сохранили ваши локальные настройки."
            destination = .authentication
        case .unauthenticated:
            authNotice = nil
            destination = .authentication
        }
    }

    /// Аудит 26.07.2026 P2: у сплэша не было своего таймаута.
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
        // Registration must never be held behind onboarding during the smoke
        // flow; onboarding can be opened later from the profile/settings flow.
        withAnimation(.easeOut(duration: 0.32)) {
            destination = .app
        }
        Logger.app.info("[AuthGate] destination set to app token=\(APIClient.shared.authToken != nil)")
        flushPendingDeepLink()
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
    // Аудит 26.07.2026 P2: ссылка ждала входа в @State pendingURL и терялась,
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
}

// MARK: - Cinematic splash («restoring session»)

/// Сплэш берёт цвета ИЗ ШЕЛЛА (PlinkTheatre), а не держит свою копию.
///
/// Аудит 04.08.2026: здесь лежала третья палитра проекта со своими значениями
/// (#060d0f вместо #0B0B0D и т.д.) и с мёртвыми teal-токенами от палитры,
/// которой в продукте уже нет. Сплэш и вход показываются друг за другом, и
/// расхождение читалось как смена фона при переходе.
private enum SplashPalette {
    static let velvetDeep = PlinkTheatre.velvetDeep
    static let velvet = PlinkTheatre.velvet
    static let screenLight = PlinkTheatre.screen
    static let muted = PlinkTheatre.muted
    /// Акцент сплэша — тёплый свет, тот же, что у знака и у входа.
    static let accent = PlinkTheatre.warm
}

/// Луч проектора: трапеция от узкой «апертуры» сверху к широкому основанию.
private struct ProjectorBeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let apertureWidth = rect.width * 0.14
        path.move(to: CGPoint(x: rect.midX - apertureWidth / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + apertureWidth / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct CinematicSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var appeared = false
    @State private var pulsing = false

    var body: some View {
        ZStack {
            // Бархат кинозала: чуть светлее у «экрана» сверху, глубже к полу.
            LinearGradient(
                colors: [SplashPalette.velvet, SplashPalette.velvetDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            projectorBeam
                .accessibilityHidden(true)

            content
        }
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.25 : 0.6)) {
                appeared = true
            }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }

    // MARK: Слои

    /// Мягкий луч проектора сверху — как на лендинге.
    private var projectorBeam: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if reduceTransparency {
                    // Без blur: плоская световая вуаль сверху.
                    LinearGradient(
                        colors: [SplashPalette.screenLight.opacity(0.06), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: proxy.size.height * 0.5)
                } else {
                    ProjectorBeamShape()
                        .fill(
                            LinearGradient(
                                colors: [
                                    SplashPalette.screenLight.opacity(0.10),
                                    SplashPalette.screenLight.opacity(0.03),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height * 0.58)
                        .blur(radius: 26)
                        .blendMode(.screen)

                    // «Апертура»: точка света в самом верху луча.
                    Circle()
                        .fill(SplashPalette.screenLight.opacity(0.35))
                        .frame(width: 10, height: 10)
                        .blur(radius: 10)
                        .frame(maxWidth: .infinity)
                        .offset(y: -2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .opacity(appeared ? 1 : 0)
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer()

            logoMark
                .scaleEffect(pulsing ? 1.04 : 1.0)

            // Ровно тот же компонент, что на экране входа, — со светящейся
            // щелью на месте «I». Раньше здесь стоял свой Text("PLINK"), и
            // сплэш с входом показывали разные написания одного слова.
            PlinkWordmark(size: 34)
                .padding(.top, 22)

            Text("СМОТРИМ ВМЕСТЕ")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(3.5)
                .padding(.leading, 3.5) // компенсация tracking после последнего символа
                .foregroundStyle(SplashPalette.muted)
                .padding(.top, 10)

            Spacer()

            ProgressView()
                .progressViewStyle(.circular)
                .tint(SplashPalette.accent)
                .scaleEffect(0.9)
                .opacity(0.85)
                .padding(.bottom, 48)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: (appeared || reduceMotion) ? 0 : 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plink. Смотрим вместе. Загрузка")
    }

    /// Логотип сплэша — тот же знак, что на иконке и на экране входа.
    ///
    /// Здесь был свой «слоёный play-кадр» в teal-градиенте: третья версия
    /// логотипа в одном продукте (иконка, вход, сплэш — все разные). Знак
    /// теперь один.
    private var logoMark: some View {
        PlinkBrandMark(size: 82)
    }
}

extension Notification.Name {
    static let plinkSignedOut = Notification.Name("plinkSignedOut")
    static let plinkSessionExpired = Notification.Name("plinkSessionExpired")
    static let plinkRoomCreated = Notification.Name("plinkRoomCreated")
    /// Posted after leave/end so Home/Friends/Rooms re-sync active vs history lists.
    static let plinkRoomsDidChange = Notification.Name("plinkRoomsDidChange")
    static let plinkProfileDidUpdate = Notification.Name("plinkProfileDidUpdate")
}
