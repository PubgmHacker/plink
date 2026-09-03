// Plink/Features/Auth2026/AuthErrorCopy.swift
//
// Человеческий русский текст на каждую ошибку входа и регистрации. Сырой ответ
// сервера и коды на экран не попадают: «Неверная почта или пароль», а не
// «401 invalid_credentials».
//
// Жил внутри LoginView2026.swift; вынесен в свой файл, когда вход и регистрация
// стали одним экраном (PlinkAuthScreen) и старые два были удалены.

import Foundation

enum AuthErrorCopy {
    static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .invalidCredentials:
                return L10n.text(.errBadCredentials)
            case .conflict:
                return L10n.text(.errAccountExists)
            case .unauthorized, .unauthorizedNeedsRefresh:
                return L10n.text(.errSessionEnded)
            case .notFound:
                return L10n.text(.errNotFound)
            // 402 и 503 на экране входа означают проблему не с подпиской, а с
            // самим сервисом: покупать здесь нечего, поэтому отдаём текст
            // сервера, если он есть, и нейтральную формулировку иначе.
            case .subscriptionRequired(_, _, let message):
                return message.isEmpty ? L10n.text(.errPlusOnly) : message
            case .unavailable(_, let message):
                return message.isEmpty ? L10n.text(.errComingSoon) : message
            case .invalidURL, .invalidResponse, .decodingError, .networkError:
                return L10n.text(.errUnavailable)
            case .serverError(let status, let message):
                if (400..<500).contains(status),
                   !message.isEmpty,
                   !message.lowercased().contains("unknown") {
                    return message
                }
                return L10n.text(.errUnavailable)
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return L10n.text(.errOffline)
            case .timedOut:
                return L10n.text(.errTimeout)
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return L10n.text(.errConnect)
            default:
                return L10n.text(.errGeneric)
            }
        }
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("invalid credentials") ||
            text.localizedCaseInsensitiveContains("неверный email") {
            return L10n.text(.errBadCredentials)
        }
        if text.localizedCaseInsensitiveContains("server") ||
            text.localizedCaseInsensitiveContains("host") ||
            text.localizedCaseInsensitiveContains("сервер") {
            return L10n.text(.errUnavailable)
        }
        return L10n.text(.errGeneric)
    }
}
