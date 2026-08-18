// Plink/Features/WatchRoom/AuthTokenProvider.swift
// Auth token provider with refresh support
//
// Instead of fixed String token, clients use AuthTokenProvider
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
        // Читаем через единое хранилище. Прямое чтение
        // "rave_auth_token" переставало работать после миграции ключа M39 —
        // комната теряла токен, не получала realtime-тикет и медиа,
        // и видео «не грузилось вообще».
        AuthTokenStore.shared.token
    }

    public func refreshToken() async -> String? {
        // Call POST /api/auth/refresh with refresh token from Keychain
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
            // Пишем через AuthTokenStore: он обновляет оба ключа Keychain и
            // сбрасывает свой кэш. Прямая запись только в легаси-ключ оставляла
            // в памяти хранилища устаревший токен после обновления сессии.
            AuthTokenStore.shared.save(decoded.accessToken)
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
