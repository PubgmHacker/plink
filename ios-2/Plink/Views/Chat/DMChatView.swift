import SwiftUI
import PhotosUI

// MARK: - DM Chat View v7 — Telegram glassmorphism + reactions

struct DMChatView: View {
    @EnvironmentObject private var dmService: DMChatService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var friendManager = FriendManager.shared

    let friend: Friend
    @State private var messageText = ""
    @State private var showEmojiPicker = false
    @State private var showWatchTogether = false
    @State private var showPeerProfile = false
    @State private var showChatActions = false
    @State private var confirmDeleteChat = false
    @State private var confirmBlockUser = false
    @State private var reactionTarget: DirectMessage?
    // Telegram-style chat features
    @State private var replyTarget: DirectMessage?
    @State private var pinTarget: DirectMessage?
    @State private var isSelecting = false
    @State private var selectedMessageIDs: Set<String> = []
    @State private var showForwardSheet = false
    @State private var forwardIDs: [String] = []
    @State private var editTarget: DirectMessage?
    @State private var deleteTarget: DirectMessage?
    @FocusState private var isInputFocused: Bool
    /// Аудит 26.07.2026 P2: серверный лимит 280 считается по wire-строке, куда
    /// входит маркер стиля пузыря. Раньше UI обещал 280, а сервис молча срезал
    /// хвост под маркер — считаем лимит там же, где его применяет отправка.
    private var charLimit: Int { DMChatService.textLimit(forStyleID: editTarget?.bubbleStyle) }
    @State private var lastSendTime: Date = .distantPast
    /// Аудит 26.07.2026 P1: id нижнего сообщения при последнем автоскролле —
    /// защищает читателя истории от сброса вниз на каждый historyEpoch.
    @State private var lastAutoScrollBottomID: String?
    @State private var wallpaper = PlinkChatWallpaperPrefs.current
    @State private var voiceRecorder = VoiceNoteRecorder()
    @State private var voiceError: String?
    @State private var voiceStartInFlight = false
    /// Finger is currently holding the mic (Telegram hold-to-record).
    @State private var voiceFingerDown = false
    /// Drag left past threshold → cancel (VK / Telegram).
    @State private var voiceCancelArmed = false
    @State private var voiceDragX: CGFloat = 0
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoDraft: ChatPhotoDraft?
    @State private var photoCaption = ""
    @State private var photoError: String?
    @ObservedObject private var blockManager = UserBlockManager.shared

    /// Telegram iOS 2026 private-chat navigation metrics.
    private enum TGHeader {
        /// Avatar sits on the right (Telegram 2025–26 chat header)
        static let avatar: CGFloat = 40
        static let barHeight: CGFloat = 52
        static let nameSize: CGFloat = 16
        static let statusSize: CGFloat = 12
        /// Classic Telegram “online” green
        static let online = Color(red: 0.20, green: 0.78, blue: 0.35)
    }

    private var chatsUnreadBadge: Int {
        max(0, dmService.totalUnread - dmService.unreadCount(for: friend.id))
    }

    private var headerPresence: String {
        if dmService.typingByFriend[friend.id] == true { return LocalizationManager.shared.string(.dmTyping) }
        return FriendPresence.headerStatus(
            isOnline: liveFriend.isOnline,
            lastSeenAt: liveFriend.lastSeenAt
        )
    }

    private var headerIsOnline: Bool {
        if liveFriend.deleted { return false }
        return liveFriend.isOnline || headerPresence == "в сети"
    }

    /// Live friend snapshot (avatarURL updates when they change photo).
    private var liveFriend: Friend {
        friendManager.friends.first(where: { $0.id == friend.id }) ?? friend
    }

    private var peerAvatarURL: URL? {
        // Touch epoch so Observation / ObservedObject refresh re-renders avatar
        _ = friendManager.avatarEpoch
        // Uses per-user ?v= so a friend photo update reloads without flicker thrash
        return PlinkAvatarURL.stable(userId: liveFriend.id, stored: liveFriend.avatarURL)
    }

    private var peerLetter: String {
        PlinkAvatarURL.letter(from: liveFriend.displayTitle)
    }

    private var meId: String {
        dmService.currentUserId
            ?? UserDefaults.standard.string(forKey: "plink_current_user_id")
            ?? ""
    }

    private var meLetter: String {
        let name = UserDefaults.standard.string(forKey: "plink_current_display_name")
            ?? UserDefaults.standard.string(forKey: "plink_current_username")
            ?? "?"
        return PlinkAvatarURL.letter(from: name)
    }

    private var meAvatarURL: URL? {
        PlinkAvatarURL.stable(userId: meId.isEmpty ? nil : meId, stored: nil)
    }

    private var messages: [DirectMessage] {
        dmService.messages(for: friend.id)
    }

    var body: some View {
        ZStack {
            wallpaper.background

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                    if let pin = currentPins.last {
                        pinnedBar(pin, proxy: proxy)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Аудит 26.07.2026 P1: пагинация — подгрузка страницы старше
                            // (before = createdAt верхнего сообщения, ISO8601).
                            if dmService.hasMoreHistory(for: friend.id), !messages.isEmpty {
                                ProgressView()
                                    .tint(.white.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    // id от верхнего сообщения: после prepend identity меняется
                                    // и onAppear может сработать для следующей страницы
                                    .id("dm-history-loader-\(messages.first?.id ?? "")")
                                    .onAppear {
                                        let anchorID = messages.first?.id
                                        Task {
                                            await dmService.loadOlderMessages(
                                                friendId: friend.id,
                                                friendName: liveFriend.displayTitle,
                                                friendAvatarURL: liveFriend.avatarURL
                                            )
                                            // Держим прежний верх на месте после prepend
                                            if let anchorID {
                                                proxy.scrollTo(anchorID, anchor: .top)
                                            }
                                        }
                                    }
                            }
                            DMDayDivider(label: "Сегодня")

                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                                let own = msg.isFromCurrentUser(currentUserId: meId)
                                let prevId = index > 0 ? messages[index - 1].senderID : nil
                                let nextId = index + 1 < messages.count ? messages[index + 1].senderID : nil
                                let cluster = ChatClusterLayout.compute(
                                    senderId: msg.senderID,
                                    previousSenderId: prevId,
                                    nextSenderId: nextId,
                                    isOwn: own
                                )
                                DMMessageRow(
                                    message: msg,
                                    isOwn: own,
                                    avatarURL: own ? meAvatarURL : peerAvatarURL,
                                    letter: own ? meLetter : peerLetter,
                                    cluster: cluster,
                                    onReact: { reactionTarget = msg },
                                    onToggleChip: { emoji in
                                        Task {
                                            await dmService.toggleReaction(
                                                emoji: emoji,
                                                on: msg,
                                                friendId: friend.id
                                            )
                                        }
                                    },
                                    senderIsAdmin: own ? (AuthService.shared.currentUserValue?.isAdmin ?? false) : false,
                                    senderIsPremium: own ? (AuthService.shared.currentUserValue?.isPremium ?? false) : false,
                                    replySenderName: msg.replyPreviewSenderID.map { $0 == meId ? "Вы" : liveFriend.displayTitle },
                                    isSelecting: isSelecting,
                                    isSelected: selectedMessageIDs.contains(msg.id),
                                    onReply: { startReply(msg) },
                                    onPinRequest: { pinTarget = msg },
                                    onForward: {
                                        forwardIDs = [msg.id]
                                        showForwardSheet = true
                                    },
                                    onSelect: { enterSelection(with: msg) },
                                    onToggleSelection: { toggleSelection(msg) },
                                    onQuoteTap: { quotedId in
                                        withAnimation { proxy.scrollTo(quotedId, anchor: .center) }
                                    },
                                    onEdit: { startEdit(msg) },
                                    onDelete: { deleteTarget = msg },
                                    isFailed: dmService.failedMessageIDs.contains(msg.id),
                                    onRetry: { dmService.retrySend(messageId: msg.id, friend: friend) }
                                )
                                .id(msg.id)
                                .padding(.horizontal, 8)
                                .padding(.top, cluster.topPadding)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.bottom, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 24)
                            .onEnded { value in
                                // Swipe down to hide keyboard (Telegram-like)
                                if value.translation.height > 40 {
                                    isInputFocused = false
                                    showEmojiPicker = false
                                }
                            }
                    )
                    // Аудит 26.07.2026 P1: не дёргаем читателя вниз по глобальному
                    // historyEpoch (isRead-флипы, реакции, loadHistory чужих чатов) —
                    // скроллим только когда внизу ЭТОГО чата появилось новое сообщение.
                    .onChange(of: dmService.historyEpoch) { _, _ in
                        let bottomID = messages.last?.id
                        guard let bottomID, bottomID != lastAutoScrollBottomID else { return }
                        lastAutoScrollBottomID = bottomID
                        DispatchQueue.main.async { scrollToBottom(proxy: proxy) }
                    }
                    .onAppear {
                        lastAutoScrollBottomID = messages.last?.id
                        DispatchQueue.main.async {
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                    }
                    }
                }

                if showEmojiPicker {
                    EmojiPickerGrid(chatText: $messageText)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .background(.ultraThinMaterial)
                }

                if let target = replyTarget {
                    replyComposerBar(target)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let editing = editTarget {
                    editComposerBar(editing)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if isSelecting {
                    selectionActionBar
                } else {
                    glassInputBar
                }
            }
        }
        // Telegram: fixed top bar over chat (safe-area aware)
        .safeAreaInset(edge: .top, spacing: 0) {
            telegramNavBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showWatchTogether) {
            RoomCreationView { room in
                showWatchTogether = false
                let code = room.code
                let name = room.name
                dmService.sendMessage("Мы создали комнату «\(name)» · код \(code). Смотрим вместе!", to: friend)
            }
            .environmentObject(APIClient.shared)
        }
        .sheet(isPresented: $showPeerProfile) {
            NavigationStack {
                FriendProfileView(
                    userId: liveFriend.id,
                    usernameHint: liveFriend.deleted ? "Удалённый аккаунт" : liveFriend.username,
                    onWatchTogether: liveFriend.deleted ? nil : {
                        showPeerProfile = false
                        showWatchTogether = true
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Закрыть") { showPeerProfile = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $photoDraft) { draft in
            PhotoSendPreviewSheet(
                draft: draft,
                caption: $photoCaption,
                onCancel: {
                    photoDraft = nil
                    selectedPhotoItem = nil
                    photoCaption = ""
                },
                onSend: {
                    dmService.sendPhoto(
                        dataURL: draft.compressed.dataURL,
                        previewImage: draft.compressed.image,
                        caption: photoCaption,
                        to: liveFriend
                    )
                    photoDraft = nil
                    selectedPhotoItem = nil
                    photoCaption = ""
                    HapticManager.impact(.medium)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $reactionTarget) { msg in
            DMReactionPickerSheet(
                message: msg,
                onPick: { emoji in
                    reactionTarget = nil
                    Task {
                        await dmService.toggleReaction(emoji: emoji, on: msg, friendId: friend.id)
                    }
                },
                onDismiss: { reactionTarget = nil }
            )
            .presentationDetents([.height(160)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .confirmationDialog(
            "Закрепить сообщение?",
            isPresented: Binding(
                get: { pinTarget != nil },
                set: { if !$0 { pinTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Закрепить у себя") {
                if let msg = pinTarget {
                    Task { await dmService.pinMessage(msg, forBoth: false, friendId: friend.id) }
                }
                pinTarget = nil
            }
            Button("Закрепить у себя и у \(liveFriend.displayTitle)") {
                if let msg = pinTarget {
                    Task { await dmService.pinMessage(msg, forBoth: true, friendId: friend.id) }
                }
                pinTarget = nil
            }
            Button("Отмена", role: .cancel) { pinTarget = nil }
        }
        .confirmationDialog(
            LocalizationManager.shared.string(.dmDeleteTitle),
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(LocalizationManager.shared.string(.dmDeleteForMe), role: .destructive) {
                if let msg = deleteTarget {
                    Task { await dmService.deleteMessage(msg, forBoth: false, friendId: friend.id) }
                }
                deleteTarget = nil
            }
            if deleteTarget?.isFromCurrentUser(currentUserId: meId) == true {
                Button("\(LocalizationManager.shared.string(.dmDeleteForBothPrefix)) \(liveFriend.displayTitle)", role: .destructive) {
                    if let msg = deleteTarget {
                        Task { await dmService.deleteMessage(msg, forBoth: true, friendId: friend.id) }
                    }
                    deleteTarget = nil
                }
            }
            Button("Отмена", role: .cancel) { deleteTarget = nil }
        }
        .sheet(isPresented: $showForwardSheet) {
            DMForwardSheet(
                friends: friendManager.friends.filter { $0.id != friend.id && !$0.deleted },
                onPick: { target in
                    let ids = forwardIDs
                    showForwardSheet = false
                    Task {
                        let ok = await dmService.forwardMessages(ids, to: target)
                        if ok { HapticManager.impact(.medium) }
                        exitSelection()
                        forwardIDs = []
                    }
                },
                onCancel: { showForwardSheet = false }
            )
        }
        .preferredColorScheme(.dark)
        .onAppear {
            dmService.chatDidOpen(friendId: friend.id)
            Task { await dmService.refreshUnread() }
            // Telegram-style draft: restore unsent text for this chat
            if messageText.isEmpty {
                messageText = UserDefaults.standard.string(forKey: "plink.dm_draft_\(friend.id)") ?? ""
            }
        }
        .onDisappear {
            dmService.chatDidClose(friendId: friend.id)
            // Telegram-style draft: persist unsent text per chat
            let draft = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
            if draft.isEmpty || editTarget != nil {
                UserDefaults.standard.removeObject(forKey: "plink.dm_draft_\(friend.id)")
            } else {
                UserDefaults.standard.set(draft, forKey: "plink.dm_draft_\(friend.id)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkChatWallpaperChanged)) { _ in
            wallpaper = PlinkChatWallpaperPrefs.current
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await preparePhotoDraft(from: item) }
        }
        .alert("Фото", isPresented: Binding(
            get: { photoError != nil },
            set: { if !$0 { photoError = nil } }
        )) {
            Button("OK", role: .cancel) { photoError = nil }
        } message: {
            Text(photoError ?? "")
        }
        .task {
            dmService.chatDidOpen(friendId: friend.id)
            // Seed live friends so avatar / last-seen stay fresh
            await friendManager.loadFriends()
            // Force full history apply (newest window) — fixes preview vs open mismatch
            await dmService.loadHistory(
                friendId: friend.id,
                friendName: liveFriend.displayTitle,
                friendAvatarURL: liveFriend.avatarURL,
                quiet: false
            )
            await dmService.loadPins(friendId: friend.id)
            // Аудит 26.07.2026 P2: список друзей и закрепления не нужны каждые 5 с —
            // это лишние 2 запроса на тик поверх истории и typing.
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                tick &+= 1
                if tick % 4 == 0 {
                    await friendManager.loadFriends()
                }
                // Quiet polling prevents full-list visual churn and reduces chat lag.
                await dmService.loadHistory(
                    friendId: friend.id,
                    friendName: liveFriend.displayTitle,
                    friendAvatarURL: liveFriend.avatarURL,
                    quiet: true
                )
                if tick % 4 == 0 {
                    await dmService.loadPins(friendId: friend.id)
                }
                await dmService.loadTyping(friendId: friend.id)
            }
        }
    }

    // MARK: - Telegram-style chat helpers (reply / pin / select / forward)

    private var currentPins: [DMPinnedMessage] {
        dmService.pinsByFriend[friend.id] ?? []
    }

    private func startReply(_ msg: DirectMessage) {
        guard !isSelecting else { return }
        HapticManager.impact(.light)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { replyTarget = msg }
        isInputFocused = true
    }

    private func enterSelection(with msg: DirectMessage) {
        HapticManager.impact(.medium)
        withAnimation {
            isSelecting = true
            selectedMessageIDs = [msg.id]
        }
    }

    private func toggleSelection(_ msg: DirectMessage) {
        if selectedMessageIDs.contains(msg.id) {
            selectedMessageIDs.remove(msg.id)
        } else {
            selectedMessageIDs.insert(msg.id)
        }
        if selectedMessageIDs.isEmpty { exitSelection() }
    }

    private func exitSelection() {
        withAnimation {
            isSelecting = false
            selectedMessageIDs = []
        }
    }

    private func orderedSelectedIDs() -> [String] {
        messages.filter { selectedMessageIDs.contains($0.id) }.map(\.id)
    }

    /// Telegram pinned-message bar (top of chat, tap → scroll to message).
    @ViewBuilder
    private func pinnedBar(_ pin: DMPinnedMessage, proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Cinema2026.accent)
                .frame(width: 3, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Cinema2026.accent)
                    Text(currentPins.count > 1
                         ? "Закреплённые сообщения · \(currentPins.count)"
                         : "Закреплённое сообщение")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Cinema2026.accent)
                }
                Text(pin.text.isEmpty ? "Сообщение" : pin.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Menu {
                Button {
                    Task { await dmService.unpinMessage(messageId: pin.messageId, forBoth: false, friendId: friend.id) }
                } label: {
                    Label("Открепить у себя", systemImage: "pin.slash")
                }
                Button(role: .destructive) {
                    Task { await dmService.unpinMessage(messageId: pin.messageId, forBoth: true, friendId: friend.id) }
                } label: {
                    Label("Открепить у обоих", systemImage: "pin.slash.fill")
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(8)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation { proxy.scrollTo(pin.messageId, anchor: .center) }
        }
    }

    /// Telegram reply bar above the composer.
    private func replyComposerBar(_ target: DirectMessage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Cinema2026.accent)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Cinema2026.accent)
                .frame(width: 3, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(target.isFromCurrentUser(currentUserId: meId) ? "Вы" : liveFriend.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Cinema2026.accent)
                Text(target.isVoiceNote
                     ? "🎤 Голосовое сообщение"
                     : (target.isPhotoMessage ? "📷 Фото" : target.text))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                withAnimation { replyTarget = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    /// Telegram selection-mode bottom bar («Переслать N»).
    private var selectionActionBar: some View {
        HStack(spacing: 16) {
            Button("Отмена") { exitSelection() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text("Выбрано: \(selectedMessageIDs.count)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button {
                forwardIDs = orderedSelectedIDs()
                showForwardSheet = true
            } label: {
                Label("Переслать", systemImage: "arrowshape.turn.up.right.fill")
                    .font(.system(size: 15, weight: .bold))
            }
            .disabled(selectedMessageIDs.isEmpty)
            .foregroundStyle(selectedMessageIDs.isEmpty ? Color.white.opacity(0.3) : Cinema2026.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    /// Telegram edit bar above the composer («Редактирование»).
    private func editComposerBar(_ target: DirectMessage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Cinema2026.accent)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Cinema2026.accent)
                .frame(width: 3, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizationManager.shared.string(.dmEditing))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Cinema2026.accent)
                Text(target.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                withAnimation {
                    editTarget = nil
                }
                messageText = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func startEdit(_ msg: DirectMessage) {
        guard msg.isFromCurrentUser(currentUserId: meId), !msg.isVoiceNote, !msg.isPhotoMessage else { return }
        HapticManager.impact(.light)
        withAnimation {
            replyTarget = nil
            editTarget = msg
        }
        messageText = msg.text
        isInputFocused = true
    }

    // MARK: - Telegram 2026 glass chat header

    /// Layout: [← Чаты · badge]  [  ник / online  ]  [ avatar ⋯ ]
    private func preparePhotoDraft(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoError = "Не удалось прочитать фото"
                return
            }
            let compressed = try ChatImageCompressor.compress(data)
            await MainActor.run {
                photoCaption = ""
                photoDraft = ChatPhotoDraft(compressed: compressed)
            }
        } catch {
            await MainActor.run {
                photoError = "Не удалось подготовить фото: \(error.localizedDescription)"
                selectedPhotoItem = nil
            }
        }
    }

    private var telegramNavBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // ── Left: back to all chats (glass pill + unread indicator)
                Button {
                    HapticManager.selection()
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                        Text(LocalizationManager.shared.string(.dmChatsBack))
                            .font(.system(size: 16, weight: .semibold))
                        if chatsUnreadBadge > 0 {
                            Text(chatsUnreadBadge > 99 ? "99+" : "\(chatsUnreadBadge)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Cinema2026.accent, in: Capsule())
                        }
                    }
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.7)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    chatsUnreadBadge > 0
                    ? "К чатам, непрочитанных \(chatsUnreadBadge)"
                    : "К чатам"
                )

                Spacer(minLength: 4)

                // ── Center: glass capsule with nick + presence (tap → profile)
                Button {
                    HapticManager.impact(.light)
                    showPeerProfile = true
                } label: {
                    VStack(spacing: 1) {
                        Text(liveFriend.displayTitle)
                            .font(.system(size: TGHeader.nameSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(headerPresence)
                            .font(.system(size: TGHeader.statusSize, weight: headerIsOnline ? .semibold : .regular))
                            .foregroundStyle(
                                headerIsOnline
                                ? TGHeader.online
                                : Color.white.opacity(0.55)
                            )
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .frame(minWidth: 120, maxWidth: 200)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(liveFriend.displayTitle), \(headerPresence)")
                .accessibilityHint("Открыть профиль")

                Spacer(minLength: 4)

                // ── Right: avatar + more
                HStack(spacing: 8) {
                    Button {
                        HapticManager.impact(.light)
                        showPeerProfile = true
                    } label: {
                        Group {
                            if liveFriend.deleted {
                                PlinkDeletedAvatar(size: TGHeader.avatar)
                            } else {
                                PlinkStableAvatar(
                                    url: peerAvatarURL,
                                    letter: peerLetter,
                                    size: TGHeader.avatar,
                                    userId: liveFriend.id
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                )
                                .overlay(alignment: .bottomTrailing) {
                                    if headerIsOnline {
                                        Circle()
                                            .fill(TGHeader.online)
                                            .frame(width: 11, height: 11)
                                            .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1.5))
                                            .offset(x: 1, y: 1)
                                    }
                                }
                            }
                        }
                        .id("tg-av-\(liveFriend.id)-\(friendManager.avatarEpoch)-\(peerAvatarURL?.absoluteString ?? "")")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Профиль \(liveFriend.displayTitle)")

                    Button {
                        HapticManager.impact(.light)
                        showChatActions = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ещё")
                }
                .padding(.trailing, 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: TGHeader.barHeight)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
        .background {
            // Glass curtain under status bar (Telegram 2026 liquid glass)
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.28),
                            Color.black.opacity(0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea(edges: .top)
        }
        .confirmationDialog(
            liveFriend.displayTitle,
            isPresented: $showChatActions,
            titleVisibility: .visible
        ) {
            Button("Профиль") { showPeerProfile = true }
            if !liveFriend.deleted {
                Button("Смотреть вместе") { showWatchTogether = true }
            }
            Button("Удалить чат", role: .destructive) {
                confirmDeleteChat = true
            }
            if blockManager.isBlocked(liveFriend.id) {
                Button("Разблокировать") {
                    blockManager.unblockUser(liveFriend.id)
                    HapticManager.impact(.light)
                }
            } else {
                Button("Заблокировать", role: .destructive) {
                    confirmBlockUser = true
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Удалить чат?", isPresented: $confirmDeleteChat) {
            Button("Удалить", role: .destructive) {
                Task {
                    await dmService.deleteChat(with: liveFriend)
                    await MainActor.run { dismiss() }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("История переписки с \(liveFriend.displayTitle) будет удалена. Это действие нельзя отменить.")
        }
        .alert("Внести в чёрный список?", isPresented: $confirmBlockUser) {
            Button("Заблокировать", role: .destructive) {
                Task {
                    await blockManager.blockAndDeleteChat(
                        userId: liveFriend.id,
                        friend: liveFriend
                    )
                    HapticManager.impact(.heavy)
                    await MainActor.run { dismiss() }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Точно хотите внести \(liveFriend.displayTitle) в чёрный список? Пользователь не сможет отправлять вам сообщения и приглашать в комнаты. Переписка будет удалена.")
        }
    }

    // MARK: - Glass input

    private var glassInputBar: some View {
        VStack(spacing: 0) {
        // M16: баннер ИИ-модератора (мут за маты / отклонённое фото).
        // Аудит 26.07.2026 P1: показываем ЛЮБУЮ ошибку сервиса — раньше фильтр по
        // ключевым словам скрывал сетевые сбои, и отправка падала «молча».
        if let modMsg = dmService.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.red.opacity(0.9))
                Text(modMsg)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    dmService.errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.18))
        }
        Group {
            if liveFriend.deleted {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .foregroundStyle(.white.opacity(0.55))
                    Text(LocalizationManager.shared.string(.dmDeletedAccount))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)
            } else if blockManager.isBlocked(friend.id) {
                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.orange.opacity(0.9))
                    Text("Вы заблокировали \(liveFriend.displayTitle)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Button("Разблок.") {
                        blockManager.unblockUser(friend.id)
                        HapticManager.impact(.light)
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Cinema2026.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)
            } else {
                // Stable layout: left content changes, mic keeps the same identity
                // so hold-gesture is not cancelled when recording UI appears.
                HStack(spacing: 10) {
                    if voiceRecorder.isRecording || voiceFingerDown {
                        voiceRecordingLeading
                    } else {
                        composerLeading
                    }

                    // Empty text → mic (hold). Has text → send (tap). While recording always mic.
                    if messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || voiceRecorder.isRecording || voiceFingerDown {
                        voiceMicButton
                    } else {
                        Button(action: sendAction) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.85))
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Cinema2026.accent))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Отправить")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .onChange(of: voiceRecorder.durationSec) { _, dur in
                    if dur >= VoiceNoteRecorder.maxDuration {
                        finishVoiceRecording(send: true)
                    }
                }
            }
        }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
        .alert("Голосовое", isPresented: Binding(
            get: { voiceError != nil },
            set: { if !$0 { voiceError = nil } }
        )) {
            Button("OK", role: .cancel) { voiceError = nil }
        } message: {
            Text(voiceError ?? "")
        }
    }

    // MARK: - Voice recording (Telegram / VK style)

    private var composerLeading: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Cinema2026.accent)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Галерея")
            .simultaneousGesture(TapGesture().onEnded { Task { await PlinkPermissions.preparePhotoPicker() } })

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showEmojiPicker.toggle()
                }
                if showEmojiPicker { isInputFocused = false }
            } label: {
                Image(systemName: showEmojiPicker ? "keyboard.fill" : "face.smiling.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(showEmojiPicker ? Cinema2026.accent : Color.white.opacity(0.55))
                    .frame(width: 34, height: 36)
            }

            TextField("Сообщение", text: $messageText, axis: .vertical)
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .lineLimit(1...5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 42)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
                )
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit { sendAction() }
                .onChange(of: messageText) { _, newValue in
                    if !newValue.isEmpty, editTarget == nil {
                        dmService.sendTyping(friendId: friend.id)
                    }
                    if newValue.count > charLimit {
                        messageText = String(newValue.prefix(charLimit))
                        HapticManager.impact(.light)
                    }
                }
                // M25 UX: счётчик символов появляется при приближении к лимиту
                .overlay(alignment: .topTrailing) {
                    if messageText.count >= charLimit - 40 {
                        Text("\(messageText.count)/\(charLimit)")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(messageText.count >= charLimit ? Color.red : Color.white.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .offset(x: -10, y: -9)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.15), value: messageText.count >= charLimit)
                    }
                }
        }
    }

    /// Left side of bar while holding: cancel hint + levels + timer.
    private var voiceRecordingLeading: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                Text(voiceCancelArmed ? "Отмена" : "Влево")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(voiceCancelArmed ? Color.red.opacity(0.95) : Color.white.opacity(0.45))

            Spacer(minLength: 4)

            VoiceLevelBars(level: voiceRecorder.peakLevel, active: true)
                .frame(width: 64, height: 22)

            Text(PlinkVoiceWire.formatDuration(voiceRecorder.durationSec))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(minWidth: 40, alignment: .trailing)
        }
    }

    /// Mic stays mounted while recording so the hold gesture never drops.
    private var voiceMicButton: some View {
        let recording = voiceRecorder.isRecording || voiceFingerDown
        return ZStack {
            Circle()
                .fill(
                    voiceCancelArmed
                    ? Color.red.opacity(0.35)
                    : (recording ? Cinema2026.accent.opacity(0.28) : Color.white.opacity(0.10))
                )
                .frame(width: recording ? 58 : 44, height: recording ? 58 : 44)
                .scaleEffect(recording ? 1.0 + CGFloat(voiceRecorder.peakLevel) * 0.12 : 1)
            Circle()
                .fill(voiceCancelArmed ? Color.red : (recording ? Cinema2026.accent : Color.white.opacity(0.14)))
                .frame(width: recording ? 46 : 40, height: recording ? 46 : 40)
            Image(systemName: voiceCancelArmed ? "trash.fill" : "mic.fill")
                .font(.system(size: recording ? 20 : 18, weight: .semibold))
                .foregroundStyle(recording || voiceCancelArmed ? Color.white : Color.white.opacity(0.85))
        }
        .offset(x: max(-80, min(0, voiceDragX * 0.3)))
        .contentShape(Circle().scale(1.6))
        .gesture(voiceHoldGesture)
        .animation(.easeOut(duration: 0.08), value: voiceRecorder.peakLevel)
        .accessibilityLabel("Удерживайте для голосового сообщения")
        .accessibilityHint("Отпустите, чтобы отправить. Сдвиньте влево, чтобы отменить")
    }

    private var voiceHoldGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                voiceFingerDown = true
                voiceDragX = value.translation.width
                let cancel = value.translation.width < -55
                if cancel != voiceCancelArmed {
                    voiceCancelArmed = cancel
                    HapticManager.impact(cancel ? .rigid : .light)
                }
                if voiceRecorder.isRecording {
                    return
                }
                guard !voiceStartInFlight else { return }
                voiceStartInFlight = true
                isInputFocused = false
                showEmojiPicker = false
                Task {
                    HapticManager.impact(.medium)
                    let ok = await voiceRecorder.start()
                    await MainActor.run {
                        voiceStartInFlight = false
                        // Finger already up while permission sheet was open → drop
                        if !voiceFingerDown {
                            if ok { voiceRecorder.cancel() }
                            resetVoiceGestureUI()
                            return
                        }
                        if !ok {
                            resetVoiceGestureUI()
                            if case .failed(let m) = voiceRecorder.state {
                                voiceError = m
                            } else {
                                voiceError = "Нет доступа к микрофону. Разрешите в окне iOS или в Настройках."
                            }
                        }
                    }
                }
            }
            .onEnded { _ in
                voiceFingerDown = false
                voiceStartInFlight = false
                let shouldCancel = voiceCancelArmed
                // If still starting (permission), cancel is handled when start returns
                if voiceRecorder.isRecording || {
                    if case .encoding = voiceRecorder.state { return true }
                    return false
                }() {
                    finishVoiceRecording(send: !shouldCancel)
                } else {
                    // Never got to recording (permission / short tap)
                    if case .failed(let m) = voiceRecorder.state {
                        voiceError = m
                    }
                    voiceRecorder.cancel()
                }
                resetVoiceGestureUI()
            }
    }

    private func resetVoiceGestureUI() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            voiceCancelArmed = false
            voiceDragX = 0
            voiceFingerDown = false
        }
    }

    private func finishVoiceRecording(send: Bool) {
        guard voiceRecorder.isRecording || {
            if case .encoding = voiceRecorder.state { return true }
            return false
        }() else {
            if case .failed(let m) = voiceRecorder.state {
                voiceError = m
            }
            voiceRecorder.cancel()
            resetVoiceGestureUI()
            return
        }

        if !send {
            voiceRecorder.cancel()
            HapticManager.impact(.light)
            resetVoiceGestureUI()
            return
        }

        guard let exported = voiceRecorder.stopAndExport() else {
            if case .failed(let m) = voiceRecorder.state {
                voiceError = m
            }
            resetVoiceGestureUI()
            return
        }
        HapticManager.impact(.medium)
        dmService.sendVoiceNote(
            dataURL: exported.dataURL,
            durationSec: exported.duration,
            to: friend
        )
        resetVoiceGestureUI()
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastID = messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    private func sendAction() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSendTime) >= 0.4 else {
            HapticManager.impact(.light)
            return
        }
        lastSendTime = now
        if let editing = editTarget {
            Task { await dmService.editMessage(editing, newText: text, friendId: friend.id) }
            withAnimation { editTarget = nil }
        } else {
            dmService.sendMessage(text, to: friend, replyTo: replyTarget)
        }
        messageText = ""
        withAnimation { replyTarget = nil }
        UserDefaults.standard.removeObject(forKey: "plink.dm_draft_\(friend.id)")
        HapticManager.impact(.light)
    }
}

// MARK: - Reaction picker (Telegram quick bar)

private struct DMReactionPickerSheet: View {
    let message: DirectMessage
    let onPick: (String) -> Void
    let onDismiss: () -> Void

    private let emojis = ["❤️", "👍", "😂", "😮", "😢", "🔥", "👏", "🎉", "💯", "🥰"]

    var body: some View {
        VStack(spacing: 14) {
            Text(LocalizationManager.shared.string(.dmReaction))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 8) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        HapticManager.impact(.light)
                        onPick(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Circle avatar

private struct DMCircleAvatar: View {
    let url: URL?
    let letter: String
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        letterView
                    }
                }
            } else {
                letterView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .id(url?.absoluteString ?? "letter-\(letter)")
    }

    private var letterView: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Cinema2026.accent.opacity(0.75), Color.purple.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(letter)
                .font(.system(size: max(10, size * 0.38), weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - DM Bubble (Telegram clusters + reactions + glass capsules)

private struct DMMessageRow: View {
    let message: DirectMessage
    let isOwn: Bool
    var avatarURL: URL?
    var letter: String = "?"
    var cluster: ChatClusterLayout
    var onReact: () -> Void
    var onToggleChip: (String) -> Void
    /// Sender roles — drive admin/premium ring on chat avatar.
    var senderIsAdmin: Bool = false
    var senderIsPremium: Bool = false
    // Telegram-style features
    var replySenderName: String? = nil
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onReply: () -> Void = {}
    var onPinRequest: () -> Void = {}
    var onForward: () -> Void = {}
    var onSelect: () -> Void = {}
    var onToggleSelection: () -> Void = {}
    var onQuoteTap: (String) -> Void = { _ in }
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    // Аудит 26.07.2026 P1: маркер «не отправлено» + повтор отправки
    var isFailed: Bool = false
    var onRetry: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            DMBubble(
                message: message,
                isOwn: isOwn,
                avatarURL: avatarURL,
                letter: letter,
                cluster: cluster,
                maxBubbleWidth: min(
                    PlinkTelegramBubbleMetrics.maxBubbleWidth,
                    geo.size.width * PlinkTelegramBubbleMetrics.maxWidthRatio
                ),
                onReact: onReact,
                onToggleChip: onToggleChip,
                senderIsAdmin: senderIsAdmin,
                senderIsPremium: senderIsPremium,
                replySenderName: replySenderName,
                isSelecting: isSelecting,
                isSelected: isSelected,
                onReply: onReply,
                onPinRequest: onPinRequest,
                onForward: onForward,
                onSelect: onSelect,
                onToggleSelection: onToggleSelection,
                onQuoteTap: onQuoteTap,
                onEdit: onEdit,
                onDelete: onDelete,
                isFailed: isFailed,
                onRetry: onRetry
            )
        }
        .frame(minHeight: 1)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DMBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    var avatarURL: URL?
    var letter: String = "?"
    var cluster: ChatClusterLayout
    var maxBubbleWidth: CGFloat = PlinkTelegramBubbleMetrics.maxBubbleWidth
    var onReact: () -> Void
    var onToggleChip: (String) -> Void
    /// Sender roles — drive admin/premium ring on chat avatar.
    var senderIsAdmin: Bool = false
    var senderIsPremium: Bool = false
    // Telegram-style features
    var replySenderName: String? = nil
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onReply: () -> Void = {}
    var onPinRequest: () -> Void = {}
    var onForward: () -> Void = {}
    var onSelect: () -> Void = {}
    var onToggleSelection: () -> Void = {}
    var onQuoteTap: (String) -> Void = { _ in }
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    // Аудит 26.07.2026 P1: маркер «не отправлено» + повтор отправки
    var isFailed: Bool = false
    var onRetry: () -> Void = {}

    /// Horizontal swipe offset (Telegram swipe-to-reply).
    @State private var dragOffset: CGFloat = 0

    private let avatarSize: CGFloat = PlinkTelegramBubbleMetrics.avatarSize

    private var photoURL: URL? {
        APIClient.shared.baseURL.appendingPathComponent("messages/photo/\(message.id)")
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn {
                Spacer(minLength: 36)
            } else {
                avatarSlot
            }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
                if let forwarded = message.forwardedFromName {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.right.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Переслано от \(forwarded)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Cinema2026.accent.opacity(0.9))
                    .padding(.horizontal, 4)
                }

                if let quote = message.replyPreviewText {
                    Button {
                        if let quotedId = message.replyToID { onQuoteTap(quotedId) }
                    } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Cinema2026.accent)
                                .frame(width: 3, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(replySenderName ?? "Ответ")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Cinema2026.accent)
                                Text(quote.isEmpty ? "Сообщение" : quote)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Group {
                    if message.isVoiceNote {
                        VoiceNoteBubble(
                            message: message,
                            isOwn: isOwn,
                            maxWidth: maxBubbleWidth
                        )
                    } else if message.isPhotoMessage {
                        PlinkPhotoMessageBubble(
                            imageURL: photoURL,
                            localImage: ChatPhotoCache.shared.image(for: message.id),
                            caption: message.text,
                            isOwn: isOwn,
                            styleID: message.bubbleStyle,
                            isLastInGroup: cluster.isLastInGroup
                        )
                        .frame(maxWidth: min(maxBubbleWidth, PlinkTelegramBubbleMetrics.maxPhotoBubbleWidth), alignment: isOwn ? .trailing : .leading)
                    } else {
                        PlinkMessageBubble(
                            text: message.text,
                            isOwn: isOwn,
                            styleID: message.bubbleStyle,
                            fontSize: PlinkTelegramBubbleMetrics.fontSize,
                            isLastInGroup: cluster.isLastInGroup
                        )
                    }
                }
                .contextMenu {
                    Button {
                        onReact()
                    } label: {
                        Label("Реакция", systemImage: "face.smiling")
                    }
                    Button {
                        onReply()
                    } label: {
                        Label("Ответить", systemImage: "arrowshape.turn.up.left")
                    }
                    if !message.isVoiceNote {
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("Копировать", systemImage: "doc.on.doc")
                        }
                    }
                    Button {
                        onForward()
                    } label: {
                        Label("Переслать", systemImage: "arrowshape.turn.up.right")
                    }
                    Button {
                        onPinRequest()
                    } label: {
                        Label("Закрепить", systemImage: "pin")
                    }
                    if isOwn && !message.isVoiceNote {
                        Button {
                            onEdit()
                        } label: {
                            Label(LocalizationManager.shared.string(.dmEdit), systemImage: "pencil")
                        }
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label(LocalizationManager.shared.string(.dmDelete), systemImage: "trash")
                    }
                    Divider()
                    Button {
                        onSelect()
                    } label: {
                        Label("Выбрать", systemImage: "checkmark.circle")
                    }
                }
                // Removed onLongPressGesture — conflicts with .contextMenu causing flicker.
                // contextMenu already provides long-press behaviour.

                // Reaction chips under bubble (Telegram)
                if !message.reactions.isEmpty {
                    reactionChips
                }

                if cluster.isLastInGroup {
                    HStack(spacing: 3) {
                        if message.editedAt != nil {
                            Text(LocalizationManager.shared.string(.dmEdited))
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.8))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.black.opacity(0.42)))
                        }
                        Text(message.timeString)
                            .font(.system(size: 11, weight: .semibold))
                            // Time sits on wallpaper — use solid pill so it never vanishes
                            .foregroundStyle(Color.white.opacity(0.95))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.42)))
                        if isOwn && !isFailed {
                            // Telegram ticks: one gray = sent, two blue = read
                            TelegramReadTicks(isRead: message.isRead)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.black.opacity(0.42)))
                        }
                    }
                    .padding(.horizontal, 2)
                }

                // Аудит 26.07.2026 P1: неотправленное сообщение — красный маркер
                // с кнопкой «Повторить» (медиа не ретраим — исходных байтов нет).
                if isFailed {
                    let retryable = !message.isVoiceNote && !message.isPhotoMessage
                    Button {
                        if retryable { onRetry() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(retryable ? "Не отправлено · Повторить" : "Не отправлено")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.red.opacity(0.95))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.42)))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 2)
                }
            }
            .frame(maxWidth: maxBubbleWidth, alignment: isOwn ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)

            if isOwn {
                avatarSlot
            } else {
                Spacer(minLength: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
        .overlay(alignment: .leading) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? Cinema2026.accent : Color.white.opacity(0.45))
                    .padding(.leading, 2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        // M26 UX: двойной тап — быстрая реакция ❤️ (Telegram/iMessage 2026)
        .onTapGesture(count: 2) {
            if !isSelecting {
                HapticManager.impact(.medium)
                onToggleChip("❤️")
            }
        }
        .onTapGesture {
            if isSelecting {
                HapticManager.impact(.light)
                onToggleSelection()
            }
        }
        .offset(x: dragOffset)
        .overlay(alignment: isOwn ? .leading : .trailing) {
            if abs(dragOffset) > 30 {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(8)
                    .background(Circle().fill(Color.black.opacity(0.35)))
                    .transition(.opacity)
            }
        }
        .simultaneousGesture(replySwipeGesture)
    }

    /// Telegram swipe-to-reply — works in both directions (← and →).
    private var replySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard !isSelecting else { return }
                let t = value.translation.width
                guard abs(t) > abs(value.translation.height) else { return }
                dragOffset = max(-72, min(72, t * 0.55))
            }
            .onEnded { value in
                let shouldReply = !isSelecting
                    && abs(value.translation.width) > 56
                    && abs(value.translation.width) > abs(value.translation.height)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    dragOffset = 0
                }
                if shouldReply {
                    HapticManager.impact(.medium)
                    onReply()
                }
            }
    }

    private var reactionChips: some View {
        HStack(spacing: 4) {
            ForEach(message.reactions, id: \.emoji) { chip in
                Button {
                    HapticManager.impact(.light)
                    onToggleChip(chip.emoji)
                } label: {
                    HStack(spacing: 3) {
                        Text(chip.emoji)
                            .font(.system(size: 13))
                        if chip.count > 1 {
                            Text("\(chip.count)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(chip.includesMe
                                  ? Cinema2026.accent.opacity(0.35)
                                  : Color.white.opacity(0.10))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                chip.includesMe
                                ? Cinema2026.accent.opacity(0.55)
                                : Color.white.opacity(0.12),
                                lineWidth: 0.8
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var avatarSlot: some View {
        if cluster.showAvatar {
            PlinkStableAvatar(
                url: avatarURL,
                letter: letter,
                size: avatarSize,
                userId: message.senderID,
                isAdmin: senderIsAdmin,
                isPremium: senderIsPremium
            )
        } else {
            Color.clear.frame(width: avatarSize, height: avatarSize)
        }
    }
}

// MARK: - Photo preview sheet

struct ChatPhotoDraft: Identifiable {
    let id = UUID()
    let compressed: ChatCompressedImage
}

struct PhotoSendPreviewSheet: View {
    let draft: ChatPhotoDraft
    @Binding var caption: String
    let onCancel: () -> Void
    let onSend: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(uiImage: draft.compressed.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))

                TextField("Добавить подпись…", text: $caption, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 16))
                    .foregroundStyle(Cinema2026.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Cinema2026.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onChange(of: caption) { _, value in
                        if value.count > 240 { caption = String(value.prefix(240)) }
                    }

                Text("Сжато до \(max(1, draft.compressed.byteCount / 1024)) KB")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Cinema2026.secondary)

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Cinema2026.background.ignoresSafeArea())
            .navigationTitle("Отправить фото")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить", action: onSend)
                        .fontWeight(.bold)
                }
            }
        }
    }
}

// MARK: - Voice note bubble (play real audio)

private struct VoiceNoteBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    var maxWidth: CGFloat = PlinkTelegramBubbleMetrics.maxVoiceBubbleWidth
    @State private var player = VoiceNotePlayer.shared
    @State private var playError: String?

    private var durationLabel: String {
        if let d = message.voiceDurationSec {
            return PlinkVoiceWire.formatDuration(d)
        }
        return "0:00"
    }

    private var isThisPlaying: Bool {
        player.playingMessageId == message.id
    }

    private var canPlay: Bool {
        // Voice notes always try play — local cache or server stream
        message.isVoiceNote || message.hasMedia || message.mediaType == "voice"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                guard canPlay else { return }
                HapticManager.impact(.light)
                playError = nil
                player.toggle(messageId: message.id)
                // Surface player errors shortly after tap
                Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if player.playingMessageId == nil,
                       let err = player.errorMessage, !err.isEmpty {
                        playError = err
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(isOwn ? Color.black.opacity(0.22) : Cinema2026.accent.opacity(0.85))
                        .frame(width: 44, height: 44)
                    if player.isLoading && isThisPlaying {
                        ProgressView()
                            .tint(isOwn ? .white : .black)
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isOwn ? Color.white : Color.black.opacity(0.85))
                            .offset(x: isThisPlaying ? 0 : 1)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canPlay)

            VStack(alignment: .leading, spacing: 7) {
                // Static fake waveform + progress overlay (Telegram-like)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        VoiceWaveformStrip(seed: message.id, progress: isThisPlaying ? player.progress : 0)
                            .frame(height: 22)
                        // scrub progress line
                        Rectangle()
                            .fill(isOwn ? Color.white.opacity(0.55) : Cinema2026.accent.opacity(0.9))
                            .frame(width: 2, height: 22)
                            .offset(x: max(0, geo.size.width * (isThisPlaying ? player.progress : 0) - 1))
                    }
                }
                .frame(height: 22)

                HStack {
                    Text(durationLabel)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.8))
                    if let playError {
                        Text("· \(playError)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.red.opacity(0.85))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(
                minWidth: PlinkTelegramBubbleMetrics.minVoiceBubbleWidth,
                idealWidth: min(maxWidth, PlinkTelegramBubbleMetrics.maxVoiceBubbleWidth),
                maxWidth: min(maxWidth, PlinkTelegramBubbleMetrics.maxVoiceBubbleWidth),
                alignment: .leading
            )
        }
        .frame(maxWidth: min(maxWidth, PlinkTelegramBubbleMetrics.maxVoiceBubbleWidth), alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, PlinkTelegramBubbleMetrics.padV)
        .background(
            ZStack {
                Color(hex: "#1A1C20")
                if isOwn {
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.64, blue: 1.0),
                            Color(red: 0.11, green: 0.78, blue: 0.48)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color(hex: "#2E333A")
                }
            }
        )
        .clipShape(V5BubbleShape(isOutgoing: isOwn, isLastInGroup: true))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(isOwn ? 0.20 : 0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }
}

// MARK: - Voice UI helpers

/// Live mic level bars while recording (VK / TG style).
private struct VoiceLevelBars: View {
    var level: Float
    var active: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<8, id: \.self) { i in
                let phase = abs(sin(Double(i) * 0.9 + Double(level) * 8))
                let h = active
                    ? 4 + CGFloat(level) * 16 * CGFloat(0.35 + phase * 0.65)
                    : 4
                Capsule()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 3.5, height: max(4, h))
            }
        }
        .animation(.easeOut(duration: 0.06), value: level)
    }
}

/// Decorative waveform for a voice bubble (deterministic from message id).
private struct VoiceWaveformStrip: View {
    let seed: String
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            let count = 28
            let w = max(2, (geo.size.width - CGFloat(count - 1) * 2) / CGFloat(count))
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<count, id: \.self) { i in
                    let h = barHeight(index: i)
                    let filled = Double(i) / Double(count) <= progress
                    Capsule()
                        .fill(Color.white.opacity(filled ? 0.95 : 0.28))
                        .frame(width: w, height: h)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func barHeight(index: Int) -> CGFloat {
        // Stable pseudo-random heights from seed
        var hash: UInt64 = 5381
        for u in seed.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(u.value)
        }
        hash = hash &+ UInt64(index) &* 2654435761
        let n = Double((hash % 1000)) / 1000.0
        return 5 + CGFloat(n) * 16
    }
}

// MARK: - Telegram read ticks (✓ / ✓✓)

/// Exact Telegram semantics:
///  - not read → single gray check
///  - read by peer → two blue checks (slightly overlapping)
private struct TelegramReadTicks: View {
    let isRead: Bool

    private var tickColor: Color {
        isRead ? Color(red: 0.34, green: 0.78, blue: 1.0) : Color.white.opacity(0.45)
    }

    var body: some View {
        HStack(spacing: isRead ? -4.5 : 0) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            if isRead {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(tickColor)
        .accessibilityLabel(isRead ? "Прочитано" : "Отправлено")
    }
}

// MARK: - Day Divider (glass capsule)

private struct DMDayDivider: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.48))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }
}

// MARK: - Forward sheet (Telegram «Переслать»)

private struct DMForwardSheet: View {
    let friends: [Friend]
    let onPick: (Friend) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if friends.isEmpty {
                    Text(LocalizationManager.shared.string(.dmNoForwardFriends))
                        .foregroundStyle(.secondary)
                }
                ForEach(friends, id: \.id) { f in
                    Button {
                        onPick(f)
                    } label: {
                        HStack(spacing: 12) {
                            PlinkStableAvatar(
                                url: PlinkAvatarURL.stable(userId: f.id, stored: f.avatarURL),
                                letter: PlinkAvatarURL.letter(from: f.displayTitle),
                                size: 40,
                                userId: f.id,
                                isAdmin: false,
                                isPremium: false
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.displayTitle)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(f.isOnline ? "в сети" : "не в сети")
                                    .font(.system(size: 12))
                                    .foregroundStyle(f.isOnline ? .green : .secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Переслать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { onCancel() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
