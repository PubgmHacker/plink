import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - DM Chat Service v4 (history + unread badges)
/// Личные сообщения + счётчик непрочитанных для списка «Чаты».
@MainActor
final class DMChatService: ObservableObject {

    /// Shared instance so friends list badges and open chat share state.
    static let shared = DMChatService(api: APIClient.shared)

    @Published private(set) var conversations: [String: [DirectMessage]] = [:]
    @Published private(set) var lastMessages: [Conversation] = []
    /// friendId → unread count (only when user is NOT in that chat)
    @Published private(set) var unreadByFriend: [String: Int] = [:]
    /// friendId → last message preview (for list subtitle)
    @Published private(set) var lastPreviewByFriend: [String: String] = [:]
    /// friendId → last message / activity time (Telegram chat reordering)
    @Published private(set) var lastActivityAtByFriend: [String: Date] = [:]
    /// Bumps when inbox activity changes so chat list can re-sort.
    @Published private(set) var inboxEpoch: Int = 0
    @Published private(set) var historyEpoch: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Currently open DM friend id — unread for this id stays 0 while open.
    private(set) var openFriendId: String?

    private let api: APIClient
    private var unreadPollTask: Task<Void, Never>?

    init(api: APIClient) {
        self.api = api
    }

    /// Start aggressive background unread polling (≈1s) for instant badges.
    /// Telegram-style pins per friend (my view of each chat).
    @Published private(set) var pinsByFriend: [String: [DMPinnedMessage]] = [:]
    /// Telegram-style typing indicator: friendId → peer is typing right now.
    @Published private(set) var typingByFriend: [String: Bool] = [:]
    private var lastTypingSentAt: [String: Date] = [:]
    /// friendId → last known display name (for realtime-triggered reloads)
    private var friendNameById: [String: String] = [:]
    private var typingClearTasks: [String: Task<Void, Never>] = [:]

    func startUnreadPolling() {
        guard unreadPollTask == nil else { return }
        // DM realtime channel: instant message/typing events (poll stays as fallback)
        DMRealtimeClient.shared.onEvent = { [weak self] event in
            self?.handleRealtimeEvent(event)
        }
        DMRealtimeClient.shared.start()
        unreadPollTask = Task { [weak self] in
            await self?.refreshUnread()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                guard !Task.isCancelled else { break }
                await self?.refreshUnread()
            }
        }
    }

    func stopUnreadPolling() {
        unreadPollTask?.cancel()
        unreadPollTask = nil
        DMRealtimeClient.shared.stop()
    }

    // MARK: - Realtime (user '@me' channel)

    private func handleRealtimeEvent(_ event: DMRealtimeClient.Event) {
        guard event.type == "dm.event", let from = event.fromUserId, !from.isEmpty else { return }
        switch event.event {
        case "typing":
            typingByFriend[from] = true
            typingClearTasks[from]?.cancel()
            typingClearTasks[from] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                self?.typingByFriend[from] = false
            }
        case "message", "edited", "deleted":
            Task { [weak self] in
                guard let self else { return }
                if self.openFriendId == from || self.conversations[self.conversationID(with: from)] != nil {
                    await self.loadHistory(
                        friendId: from,
                        friendName: self.friendNameById[from] ?? "",
                        quiet: true
                    )
                }
                await self.refreshUnread()
            }
        default:
            break
        }
    }

    var currentUserId: String? {
        if let id = UserDefaults.standard.string(forKey: "plink_current_user_id"), !id.isEmpty {
            return id
        }
        if let id = AuthService.shared.currentUserValue?.id, !id.isEmpty {
            return id
        }
        return UserDefaults.standard.data(forKey: "rave_saved_user")
            .flatMap { try? JSONDecoder().decode(User.self, from: $0) }?.id
    }

    var totalUnread: Int {
        unreadByFriend.values.reduce(0, +)
    }

    func unreadCount(for friendId: String) -> Int {
        if openFriendId == friendId { return 0 }
        return unreadByFriend[friendId] ?? 0
    }

    func lastActivityAt(for friendId: String) -> Date? {
        lastActivityAtByFriend[friendId]
    }

    private func touchActivity(friendId: String, at date: Date = Date(), preview: String? = nil) {
        var acts = lastActivityAtByFriend
        let prev = acts[friendId]
        if prev == nil || date >= (prev ?? .distantPast) {
            acts[friendId] = date
            lastActivityAtByFriend = acts
            if let preview, !preview.isEmpty {
                lastPreviewByFriend[friendId] = preview
            }
            inboxEpoch &+= 1
        }
    }

    // MARK: - Open / close chat (drives badge zeroing)

    func chatDidOpen(friendId: String) {
        openFriendId = friendId
        // Instant badge clear — don't wait for next poll
        if unreadByFriend[friendId] != nil {
            var next = unreadByFriend
            next.removeValue(forKey: friendId)
            unreadByFriend = next
        }
    }

    func chatDidClose(friendId: String) {
        if openFriendId == friendId {
            openFriendId = nil
        }
        Task { await refreshUnread() }
    }

    // MARK: - Unread summary (GET /messages/unread)

    func refreshUnread() async {
        ensureToken()
        guard api.authToken != nil else { return }
        do {
            let items: [UnreadDTO] = try await api.request("messages/unread")
            var counts: [String: Int] = [:]
            var previews: [String: String] = lastPreviewByFriend
            var activities: [String: Date] = lastActivityAtByFriend
            var activityChanged = false
            for item in items {
                if openFriendId == item.friendId {
                    // Open chat — treat as read optimistically, still track last activity
                } else if item.unreadCount > 0 {
                    counts[item.friendId] = item.unreadCount
                }
                if let p = item.lastPreview, !p.isEmpty {
                    previews[item.friendId] = PlinkBubbleWire.decode(p).text
                }
                if let at = item.lastAt {
                    let prev = activities[item.friendId]
                    if prev == nil || at > (prev ?? .distantPast) {
                        activities[item.friendId] = at
                        activityChanged = true
                    }
                }
            }
            // Only publish if changed — but always update when counts differ for snappy UI
            if counts != unreadByFriend {
                unreadByFriend = counts
            }
            lastPreviewByFriend = previews
            if activityChanged || activities != lastActivityAtByFriend {
                lastActivityAtByFriend = activities
                inboxEpoch &+= 1
            }
        } catch {
            Logger.api.warn("DM unread refresh failed")
        }
    }

    // MARK: - Load History (GET /api/messages/dm/:friendId)

    func loadHistory(friendId: String, friendName: String, friendAvatarURL: String? = nil, quiet: Bool = false) async {
        ensureToken()
        guard api.authToken != nil else {
            Logger.api.warn("DM history skipped without token")
            return
        }
        let convID = conversationID(with: friendId)
        if !friendName.isEmpty { friendNameById[friendId] = friendName }
        if !quiet {
            isLoading = true
        }
        defer { if !quiet { isLoading = false } }

        do {
            let dtos: [DMMessageDTO] = try await api.request("messages/dm/\(friendId)")
            // Server marks inbound as read on this GET
            if openFriendId == friendId {
                unreadByFriend[friendId] = nil
                unreadByFriend = unreadByFriend.filter { $0.value > 0 }
            }
            let me = currentUserId ?? ""
            let messages = dtos.map { dto -> DirectMessage in
                let isOwn = !me.isEmpty && dto.senderID == me
                let decoded = PlinkBubbleWire.decode(dto.content)
                let chips = (dto.reactions ?? []).map {
                    DMReactionChip(emoji: $0.emoji, count: $0.count, includesMe: $0.includesMe)
                }
                // Telegram read receipt:
                //  - outbound (I sent): isRead=true means peer opened the chat (✓✓)
                //  - inbound: isRead is for our unread badge; default true once history loaded
                let readFlag: Bool
                if isOwn {
                    readFlag = dto.isRead ?? false
                } else {
                    readFlag = dto.isRead ?? true
                }
                let voiceMeta = PlinkVoiceWire.decode(decoded.text)
                let isVoice = dto.mediaType == "voice" || (dto.hasMedia == true) || voiceMeta.isVoice
                let displayText = voiceMeta.isVoice ? voiceMeta.displayText : decoded.text
                return DirectMessage(
                    id: dto.id,
                    conversationID: convID,
                    senderID: dto.senderID,
                    recipientID: dto.receiverID,
                    senderName: isOwn ? "You" : friendName,
                    text: displayText,
                    timestamp: dto.createdAt,
                    isRead: readFlag,
                    senderAvatarURL: isOwn ? nil : friendAvatarURL,
                    bubbleStyle: decoded.styleID,
                    reactions: chips,
                    mediaType: isVoice ? "voice" : dto.mediaType,
                    mediaDurationSec: dto.mediaDurationSec ?? voiceMeta.durationSec,
                    hasMedia: isVoice || (dto.hasMedia == true),
                    replyToID: dto.replyTo?.id,
                    replyPreviewText: dto.replyTo.map { (r) -> String in
                        if r.mediaType == "voice" { return "🎤 Голосовое сообщение" }
                        if r.mediaType == "photo" { return "📷 Фото" }
                        return PlinkBubbleWire.decode(r.content).text
                    },
                    replyPreviewSenderID: dto.replyTo?.senderID,
                    forwardedFromName: dto.forwardedFromName,
                    editedAt: dto.editedAt
                )
            }
            // Server history is source of truth for this window (newest 200).
            // Keep only very recent optimistic locals not yet on server.
            if messages.isEmpty, let existing = conversations[convID], !existing.isEmpty {
                _ = existing
            } else {
                var merged = messages
                if let existing = conversations[convID] {
                    let serverIds = Set(messages.map(\.id))
                    let newestServer = messages.map(\.timestamp).max() ?? .distantPast
                    let localsOnly = existing.filter { msg in
                        !serverIds.contains(msg.id)
                            && msg.id.count > 20 // UUID optimistic
                            && msg.timestamp >= newestServer.addingTimeInterval(-60)
                    }
                    for loc in localsOnly {
                        if !merged.contains(where: {
                            $0.text == loc.text && abs($0.timestamp.timeIntervalSince(loc.timestamp)) < 45
                        }) {
                            merged.append(loc)
                        }
                    }
                    merged.sort { $0.timestamp < $1.timestamp }
                }
                // Always apply server snapshot when quiet==false (open chat) or when
                // content changed — fixes "preview shows msg, open chat shows old only".
                let prev = conversations[convID] ?? []
                let changed = !quiet
                    || prev.count != merged.count
                    || zip(prev, merged).contains {
                        $0.id != $1.id
                            || $0.text != $1.text
                            || $0.bubbleStyle != $1.bubbleStyle
                            || $0.reactions != $1.reactions
                            || $0.isRead != $1.isRead
                            || $0.hasMedia != $1.hasMedia
                    }
                if changed {
                    conversations[convID] = merged
                    historyEpoch &+= 1
                }
            }
            // Preview / activity from real last message in conversation
            if let last = (conversations[convID] ?? messages).last {
                lastPreviewByFriend[friendId] = last.text
                touchActivity(friendId: friendId, at: last.timestamp, preview: last.text)
                // Peer activity ⇒ fresher last-seen for presence UI
                if last.senderID == friendId {
                    NotificationCenter.default.post(
                        name: .plinkFriendActivity,
                        object: friendId,
                        userInfo: ["at": last.timestamp]
                    )
                }
            }
            _ = convID
        } catch {
            Logger.api.warn("DM history load failed")
            // Keep existing conversation on error
        }
    }

    func messages(for friendID: String) -> [DirectMessage] {
        let convID = conversationID(with: friendID)
        let msgs = conversations[convID] ?? []
        // Filter out messages from blocked users (Telegram-style)
        return msgs.filter { msg in
            !UserBlockManager.shared.isBlocked(msg.senderID)
        }
    }

    // MARK: - Delete chat (Telegram)

    /// Clears local + server thread with friend. Does not remove the friendship.
    func deleteChat(with friend: Friend) async {
        let friendId = friend.id
        let convID = conversationID(with: friendId)
        // Optimistic local clear
        conversations[convID] = []
        lastPreviewByFriend[friendId] = nil
        lastActivityAtByFriend[friendId] = nil
        unreadByFriend[friendId] = nil
        unreadByFriend = unreadByFriend.filter { $0.value > 0 }
        lastMessages.removeAll { $0.id == convID }
        historyEpoch &+= 1
        inboxEpoch &+= 1

        ensureToken()
        struct Resp: Decodable { let success: Bool?; let deleted: Int? }
        do {
            let _: Resp = try await api.request(
                "messages/dm/\(friendId)",
                method: .delete
            )
            Logger.api.info("DM chat deleted")
        } catch {
            Logger.api.warn("DM chat delete sync failed")
            // Local clear already applied — list stays clean offline
        }
    }

    /// Hide chat from list without server wipe (after block).
    func clearLocalChat(friendId: String) {
        let convID = conversationID(with: friendId)
        conversations[convID] = []
        lastPreviewByFriend[friendId] = nil
        lastActivityAtByFriend[friendId] = nil
        unreadByFriend[friendId] = nil
        unreadByFriend = unreadByFriend.filter { $0.value > 0 }
        lastMessages.removeAll { $0.id == convID }
        historyEpoch &+= 1
        inboxEpoch &+= 1
    }

    // MARK: - Send voice note (real audio)

    /// Upload recorded AAC/m4a and create a DM voice note.
    /// - Parameters:
    ///   - dataURL: `data:audio/mp4;base64,...`
    ///   - durationSec: measured recording length
    func sendVoiceNote(dataURL: String, durationSec: TimeInterval, to friend: Friend) {
        if friend.deleted {
            errorMessage = "Нельзя написать удалённому аккаунту"
            return
        }
        if UserBlockManager.shared.isBlocked(friend.id) {
            errorMessage = "Пользователь заблокирован"
            return
        }
        ensureToken()
        let me = currentUserId
            ?? UserDefaults.standard.string(forKey: "plink_current_user_id")
            ?? "me"
        if me != "me", UserDefaults.standard.string(forKey: "plink_current_user_id") == nil {
            UserDefaults.standard.set(me, forKey: "plink_current_user_id")
        }

        let convID = conversationID(with: friend.id)
        let localID = UUID().uuidString
        let styleID = PlinkBubbleStylePrefs.currentID
        let dur = max(0.5, min(60, durationSec))
        let voiceBody = PlinkVoiceWire.encode(durationSec: dur)
        let wireContent = PlinkBubbleWire.encode(text: voiceBody, styleID: styleID)
        let preview = PlinkVoiceWire.decode(voiceBody).displayText

        let message = DirectMessage(
            id: localID,
            conversationID: convID,
            senderID: me,
            recipientID: friend.id,
            senderName: "You",
            text: preview,
            timestamp: Date(),
            isRead: false,
            senderAvatarURL: nil,
            bubbleStyle: styleID,
            reactions: [],
            mediaType: "voice",
            mediaDurationSec: dur,
            hasMedia: true
        )

        var list = conversations[convID] ?? []
        list.append(message)
        conversations[convID] = list
        historyEpoch &+= 1
        lastPreviewByFriend[friend.id] = "🎤 Голосовое сообщение"
        touchActivity(friendId: friend.id, at: message.timestamp, preview: "🎤 Голосовое сообщение")
        updateLastMessage(conversationID: convID, friend: friend, message: message)

        // Play immediately from local bytes (before / while upload runs)
        if let raw = Self.decodeDataURL(dataURL) {
            VoiceNotePlayer.shared.registerLocal(messageId: localID, data: raw)
        }

        struct Body: Encodable {
            let receiverId: String
            let audioData: String
            let durationSec: Double
            let content: String
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let saved: DMMessageDTO = try await api.request(
                    "messages/dm/voice",
                    method: .post,
                    body: Body(
                        receiverId: friend.id,
                        audioData: dataURL,
                        durationSec: dur,
                        content: wireContent
                    )
                )
                // Re-key local audio so play keeps working after id swap
                VoiceNotePlayer.shared.promote(from: localID, to: saved.id)
                if var cur = conversations[convID],
                   let idx = cur.firstIndex(where: { $0.id == localID }) {
                    let decoded = PlinkBubbleWire.decode(saved.content.isEmpty ? wireContent : saved.content)
                    let voiceMeta = PlinkVoiceWire.decode(decoded.text)
                    cur[idx] = DirectMessage(
                        id: saved.id,
                        conversationID: convID,
                        senderID: saved.senderID.isEmpty ? me : saved.senderID,
                        recipientID: saved.receiverID.isEmpty ? friend.id : saved.receiverID,
                        senderName: "You",
                        text: voiceMeta.isVoice ? voiceMeta.displayText : (decoded.text.isEmpty ? preview : decoded.text),
                        timestamp: saved.createdAt,
                        isRead: false,
                        senderAvatarURL: nil,
                        bubbleStyle: decoded.styleID ?? styleID,
                        reactions: [],
                        mediaType: saved.mediaType ?? "voice",
                        mediaDurationSec: saved.mediaDurationSec ?? dur,
                        hasMedia: true
                    )
                    conversations[convID] = cur
                    historyEpoch &+= 1
                }
            } catch {
                errorMessage = "Голосовое: \(error.localizedDescription)"
                Logger.api.warn("DM voice note send failed")
                // Keep optimistic row — still playable from local cache
            }
        }
    }

    /// Upload compressed JPEG/WebP-compatible image data and create a DM photo message.
    func sendPhoto(dataURL: String, previewImage: UIImage?, caption: String, to friend: Friend) {
        if friend.deleted {
            errorMessage = "Нельзя написать удалённому аккаунту"
            return
        }
        if UserBlockManager.shared.isBlocked(friend.id) {
            errorMessage = "Пользователь заблокирован"
            return
        }
        ensureToken()
        let me = currentUserId
            ?? UserDefaults.standard.string(forKey: "plink_current_user_id")
            ?? "me"
        if me != "me", UserDefaults.standard.string(forKey: "plink_current_user_id") == nil {
            UserDefaults.standard.set(me, forKey: "plink_current_user_id")
        }

        let convID = conversationID(with: friend.id)
        let localID = UUID().uuidString
        let styleID = PlinkBubbleStylePrefs.currentID
        let body = String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        let wireContent = PlinkBubbleWire.encode(text: body, styleID: styleID)
        let preview = body.isEmpty ? "📷 Фото" : "📷 \(body)"
        let message = DirectMessage(
            id: localID,
            conversationID: convID,
            senderID: me,
            recipientID: friend.id,
            senderName: "You",
            text: body,
            timestamp: Date(),
            isRead: false,
            senderAvatarURL: nil,
            bubbleStyle: styleID,
            reactions: [],
            mediaType: "photo",
            mediaDurationSec: nil,
            hasMedia: true
        )
        var list = conversations[convID] ?? []
        list.append(message)
        conversations[convID] = list
        historyEpoch &+= 1
        lastPreviewByFriend[friend.id] = preview
        touchActivity(friendId: friend.id, at: message.timestamp, preview: preview)
        updateLastMessage(conversationID: convID, friend: friend, message: message)
        if let previewImage {
            ChatPhotoCache.shared.register(previewImage, for: localID)
        }

        struct Body: Encodable {
            let receiverId: String
            let imageData: String
            let content: String
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let saved: DMMessageDTO = try await api.request(
                    "messages/dm/photo",
                    method: .post,
                    body: Body(receiverId: friend.id, imageData: dataURL, content: wireContent)
                )
                if let previewImage {
                    ChatPhotoCache.shared.promote(from: localID, to: saved.id)
                    ChatPhotoCache.shared.register(previewImage, for: saved.id)
                }
                if var cur = conversations[convID],
                   let idx = cur.firstIndex(where: { $0.id == localID }) {
                    let decoded = PlinkBubbleWire.decode(saved.content.isEmpty ? wireContent : saved.content)
                    cur[idx] = DirectMessage(
                        id: saved.id,
                        conversationID: convID,
                        senderID: saved.senderID.isEmpty ? me : saved.senderID,
                        recipientID: saved.receiverID.isEmpty ? friend.id : saved.receiverID,
                        senderName: "You",
                        text: decoded.text.isEmpty ? body : decoded.text,
                        timestamp: saved.createdAt,
                        isRead: false,
                        senderAvatarURL: nil,
                        bubbleStyle: decoded.styleID ?? styleID,
                        reactions: [],
                        mediaType: "photo",
                        mediaDurationSec: nil,
                        hasMedia: true
                    )
                    conversations[convID] = cur
                    historyEpoch &+= 1
                }
            } catch {
                errorMessage = "Фото: \(error.localizedDescription)"
                Logger.api.warn("DM photo send failed")
            }
        }
    }

    /// Extract raw audio bytes from `data:audio/...;base64,...` or bare base64.
    private static func decodeDataURL(_ dataURL: String) -> Data? {
        if let range = dataURL.range(of: "base64,") {
            let b64 = String(dataURL[range.upperBound...])
            return Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
        }
        return Data(base64Encoded: dataURL, options: .ignoreUnknownCharacters)
    }

    // MARK: - Send

    func sendMessage(_ text: String, to friend: Friend, replyTo replyTarget: DirectMessage? = nil) {
        if friend.deleted {
            errorMessage = "Нельзя написать удалённому аккаунту"
            return
        }
        if UserBlockManager.shared.isBlocked(friend.id) {
            errorMessage = "Пользователь заблокирован"
            return
        }
        // Allow room-invite payloads (up to 280 server-side)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let payload = String(trimmed.prefix(280))

        ensureToken()
        // Stable id for isOwnMessage + conversation key
        let me = currentUserId
            ?? UserDefaults.standard.string(forKey: "plink_current_user_id")
            ?? "me"
        if me != "me", UserDefaults.standard.string(forKey: "plink_current_user_id") == nil {
            UserDefaults.standard.set(me, forKey: "plink_current_user_id")
        }

        let convID = conversationID(with: friend.id)
        let localID = UUID().uuidString
        let styleID = PlinkBubbleStylePrefs.currentID
        // Wire style so peer devices render the same bubble (fits in 280 server limit)
        let markerLen = "[[bs:\(BubbleStyleRegistry.migrateLegacyID(styleID))]]".count
        let body = String(payload.prefix(max(1, 280 - markerLen)))
        let wireContent = PlinkBubbleWire.encode(text: body, styleID: styleID)

        let message = DirectMessage(
            id: localID,
            conversationID: convID,
            senderID: me,
            recipientID: friend.id,
            senderName: "You",
            text: body,
            timestamp: Date(),
            isRead: false,
            senderAvatarURL: nil,
            bubbleStyle: styleID,
            reactions: [],
            replyToID: replyTarget?.id,
            replyPreviewText: replyTarget.map { (t) -> String in
                if t.isVoiceNote { return "🎤 Голосовое сообщение" }
                if t.isPhotoMessage { return "📷 Фото" }
                return t.text
            },
            replyPreviewSenderID: replyTarget?.senderID
        )

        var list = conversations[convID] ?? []
        list.append(message)
        conversations[convID] = list
        historyEpoch &+= 1
        lastPreviewByFriend[friend.id] = body
        touchActivity(friendId: friend.id, at: message.timestamp, preview: body)
        updateLastMessage(conversationID: convID, friend: friend, message: message)

        struct Body: Encodable { let receiverId: String; let content: String; let replyToId: String? }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let saved: DMMessageDTO = try await api.request(
                    "messages/dm",
                    method: .post,
                    body: Body(receiverId: friend.id, content: wireContent, replyToId: replyTarget?.id)
                )
                // Replace optimistic message in-place — do NOT wipe history
                // (full reload was clearing UI / crashing identity updates).
                if var cur = conversations[convID],
                   let idx = cur.firstIndex(where: { $0.id == localID }) {
                    let decoded = PlinkBubbleWire.decode(saved.content.isEmpty ? wireContent : saved.content)
                    cur[idx] = DirectMessage(
                        id: saved.id,
                        conversationID: convID,
                        senderID: saved.senderID.isEmpty ? me : saved.senderID,
                        recipientID: saved.receiverID.isEmpty ? friend.id : saved.receiverID,
                        senderName: "You",
                        text: decoded.text.isEmpty ? body : decoded.text,
                        timestamp: saved.createdAt,
                        isRead: false,
                        senderAvatarURL: nil,
                        bubbleStyle: decoded.styleID ?? styleID,
                        reactions: [],
                        replyToID: replyTarget?.id,
                        replyPreviewText: replyTarget.map { (t) -> String in
                            if t.isVoiceNote { return "🎤 Голосовое сообщение" }
                            if t.isPhotoMessage { return "📷 Фото" }
                            return t.text
                        },
                        replyPreviewSenderID: replyTarget?.senderID
                    )
                    conversations[convID] = cur
                    historyEpoch &+= 1
                }
            } catch {
                errorMessage = error.localizedDescription
                Logger.api.warn("DM send failed")
                // Keep optimistic message visible so chat does not "disappear"
            }
        }
    }

    func receiveMessage(_ message: DirectMessage, from friend: Friend) {
        let convID = conversationID(with: friend.id)
        if conversations[convID] == nil { conversations[convID] = [] }
        if conversations[convID]?.contains(where: { $0.id == message.id }) == true { return }
        let decoded = PlinkBubbleWire.decode(message.text)
        let normalized = DirectMessage(
            id: message.id,
            conversationID: message.conversationID,
            senderID: message.senderID,
            recipientID: message.recipientID,
            senderName: message.senderName,
            text: decoded.text,
            timestamp: message.timestamp,
            isRead: message.isRead,
            senderAvatarURL: message.senderAvatarURL,
            bubbleStyle: decoded.styleID ?? message.bubbleStyle,
            reactions: message.reactions
        )
        conversations[convID]?.append(normalized)
        historyEpoch &+= 1
        lastPreviewByFriend[friend.id] = normalized.text
        touchActivity(friendId: friend.id, at: normalized.timestamp, preview: normalized.text)
        updateLastMessage(conversationID: convID, friend: friend, message: normalized)
        if openFriendId != friend.id, normalized.senderID != currentUserId {
            unreadByFriend[friend.id, default: 0] += 1
        }
        // Freshen last-seen from inbound DMs
        if normalized.senderID == friend.id {
            NotificationCenter.default.post(
                name: .plinkFriendActivity,
                object: friend.id,
                userInfo: ["at": normalized.timestamp]
            )
        }
    }

    // MARK: - Reactions (Telegram-style)

    /// Toggle reaction on a message. Same emoji again removes; other replaces.
    func toggleReaction(emoji: String, on message: DirectMessage, friendId: String) async {
        // Optimistic local update
        applyOptimisticReaction(emoji: emoji, messageId: message.id, friendId: friendId)
        ensureToken()
        struct Body: Encodable { let emoji: String }
        struct Resp: Decodable {
            let success: Bool?
            let reactions: [ReactionDTO]?
        }
        do {
            let resp: Resp = try await api.request(
                "messages/dm/\(message.id)/react",
                method: .post,
                body: Body(emoji: emoji)
            )
            if let chips = resp.reactions {
                setReactions(
                    chips.map { DMReactionChip(emoji: $0.emoji, count: $0.count, includesMe: $0.includesMe) },
                    messageId: message.id,
                    friendId: friendId
                )
            }
        } catch {
            Logger.api.warn("DM reaction sync failed")
            // Soft-fail: keep optimistic state; next history poll reconciles
        }
    }

    private func applyOptimisticReaction(emoji: String, messageId: String, friendId: String) {
        let convID = conversationID(with: friendId)
        guard var list = conversations[convID],
              let idx = list.firstIndex(where: { $0.id == messageId }) else { return }
        var chips = list[idx].reactions
        if let i = chips.firstIndex(where: { $0.emoji == emoji && $0.includesMe }) {
            // Toggle off
            let c = chips[i]
            if c.count <= 1 {
                chips.remove(at: i)
            } else {
                chips[i] = DMReactionChip(emoji: emoji, count: c.count - 1, includesMe: false)
            }
        } else {
            // Remove previous own reaction on other emoji
            chips = chips.compactMap { chip in
                if chip.includesMe {
                    if chip.count <= 1 { return nil }
                    return DMReactionChip(emoji: chip.emoji, count: chip.count - 1, includesMe: false)
                }
                return chip
            }
            if let i = chips.firstIndex(where: { $0.emoji == emoji }) {
                let c = chips[i]
                chips[i] = DMReactionChip(emoji: emoji, count: c.count + 1, includesMe: true)
            } else {
                chips.append(DMReactionChip(emoji: emoji, count: 1, includesMe: true))
            }
        }
        chips.sort { $0.count > $1.count }
        list[idx].reactions = chips
        conversations[convID] = list
        historyEpoch &+= 1
    }

    private func setReactions(_ chips: [DMReactionChip], messageId: String, friendId: String) {
        let convID = conversationID(with: friendId)
        guard var list = conversations[convID],
              let idx = list.firstIndex(where: { $0.id == messageId }) else { return }
        list[idx].reactions = chips
        conversations[convID] = list
        historyEpoch &+= 1
    }

    // MARK: - Helpers

    // MARK: - Telegram-style pins

    func loadPins(friendId: String) async {
        ensureToken()
        guard api.authToken != nil else { return }
        struct PinDTO: Decodable {
            let messageId: String
            let pinnedByID: String?
            let pinnedAt: Date?
            let content: String
            let senderID: String
            let mediaType: String?
            let messageCreatedAt: Date?
        }
        do {
            let dtos: [PinDTO] = try await api.request("messages/dm/\(friendId)/pins")
            let pins = dtos.map { (d) -> DMPinnedMessage in
                let text: String
                if d.mediaType == "voice" {
                    text = "🎤 Голосовое сообщение"
                } else if d.mediaType == "photo" {
                    text = "📷 Фото"
                } else {
                    text = PlinkBubbleWire.decode(d.content).text
                }
                return DMPinnedMessage(
                    messageId: d.messageId,
                    senderID: d.senderID,
                    text: text,
                    pinnedAt: d.pinnedAt,
                    messageCreatedAt: d.messageCreatedAt
                )
            }
            if pinsByFriend[friendId] != pins {
                pinsByFriend[friendId] = pins
            }
        } catch {
            Logger.api.warn("DM pins load failed")
        }
    }

    /// Telegram: «Закрепить у себя» (forBoth=false) / «Закрепить у обоих» (forBoth=true).
    func pinMessage(_ message: DirectMessage, forBoth: Bool, friendId: String) async {
        ensureToken()
        struct Body: Encodable { let messageId: String; let forBoth: Bool }
        struct Resp: Decodable { let success: Bool? }
        do {
            let _: Resp = try await api.request(
                "messages/dm/\(friendId)/pin",
                method: .post,
                body: Body(messageId: message.id, forBoth: forBoth)
            )
            await loadPins(friendId: friendId)
        } catch {
            errorMessage = "Не удалось закрепить сообщение"
            Logger.api.warn("DM pin failed")
        }
    }

    func unpinMessage(messageId: String, forBoth: Bool, friendId: String) async {
        ensureToken()
        struct Resp: Decodable { let success: Bool?; let removed: Int? }
        do {
            let _: Resp = try await api.request(
                "messages/dm/\(friendId)/pin/\(messageId)?forBoth=\(forBoth)",
                method: .delete
            )
            await loadPins(friendId: friendId)
        } catch {
            errorMessage = "Не удалось открепить сообщение"
            Logger.api.warn("DM unpin failed")
        }
    }

    // MARK: - Telegram-style forward

    /// Forward messages to another friend. Returns true on success.
    @discardableResult
    func forwardMessages(_ messageIds: [String], to target: Friend) async -> Bool {
        ensureToken()
        struct Body: Encodable { let toUserId: String; let messageIds: [String] }
        struct Resp: Decodable { let success: Bool?; let forwarded: Int? }
        do {
            let _: Resp = try await api.request(
                "messages/dm/forward",
                method: .post,
                body: Body(toUserId: target.id, messageIds: messageIds)
            )
            await loadHistory(
                friendId: target.id,
                friendName: target.displayTitle,
                friendAvatarURL: target.avatarURL,
                quiet: true
            )
            touchActivity(friendId: target.id, preview: "↪️ Пересланное сообщение")
            return true
        } catch {
            errorMessage = "Не удалось переслать сообщение"
            Logger.api.warn("DM forward failed")
            return false
        }
    }

    // MARK: - Telegram-style edit / delete / typing

    /// Edit own text message («изменено»). Returns true on success.
    @discardableResult
    func editMessage(_ message: DirectMessage, newText: String, friendId: String) async -> Bool {
        ensureToken()
        let wire = PlinkBubbleWire.encode(text: newText, styleID: message.bubbleStyle)
        struct Body: Encodable { let content: String }
        struct Resp: Decodable { let success: Bool? }
        do {
            let _: Resp = try await api.request(
                "messages/dm/message/\(message.id)",
                method: .patch,
                body: Body(content: wire)
            )
            let convID = conversationID(with: friendId)
            if var msgs = conversations[convID],
               let idx = msgs.firstIndex(where: { $0.id == message.id }) {
                msgs[idx].text = newText
                msgs[idx].editedAt = Date()
                conversations[convID] = msgs
                historyEpoch += 1
            }
            return true
        } catch {
            errorMessage = "Не удалось изменить сообщение"
            Logger.api.warn("DM edit failed")
            return false
        }
    }

    /// Delete message: for me only, or for both (own messages, Telegram-style).
    @discardableResult
    func deleteMessage(_ message: DirectMessage, forBoth: Bool, friendId: String) async -> Bool {
        ensureToken()
        struct Resp: Decodable { let success: Bool? }
        do {
            let _: Resp = try await api.request(
                "messages/dm/message/\(message.id)?forBoth=\(forBoth)",
                method: .delete
            )
            let convID = conversationID(with: friendId)
            if var msgs = conversations[convID] {
                msgs.removeAll { $0.id == message.id }
                conversations[convID] = msgs
                historyEpoch += 1
            }
            await loadPins(friendId: friendId)
            return true
        } catch {
            errorMessage = "Не удалось удалить сообщение"
            Logger.api.warn("DM delete failed")
            return false
        }
    }

    /// Throttled typing ping (max 1 per 3s) — Telegram «печатает…».
    func sendTyping(friendId: String) {
        let now = Date()
        if let last = lastTypingSentAt[friendId], now.timeIntervalSince(last) < 3 { return }
        lastTypingSentAt[friendId] = now
        ensureToken()
        struct Resp: Decodable { let success: Bool? }
        Task {
            do {
                let _: Resp = try await api.request(
                    "messages/dm/\(friendId)/typing",
                    method: .post
                )
            } catch {
                // best-effort
            }
        }
    }

    /// Poll peer typing state (piggybacks on the 5s history poll).
    func loadTyping(friendId: String) async {
        ensureToken()
        struct Resp: Decodable { let typing: Bool }
        do {
            let resp: Resp = try await api.request("messages/dm/\(friendId)/typing")
            if typingByFriend[friendId] != resp.typing {
                typingByFriend[friendId] = resp.typing
            }
        } catch {
            // quiet — typing is best-effort
        }
    }

    func conversationID(with friendID: String) -> String {
        let me = currentUserId ?? "me"
        let ids = [me, friendID].sorted()
        return "dm_\(ids.joined(separator: "_"))"
    }

    private func ensureToken() {
        if api.authToken == nil {
            api.authToken = KeychainHelper.read(for: "rave_auth_token")
                ?? AuthService.shared.authToken
        }
    }

    private func updateLastMessage(conversationID: String, friend: Friend, message: DirectMessage) {
        let conv = Conversation(
            id: conversationID,
            participant: UserPreview(id: friend.id, username: friend.username, avatarURL: friend.avatarURL, isOnline: friend.isOnline),
            lastMessage: message,
            unreadCount: unreadCount(for: friend.id),
            updatedAt: message.timestamp
        )
        lastMessages.removeAll { $0.id == conversationID }
        lastMessages.insert(conv, at: 0)
    }
}

// MARK: - DTOs

private struct UnreadDTO: Decodable {
    let friendId: String
    let unreadCount: Int
    let lastPreview: String?
    let lastAt: Date?
}

private struct ReactionDTO: Decodable {
    let emoji: String
    let count: Int
    let includesMe: Bool
}

private struct DMMessageDTO: Decodable {
    struct ReplyRefDTO: Decodable {
        let id: String
        let content: String
        let senderID: String
        let mediaType: String?
    }

    let id: String
    let senderID: String
    let receiverID: String
    let content: String
    let createdAt: Date
    let isRead: Bool?
    let reactions: [ReactionDTO]?
    let mediaType: String?
    let mediaDurationSec: Double?
    let hasMedia: Bool?
    let replyTo: ReplyRefDTO?
    let forwardedFromID: String?
    let forwardedFromName: String?
    let editedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, content, createdAt, isRead, reactions
        case senderID, receiverID
        case senderId, receiverId
        case mediaType, mediaDurationSec, hasMedia
        case replyTo, forwardedFromID, forwardedFromName, editedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        content = try c.decode(String.self, forKey: .content)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        isRead = try c.decodeIfPresent(Bool.self, forKey: .isRead)
        reactions = try c.decodeIfPresent([ReactionDTO].self, forKey: .reactions)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
        mediaDurationSec = try c.decodeIfPresent(Double.self, forKey: .mediaDurationSec)
        hasMedia = try c.decodeIfPresent(Bool.self, forKey: .hasMedia)
        replyTo = try c.decodeIfPresent(ReplyRefDTO.self, forKey: .replyTo)
        forwardedFromID = try c.decodeIfPresent(String.self, forKey: .forwardedFromID)
        forwardedFromName = try c.decodeIfPresent(String.self, forKey: .forwardedFromName)
        editedAt = try c.decodeIfPresent(Date.self, forKey: .editedAt)
        if let s = try c.decodeIfPresent(String.self, forKey: .senderID) {
            senderID = s
        } else {
            senderID = try c.decode(String.self, forKey: .senderId)
        }
        if let r = try c.decodeIfPresent(String.self, forKey: .receiverID) {
            receiverID = r
        } else {
            receiverID = try c.decode(String.self, forKey: .receiverId)
        }
    }
}
