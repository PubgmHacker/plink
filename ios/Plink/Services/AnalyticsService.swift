// Analytics — Firebase + console. Core funnel for MVP beta.
// P1/P2 fix: Firebase is optional. If GoogleService-Info.plist is placeholder
// or missing, Analytics.logEvent calls are skipped (no crash).

import Foundation
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

final class AnalyticsService {
    static let shared = AnalyticsService()

    /// Set to true only when FirebaseApp.configure() succeeded.
    static var firebaseConfigured: Bool = false

    private init() {}

    func track(_ event: String, parameters: [String: Any] = [:]) {
        var params: [String: Any] = parameters
        params["ts"] = Int(Date().timeIntervalSince1970)
        Logger.app.info("[Analytics] \(event) \(params)")

        // Only call Firebase if configured — otherwise crash
        guard Self.firebaseConfigured else { return }

        #if canImport(FirebaseAnalytics)
        // Firebase rejects non-string/number values — sanitize
        let safe = params.compactMapValues { v -> Any? in
            switch v {
            case is String, is Int, is Double, is Float, is Bool: return v
            default: return String(describing: v)
            }
        }
        Analytics.logEvent(event, parameters: safe)
        #endif
    }

    // MARK: - Lifecycle / auth

    func appOpen() { track("app_open") }
    func signUp() { track("sign_up") }
    func login() { track("login") }
    func logout() { track("logout") }

    // MARK: - Core room loop

    func roomCreated(source: String = "unknown") {
        track("room_created", parameters: ["source": source])
        track("funnel_first_room", parameters: ["source": source])
    }
    func roomJoined(via: String = "code") {
        track("room_joined", parameters: ["via": via])
        track("funnel_join", parameters: ["via": via])
    }
    func roomLeft() { track("room_left") }
    /// Воронка: сессия в комнате завершена (выход после просмотра).
    func roomFinished(driftMs: Int = 0, participantCount: Int = 1) {
        track("funnel_first_finish", parameters: [
            "drift_ms": driftMs,
            "participants": participantCount,
        ])
    }
    func messageSent() { track("message_sent") }
    func shareRoom() { track("share_room") }
    func inviteFriend() { track("invite_friend") }
    func funnelInvite() { track("funnel_invite") }

    // MARK: - Media / premium

    func themeChanged(_ theme: String) {
        track("theme_changed", parameters: ["theme": theme])
    }
    func emojiUsed(_ pack: String = "default") {
        track("emoji_used", parameters: ["pack": pack])
    }
    func aiUsed() { track("ai_chat_used") }
    func premiumPurchased(productId: String = "") {
        track("premium_purchased", parameters: ["product_id": productId])
    }
    func premiumCanceled() { track("premium_canceled") }

    // MARK: - Sync quality

    func syncDriftMs(_ ms: Int) {
        track("sync_drift", parameters: ["drift_ms": ms])
    }
}
