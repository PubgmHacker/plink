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
                return "Неверная почта или пароль"
            case .conflict:
                return "Аккаунт с такими данными уже существует"
            case .unauthorized, .unauthorizedNeedsRefresh:
                return "Сессия завершена. Войдите снова"
            case .notFound:
                return "Не удалось найти нужные данные"
            // 402 и 503 на экране входа означают проблему не с подпиской, а с
            // самим сервисом: покупать здесь нечего, поэтому отдаём текст
            // сервера, если он есть, и нейтральную формулировку иначе.
            case .subscriptionRequired(_, _, let message):
                return message.isEmpty ? "Эта возможность доступна в Плинк+" : message
            case .unavailable(_, let message):
                return message.isEmpty ? "Функция скоро появится" : message
            case .invalidURL, .invalidResponse, .decodingError, .serverError, .networkError:
                return "Plink сейчас недоступен. Попробуйте ещё раз чуть позже"
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "Нет подключения к интернету"
            case .timedOut:
                return "Сервис отвечает слишком долго. Попробуйте ещё раз"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Не удалось подключиться к Plink. Проверьте интернет и повторите"
            default:
                return "Не удалось выполнить действие. Попробуйте ещё раз"
            }
        }
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("invalid credentials") ||
            text.localizedCaseInsensitiveContains("неверный email") {
            return "Неверная почта или пароль"
        }
        if text.localizedCaseInsensitiveContains("server") ||
            text.localizedCaseInsensitiveContains("host") ||
            text.localizedCaseInsensitiveContains("сервер") {
            return "Plink сейчас недоступен. Попробуйте ещё раз чуть позже"
        }
        return "Не удалось выполнить действие. Попробуйте ещё раз"
    }
}
