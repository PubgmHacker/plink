import SwiftUI
#if os(iOS)
import UIKit
import AVFoundation
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

// MARK: - AppDelegate (orientation lock)
//
// 🔧 FIX v2 (July 2026): user-reported bug — "when watching video in landscape
// and swiping left = tabbar appears, screen auto-rotates to portrait, room closes".
//
// Root cause: RoomView was opened via `navigationDestination(item:)` inside a
// NavigationStack inside a TabView. The iOS edge-swipe gesture (used by
// NavigationStack for "swipe to go back") fires when the user swipes left
// from the screen edge in landscape — popping RoomView, returning to the tab,
// re-showing the tabbar, and triggering RoomView.onDisappear → forcePortrait().
// Result: room closes and screen rotates — exactly what the user reported.
//
// Fix: lock the device orientation at the AppDelegate level while RoomView is
// presented. AppDelegate.orientationLock is set to .landscape or .portrait by
// RoomView (via OrientationManager) and to .allByDefault otherwise. Combined
// with `interactiveDismissDisabled(true)` and `.fullScreenCover` presentation
// (see MainTabView), this completely isolates RoomView from TabView gestures
// and system edge-swipe handling.
#if os(iOS)
final class PlinkAppDelegate: NSObject, UIApplicationDelegate {

    /// Active orientation mask. Defaults to `.all` so the rest of the app
    /// supports all orientations. RoomView sets this to `.portrait` or
    /// `.landscape` via OrientationManager.lockOrientation(_:).
    static var orientationLock: UIInterfaceOrientationMask = .all

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        let lock = PlinkAppDelegate.orientationLock
        Logger.app.info("AppDelegate supportedInterfaceOrientations → \(lock)")
        return lock
    }

    // M20: Shake-to-report — заменяем window на PlinkShakeWindow
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Wire shake detection via notification
        NotificationCenter.default.addObserver(
            forName: .plinkShakeDetected,
            object: nil,
            queue: .main
        ) { _ in } // handled in ShakeDetectorModifier
        // P1.4 Firebase - optional, only configure if valid GoogleService-Info.plist exists
        #if canImport(FirebaseCore)
        if let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plistData = FileManager.default.contents(atPath: plistPath),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
           let appId = plist["GOOGLE_APP_ID"] as? String,
           !appId.isEmpty,
           appId != "YOUR_GOOGLE_APP_ID"  // placeholder check
        {
            // Valid Firebase config — configure
            FirebaseApp.configure()
            AnalyticsService.firebaseConfigured = true
            Logger.app.info("[Firebase] Configured successfully")
        } else {
            // No valid GoogleService-Info.plist — skip Firebase (no crash)
            Logger.app.warn("[Firebase] Skipped — GoogleService-Info.plist is placeholder or missing")
            AnalyticsService.firebaseConfigured = false
        }
        #endif
        AnalyticsService.shared.appOpen()
        // M12: локальный crash-репортер — работает без Firebase; отправляет
        // отчёты прошлых сессий на /api/telemetry/crash при запуске.
        CrashReporter.shared.install()
        CrashReporter.shared.uploadPendingReports()
        // Soft-detect LiveKit so mic UI can appear when ops enable keys
        if let base = URL(string: PlinkConfig.baseURLString) {
            Task { await FeatureFlags.refreshLiveKitAvailability(apiBaseURL: base) }
        }
        return true
    }

    // MARK: - Push notifications (APNs device token → backend)

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Logger.app.info("[Push] APNs device token received")
        Task { await PlinkAppDelegate.sendPushToken(token) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger.app.error("[Push] APNs registration failed: \(error.localizedDescription)")
    }

    private static func sendPushToken(_ token: String) async {
        guard let auth = KeychainHelper.read(for: "rave_auth_token"),
              let url = URL(string: PlinkConfig.apiURLString + "/auth/fcm-token") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token])
        _ = try? await URLSession.shared.data(for: req)
    }
}
#else
final class PlinkAppDelegate: NSObject {
    static var orientationLock: Int = 0
}
#endif

// MARK: - App Entry Point
/// Конфигурирует dependency injection, прокидывает JWT-токен между сервисами,
/// управляет корневой навигацией + жизненным циклом WebSocket,
/// и обрабатывает Universal Links (deep-linking, Блок 3).
@main
struct PlinkApp: App {

    // 🔧 Wire up AppDelegate so `supportedInterfaceOrientationsFor` is consulted
    // by UIKit. Required for the orientation-lock fix above.
    #if os(iOS)
    @UIApplicationDelegateAdaptor(PlinkAppDelegate.self) private var appDelegate
    #endif

    // MARK: - Service Singletons (app lifetime)

    private let apiClient: APIClient
    private let authService: AuthService
    private let mediaService: MediaService
    private let roomService: RoomService

    // Социальный слой (Блок 3)
    // 🔧 FIX C5: Inject shared apiClient into FriendManager (was: own unauth client)
    @State private var friendManager: FriendManager

    // 🔧 FIX C4: Inject shared apiClient into DMChatService (was: own unauth client)
    @State private var dmChatService: DMChatService

    // Deep-linking (Блок 3)
    @StateObject private var deepLinkRouter = DeepLinkRouter()

    // MARK: - State

    @State private var showProfile = false
    @State private var showFriends = false
    @State private var showCreateRoom = false
    @State private var deepLinkRoom: Room?
    @State private var friendInviteAlert: FriendInviteAlert?

    // MARK: - Init

    init() {
        // 🔧 v56 (Gemini): Configure AVAudioSession at app launch.
        // Tells iOS: "we are a media player, don't kill WebKit/AVPlayer
        // when app goes inactive (Control Center, notification shade)".
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Logger.app.warn("v56: AVAudioSession config failed: \(error)")
        }
        #endif

        let api = APIClient.shared
        apiClient = api
        authService = AuthService.shared
        mediaService = MediaService()
        roomService = RoomService(api: api)
        // 🔧 FIX C5: Shared authenticated client injected into social layer
        _friendManager = State(initialValue: FriendManager(api: api))
        // 🔧 FIX C4: Shared authenticated client injected into DM layer
        _dmChatService = State(initialValue: DMChatService(api: api))
    }

    // MARK: - Root View

    var body: some Scene {
        WindowGroup {
            // PATCH: new cinematic launch gate
            AuthLaunchGate(
                dependencies: AppDependencies(
                    apiClient: apiClient,
                    authService: authService,
                    roomService: roomService,
                    mediaService: mediaService,
                    friendManager: friendManager,
                    dmChatService: dmChatService
                ),
                onboardingStore: UserDefaultsOnboardingStore()
            )
            .environmentObject(deepLinkRouter)
            .environmentObject(friendManager)
            .environmentObject(dmChatService)
            .environmentObject(apiClient)
            .onOpenURL { url in
                handleDeepLink(url)
            }
            // M20: оффлайн-баннер поверх всего приложения
            .withOfflineBanner()
            // M20: shake-to-report на корневом уровне
            .shakeToReport()
        }
    }

    // MARK: - Login Content

    // loginContent removed — AuthLaunchGate handles auth flow
    // (uses LoginView2026 from Auth2026 folder)

    // MARK: - Deep-Link Handler (Блок 3)

    /// Обрабатывает вход��щие Universal Links и custom scheme.
    private func handleDeepLink(_ url: URL) {
        deepLinkRouter.handle(url)

        switch deepLinkRouter.pendingLink {
        case .room(let code):
            // Присоединяемся к комнате по коду из ссылки.
            Task {
                do {
                    let room = try await roomService.joinRoom(code: code)
                await MainActor.run {
                        deepLinkRoom = room
                        deepLinkRouter.clear()
                    }
                } catch {
                    // Комната не найдена — сбрасываем.
                await MainActor.run { deepLinkRouter.clear() }
                }
            }

        case .friendInvite(let userId):
            // 🔧 FIX L10: Fetch real username from server (was: hardcoded "Пользователь").
            Task {
                let username = await fetchUsername(userId: userId)
            await MainActor.run {
                    friendInviteAlert = FriendInviteAlert(userId: userId, username: username)
                    deepLinkRouter.clear()
                }
            }

        case .none:
            break
        }
    }

    /// 🔧 FIX L10: Fetch user display name from server for friend-invite alerts.
    private func fetchUsername(userId: String) async -> String {
        // Try to fetch the user's profile from /api/users/:id
        // Falls back to a generic localized string if the request fails.
        struct UserDTO: Decodable {
            let username: String?
        }
        do {
            let user: UserDTO = try await apiClient.request("users/\(userId)")
            return user.username ?? "Пользователь"
        } catch {
            Logger.api.warn("Failed to fetch username for friend invite: \(error.localizedDescription)")
            return "Пользователь"
        }
    }

}

// MARK: - Friend Invite Alert Model
private struct FriendInviteAlert: Identifiable, Equatable {
    let id = UUID()
    let userId: String
    let username: String

    static func == (lhs: FriendInviteAlert, rhs: FriendInviteAlert) -> Bool {
        lhs.id == rhs.id
    }
}
