//  PushNotificationService.swift
//  Plink — M39
//
//  Правило продукта: мы НИКОГДА не спрашиваем разрешение на пуши на первом экране.
//  Сначала человек должен хотя бы раз посмотреть видео вместе с другом — тогда он понимает,
//  зачем ему уведомления. Разница в согласиях здесь кратная, а второго шанса iOS не даёт.

import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()

    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    @Published var roomStartedEnabled = true
    @Published var friendRequestsEnabled = true
    @Published var messagesEnabled = true

    private let askedKey = "plink.push.askedAt"
    private let sessionsKey = "plink.push.watchSessions"

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Спрашиваем только после первого совместного просмотра и ровно один раз.
    var shouldAskNow: Bool {
        guard status == .notDetermined else { return false }
        guard UserDefaults.standard.object(forKey: askedKey) == nil else { return false }
        return UserDefaults.standard.integer(forKey: sessionsKey) >= 1
    }

    func noteWatchSessionFinished() {
        let count = UserDefaults.standard.integer(forKey: sessionsKey)
        UserDefaults.standard.set(count + 1, forKey: sessionsKey)
    }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        UserDefaults.standard.set(Date(), forKey: askedKey)
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge, .provisional])
            await refreshStatus()
            if granted { UIApplication.shared.registerForRemoteNotifications() }
            return granted
        } catch {
            return false
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func handle(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await send(path: "/api/push/register", method: "POST", body: [
            "token": token,
            "platform": "ios",
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        ]) }
    }

    func unregister() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus != .notDetermined else { return }
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    func syncPreferences() async {
        await send(path: "/api/push/preferences", method: "PATCH", body: [
            "roomStarted": roomStartedEnabled,
            "friendRequests": friendRequestsEnabled,
            "messages": messagesEnabled,
        ])
    }

    private func send(path: String, method: String, body: [String: Any]) async {
        guard let url = URL(string: APIConfig.baseURL + path) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = AuthTokenStore.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15
        _ = try? await URLSession.shared.data(for: request)
    }
}

extension PushNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let link = info["deeplink"] as? String, let url = URL(string: link) else { return }
        await MainActor.run { DeepLinkRouter.shared.handle(url: url) }
    }
}
