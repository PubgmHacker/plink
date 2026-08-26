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
    /// M39-fix: архивированные чаты (Telegram-style) — скрыты из основного списка, состояние хранится локально.
    @Published private(set) var archivedFriendIDs: Set<String> = []
    private static let archivedKey = "plink.dm.archived.v1"
    /// Bumps when inbox activity changes so chat list can re-sort.
    @Published private(set) var inboxEpoch: Int = 0
    @Published private(set) var historyEpoch: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    // Явный учёт оптимистичных локальных сообщений вместо
    // эвристики «id длиннее 20 символов» — серверные UUID тоже 36 символов,
    // из-за чего удалённые собеседником сообщения «воскресали» при merge.
    private var pendingLocalIDs: Set<String> = []
    /// Messages that failed to send (network or server refused): they are flagged in
    /// the UI and are never dropped from the feed by a merge.
    @Published private(set) var failedMessageIDs: Set<String> = []
    /// Пагинация истории. friendId → есть ли страницы старше.
    @Published private(set) var hasMoreHistoryByFriend: [String: Bool] = [:]
    @Published private(set) var isLoadingOlderHistory = false
    /// Размер серверного окна истории без курсора (take: 200 на бэкенде).
    private static let serverHistoryWindow = 200
    /// Размер страницы при подгрузке старых сообщений (?before=&limit=).
    private static let olderPageSize = 100

    /// Currently open DM friend id — unread for this id stays 0 while open.
    private(set) var openFriendId: String?

    private let api: APIClient
    private var unreadPollTask: Task<Void, Never>?
    /// fallback-интервал опроса непрочитанных. Мгновенные
    /// события идут через DMRealtimeClient, поэтому раз в секунду больше не бьём —
    /// это жгло батарею и трафик и поллило сервер даже в фоне.
    private static let unreadPollIntervalNs: UInt64 = 15_000_000_000

    init(api: APIClient) {
        self.api = api
        self.archivedFriendIDs = Set(UserDefaults.standard.stringArray(forKey: Self.archivedKey) ?? [])
        restoreInboxCache()
        restorePendingChatDeletes()
        pruneForeignCaches()
        // Ревью 26.07.2026: выход из аккаунта обязан уносить офлайн-кэш DM,
        // иначе следующий пользователь на этом устройстве увидит чужую переписку.
        signOutObserver = NotificationCenter.default.addObserver(
            forName: .plinkSignedOut,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.purgeOfflineCaches() }
        }
    }

    // MARK: - Archive (Telegram-style, локально)

    func isArchived(_ friendId: String) -> Bool { archivedFriendIDs.contains(friendId) }

    /// Архивировать чат: убрать из основного списка. Состояние хранится локально между запусками.
    func archiveChat(with friend: Friend) async {
        archivedFriendIDs.insert(friend.id)
        UserDefaults.standard.set(Array(archivedFriendIDs), forKey: Self.archivedKey)
    }

    /// Вернуть архивированный чат обратно в основной список.
    func unarchiveChat(friendId: String) {
        archivedFriendIDs.remove(friendId)
        UserDefaults.standard.set(Array(archivedFriendIDs), forKey: Self.archivedKey)
    }

    // MARK: - Офлайн-кэш инбокса / диалога

    /// Снимок инбокса на диске: холодный старт без сети показывает список чатов,
    /// а не пустоту. Свежие сетевые данные всегда важнее кэша.
    private struct InboxCacheSnapshot: Codable {
        var previews: [String: String]
        var unread: [String: Int]
        var activity: [String: Date]
    }

    // Ревью 26.07.2026: ключи кэша обязаны быть привязаны к аккаунту — раньше
    // `…history.cache.v1.<friendId>` подставлял переписку прошлого пользователя
    // в диалог нового (общий друг на том же устройстве).
    private static let inboxCacheKeyPrefix = "plink.dm.inbox.cache.v1."
    private static let historyCacheKeyPrefix = "plink.dm.history.cache.v1."
    private static let pendingDeletesKeyPrefix = "plink.dm.pendingDeletes.v1."
    /// Сколько последних сообщений диалога держим в офлайн-кэше.
    private static let historyCacheLimit = 60
    /// Троттлинг записи инбокса на диск.
    private var lastInboxPersistAt: Date = .distantPast
    /// Троттлинг записи истории диалога на диск (convID → момент записи).
    private var lastHistoryPersistAt: [String: Date] = [:]
    /// Диалоги, историю которых уже поднимали из кэша (кэш не должен лечь поверх сети).
    private var historyRestoredFor: Set<String> = []
    /// Диалоги, по которым сеть уже отвечала в этой сессии (кэш перестаёт быть авторитетом).
    private var historyNetworkConfirmed: Set<String> = []
    /// Удаления чата, не доехавшие до сервера: friendId → момент локального удаления.
    /// Отсечка нужна, чтобы серверный DELETE (скрывает ВЕСЬ тред) не унёс сообщения,
    /// пришедшие уже после удаления и ни разу не показанные пользователю.
    private var pendingChatDeletes: [String: Date] = [:]
    private var pendingDeletesRestored = false
    /// Пользователь, которому принадлежит текущее состояние/кэш.
    private var cacheOwnerId: String?
    private var signOutObserver: NSObjectProtocol?

    private func cacheScope() -> String? {
        guard let me = currentUserId, !me.isEmpty else { return nil }
        // Сессия могла истечь и смениться без нотификации выхода
        // (AuthService.restoreAndValidateSession → signOutLocally(postNotification: false)),
        // поэтому владельца кэша сверяем на каждом обращении.
        if let owner = cacheOwnerId, owner != me {
            resetInMemoryState()
        }
        cacheOwnerId = me
        return me
    }

    private func inboxCacheKey() -> String? {
        cacheScope().map { Self.inboxCacheKeyPrefix + $0 }
    }

    private func historyCacheKey(friendId: String) -> String? {
        cacheScope().map { Self.historyCacheKeyPrefix + $0 + "." + friendId }
    }

    private func pendingDeletesKey() -> String? {
        cacheScope().map { Self.pendingDeletesKeyPrefix + $0 }
    }

    /// Снести кэши DM, не принадлежащие текущему аккаунту (в т.ч. ключи ранней
    /// сборки без привязки к пользователю) — тексты чужих переписок в plist не место.
    private func pruneForeignCaches() {
        guard let me = cacheScope() else { return }
        let defaults = UserDefaults.standard
        let mine = [
            Self.inboxCacheKeyPrefix + me,
            Self.pendingDeletesKeyPrefix + me
        ]
        let myHistoryPrefix = Self.historyCacheKeyPrefix + me + "."
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("plink.dm.inbox.cache.v1")
            || key.hasPrefix("plink.dm.history.cache.v1")
            || key.hasPrefix("plink.dm.pendingDeletes.v1") {
            if mine.contains(key) || key.hasPrefix(myHistoryPrefix) { continue }
            defaults.removeObject(forKey: key)
        }
    }

    /// Полная очистка локального состояния DM при выходе из аккаунта.
    private func purgeOfflineCaches() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(Self.inboxCacheKeyPrefix)
            || key.hasPrefix(Self.historyCacheKeyPrefix)
            || key.hasPrefix(Self.pendingDeletesKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
        cacheOwnerId = nil
        resetInMemoryState()
    }

    /// Сброс только оперативного состояния (диск не трогаем).
    private func resetInMemoryState() {
        conversations = [:]
        lastMessages = []
        unreadByFriend = [:]
        lastPreviewByFriend = [:]
        lastActivityAtByFriend = [:]
        pinsByFriend = [:]
        typingByFriend = [:]
        pendingLocalIDs = []
        failedMessageIDs = []
        pendingChatDeletes = [:]
        pendingDeletesRestored = false
        historyRestoredFor = []
        historyNetworkConfirmed = []
        lastHistoryPersistAt = [:]
        openFriendId = nil
        inboxEpoch &+= 1
        historyEpoch &+= 1
    }

    private func restoreInboxCache() {
        guard let key = inboxCacheKey(),
              let data = UserDefaults.standard.data(forKey: key),
              let snap = try? JSONDecoder().decode(InboxCacheSnapshot.self, from: data) else { return }
        // Вызывается только из init: словари ещё пустые, кэш ничего не перетирает.
        if lastPreviewByFriend.isEmpty { lastPreviewByFriend = snap.previews }
        if unreadByFriend.isEmpty { unreadByFriend = snap.unread.filter { $0.value > 0 } }
        if lastActivityAtByFriend.isEmpty { lastActivityAtByFriend = snap.activity }
        inboxEpoch &+= 1
    }

    private func persistInboxCache(force: Bool = false) {
        guard let key = inboxCacheKey() else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastInboxPersistAt) < 3 { return }
        lastInboxPersistAt = now
        let snap = InboxCacheSnapshot(
            previews: lastPreviewByFriend,
            unread: unreadByFriend,
            activity: lastActivityAtByFriend
        )
        guard let data = try? JSONEncoder().encode(snap) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Поднять последнюю известную историю диалога до ответа сети (один раз за сессию).
    private func restoreHistoryCache(friendId: String, convID: String) {
        guard !historyRestoredFor.contains(convID),
              !historyNetworkConfirmed.contains(convID),
              (conversations[convID]?.isEmpty ?? true),
              let key = historyCacheKey(friendId: friendId),
              let data = UserDefaults.standard.data(forKey: key),
              let cached = try? JSONDecoder().decode([DirectMessage].self, from: data),
              !cached.isEmpty,
              // Страховка от чужого/устаревшего кэша: convID содержит оба участника.
              cached.allSatisfy({ $0.conversationID == convID }) else { return }
        // Ревью 26.07.2026: отмечаем диалог только когда кэш реально применён —
        // иначе одна realtime-строка навсегда блокировала подъём кэша за сессию.
        historyRestoredFor.insert(convID)
        conversations[convID] = cached.sorted { $0.timestamp < $1.timestamp }
        historyEpoch &+= 1
    }

    private func persistHistoryCache(friendId: String, convID: String, force: Bool = false) {
        guard let key = historyCacheKey(friendId: friendId) else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastHistoryPersistAt[convID] ?? .distantPast) < 5 { return }
        let msgs = conversations[convID] ?? []
        // Ревью 26.07.2026: оптимистичные/неотправленные сообщения в кэш не пишем —
        // pendingLocalIDs/failedMessageIDs живут только в памяти, и после перезапуска
        // такая строка выглядела бы доставленной, а затем молча исчезала.
        let persistable = msgs.filter {
            !pendingLocalIDs.contains($0.id) && !failedMessageIDs.contains($0.id)
        }
        guard !persistable.isEmpty else {
            lastHistoryPersistAt[convID] = now
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        let tail = Array(persistable.suffix(Self.historyCacheLimit))
        guard let data = try? JSONEncoder().encode(tail) else { return }
        lastHistoryPersistAt[convID] = now
        UserDefaults.standard.set(data, forKey: key)
    }

    private func restorePendingChatDeletes() {
        guard !pendingDeletesRestored, let key = pendingDeletesKey() else { return }
        pendingDeletesRestored = true
        guard let data = UserDefaults.standard.data(forKey: key),
              let map = try? JSONDecoder().decode([String: Date].self, from: data) else { return }
        pendingChatDeletes = map
    }

    private func savePendingChatDeletes() {
        guard let key = pendingDeletesKey() else { return }
        guard !pendingChatDeletes.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(pendingChatDeletes) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Досылка удалений чата, не доехавших до сервера (офлайн-очередь).
    /// Вызывается ТОЛЬКО после сверки с инбоксом: если после локального удаления
    /// пришли новые сообщения, удаление уже снято из очереди (чат честно вернулся).
    private func flushPendingChatDeletes() async {
        guard !pendingChatDeletes.isEmpty, api.authToken != nil else { return }
        struct Resp: Decodable { let success: Bool?; let deleted: Int? }
        for friendId in Array(pendingChatDeletes.keys) {
            do {
                let _: Resp = try await api.request("messages/dm/\(friendId)", method: .delete)
                pendingChatDeletes.removeValue(forKey: friendId)
            } catch {
                Logger.api.warn("DM chat delete retry failed")
                break // сеть всё ещё недоступна — повторим на следующем опросе
            }
        }
        savePendingChatDeletes()
    }

    /// После подмены localID на серверный id в ленте может
    /// оказаться вторая копия того же сообщения (поллинг успел вставить серверную
    /// версию до ответа POST). Оставляем строку с индексом `keeping`.
    private func removeDuplicateRows(in list: inout [DirectMessage], id: String, keeping idx: Int) {
        guard list.filter({ $0.id == id }).count > 1 else { return }
        var dups: [Int] = []
        for (i, msg) in list.enumerated() where i != idx && msg.id == id {
            dups.append(i)
        }
        for i in dups.reversed() { list.remove(at: i) }
    }

    /// Maximum DM text length: the server's limit of 280 is counted over the wire
    /// string, which includes the bubble-style marker `[[bs:…]]`. The UI must compute
    /// the limit dynamically, otherwise the tail of a message is silently truncated.
    nonisolated static func textLimit(forStyleID styleID: String? = nil) -> Int {
        let id = BubbleStyleRegistry.migrateLegacyID(styleID ?? PlinkBubbleStylePrefs.currentID)
        let markerLen = "[[bs:\(id)]]".count
        return max(1, 280 - markerLen)
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
                try? await Task.sleep(nanoseconds: Self.unreadPollIntervalNs)
                guard !Task.isCancelled else { break }
                #if canImport(UIKit)
                // В фоне не поллим: бейджи всё равно обновит push / realtime при возврате.
                guard UIApplication.shared.applicationState == .active else { continue }
                #endif
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
            let isNewMessage = event.event == "message"
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
                // Ревью 26.07.2026: приглашения в комнату приходят обычным DM
                // (payload plink-invite:…) и раньше обнаруживались только 20-секундным
                // поллингом — карточка появлялась с задержкой до 20 с.
                if isNewMessage {
                    await RoomInviteService.shared.refreshFromServer()
                }
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
            .flatMap { User.decodeCached($0) }?.id
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
            persistInboxCache()
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
        // Ревью 26.07.2026: запись кэша троттлится, поэтому на выходе из чата
        // сохраняем последнее состояние ленты принудительно.
        persistHistoryCache(friendId: friendId, convID: conversationID(with: friendId), force: true)
        Task { await refreshUnread() }
    }

    // MARK: - Unread summary (GET /messages/unread)

    func refreshUnread() async {
        ensureToken()
        guard api.authToken != nil else { return }
        restorePendingChatDeletes()
        do {
            let items: [UnreadDTO] = try await api.request("messages/unread")
            var counts: [String: Int] = [:]
            // Ревью 26.07.2026: превью/время собираем с нуля из ответа сервера —
            // раньше словарь только пополнялся, и восстановленный с диска мусор
            // (чат очищен на другом устройстве) висел в списке навсегда.
            // Кэш остаётся авторитетом только до первого успешного ответа.
            var previews: [String: String] = [:]
            var activities: [String: Date] = [:]
            for item in items {
                if let deletedAt = pendingChatDeletes[item.friendId] {
                    if let at = item.lastAt, at > deletedAt {
                        // Ревью 26.07.2026: после локального удаления пришли новые
                        // сообщения — отменяем отложенный DELETE (он скрыл бы весь
                        // тред), чат честно возвращается вместе с непрочитанным.
                        pendingChatDeletes.removeValue(forKey: item.friendId)
                        savePendingChatDeletes()
                    } else {
                        continue
                    }
                }
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
                    }
                }
            }
            // Only publish if changed — but always update when counts differ for snappy UI
            if counts != unreadByFriend {
                unreadByFriend = counts
            }
            if previews != lastPreviewByFriend {
                lastPreviewByFriend = previews
            }
            if activities != lastActivityAtByFriend {
                lastActivityAtByFriend = activities
                inboxEpoch &+= 1
            }
            // Снимок инбокса на диск для холодного старта без сети.
            persistInboxCache()
            // Ревью 26.07.2026: досылаем офлайн-удаления ПОСЛЕ сверки с инбоксом —
            // раньше флэш шёл первым и мог скрыть тред вместе с новыми сообщениями.
            await flushPendingChatDeletes()
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
        // До ответа сети показываем последний офлайн-снимок
        // диалога (раньше холодный старт без сети давал пустую переписку).
        restoreHistoryCache(friendId: friendId, convID: convID)
        if !quiet {
            isLoading = true
        }
        defer { if !quiet { isLoading = false } }

        let confirmedBeforeThisLoad = historyNetworkConfirmed.contains(convID)
        do {
            let dtos: [DMMessageDTO] = try await api.request("messages/dm/\(friendId)")
            // Server marks inbound as read on this GET
            if openFriendId == friendId {
                unreadByFriend[friendId] = nil
                unreadByFriend = unreadByFriend.filter { $0.value > 0 }
            }
            let me = currentUserId ?? ""
            let messages = dtos.map {
                mapDTO($0, convID: convID, friendName: friendName, friendAvatarURL: friendAvatarURL, me: me)
            }
            // Server history is source of truth for this window (newest 200).
            // Keep only very recent optimistic locals not yet on server.
            historyNetworkConfirmed.insert(convID)
            if messages.isEmpty, let existing = conversations[convID], !existing.isEmpty {
                // Если в ленте лежал только офлайн-кэш, а сервер
                // отдал пусто — кэш устарел (чат очищен/удалён на другом устройстве).
                // Собственные неотправленные сообщения при этом сохраняем.
                if !confirmedBeforeThisLoad {
                    let keep = existing.filter {
                        pendingLocalIDs.contains($0.id) || failedMessageIDs.contains($0.id)
                    }
                    if keep.count != existing.count {
                        conversations[convID] = keep
                        historyEpoch &+= 1
                        // force: устаревший кэш надо стереть сразу, иначе он
                        // «воскресит» удалённый чат на следующем холодном старте.
                        persistHistoryCache(friendId: friendId, convID: convID, force: true)
                    }
                }
            } else {
                var merged = messages
                if let existing = conversations[convID] {
                    let serverIds = Set(messages.map(\.id))
                    // Оставляем только ЯВНО локальные сообщения
                    // (in-flight / failed). Раньше фильтр «UUID + свежее минуты»
                    // пропускал и серверные сообщения, удалённые собеседником, —
                    // они «воскресали» как призраки при каждом 5-секундном опросе.
                    let localsOnly = existing.filter { msg in
                        !serverIds.contains(msg.id)
                            && (pendingLocalIDs.contains(msg.id) || failedMessageIDs.contains(msg.id))
                    }
                    for loc in localsOnly {
                        // Сравниваем ещё и отправителя — раньше
                        // входящее сообщение с тем же текстом «съедало» наш локальный
                        // пузырь. Окно по времени остаётся страховкой на случай, когда
                        // POST ещё не ответил; окончательный дедуп идёт по id при ответе.
                        if !merged.contains(where: {
                            $0.senderID == loc.senderID
                                && $0.text == loc.text
                                && abs($0.timestamp.timeIntervalSince(loc.timestamp)) < 45
                        }) {
                            merged.append(loc)
                        }
                    }
                    // Страницы, подгруженные пагинацией (старше
                    // серверного окна), не затираем поллингом свежего окна.
                    if messages.count >= Self.serverHistoryWindow,
                       let oldestServer = messages.map(\.timestamp).min() {
                        let olderPages = existing.filter { msg in
                            !serverIds.contains(msg.id)
                                && msg.timestamp < oldestServer
                                && !pendingLocalIDs.contains(msg.id)
                                && !failedMessageIDs.contains(msg.id)
                        }
                        merged.append(contentsOf: olderPages)
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
                    persistHistoryCache(friendId: friendId, convID: convID)
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

    /// Shared DTO → DirectMessage mapping, used by both history and pagination.
    private func mapDTO(
        _ dto: DMMessageDTO,
        convID: String,
        friendName: String,
        friendAvatarURL: String?,
        me: String
    ) -> DirectMessage {
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

    // MARK: - Пагинация истории

    /// Есть ли сообщения старше уже загруженных (триггер «подгрузить раньше»).
    func hasMoreHistory(for friendId: String) -> Bool {
        if let known = hasMoreHistoryByFriend[friendId] { return known }
        // До первого запроса судим по полноте серверного окна (полные 200 = вероятно есть ещё)
        let convID = conversationID(with: friendId)
        return (conversations[convID]?.count ?? 0) >= Self.serverHistoryWindow
    }

    /// Подгрузка старой страницы: before = createdAt самого верхнего сообщения (ISO8601).
    func loadOlderMessages(friendId: String, friendName: String, friendAvatarURL: String? = nil) async {
        ensureToken()
        guard api.authToken != nil, !isLoadingOlderHistory else { return }
        let convID = conversationID(with: friendId)
        guard let oldest = conversations[convID]?.first else { return }
        if hasMoreHistoryByFriend[friendId] == false { return }
        isLoadingOlderHistory = true
        defer { isLoadingOlderHistory = false }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        do {
            let dtos: [DMMessageDTO] = try await api.request(
                "messages/dm/\(friendId)",
                query: [
                    "before": iso.string(from: oldest.timestamp),
                    "limit": String(Self.olderPageSize),
                ]
            )
            hasMoreHistoryByFriend[friendId] = dtos.count >= Self.olderPageSize
            guard !dtos.isEmpty else { return }
            let me = currentUserId ?? ""
            let older = dtos.map {
                mapDTO($0, convID: convID, friendName: friendName, friendAvatarURL: friendAvatarURL, me: me)
            }
            var cur = conversations[convID] ?? []
            let existingIds = Set(cur.map(\.id))
            let fresh = older
                .filter { !existingIds.contains($0.id) }
                .sorted { $0.timestamp < $1.timestamp }
            guard !fresh.isEmpty else { return }
            cur.insert(contentsOf: fresh, at: 0)
            conversations[convID] = cur
            historyEpoch &+= 1
        } catch {
            Logger.api.warn("DM older history load failed")
        }
    }

    // MARK: - Явное «прочитано»

    /// Отметить чат прочитанным из списка чатов БЕЗ подмены openFriendId.
    /// Раньше вместо этого звали chatDidOpen — чат «висел открытым»: бейдж молчал,
    /// а все будущие входящие авточитались realtime-обработчиком.
    func markChatRead(friendId: String) async {
        ensureToken()
        guard api.authToken != nil else { return }
        // Мгновенно чистим локальный бейдж (сервер догонит следующим опросом)
        if unreadByFriend[friendId] != nil {
            var next = unreadByFriend
            next.removeValue(forKey: friendId)
            unreadByFriend = next
        }
        struct Resp: Decodable { let success: Bool?; let marked: Int? }
        do {
            let _: Resp = try await api.request("messages/dm/\(friendId)/read", method: .post)
        } catch {
            Logger.api.warn("DM mark-read failed")
        }
    }

    // MARK: - Повтор отправки

    /// Повторная отправка неотправленного ТЕКСТОВОГО сообщения (медиа-байты не храним).
    func retrySend(messageId: String, friend: Friend) {
        let convID = conversationID(with: friend.id)
        guard var msgs = conversations[convID],
              let idx = msgs.firstIndex(where: { $0.id == messageId }) else {
            failedMessageIDs.remove(messageId)
            return
        }
        let msg = msgs[idx]
        guard !msg.isVoiceNote, !msg.isPhotoMessage else { return }
        msgs.remove(at: idx)
        conversations[convID] = msgs
        failedMessageIDs.remove(messageId)
        historyEpoch &+= 1
        let replyTarget = msg.replyToID.flatMap { rid in msgs.first(where: { $0.id == rid }) }
        sendMessage(msg.text, to: friend, replyTo: replyTarget)
    }

    /// Пришла ли по сети история этого диалога.
    /// Пока не пришла, лента — офлайн-снимок: считать по ней «первое
    /// непрочитанное» нельзя, в снимке нет только что доставленных сообщений.
    func historyConfirmed(for friendID: String) -> Bool {
        historyNetworkConfirmed.contains(conversationID(with: friendID))
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
        // Ревью 26.07.2026: отсечка для офлайн-очереди — всё, что придёт позже,
        // удалением не затрагивается (иначе серверный DELETE унёс бы и его).
        let deleteCutoff = Date()
        // Optimistic local clear
        conversations[convID] = []
        lastPreviewByFriend[friendId] = nil
        lastActivityAtByFriend[friendId] = nil
        unreadByFriend[friendId] = nil
        unreadByFriend = unreadByFriend.filter { $0.value > 0 }
        lastMessages.removeAll { $0.id == convID }
        historyEpoch &+= 1
        inboxEpoch &+= 1
        persistHistoryCache(friendId: friendId, convID: convID, force: true)
        persistInboxCache(force: true)

        ensureToken()
        struct Resp: Decodable { let success: Bool?; let deleted: Int? }
        do {
            let _: Resp = try await api.request(
                "messages/dm/\(friendId)",
                method: .delete
            )
            if pendingChatDeletes.removeValue(forKey: friendId) != nil { savePendingChatDeletes() }
            Logger.api.info("DM chat deleted")
        } catch {
            Logger.api.warn("DM chat delete sync failed")
            // Удаление больше не теряется при отказе сети —
            // ставим в очередь и досылаем при следующем опросе непрочитанных.
            pendingChatDeletes[friendId] = deleteCutoff
            savePendingChatDeletes()
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
        persistHistoryCache(friendId: friendId, convID: convID, force: true)
        persistInboxCache(force: true)
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
        pendingLocalIDs.insert(localID) // Явный in-flight учёт
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
                    removeDuplicateRows(in: &cur, id: saved.id, keeping: idx)
                    conversations[convID] = cur
                    historyEpoch &+= 1
                    persistHistoryCache(friendId: friend.id, convID: convID)
                }
                pendingLocalIDs.remove(localID)
            } catch {
                // Маркер «не отправлено» вместо тихой потери
                pendingLocalIDs.remove(localID)
                failedMessageIDs.insert(localID)
                errorMessage = "Голосовое не отправлено: \(error.localizedDescription)"
                historyEpoch &+= 1
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
        pendingLocalIDs.insert(localID) // Явный in-flight учёт
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
                    removeDuplicateRows(in: &cur, id: saved.id, keeping: idx)
                    conversations[convID] = cur
                    historyEpoch &+= 1
                    persistHistoryCache(friendId: friend.id, convID: convID)
                }
                pendingLocalIDs.remove(localID)
            } catch {
                // Маркер «не отправлено» вместо тихой потери
                pendingLocalIDs.remove(localID)
                failedMessageIDs.insert(localID)
                errorMessage = "Фото не отправлено: \(error.localizedDescription)"
                historyEpoch &+= 1
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
        // Wire style so peer devices render the same bubble (fits in 280 server limit).
        // Лимит считается тем же textLimit(), что показывает
        // композер, — раньше UI обещал 280, а сервис резал под маркер стиля.
        let body = String(trimmed.prefix(Self.textLimit(forStyleID: styleID)))
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
        pendingLocalIDs.insert(localID) // Явный in-flight учёт
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
                    removeDuplicateRows(in: &cur, id: saved.id, keeping: idx)
                    conversations[convID] = cur
                    historyEpoch &+= 1
                    persistHistoryCache(friendId: friend.id, convID: convID)
                }
                pendingLocalIDs.remove(localID)
            } catch {
                // Помечаем как «не отправлено» (красный маркер
                // + «Повторить» в UI) вместо тихой потери через 60 секунд.
                pendingLocalIDs.remove(localID)
                failedMessageIDs.insert(localID)
                errorMessage = "Сообщение не отправлено: \(error.localizedDescription)"
                historyEpoch &+= 1
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
            // Query нельзя класть в path
            // appendingPathComponent кодирует «?» в %3F и роут не матчится.
            let _: Resp = try await api.request(
                "messages/dm/\(friendId)/pin/\(messageId)",
                method: .delete,
                query: ["forBoth": forBoth ? "true" : "false"]
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
            // Query нельзя класть в path
            // appendingPathComponent кодирует «?» в %3F и роут не матчится.
            let _: Resp = try await api.request(
                "messages/dm/message/\(message.id)",
                method: .delete,
                query: ["forBoth": forBoth ? "true" : "false"]
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
            api.authToken = AuthTokenStore.shared.token
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
