//  DeepLinkRouter+UniversalLinks.swift
//  Plink — M39
//
//  Бэкенд теперь отдаᄅт AASA в корне домена, значит ссылка https://plink.app/r/ABCD
//  должна открываться прямо в приложении, а не в Safari. Без этого весь
//  виральный контур «пригласил → пришᄅл → смотрит» теряет шаг на лендинге.

import Foundation

extension DeepLinkRouter {

    enum Destination: Equatable {
        case room(code: String)
        case profile(username: String)
        case paywall
        case unknown
    }

    private static let allowedHosts: Set<String> = ["plink.app", "www.plink.app"]

    /// Разбор входящей ссылки. Чистая функция — еᄅ легко покрыть тестами.
    static func destination(for url: URL) -> Destination {
        // Кастомная схема plink://
        if url.scheme == "plink" {
            switch url.host {
            case "room":
                let code = url.pathComponents.dropFirst().first ?? ""
                return code.isEmpty ? .unknown : .room(code: code.uppercased())
            case "u", "user":
                let name = url.pathComponents.dropFirst().first ?? ""
                return name.isEmpty ? .unknown : .profile(username: name)
            case "plus", "paywall":
                return .paywall
            default:
                return .unknown
            }
        }

        // Universal Link https://plink.app/...
        guard let host = url.host?.lowercased(), allowedHosts.contains(host) else {
            return .unknown
        }

        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return .unknown }

        switch parts[0] {
        case "r":
            let code = parts[1].uppercased()
            let isValid = code.count >= 4 && code.count <= 12
                && code.allSatisfy { $0.isLetter || $0.isNumber }
            return isValid ? .room(code: code) : .unknown
        case "u":
            let name = parts[1]
            let isValid = name.count >= 3 && name.count <= 32
                && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
            return isValid ? .profile(username: name) : .unknown
        case "plus":
            return .paywall
        default:
            return .unknown
        }
    }

    /// Если пользователь ещᄅ не вошёл, ссылку надо запомнить и применить после входа.
    /// Потерять еᄅ здесь — значит потерять приглашᄅнного друга.
    private static let pendingKey = "plink.pendingDeepLink"

    static func storePending(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: pendingKey)
    }

    static func consumePending() -> Destination? {
        guard let raw = UserDefaults.standard.string(forKey: pendingKey),
              let url = URL(string: raw) else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        return destination(for: url)
    }
}
