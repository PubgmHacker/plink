//
//  PlinkSessionSyncGate.swift
//  Plink
//
//  P0 — Two-device sync & security runtime gate.
//  Implements Section 10.2 of PLINK_CUSTOMIZATION_AUTH_ADMIN_SPEC_FOR_GLM_5_2.md
//
//  Phase 0.2: AuthService.shared is now `static let` (singleton).
//  Phase 2.5: RecentAuthGate uses real LocalAuthentication (Face ID / Touch ID)
//             with password fallback via real AuthService.signIn().
//  Phase 2.6: checkNicknameAvailability wired to real backend.
//  Phase 2.7: requestAccountDeletion wired to real backend.
//  Phase 4:   Heartbeat / signout-others call real endpoints via APIClient.
//

import SwiftUI
import Foundation
import LocalAuthentication

// MARK: - AuthService.shared bridge
// The real `AuthService` in `Plink/Services/AuthService.swift` is constructed
// with `init(api: APIClient)` and is `@MainActor`-isolated.
//
// CRITICAL (Phase 0.2 fix): previously this was a `static var` computed
// property, which created a NEW AuthService on every access — each with its
// own fresh `currentUser` / `authToken` snapshot read from Keychain. That
// silently broke any code that wrote to one instance and read from another
// (e.g. `signIn` updated instance A, then `LaunchScreen` read `authToken`
// from instance B which was still nil). Switched to `static let` so the
// singleton is created exactly once on first access (Swift guarantees
// thread-safe lazy init for `static let`) and shared everywhere.
extension AuthService {
    @MainActor
    static let shared: AuthService = AuthService(api: APIClient.shared)
}

// MARK: - Heartbeat DTOs (file-scope for generic inference)

struct HeartbeatResponseDTO: Codable, Sendable {
    let sessions: [HeartbeatSessionDTO]
    let currentDeviceIsPrimary: Bool
    let primaryDevice: String?
    let primarySince: Date?
    let lastAuthAt: Date?
}

struct HeartbeatSessionDTO: Codable, Sendable, Identifiable {
    let id: String
    let device: String
    let location: String?
    let lastSeen: Date
    let isCurrent: Bool
}

// MARK: - SessionSyncState

enum SessionSyncState: Sendable, Equatable {
    case idle
    case syncing
    case current                       // this device is the active session
    case superseded(device: String, at: Date)  // another device took over
    case revoked                       // server invalidated this session
    case offline                       // cannot reach backend
}

// MARK: - RecentAuthStatus

enum RecentAuthStatus: Sendable, Equatable {
    case fresh(expiresAt: Date)        // < 5 min ago — admin mutations allowed
    case stale                         // requires re-auth before admin actions
    case required                      // hard gate: must pass 2FA again
}

// MARK: - SessionSyncGate

@MainActor
@Observable
final class SessionSyncGate {
    var state: SessionSyncState = .idle
    var recentAuth: RecentAuthStatus = .stale
    var lastHeartbeat: Date?

    /// Server-pushed list of active sessions for this account.
    private(set) var activeSessions: [ActiveSession] = []

    /// Set when `requireRecentAuth` fails — views observe to present
    /// the password fallback sheet on their own (the gate itself does not
    /// present UI; it only reports state).
    var pendingReauth: Bool = false

    private var heartbeatTask: Task<Void, Never>?
    private let window: TimeInterval = 300 // 5 min recent-auth window

    init() {}

    // MARK: - Boot

    func start() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
            }
        }
    }

    func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    // MARK: - Heartbeat

    private func tick() async {
        // Phase 4: real POST /api/auth/heartbeat
        guard AuthService.shared.authToken != nil else {
            self.state = .offline
            return
        }
        do {
            let resp: HeartbeatResponseDTO = try await APIClient.shared.request(
                "auth/heartbeat", method: .post
            )
            self.lastHeartbeat = Date()
            self.activeSessions = resp.sessions.map {
                ActiveSession(id: $0.id, device: $0.device, location: $0.location,
                              lastSeen: $0.lastSeen, isCurrent: $0.isCurrent)
            }
            if resp.currentDeviceIsPrimary {
                self.state = .current
            } else if let dev = resp.primaryDevice, let since = resp.primarySince {
                self.state = .superseded(device: dev, at: since)
            }
            if let last = resp.lastAuthAt {
                let elapsed = Date().timeIntervalSince(last)
                if elapsed < window {
                    self.recentAuth = .fresh(expiresAt: last.addingTimeInterval(window))
                } else {
                    self.recentAuth = .stale
                }
            }
        } catch {
            // Network failure — don't downgrade state, just record lastHeartbeat.
            self.lastHeartbeat = Date()
        }
    }

    // MARK: - Mark fresh

    /// Call after the user successfully authenticates (sign-in, 2FA, biometric).
    func markFreshAuth() {
        self.recentAuth = .fresh(expiresAt: Date().addingTimeInterval(window))
        self.pendingReauth = false
    }

    // MARK: - Force re-auth

    /// Used by Admin mutations and "Delete account". Returns true if the user
    /// successfully re-authenticated within `window`.
    ///
    /// Phase 2.5: tries biometric (Face ID / Touch ID) first; if unavailable
    /// or failed, sets `pendingReauth = true` so the calling view can present
    /// a password fallback sheet. The view calls `confirmReauth(password:)`
    /// when the user submits their password.
    func requireRecentAuth() async -> Bool {
        if case .fresh = recentAuth { return true }

        // Try biometric first.
        let biometricOK = await tryBiometric()
        if biometricOK {
            markFreshAuth()
            return true
        }

        // Fall back to password — surface a sheet on the calling view.
        pendingReauth = true
        return false
    }

    /// Called by the password fallback sheet when the user submits.
    @discardableResult
    func confirmReauth(password: String) async -> Bool {
        // Use real AuthService.signIn with the current user's email + provided password.
        guard let email = AuthService.shared.currentUserValue?.email else {
            return false
        }
        do {
            _ = try await AuthService.shared.signIn(email: email, password: password)
            markFreshAuth()
            return true
        } catch {
            return false
        }
    }

    func cancelReauth() {
        pendingReauth = false
    }

    // MARK: - Biometric

    private func tryBiometric() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let ctx = LAContext()
            var error: NSError?
            guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                cont.resume(returning: false)
                return
            }
            ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Подтвердите вход для этого действия"
            ) { success, _ in
                cont.resume(returning: success)
            }
        }
    }

    // MARK: - Sign out other devices

    func signOutOthers() async {
        struct EmptyBody: Codable, Sendable {}
        try? await APIClient.shared.requestNoBody(
            "auth/signout-others", method: .post, body: EmptyBody()
        )
        await tick()
    }
}

// MARK: - ActiveSession

struct ActiveSession: Sendable, Identifiable, Equatable {
    let id: String
    let device: String
    let location: String?
    let lastSeen: Date
    let isCurrent: Bool

    init(id: String, device: String, location: String?, lastSeen: Date, isCurrent: Bool) {
        self.id = id
        self.device = device
        self.location = location
        self.lastSeen = lastSeen
        self.isCurrent = isCurrent
    }
}

// MARK: - View modifier: RecentAuthGate

extension View {
    /// Wrap any destructive surface (Admin, Delete account) with a re-auth gate.
    /// Observes `gate.pendingReauth` and presents a password fallback sheet
    /// automatically when biometric fails or is unavailable.
    func plinkRecentAuthGate(_ gate: SessionSyncGate) -> some View {
        modifier(RecentAuthGateModifier(gate: gate))
    }
}

private struct RecentAuthGateModifier: ViewModifier {
    @Bindable var gate: SessionSyncGate

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { gate.pendingReauth },
                set: { if !$0 { gate.cancelReauth() } }
            )) {
                ReauthSheet(gate: gate)
            }
    }
}

private struct ReauthSheet: View {
    @Bindable var gate: SessionSyncGate
    @Environment(\.dismiss) private var dismiss
    @State private var password: String = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(.cyan)

            Text("Подтвердите вход")
                .font(.headline)
            Text("Это действие требует свежей авторизации.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField("Пароль", text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit { Task { await submit() } }

            if let err = error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if loading {
                        ProgressView().tint(.white)
                    }
                    Text("Подтвердить")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(password.isEmpty || loading)

            Button("Отмена") {
                gate.cancelReauth()
                dismiss()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .presentationDetents([.medium])
    }

    private func submit() async {
        loading = true
        error = nil
        let ok = await gate.confirmReauth(password: password)
        loading = false
        if ok {
            dismiss()
        } else {
            error = "Неверный пароль."
        }
    }
}

// MARK: - Superseded banner

struct SessionSupersededBanner: View {
    @Bindable var gate: SessionSyncGate

    init(gate: SessionSyncGate) {
        self.gate = gate
    }

    var body: some View {
        if case let .superseded(device, at) = gate.state {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Аккаунт открыт на другом устройстве")
                        .font(.subheadline.bold())
                    Text("\(device) · \(at.formatted(.dateTime.hour().minute()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Выйти там") {
                    Task { await gate.signOutOthers() }
                }
                .font(.caption.bold())
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal)
        }
    }
}
