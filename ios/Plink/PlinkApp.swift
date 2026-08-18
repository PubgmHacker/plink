// Plink/PlinkApp.swift — точка входа приложения.
//
// Файл назывался RaveCloneApp.swift: Rave — конкурент, и его имя не должно
// жить в корне таргета продукта, который называется Plink. Тип внутри уже был
// PlinkApp, менялось только имя файла и ссылки на него в комментариях.

import SwiftUI
#if os(iOS)
import UIKit
import AVFoundation
import UserNotifications
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
// FIX v2 (July 2026): user-reported bug — "when watching video in landscape
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

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Delegate центра уведомлений раньше не ставился нигде
        // (единственное место было в мёртвом PushNotificationService, который никто
        // не создавал) — тап по пушу никуда не вёл, в форграунде баннер не показывался.
        UNUserNotificationCenter.current().delegate = self
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
        // Локальный crash-репортер — работает без Firebase; отправляет
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
        // FIX: токен давно живёт в AuthTokenStore (ключ plink_auth_token).
        // Старое чтение по ключу "rave_auth_token" после миграции всегда возвращало
        // пустоту — APNs-токен никогда не доезжал до бэкенда (пуши молчали).
        let stored: String? = await MainActor.run { AuthTokenStore.shared.token }
        guard let auth = stored, !auth.isEmpty,
              let url = URL(string: PlinkConfig.apiURLString + "/auth/fcm-token") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token])
        _ = try? await URLSession.shared.data(for: req)
    }
}

// MARK: - UNUserNotificationCenterDelegate (форграунд-баннер + тап по пушу)
//
// Роутинг тапа строится СТРОГО по реальным полям payload'а
// бэкенда (backend/src/services/pushService.ts кладёт content.data в корень
// APNs-JSON → сюда приходит в userInfo верхнего уровня):
//   { kind: "dm",             fromUserId: <id> }  — messages.ts:629
//   { kind: "friend_request", fromUserId: <id> }  — friends.ts:361
//   { kind: "broadcast",      topic: <string> }   — admin.ts:412
extension PlinkAppDelegate: UNUserNotificationCenterDelegate {

    // Форграунд: раньше системный дефолт молча глотал пуш — показываем баннер и звук.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    // Тап по пушу: ведём пользователя по kind. Пустой/неизвестный payload —
    // просто открываем приложение, без крэша.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        switch info["kind"] as? String {
        case "friend_request":
            // Существующий deep-link /u/<userId>: PlinkApprovedV4Root покажет алерт
            // «Добавить в друзья», а бэкенд при встречной pending-заявке
            // автоматически принимает её (friends.ts: reverse → accepted).
            if let fromUserId = info["fromUserId"] as? String, !fromUserId.isEmpty {
                Task { @MainActor in
                    DeepLinkRouter.shared.handle(DeepLinkRouter.friendInviteURL(userId: fromUserId))
                }
            }
        case "dm":
            if let fromUserId = info["fromUserId"] as? String, !fromUserId.isEmpty {
                Task { @MainActor in
                    await DMChatService.shared.refreshUnread()
                    DeepLinkRouter.shared.openChat(.dm(friendId: fromUserId))
                }
            }
        default:
            break // broadcast и всё неизвестное — просто открыть приложение
        }
        completionHandler()
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

    // Wire up AppDelegate so `supportedInterfaceOrientationsFor` is consulted
    // by UIKit. Required for the orientation-lock fix above.
    #if os(iOS)
    @UIApplicationDelegateAdaptor(PlinkAppDelegate.self) private var appDelegate
    #endif

    // MARK: - Service Singletons (app lifetime)

    private let apiClient: APIClient
    private let authService: AuthService
    private let mediaService: MediaService
    private let roomService: RoomService

    // Контейнер зависимостей собирается ОДИН раз.
    // Раньше AppDependencies(...) создавался прямо в body, а его переоценку
    // триггерит любой @Published у deepLinkRouter — сервисы внутри контейнера
    // пересоздавались и теряли состояние. (Исторически так утекал каталог
    // Discovery; само поколение Discovery удалено этим же аудитом.)
    private let dependencies: AppDependencies

    // Social layer. Both take the shared authenticated APIClient by injection:
    // a service that builds its own client gets an unauthenticated one, and every
    // request it makes fails in a way that looks like an empty friends list.
    @State private var friendManager: FriendManager

    @State private var dmChatService: DMChatService

    // Deep-linking (Блок 3)
    // Единый роутер — AppDelegate (didReceive выше) шлёт
    // тапы по пушам в DeepLinkRouter.shared, UI подписан на тот же экземпляр.
    @StateObject private var deepLinkRouter = DeepLinkRouter.shared

    // @State showProfile/showFriends/showCreateRoom удалены —
    // они только объявлялись, ни одна вьюха их не читала и не писала.

    // MARK: - Init

    init() {
        // Configure AVAudioSession at app launch.
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
        let auth = AuthService.shared
        let media = MediaService()
        let rooms = RoomService(api: api)
        apiClient = api
        authService = auth
        mediaService = media
        roomService = rooms
        // The shared authenticated client, into both social services.
        let friends = FriendManager(api: api)
        _friendManager = State(initialValue: friends)
        let dms = DMChatService(api: api)
        _dmChatService = State(initialValue: dms)
        // One dependency container for the whole application lifetime.
        dependencies = AppDependencies(
            apiClient: api,
            authService: auth,
            roomService: rooms,
            mediaService: media,
            friendManager: friends,
            dmChatService: dms
        )

        // StoreManager.apiBaseURL никогда не выставлялся,
        // из-за чего покупка не доходила до сервера, а серверная проверка прав
        // при следующем запуске отзывала Plink+. Задаём базовый URL и сразу
        // подтягиваем актуальные права из /api/billing/entitlements.
        StoreManager.shared.apiBaseURL = URL(string: PlinkConfig.baseURLString)
        Task { await StoreManager.shared.refreshEntitlement() }
    }

    // MARK: - Root View

    var body: some Scene {
        WindowGroup {
            // PATCH: new cinematic launch gate
            AuthLaunchGate(
                dependencies: dependencies,
                onboardingStore: UserDefaultsOnboardingStore()
            )
            .environmentObject(deepLinkRouter)
            .environmentObject(friendManager)
            .environmentObject(dmChatService)
            .environmentObject(apiClient)
            // Дублирующий .onOpenURL/handleDeepLink удалён —
            // единственная точка входа ссылок это AuthLaunchGate.onOpenURL,
            // единственный консьюмер pendingLink — PlinkApprovedV4Root.
            // оффлайн-баннер поверх всего приложения
            .withOfflineBanner()
            // shake-to-report на корневом уровне
            .shakeToReport()
        }
    }

    // MARK: - Login Content

    // loginContent removed — AuthLaunchGate handles auth flow
    // (uses LoginView2026 from Auth2026 folder)

    // MARK: - Deep-Link Handler (Блок 3)

    // handleDeepLink/fetchUsername удалены — состояние
    // deepLinkRoom/friendInviteAlert писалось, но нигде не читалось (тупик:
    // сервер джойнил комнату, UI не открывался). Обработка перенесена в
    // PlinkApprovedV4Root (подписка на DeepLinkRouter.shared.$pendingLink).

}
