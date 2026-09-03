// Plink/Services/GroupChatService.swift — M16/M17
// Групповые чаты (беседы), как в Telegram: список, сообщения, текст/фото.
// unread-бейджи, отметка прочтения, удаление сообщений, эмодзи-реакции.
// Серверная ИИ-модерация: муты за маты/NSFW приходят как ошибки и показываются баннером.

import Foundation
import SwiftUI

struct GroupChatDTO: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    let ownerID: String
    let myRole: String
    var memberCount: Int
    let memberIds: [String]
    let lastMessageText: String?
    let lastMessageSender: String?
    let lastMessageAt: String?
    /// Непрочитанные сообщения (var — обнуляем локально при прочтении).
    var unreadCount: Int?
    /// Описание беседы (настройки, как в Telegram).
    var description: String?
    /// Версия аватара беседы в миллисекундах — ключ ?v= и признак «фото есть».
    var avatarVersion: Double?
}

// Сервер отдаёт lastMessageAt строкой ISO-8601, иногда с
// миллисекундами (та же история, что и в APIClient/AuthService). Для сортировки
// unified inbox нужен Date, поэтому разбираем его один раз здесь, а не в каждой вьюхе.
/// Разбор ISO-8601 в датах беседы: сервер отдаёт то с миллисекундами, то без.
/// Один разборщик на все карточки — строк с датами тут три (сообщение,
/// последний визит участника, создание беседы), и три копии форматтеров
/// расходились бы при первом же изменении формата.
enum GroupISODate {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return withFraction.date(from: raw) ?? plain.date(from: raw)
    }
}

extension GroupChatDTO {
    /// Дата последнего сообщения; nil — если сообщений ещё нет или строка битая.
    var lastMessageDate: Date? { GroupISODate.parse(lastMessageAt) }
}

// MARK: - Настройки беседы (участники, роли, права)

struct GroupMemberDTO: Codable, Identifiable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let avatarURL: String?
    let avatarVersion: Double?
    let isOnline: Bool
    let lastSeenAt: String?
    var role: String
    let joinedAt: String?
    let isDeleted: Bool?

    var isOwner: Bool { role == "owner" }
    var isAdmin: Bool { role == "admin" }
    /// Имя для показа: displayName, иначе @ник.
    var name: String {
        let dn = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return dn.isEmpty ? username : dn
    }
}

/// Права участников беседы. Владелец и админы не ограничены никогда.
struct GroupPermissionsDTO: Codable, Equatable {
    var membersCanInvite: Bool
    var membersCanSendMedia: Bool
    var membersCanChangeInfo: Bool
}

/// Что именно доступно мне в этой беседе — считает сервер, клиент не угадывает.
struct GroupMyPermissionsDTO: Codable, Equatable {
    let canChangeInfo: Bool
    let canInvite: Bool
    let canSendMedia: Bool
    let canManagePermissions: Bool
    let canManageAdmins: Bool
    let canRemoveMembers: Bool
    let canDeleteGroup: Bool
}

struct GroupDetailDTO: Codable, Equatable {
    let id: String
    var title: String
    var description: String?
    let ownerID: String
    let createdAt: String?
    let myRole: String
    var memberCount: Int
    let messageCount: Int?
    var avatarVersion: Double?
    let maxMembers: Int?
    var permissions: GroupPermissionsDTO
    let myPermissions: GroupMyPermissionsDTO
    var members: [GroupMemberDTO]

    var admins: [GroupMemberDTO] { members.filter { $0.isOwner || $0.isAdmin } }
}

extension GroupMemberDTO {
    /// Последний визит участника — для строки присутствия в настройках беседы.
    var lastSeenDate: Date? { GroupISODate.parse(lastSeenAt) }
}

extension GroupDetailDTO {
    /// Когда беседу создали — строка «Создана» в информации.
    var createdDate: Date? { GroupISODate.parse(createdAt) }
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
    /// Первая загрузка ещё не завершалась. До неё пустой `groups` значит
    /// «не знаем», а не «бесед нет» — инбокс рисует скелет, а не пустоту.
    @Published private(set) var didLoadOnce = false
    /// Сюда падают ошибки ИИ-модератора (мут/NSFW) — рендерятся баннером.
    @Published var errorMessage: String?

    private let api = APIClient.shared
    private var userEventObserver: NSObjectProtocol?
    /// Request generations prevent a slower, older list response from erasing
    /// a group that arrived through the realtime hint while the first request
    /// was still in flight.
    private var groupsRequestGeneration = 0
    /// One history request per group at a time. Realtime + the two-second poll
    /// otherwise raced and made the same message appear twice during a merge.
    private var messageRequestsInFlight: Set<String> = []
    private var messageRevisionByGroup: [String: Int] = [:]

    private func messageRevision(for groupId: String) -> Int {
        messageRevisionByGroup[groupId] ?? 0
    }

    private func markMessageMutation(for groupId: String) {
        messageRevisionByGroup[groupId, default: 0] &+= 1
    }

    private func normalizedMessages(_ input: [GroupMessageDTO]) -> [GroupMessageDTO] {
        var byID: [String: GroupMessageDTO] = [:]
        for message in input where !message.id.isEmpty {
            byID[message.id] = message
        }
        return byID.values.sorted {
            let left = GroupISODate.parse($0.createdAt) ?? .distantPast
            let right = GroupISODate.parse($1.createdAt) ?? .distantPast
            if left != right { return left < right }
            return $0.id < $1.id
        }
    }

    private func mergedMessages(_ current: [GroupMessageDTO], _ incoming: [GroupMessageDTO]) -> [GroupMessageDTO] {
        normalizedMessages(current + incoming)
    }

    init() {
        userEventObserver = NotificationCenter.default.addObserver(
            forName: .plinkUserEvent,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let type = note.userInfo?["type"] as? String,
                  type.hasPrefix("group:") else { return }
            Task { @MainActor in
                await self?.handleUserEvent(type: type, userInfo: note.userInfo)
            }
        }
    }

    deinit {
        if let userEventObserver {
            NotificationCenter.default.removeObserver(userEventObserver)
        }
    }

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
        groupsRequestGeneration &+= 1
        let generation = groupsRequestGeneration
        isLoading = groups.isEmpty
        // didLoadOnce взводится и после ошибки: попытка была, скелет не вечен.
        defer {
            if generation == groupsRequestGeneration { isLoading = false; didLoadOnce = true }
        }
        do {
            let resp: GroupsResp = try await api.request("groups")
            // A newer request owns the state now. Applying this older response
            // would make a newly invited member disappear until the next poll.
            guard generation == groupsRequestGeneration else { return }
            groups = resp.groups
        } catch {
            if generation == groupsRequestGeneration {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Realtime is a freshness hint, not the data source. Always reconcile
    /// through REST so a dropped event cannot create a partial/invented row.
    private func handleUserEvent(type: String, userInfo: [AnyHashable: Any]?) async {
        guard let groupID = userInfo?["groupId"] as? String, !groupID.isEmpty else {
            await loadGroups()
            return
        }
        switch type {
        case "group:created", "group:updated", "group:role":
            await loadGroups()
        case "group:message":
            await loadGroups()
            await refreshMessages(groupId: groupID)
        case "group:removed":
            groups.removeAll { $0.id == groupID }
            messagesByGroup[groupID] = nil
        default:
            break
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
        guard messageRequestsInFlight.insert(groupId).inserted else { return }
        let revision = messageRevision(for: groupId)
        defer { messageRequestsInFlight.remove(groupId) }
        do {
            let resp: MessagesResp = try await api.request("groups/\(groupId)/messages")
            if revision == messageRevision(for: groupId) {
                messagesByGroup[groupId] = normalizedMessages(resp.messages)
            } else {
                // A send/delete/reaction landed while the snapshot was in
                // flight. Keep the local mutation and reconcile the server
                // rows without introducing duplicate IDs.
                messagesByGroup[groupId] = mergedMessages(messagesByGroup[groupId] ?? [], resp.messages)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Догрузка только новых сообщений (поллинг открытой беседы).
    func refreshMessages(groupId: String) async {
        guard messageRequestsInFlight.insert(groupId).inserted else { return }
        defer { messageRequestsInFlight.remove(groupId) }
        let existing = messagesByGroup[groupId] ?? []
        guard let last = existing.last else {
            // We already hold the per-group request gate, so perform the
            // initial request inline rather than recursively returning early.
            do {
                let resp: MessagesResp = try await api.request("groups/\(groupId)/messages")
                messagesByGroup[groupId] = normalizedMessages(resp.messages)
            } catch {
                // тихий поллинг — не шумим баннером
            }
            return
        }
        do {
            let resp: MessagesResp = try await api.request(
                "groups/\(groupId)/messages",
                query: ["after": last.createdAt]
            )
            guard !resp.messages.isEmpty else { return }
            messagesByGroup[groupId] = mergedMessages(existing, resp.messages)
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
            messagesByGroup[groupId] = mergedMessages(messagesByGroup[groupId] ?? [], [saved])
            markMessageMutation(for: groupId)
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
            markMessageMutation(for: groupId)
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
                markMessageMutation(for: groupId)
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

    // MARK: - Настройки беседы

    /// Карточка беседы: участники, роли, права. Экран настроек живёт на ней.
    func loadDetail(groupId: String) async -> GroupDetailDTO? {
        do {
            let detail: GroupDetailDTO = try await api.request("groups/\(groupId)")
            syncListRow(from: detail)
            return detail
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Тело PATCH /groups/:id. Ключ отсутствует — «не трогать»; ключ со
    /// значением null — «стереть». Без этого различия нельзя убрать описание
    /// или аватар: пустой Encodable-опционал просто выпадает из JSON.
    struct GroupPatch: Encodable {
        var title: String?
        var description: String??
        var avatarData: String??
        var membersCanInvite: Bool?
        var membersCanSendMedia: Bool?
        var membersCanChangeInfo: Bool?

        enum CodingKeys: String, CodingKey {
            case title, description, avatarData
            case membersCanInvite, membersCanSendMedia, membersCanChangeInfo
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(title, forKey: .title)
            if let description {
                if let text = description { try c.encode(text, forKey: .description) }
                else { try c.encodeNil(forKey: .description) }
            }
            if let avatarData {
                if let data = avatarData { try c.encode(data, forKey: .avatarData) }
                else { try c.encodeNil(forKey: .avatarData) }
            }
            try c.encodeIfPresent(membersCanInvite, forKey: .membersCanInvite)
            try c.encodeIfPresent(membersCanSendMedia, forKey: .membersCanSendMedia)
            try c.encodeIfPresent(membersCanChangeInfo, forKey: .membersCanChangeInfo)
        }
    }

    struct GroupPatchResult: Codable, Equatable {
        let id: String
        let title: String
        let description: String?
        let avatarVersion: Double?
        let permissions: GroupPermissionsDTO
    }

    /// Изменить беседу: название, описание, аватар, права участников.
    func patch(groupId: String, _ patch: GroupPatch) async -> GroupPatchResult? {
        do {
            let result: GroupPatchResult = try await api.request(
                "groups/\(groupId)",
                method: .patch,
                body: patch
            )
            if let idx = groups.firstIndex(where: { $0.id == groupId }) {
                groups[idx].title = result.title
                groups[idx].description = result.description
                groups[idx].avatarVersion = result.avatarVersion
            }
            if patch.avatarData != nil {
                // Строки чатов держат картинку в памяти — заставляем перечитать ?v=
                NotificationCenter.default.post(name: .plinkGroupAvatarDidChange, object: groupId)
            }
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Назначить/снять администратора (только владелец беседы).
    @discardableResult
    func setRole(groupId: String, userId: String, role: String) async -> Bool {
        struct Body: Encodable { let role: String }
        do {
            let _: OkResp = try await api.request(
                "groups/\(groupId)/members/\(userId)/role",
                method: .post,
                body: Body(role: role)
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Исключить участника (owner/admin).
    @discardableResult
    func removeMember(groupId: String, userId: String) async -> Bool {
        do {
            let _: OkResp = try await api.request(
                "groups/\(groupId)/members/\(userId)",
                method: .delete
            )
            if let idx = groups.firstIndex(where: { $0.id == groupId }) {
                groups[idx].memberCount = max(1, groups[idx].memberCount - 1)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Удалить беседу у всех участников (только владелец).
    @discardableResult
    func deleteGroup(groupId: String) async -> Bool {
        do {
            let _: OkResp = try await api.request("groups/\(groupId)", method: .delete)
            groups.removeAll { $0.id == groupId }
            messagesByGroup[groupId] = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Подтягивает строку списка под свежую карточку — чтобы название и фото
    /// в инбоксе не отставали от экрана настроек до следующего поллинга.
    private func syncListRow(from detail: GroupDetailDTO) {
        guard let idx = groups.firstIndex(where: { $0.id == detail.id }) else { return }
        groups[idx].title = detail.title
        groups[idx].description = detail.description
        groups[idx].avatarVersion = detail.avatarVersion
        groups[idx].memberCount = detail.memberCount
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
