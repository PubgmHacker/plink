//
//  WatchRoomContainer.swift
//  Plink
//
//  P0.2b: Unified WatchRoom presentation container.
//  Wraps WatchRoomCompositionRoot.makeScreenForRoom with auth + URL setup.
//

import SwiftUI

struct WatchRoomContainer: View {
    let room: Room
    @Environment(\.dismiss) private var dismiss
    @State private var resolved: SessionIdentity?
    @State private var resolveFailed = false
    /// Аудит 26.07.2026 (P0): модель живёт в @State и создаётся один раз
    /// в hydrateSession() — раньше makeScreenForRoom из body пересоздавал её
    /// на каждом пересчёте: комната сбрасывалась, WebSocket утекал.
    @State private var model: WatchRoomModel?
    /// Ensures REST leave even if user dismisses cover without tapping X.
    @State private var didSendLeave = false
    /// Paywall presentation state
    @State private var paywallTrigger: PlinkPlusPaywall.Trigger?
    
    var body: some View {
        Group {
            if let model {
                WatchRoomScreen(model: model)
            } else if resolveFailed {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Cinema2026.danger)
                    Text("Необходим вход")
                        .font(.headline)
                        .foregroundStyle(Cinema2026.text)
                    Text("Сессия не найдена. Закройте и войдите снова.")
                        .font(.subheadline)
                        .foregroundStyle(Cinema2026.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("Закрыть") { dismiss() }
                        .font(.subheadline.bold())
                        .foregroundStyle(Cinema2026.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Cinema2026.background.ignoresSafeArea())
            } else {
                ProgressView()
                    .tint(Cinema2026.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Cinema2026.background.ignoresSafeArea())
            }
        }
        .task {
            await hydrateSession()
        }
        .onDisappear {
            // Safety net: soft-leave when fullScreenCover is torn down.
            // leaveRoom is idempotent; model also calls it on X.
            guard !didSendLeave else { return }
            didSendLeave = true
            Task {
                try? await RoomService(api: APIClient.shared).leaveRoom(roomID: room.id)
            }
        }
        .sheet(item: $paywallTrigger) { trigger in
            PlinkPlusPaywall(trigger: trigger)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPlinkPlusPaywall)) { notification in
            if let trigger = notification.userInfo?["trigger"] as? PlinkPlusPaywall.Trigger {
                paywallTrigger = trigger
            }
        }
    }

    @MainActor
    private func hydrateSession() async {
        // 1) Prefer live AuthService
        var token = AuthService.shared.authToken
            ?? AuthTokenStore.shared.token
        var userId = AuthService.shared.currentUserValue?.id
            ?? UserDefaults.standard.string(forKey: "plink_current_user_id")
        var username = AuthService.shared.currentUserValue?.username
            ?? UserDefaults.standard.string(forKey: "plink_current_username")
            ?? "user"

        // 2) Re-decode cached user (ISO8601) if memory user missing
        if userId == nil || userId?.isEmpty == true {
            if let data = UserDefaults.standard.data(forKey: "rave_saved_user") {
                // Аудит 26.07.2026 (P2): единый разбор кэша профиля — терпит и
                // ISO8601 с миллисекундами, и без них (см. User.decodeCached).
                if let user = User.decodeCached(data) {
                    userId = user.id
                    username = user.username
                    UserDefaults.standard.set(user.id, forKey: "plink_current_user_id")
                    UserDefaults.standard.set(user.username, forKey: "plink_current_username")
                }
            }
        }

        // 3) Soft-refresh AuthService so the rest of the app sees the session
        if token == nil {
            token = AuthTokenStore.shared.token
        }
        if let token {
            APIClient.shared.authToken = token
            if AuthService.shared.authToken == nil {
                // Re-bind token into shared auth without full re-login
                AuthService.shared.rebindSessionFromStorage()
                if userId == nil {
                    userId = AuthService.shared.currentUserValue?.id
                        ?? UserDefaults.standard.string(forKey: "plink_current_user_id")
                }
                if username == "user" {
                    username = AuthService.shared.currentUserValue?.username
                        ?? UserDefaults.standard.string(forKey: "plink_current_username")
                        ?? "user"
                }
            }
        }

        // 4) Fallback: room host is this device (host just created the room)
        if (userId == nil || userId?.isEmpty == true), !room.hostID.isEmpty {
            userId = room.hostID
            if username == "user", !room.hostName.isEmpty {
                username = room.hostName
            }
        }

        guard let uid = userId, !uid.isEmpty, let tok = token, !tok.isEmpty else {
            resolveFailed = true
            Logger.app.warn("[WatchRoom] session missing userId=\(userId ?? "nil") token=\(token != nil)")
            return
        }

        resolved = SessionIdentity(userId: uid, username: username, token: tok)
        model = WatchRoomCompositionRoot.makeModelForRoom(
            room: room,
            userId: uid,
            username: username,
            apiBaseURL: URL(string: PlinkConfig.baseURLString)!,
            wsBaseURL: URL(string: PlinkConfig.wsURLString)!,
            authToken: tok
        )
    }
}

private struct SessionIdentity {
    let userId: String
    let username: String
    let token: String
}
