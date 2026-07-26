//
//  PlinkAuthBridge.swift
//  Plink
//
//  Phase 2.6 / 2.7 / 4 — V5 Auth bridges.
//
//  Adds the missing methods on `AuthService` that V5 surfaces need but the
//  real `AuthService` (in `Plink/Services/AuthService.swift`) does not yet
//  implement. All bridges call the real `APIClient.shared` against the
//  backend endpoints listed in PLINK_MASTER_PLAN_10_OF_10.md Phase 4.
//

import Foundation

// MARK: - DTOs for V5 auth bridges

internal struct CheckUsernameResponse: Codable, Sendable {
    let available: Bool
}

internal struct DeleteAccountRequest: Codable, Sendable {
    let reason: String
    let confirmAccountId: String  // backend requires user to type their ID
}

internal struct DeleteAccountResponse: Codable, Sendable {
    let scheduledForDeletionAt: Date?
    let message: String
}

internal struct UpdateAppearanceRequest: Codable, Sendable {
    let appThemeID: String
    let bubbleStyleID: String
    let emojiPackID: String
}

internal struct FetchAppearanceResponse: Codable, Sendable {
    let appThemeID: String
    let bubbleStyleID: String
    let emojiPackID: String
}

internal struct RoomAppearanceUpdate: Codable, Sendable {
    let themeId: String
    let themeRevision: Int
    let intensity: Double
    let motionEnabled: Bool
}

// MARK: - AuthService bridges

internal extension AuthService {

    // MARK: 2.6 — Nickname availability

    /// Phase 2.6: real `GET /api/auth/check-username?username=...`
    /// Returns true if the nickname is available for registration.
    @MainActor
    func checkNicknameAvailability(_ nickname: String) async throws -> Bool {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return false }

        let resp: CheckUsernameResponse = try await APIClient.shared.request(
            "auth/check-username",
            method: .get,
            query: ["username": trimmed]
        )
        return resp.available
    }

    // MARK: 2.7 — Account deletion

    /// Phase 2.7: real `POST /api/profile/delete`.
    /// Backend schedules the deletion with a grace period (e.g. 14 days)
    /// and returns the scheduled date.
    @MainActor
    func requestAccountDeletion(reason: String) async throws -> DeleteAccountResponse {
        guard let accountId = currentUserValue?.id else {
            throw NSError(
                domain: "PlinkAuth",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Нет активной сессии"]
            )
        }
        let body = DeleteAccountRequest(
            reason: reason,
            confirmAccountId: accountId
        )
        let resp: DeleteAccountResponse = try await APIClient.shared.request(
            "profile/delete",
            method: .post,
            body: body
        )
        return resp
    }

    // MARK: 4 — Appearance sync (ProfileAPI)

    /// Phase 4: real `PUT /api/profile/appearance`
    @MainActor
    func updateAppearance(
        appThemeID: String,
        bubbleStyleID: String,
        emojiPackID: String
    ) async throws {
        let body = UpdateAppearanceRequest(
            appThemeID: appThemeID,
            bubbleStyleID: bubbleStyleID,
            emojiPackID: emojiPackID
        )
        // 204 No Content — use requestNoBody.
        try await APIClient.shared.requestNoBody(
            "profile/appearance",
            method: .put,
            body: body
        )
    }

    /// Phase 4: real `GET /api/profile/appearance`
    @MainActor
    func fetchAppearance() async throws -> FetchAppearanceResponse {
        try await APIClient.shared.request("profile/appearance", method: .get)
    }

    // MARK: 4 — Sign out other sessions

    /// Phase 4: real `POST /api/auth/signout-others`
    @MainActor
    func signOutOtherSessions() async throws {
        struct EmptyBody: Codable, Sendable {}
        try await APIClient.shared.requestNoBody(
            "auth/signout-others",
            method: .post,
            body: EmptyBody()
        )
    }
}
