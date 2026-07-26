// Plink/Features/Auth2026/AuthLaunchGate.swift — MVP: skip + notifications + deferred deep links
// Functionality only — no design changes to splash/auth UI chrome.

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
    @State private var authRoute: AuthRoute = .login
    @State private var pendingURL: URL?
    @State private var authNotice: String?
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
                    .transition(.opacity)
                    .onAppear { flushPendingDeepLink() }
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
                pendingURL = url
            }
        }
        .onChange(of: destination) { _, newValue in
            if newValue == .app { flushPendingDeepLink() }
        }
    }

    @ViewBuilder
    private var authFlow: some View {
        switch authRoute {
        case .login:
            LoginView2026(
                sessionMessage: authNotice,
                onAuthenticated: handleAuthenticated,
                onRegister: {
                    authNotice = nil
                    authRoute = .registration
                }
            )
        case .registration:
            RegistrationView2026(
                onRegistered: handleAuthenticated,
                onLogin: { authRoute = .login }
            )
        }
    }

    private func restoreSession() async {
        async let minimumSplash: Void = Task.sleep(for: .milliseconds(650))
        let result = await dependencies.authService.restoreAndValidateSession()
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

    private func handleAuthenticated() {
        authNotice = nil
        // Sync shared API client token for the whole app
        if APIClient.shared.authToken == nil {
            APIClient.shared.authToken = AuthService.shared.authToken
                ?? KeychainHelper.read(for: "rave_auth_token")
        }
        let next: LaunchDestination = onboardingStore.needsCurrentOnboarding ? .onboarding : .app
        withAnimation(.easeOut(duration: 0.32)) {
            destination = next
        }
        if next == .app { flushPendingDeepLink() }
    }

    @MainActor
    private func completeOnboarding() {
        requestNotificationPermission()
        onboardingStore.markCompleted(version: OnboardingVersion.current)
        withAnimation(.easeOut(duration: 0.32)) {
            destination = .app
        }
        flushPendingDeepLink()
    }

    @MainActor
    private func skipOnboarding() {
        requestNotificationPermission()
        onboardingStore.markCompleted(version: OnboardingVersion.current)
        withAnimation(.easeOut(duration: 0.32)) {
            destination = .app
        }
        flushPendingDeepLink()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            #if canImport(UIKit)
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
            #endif
        }
    }

    private func flushPendingDeepLink() {
        guard let url = pendingURL else { return }
        pendingURL = nil
        deepLinkRouter.handle(url)
    }
}

enum AuthRoute: Equatable {
    case login
    case registration
}

struct CinematicSplashView: View {
    var body: some View {
        ZStack {
            Cinema2026.background.ignoresSafeArea()
            CompactLivingBackdrop(primary: Cinema2026.accent, secondary: Cinema2026.amber)
            VStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                Text("Plink")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
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
}
