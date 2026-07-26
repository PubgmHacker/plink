import Foundation
import UIKit

/// Keeps the current user marked online so friends see real presence.
@MainActor
enum PresenceHeartbeat {
    private static var task: Task<Void, Never>?

    static func start() {
        task?.cancel()
        task = Task {
            await ping()
            while !Task.isCancelled {
                // 30s — friends list ONLINE_THRESHOLD is 10 min; stay fresh
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                if UIApplication.shared.applicationState == .active {
                    await ping()
                }
            }
        }
    }

    static func stop() {
        task?.cancel()
        task = nil
    }

    static func ping() async {
        if APIClient.shared.authToken == nil {
            APIClient.shared.authToken = KeychainHelper.read(for: "rave_auth_token")
                ?? AuthService.shared.authToken
        }
        guard APIClient.shared.authToken != nil else { return }
        struct OK: Decodable { let success: Bool? }
        do {
            let _: OK = try await APIClient.shared.request("users/me/presence", method: .post)
        } catch {
            // Silent — presence is best-effort
            Logger.ws.warn("[Presence] ping failed: \(error.localizedDescription)")
        }
    }
}
