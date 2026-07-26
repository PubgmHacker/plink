//  ModerationService.swift
//  Plink — M39
//
//  Формальные механизмы модерации: жалобы, блок-лист, согласие с правилами.
//  ИИ-модерация из M16 остаётся и работает параллельно — она их не заменяет.

import Foundation

@MainActor
final class ModerationService: ObservableObject {
    static let shared = ModerationService()

    enum TargetType: String {
        case user, message, room
    }

    enum Reason: String, CaseIterable, Identifiable {
        case spam, harassment, hate, sexual, violence, illegal, copyright, other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .spam: return "Спам или реклама"
            case .harassment: return "Травля или угрозы"
            case .hate: return "Ненависть и дискриминация"
            case .sexual: return "Контент 18+"
            case .violence: return "Насилие и жестокость"
            case .illegal: return "Незаконный контент"
            case .copyright: return "Нарушение авторских прав"
            case .other: return "Другое"
            }
        }

        var icon: String {
            switch self {
            case .spam: return "envelope.badge"
            case .harassment: return "exclamationmark.bubble"
            case .hate: return "hand.raised.slash"
            case .sexual: return "eye.slash"
            case .violence: return "bolt.trianglebadge.exclamationmark"
            case .illegal: return "xmark.shield"
            case .copyright: return "c.circle"
            case .other: return "ellipsis.circle"
            }
        }
    }

    @Published private(set) var blockedUserIDs: Set<String> = []
    @Published var lastError: String?

    private let blockedKey = "plink.blockedUsers"
    private let eulaKey = "plink.eulaAcceptedVersion"
    private let currentEULAVersion = 1

    private init() {
        blockedUserIDs = Set(UserDefaults.standard.stringArray(forKey: blockedKey) ?? [])
    }

    var hasAcceptedEULA: Bool {
        UserDefaults.standard.integer(forKey: eulaKey) >= currentEULAVersion
    }

    func acceptEULA() {
        UserDefaults.standard.set(currentEULAVersion, forKey: eulaKey)
    }

    func report(targetType: TargetType, targetId: String, reason: Reason, comment: String?) async {
        var body: [String: Any] = [
            "targetType": targetType.rawValue,
            "targetId": targetId,
            "reason": reason.rawValue,
        ]
        if let comment { body["comment"] = comment }
        await send(path: "/api/moderation/report", method: "POST", body: body)
    }

    func block(userID: String) async {
        // Оптимистично скрываем сразу: ждать сеть, когда тебя оскорбляют, — плохой опыт.
        blockedUserIDs.insert(userID)
        persistBlocked()
        await send(path: "/api/moderation/block", method: "POST", body: ["userId": userID])
    }

    func unblock(userID: String) async {
        blockedUserIDs.remove(userID)
        persistBlocked()
        await send(path: "/api/moderation/block/\(userID)", method: "DELETE", body: nil)
    }

    func isBlocked(_ userID: String) -> Bool {
        blockedUserIDs.contains(userID)
    }

    func refreshBlockedList() async {
        guard let url = URL(string: PlinkConfig.baseURLString + "/api/moderation/blocked") else { return }
        var request = URLRequest(url: url)
        if let token = AuthTokenStore.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 10

        struct Response: Decodable { let blockedUserIds: [String] }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return }

        blockedUserIDs = Set(decoded.blockedUserIds)
        persistBlocked()
    }

    private func persistBlocked() {
        UserDefaults.standard.set(Array(blockedUserIDs), forKey: blockedKey)
    }

    private func send(path: String, method: String, body: [String: Any]?) async {
        guard let url = URL(string: PlinkConfig.baseURLString + path) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = AuthTokenStore.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body { request.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200..<300).contains(code) {
                lastError = "Не удалось выполнить действие. Попробуйте ещё раз."
            }
        } catch {
            lastError = "Нет связи с сервером. Действие применено локально."
        }
    }
}
