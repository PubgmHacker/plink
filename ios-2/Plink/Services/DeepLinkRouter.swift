import Foundation
import SwiftUI

// MARK: - Deep Link Router (Блок 3 — Universal Links)
/// Маршрутизатор deep-links. Распознаёт ДВА типа ссылок:
///
/// 1. Ссылка на комнату: `https://yourdomain.com/r/<code>`
///    → автоматически открывает комнату.
///
/// 2. Ссылка-приглашение в друзья: `https://yourdomain.com/u/<userId>`
///    → перебрасывает в приложение и автоматически отправляет заявку в друзья.
///
/// Поддерживает Universal Links (https), custom scheme (raveclone://),
/// и ручной ввод кода.

@MainActor
final class DeepLinkRouter: ObservableObject {

    /// Единственный экземпляр роутера на всё приложение.
    /// (FIX: "Type 'DeepLinkRouter' has no member 'shared'" — PushNotificationService
    /// и AppDelegate обрабатывают ссылки вне SwiftUI-иерархии, поэтому им нужен
    /// доступ к тому же объекту, что и @EnvironmentObject в PlinkApp.)
    static let shared = DeepLinkRouter()

    // MARK: - Published

    /// Текущий распознанный deep-link (управляет навигацией).
    @Published var pendingLink: DeepLinkType = .none

    // MARK: - Config

    static let domain = "plink.app"
    static let customScheme = "plink"
    /// Схема старых ссылок, разосланных до ребрендинга.
    static let legacyScheme = "raveclone"

    // MARK: - Parsing

    /// Разбирает URL любого типа и возвращает DeepLinkType.
    func parse(_ url: URL) -> DeepLinkType {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        // Universal Link: https://plink.app/r/<code>  или  /u/<userId>
        if url.host == Self.domain || url.host == "www.\(Self.domain)" {
            return parsePath(url.path, queryItems: components?.queryItems)
        }

        // Custom scheme: plink://r/<code> (плюс легаси raveclone://).
        // В custom-scheme URL первый сегмент пути попадает в host
        // (в plink://r/ABCDEF host = "r", path = "/ABCDEF"), поэтому склеиваем
        // host + path перед разбором — иначе /u/<userId> терял сегмент "u".
        if url.scheme == Self.customScheme || url.scheme == Self.legacyScheme {
            let fullPath = (url.host ?? "") + url.path
            return parsePath(fullPath, queryItems: components?.queryItems)
        }

        return .none
    }

    private func parsePath(_ path: String, queryItems: [URLQueryItem]?) -> DeepLinkType {
        // Нормализуем путь: убираем ведущий слэш, разбиваем на сегменты.
        let segments = path.split(separator: "/").map(String.init)

        guard let first = segments.first else { return .none }

        switch first {
        // "join" — формат ссылок из старых share-текстов (https://plink.app/join/<code>),
        // "room" — формат plink://room/<code>. Канонический — /r/<code>.
        case "r", "room", "join":
            // /r/<code> или /r?code=<code>
            if segments.count >= 2 {
                return .room(code: segments[1])
            }
            if let code = queryItems?.first(where: { $0.name == "code" })?.value {
                return .room(code: code)
            }
            return .none

        case "u":
            // /u/<userId> — приглашение в друзья
            if segments.count >= 2 {
                return .friendInvite(userId: segments[1])
            }
            if let userId = queryItems?.first(where: { $0.name == "userId" })?.value {
                return .friendInvite(userId: userId)
            }
            return .none

        default:
            // Старый формат: голый /<code> (6 символов) — считаем кодом комнаты.
            if first.count == 6, first.allSatisfy({ $0.isLetter || $0.isNumber }) {
                return .room(code: first)
            }
            return .none
        }
    }

    // MARK: - Public Handle

    /// Главный метод: парсит URL и устанавливает pendingLink для навигации.
    func handle(_ url: URL) {
        let link = parse(url)
        guard link != .none else { return }
        pendingLink = link
    }

    /// Сбрасывает текущий pending-link (после обработки).
    func clear() {
        pendingLink = .none
    }

    // MARK: - URL Generation

    /// Генерирует ссылку на комнату для Share Sheet.
    static func roomURL(code: String) -> URL {
        URL(string: "https://\(Self.domain)/r/\(code)")!
    }

    /// Генерирует ссылку-приглашение в друзья.
    static func friendInviteURL(userId: String) -> URL {
        URL(string: "https://\(Self.domain)/u/\(userId)")!
    }
}
