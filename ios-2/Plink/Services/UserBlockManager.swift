import Foundation
import Combine

// MARK: - User Block Manager (Apple UGC: report + block)
/// Local block list + real backend moderation APIs.
///
/// - POST /api/moderation/report
/// - POST /api/moderation/block
/// - DELETE /api/moderation/block/:userId
/// - GET /api/moderation/blocks
@MainActor
final class UserBlockManager: ObservableObject {

    static let shared = UserBlockManager()

    @Published private(set) var blockedUserIds: Set<String> = []

    var onBlockChanged: ((String, Bool) -> Void)?

    private let defaults = UserDefaults.standard
    private let storageKey = "rave_blocked_users"
    private var api: APIClient { APIClient.shared }

    init() {
        loadBlockedUsers()
    }

    // MARK: - Block / Unblock

    func blockUser(_ userId: String) {
        blockedUserIds.insert(userId)
        persist()
        onBlockChanged?(userId, true)
        // Telegram: blocked peer disappears from active chat flow
        DMChatService.shared.clearLocalChat(friendId: userId)
        Task { await syncBlockToServer(userId: userId) }
    }

    /// Block + wipe DM history (Telegram «Заблокировать» with chat clear).
    func blockAndDeleteChat(userId: String, friend: Friend? = nil) async {
        blockUser(userId)
        if let friend {
            await DMChatService.shared.deleteChat(with: friend)
        } else {
            // Still clear server thread if we only have id
            struct Resp: Decodable { let success: Bool? }
            _ = try? await api.request("messages/dm/\(userId)", method: .delete) as Resp
            DMChatService.shared.clearLocalChat(friendId: userId)
        }
    }

    func unblockUser(_ userId: String) {
        blockedUserIds.remove(userId)
        persist()
        onBlockChanged?(userId, false)
        Task { await syncUnblockToServer(userId: userId) }
    }

    func toggleBlock(_ userId: String) {
        if blockedUserIds.contains(userId) {
            unblockUser(userId)
        } else {
            blockUser(userId)
        }
    }

    func isBlocked(_ userId: String) -> Bool {
        blockedUserIds.contains(userId)
    }

    // MARK: - Filtering

    func filterMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard !blockedUserIds.isEmpty else { return messages }
        return messages.filter { !blockedUserIds.contains($0.senderID) }
    }

    func filterRooms(_ rooms: [Room]) -> [Room] {
        guard !blockedUserIds.isEmpty else { return rooms }
        return rooms.filter { !blockedUserIds.contains($0.hostID) }
    }

    // MARK: - Report (real backend)

    /// Report user / message / room. Reasons: spam | harassment | nsfw | other
    func report(
        targetUserId: String? = nil,
        roomId: String? = nil,
        messageId: String? = nil,
        reason: ReportReason,
        details: String? = nil
    ) async throws {
        struct Body: Encodable {
            let targetUserId: String?
            let roomId: String?
            let messageId: String?
            let reason: String
            let details: String?
        }
        struct Resp: Decodable { let success: Bool? }

        let _: Resp = try await api.request(
            "moderation/report",
            method: .post,
            body: Body(
                targetUserId: targetUserId,
                roomId: roomId,
                messageId: messageId,
                reason: reason.apiCode,
                details: details
            )
        )
    }

    /// Legacy callback API used by older call sites.
    func reportUser(_ userId: String, reason: String, onResult: @escaping (Result<Void, Error>) -> Void) {
        let mapped = ReportReason.allCases.first { $0.apiCode == reason || $0.rawValue == reason } ?? .other
        Task {
            do {
                try await report(targetUserId: userId, reason: mapped)
                onResult(.success(()))
            } catch {
                onResult(.failure(error))
            }
        }
    }

    func reportRoom(_ roomId: String, reason: String, onResult: @escaping (Result<Void, Error>) -> Void) {
        let mapped = ReportReason.allCases.first { $0.apiCode == reason || $0.rawValue == reason } ?? .other
        Task {
            do {
                try await report(roomId: roomId, reason: mapped)
                onResult(.success(()))
            } catch {
                onResult(.failure(error))
            }
        }
    }

    // MARK: - Server sync

    func refreshBlocksFromServer() async {
        struct Row: Decodable { let id: String }
        do {
            let rows: [Row] = try await api.request("moderation/blocks")
            blockedUserIds = Set(rows.map(\.id))
            persist()
        } catch {
            // Keep local list if offline
        }
    }

    private func syncBlockToServer(userId: String) async {
        struct Body: Encodable { let userId: String }
        struct Resp: Decodable { let success: Bool? }
        _ = try? await api.request("moderation/block", method: .post, body: Body(userId: userId)) as Resp
    }

    private func syncUnblockToServer(userId: String) async {
        try? await api.requestNoBody("moderation/block/\(userId)", method: .delete)
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(Array(blockedUserIds), forKey: storageKey)
    }

    private func loadBlockedUsers() {
        if let array = defaults.array(forKey: storageKey) as? [String] {
            blockedUserIds = Set(array)
        }
    }
}

// MARK: - Report Reason (matches backend REPORT_REASONS)
enum ReportReason: String, CaseIterable, Identifiable {
    case spam = "Спам"
    case harassment = "Оскорбления / травля"
    case nsfw = "Неподходящий контент (NSFW)"
    case other = "Другое"

    var id: String { apiCode }

    var apiCode: String {
        switch self {
        case .spam: return "spam"
        case .harassment: return "harassment"
        case .nsfw: return "nsfw"
        case .other: return "other"
        }
    }
}
