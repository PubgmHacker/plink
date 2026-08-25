// Plink/Services/GroupChatService.swift — M16/M17
// Групповые чаты (беседы), как в Telegram: список, сообщения, текст/фото.
// unread-бейджи, отметка прочтения, удаление сообщений, эмодзи-реакции.
// Серверная ИИ-модерация: муты за маты/NSFW приходят как ошибки и показываются баннером.

import Foundation
import SwiftUI

struct GroupChatDTO: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let ownerID: String
    let myRole: String
    let memberCount: Int
    let memberIds: [String]
    let lastMessageText: String?
    let lastMessageSender: String?
    let lastMessageAt: String?
    /// Непрочитанные сообщения (var — обнуляем локально при прочтении).
    var unreadCount: Int?
}

// Сервер отдаёт lastMessageAt строкой ISO-8601, иногда с
// миллисекундами (та же история, что и в APIClient/AuthService). Для сортировки
// unified inbox нужен Date, поэтому разбираем его один раз здесь, а не в каждой вьюхе.
extension GroupChatDTO {
    private static let isoWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Дата последнего сообщения; nil — если сообщений ещё нет или строка битая.
    var lastMessageDate: Date? {
        guard let lastMessageAt, !lastMessageAt.isEmpty else { return nil }
        return Self.isoWithFractionalSeconds.date(from: lastMessageAt)
            ?? Self.isoPlain.date(from: lastMessageAt)
    }
}

struct GroupMessageDTO: Codable, Identifiable, Equatable {
    let id: String
    let senderID: String
    let senderName: String
    let content: String
    let mediaType: String?
    let createdAt: String
    /// Реакции { "❤️": [userId, ...] } (var — обновляем локально).
    var reactions: [String: [String]]?
}

@MainActor
final class GroupChatService: ObservableObject {
    static let shared = GroupChatService()

    @Published var groups: [GroupChatDTO] = []
    @Published var messagesByGroup: [String: [GroupMessageDTO]] = [:]
    @Published var isLoading = false
    /// Сюда падают ошибки ИИ-модератора (мут/NSFW) — рендерятся баннером.
    @Published var errorMessage: String?

    private let api = APIClient.shared

    /// Суммарный unread по всем беседам — для бейджей/колокольчика.
    var unreadTotal: Int {
        groups.reduce(0) { $0 + ($1.unreadCount ?? 0) }
    }

    private struct GroupsResp: Codable { let groups: [GroupChatDTO] }
    private struct MessagesResp: Codable { let messages: [GroupMessageDTO] }
    private struct OkResp: Codable { let ok: Bool? }
    private struct ReactResp: Codable { let ok: Bool?; let reactions: [String: [String]]? }
    private struct CreatedGroupResp: Codable {
        let id: String
        let title: String
        let ownerID: String
        let memberCount: Int
    }

    // MARK: - Список бесед

    func loadGroups() async {
        isLoading = groups.isEmpty
        defer { isLoading = false }
        do {
            let resp: GroupsResp = try await api.request("groups")
            groups = resp.groups
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createGroup(title: String, memberIds: [String], clientRequestId: String) async -> Bool {
        struct Body: Encodable {
            let title: String
            let memberIds: [String]
            // Идемпотентность: таймаут → повторный тап «Создать» несёт тот же
            // ключ, сервер возвращает уже созданную беседу вместо дубля.
            let clientRequestId: String
        }
        do {
            let _: CreatedGroupResp = try await api.request(
                "groups",
                method: .post,
                body: Body(title: title, memberIds: memberIds, clientRequestId: clientRequestId)
            )
            await loadGroups()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Сообщения

    func loadMessages(groupId: String) async {
        do {
            let resp: MessagesResp = try await api.request("groups/\(groupId)/messages")
            messagesByGroup[groupId] = resp.messages
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Догрузка только новых сообщений (поллинг открытой беседы).
    func refreshMessages(groupId: String) async {
        let existing = messagesByGroup[groupId] ?? []
        guard let last = existing.last else {
            await loadMessages(groupId: groupId)
            return
        }
        do {
            let resp: MessagesResp = try await api.request(
                "groups/\(groupId)/messages",
                query: ["after": last.createdAt]
            )
            guard !resp.messages.isEmpty else { return }
            let known = Set(existing.map(\.id))
            let fresh = resp.messages.filter { !known.contains($0.id) }
            if !fresh.isEmpty {
                messagesByGroup[groupId] = existing + fresh
            }
        } catch {
            // тихий поллинг — не шумим баннером
        }
    }

    @discardableResult
    func send(groupId: String, content: String, imageData: String? = nil) async -> Bool {
        struct Body: Encodable { let content: String; let imageData: String? }
        do {
            let saved: GroupMessageDTO = try await api.request(
                "groups/\(groupId)/messages",
                method: .post,
                body: Body(content: content, imageData: imageData)
            )
            var list = messagesByGroup[groupId] ?? []
            if !list.contains(where: { $0.id == saved.id }) {
                list.append(saved)
            }
            messagesByGroup[groupId] = list
            return true
        } catch {
            // Ошибки модерации (мут/NSFW) приходят сюда и показываются баннером
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Прочтение / удаление / реакции

    /// Отметить беседу прочитанной (сервер + локальный бейдж).
    func markRead(groupId: String) async {
        if let idx = groups.firstIndex(where: { $0.id == groupId }) {
            groups[idx].unreadCount = 0
        }
        struct Empty: Encodable {}
        do {
            let _: OkResp = try await api.request(
                "groups/\(groupId)/read",
                method: .post,
                body: Empty()
            )
        } catch {
            // некритично — синхронизируется при следующем loadGroups
        }
    }

    /// Удалить сообщение (своё; owner/admin — любое). Soft delete на сервере.
    @discardableResult
    func deleteMessage(groupId: String, messageId: String) async -> Bool {
        do {
            let _: OkResp = try await api.request(
                "groups/\(groupId)/messages/\(messageId)",
                method: .delete
            )
            messagesByGroup[groupId]?.removeAll { $0.id == messageId }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Переключить эмодзи-реакцию на сообщении.
    func react(groupId: String, messageId: String, emoji: String) async {
        struct Body: Encodable { let emoji: String }
        do {
            let resp: ReactResp = try await api.request(
                "groups/\(groupId)/messages/\(messageId)/react",
                method: .post,
                body: Body(emoji: emoji)
            )
            if var list = messagesByGroup[groupId],
               let idx = list.firstIndex(where: { $0.id == messageId }) {
                list[idx].reactions = resp.reactions ?? [:]
                messagesByGroup[groupId] = list
            }
        } catch {
            // тихо — реакция не критична
        }
    }

    // MARK: - Управление

    @discardableResult
    func addMembers(groupId: String, userIds: [String]) async -> Bool {
        struct Body: Encodable { let userIds: [String] }
        do {
            let _: OkResp = try await api.request(
                "groups/\(groupId)/members",
                method: .post,
                body: Body(userIds: userIds)
            )
            await loadGroups()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func leave(groupId: String) async -> Bool {
        struct Empty: Encodable {}
        do {
            let _: OkResp = try await api.request(
                "groups/\(groupId)/leave",
                method: .post,
                body: Empty()
            )
            groups.removeAll { $0.id == groupId }
            messagesByGroup[groupId] = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
