// Plink/Features/WatchRoom/AuthTokenProvider.swift
// Auth token provider with refresh support (Brain Review 8 P1-55/P1-60)
//
// P1-55: Instead of fixed String token, clients use AuthTokenProvider
// which can refresh on 401. RESTChatCatchupClient calls refreshToken()
// on auth failure, then retries once.

import Foundation

@MainActor
public protocol AuthTokenProvider: AnyObject, Sendable {
    /// Returns current access token, or nil if not authenticated.
    var currentToken: String? { get }

    /// Refreshes the token. Returns new token or nil on failure.
    func refreshToken() async -> String?
}

/// Keychain-based token provider — reads from KeychainHelper, refreshes
/// via AuthService when token is expired or 401 is received.
@MainActor
public final class KeychainAuthTokenProvider: AuthTokenProvider {
    private let apiBaseURL: URL

    public init(apiBaseURL: URL) {
        self.apiBaseURL = apiBaseURL
    }

    public var currentToken: String? {
        KeychainHelper.read(for: "rave_auth_token")
    }

    public func refreshToken() async -> String? {
        // P1-55: call POST /api/auth/refresh with refresh token from Keychain
        guard let refreshToken = KeychainHelper.read(for: "rave_refresh_token") else {
            return currentToken  // No refresh token — return current (may be nil)
        }

        var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/auth/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["refreshToken": refreshToken]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return currentToken  // Refresh failed — return current
            }
            let decoded = try JSONDecoder().decode(RefreshResponse.self, from: data)
            // Save new token to Keychain
            KeychainHelper.save(decoded.accessToken, for: "rave_auth_token")
            if let newRefresh = decoded.refreshToken {
                KeychainHelper.save(newRefresh, for: "rave_refresh_token")
            }
            return decoded.accessToken
        } catch {
            return currentToken  // Network error — return current
        }
    }
}

private struct RefreshResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
}
