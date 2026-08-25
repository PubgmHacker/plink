// Plink/Views/Chat/GroupChatsView.swift — M16/M17
// Групповые беседы, как в Telegram: список бесед с unread-бейджами, создание,
// чат с баблами Plink, фото-картинками, реакциями, удалением и баннером ИИ-модератора.

import SwiftUI
import PhotosUI
import UIKit

extension GroupChatDTO: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Список бесед

struct GroupsListView: View {
    let friends: [Friend]
    let meId: String?
    @ObservedObject private var service = GroupChatService.shared
    @State private var showCreate = false

    private let theme = V4Theme.saved

    var body: some View {
        List {
            // skeleton-загрузка вместо spinner
            if service.isLoading && service.groups.isEmpty {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonGroupRow()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else if service.groups.isEmpty && !service.isLoading {
                VStack(spacing: 10) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(V4.muted)
                    Text(L.string(.groupsEmpty))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(V4.ink)
                    Text(L.string(.groupsEmptySubtitle))
                        .font(.system(size: 13))
                        .foregroundStyle(V4.muted)
                        .multilineTextAlignment(.center)
                    Button {
                        showCreate = true
                    } label: {
                        Text(L.string(.groupsCreate))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.buttonTextColor)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(theme.accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .listRowBackground(Color.clear)
            }

            ForEach(service.groups) { group in
                NavigationLink(value: group) {
                    groupRow(group)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await service.leave(groupId: group.id) }
                    } label: {
                        Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Беседы")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .navigationDestination(for: GroupChatDTO.self) { group in
            GroupChatView(group: group, meId: meId)
        }
        .sheet(isPresented: $showCreate) {
            CreateGroupSheet(friends: friends)
                .preferredColorScheme(.dark)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task { await service.loadGroups() }
        .refreshable { await service.loadGroups() }
    }

    @ViewBuilder
    private func groupRow(_ group: GroupChatDTO) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    // Акцентная палитра V4 вместо purple/blue
                    .fill(LinearGradient(colors: [V4.accent.opacity(0.9), V4.accent.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(V4.accentInk)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(group.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text("\(group.memberCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                if let last = group.lastMessageText, !last.isEmpty {
                    Text("\(group.lastMessageSender ?? ""): \(last)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(L.string(.groupsNoMessages))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            // unread-бейдж
            if let unread = group.unreadCount, unread > 0 {
                Text(unread > 99 ? "99+" : "\(unread)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(V4.accentInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(V4.accent))
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Создание беседы

struct CreateGroupSheet: View {
    let friends: [Friend]
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = GroupChatService.shared
    @State private var title = ""
    @State private var selected: Set<String> = []
    @State private var creating = false

    private let theme = V4Theme.saved

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например: Киновечер \u{1F3AC}", text: $title)
                        .foregroundStyle(V4.ink)
                        .listRowBackground(V4.surface.opacity(0.55))
                }
                Section("Участники (\(selected.count))") {
                    if friends.isEmpty {
                        Text(L.string(.groupsAddFriendsHint))
                            .font(.footnote)
                            .foregroundStyle(V4.muted)
                            .listRowBackground(V4.surface.opacity(0.55))
                    }
                    ForEach(friends) { friend in
                        Button {
                            if selected.contains(friend.id) {
                                selected.remove(friend.id)
                            } else {
                                selected.insert(friend.id)
                            }
                            HapticManager.selection()
                        } label: {
                            HStack {
                                Text(friend.displayName ?? "@\(friend.username)")
                                    .foregroundStyle(V4.ink)
                                Spacer()
                                Image(systemName: selected.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(friend.id) ? theme.accentColor : V4.muted)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(V4.surface.opacity(0.55))
                    }
                }
                if let err = service.errorMessage {
                    Section {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(V4.danger)
                            .listRowBackground(V4.surface.opacity(0.55))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background {
                ZStack {
                    V4.canvas
                    RadialGradient(
                        colors: [theme.accentColor.opacity(0.10), .clear],
                        center: UnitPoint(x: 0.5, y: 0),
                        startRadius: 0,
                        endRadius: 420
                    )
                }
                .ignoresSafeArea()
            }
            // Главное действие — большая кнопка снизу; тулбар оставлен закрытию.
            .safeAreaInset(edge: .bottom) {
                Button {
                    creating = true
                    service.errorMessage = nil
                    Task {
                        let ok = await service.createGroup(
                            title: trimmedTitle,
                            memberIds: Array(selected)
                        )
                        creating = false
                        if ok { dismiss() }
                    }
                } label: {
                    Group {
                        if creating {
                            ProgressView().tint(theme.buttonTextColor)
                        } else {
                            Text("Создать беседу")
                                .font(.system(size: 15.5, weight: .bold))
                                .foregroundStyle(theme.buttonTextColor)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(trimmedTitle.isEmpty ? theme.accentColor.opacity(0.4) : theme.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(trimmedTitle.isEmpty || creating)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .navigationTitle("Новая беседа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                V4SheetCloseToolbarItem { dismiss() }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Фото с авторизованной загрузкой (Bearer, в отличие от AsyncImage)

struct GroupPhotoView: View {
    let groupId: String
    let messageId: String
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 220, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if failed {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 220, height: 140)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                            Text(L.string(.groupsPhotoUnavailable))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    )
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 220, height: 160)
                    .overlay(ProgressView().tint(.white))
            }
        }
        .task {
            guard image == nil else { return }
            var req = URLRequest(url: APIClient.shared.baseURL.appendingPathComponent("groups/\(groupId)/messages/\(messageId)/photo"))
            if let token = APIClient.shared.authToken {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let ui = UIImage(data: data) {
                image = ui
            } else {
                failed = true
            }
        }
    }
}

// MARK: - Экран беседы

struct GroupChatView: View {
    let group: GroupChatDTO
    let meId: String?
    @ObservedObject private var service = GroupChatService.shared
    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var sending = false

    private let theme = V4Theme.saved

    /// Быстрые реакции в контекстном меню.
    private let quickReactions = ["\u{2764}\u{FE0F}", "\u{1F602}", "\u{1F525}", "\u{1F44D}", "\u{1F62E}"]

    private var messages: [GroupMessageDTO] {
        service.messagesByGroup[group.id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(messages) { msg in
                            messageRow(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    // Новое видимое сообщение = прочитано
                    Task { await service.markRead(groupId: group.id) }
                }
            }

            // Баннер ИИ-модератора (мут за маты / отклонённое фото)
            if let modMsg = service.errorMessage,
               modMsg.contains("Мут") || modMsg.contains("замучены") || modMsg.contains("отклонено") {
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
                        service.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(V4.danger.opacity(0.18))
            }

            inputBar
        }
        .background {
            ZStack {
                V4.canvas
                RadialGradient(
                    colors: [theme.accentColor.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.5, y: 0),
                    startRadius: 0,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await service.loadMessages(groupId: group.id)
            await service.markRead(groupId: group.id)
            // scenePhase guard — не поллим когда app в фоне
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                let appState = await MainActor.run { UIApplication.shared.applicationState }
                guard appState == .active else { continue }
                await service.refreshMessages(groupId: group.id)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await sendPhoto(item) }
        }
    }

    @ViewBuilder
    private func messageRow(_ msg: GroupMessageDTO) -> some View {
        let own = (meId != nil && msg.senderID == meId)
        let canDelete = own || group.myRole == "owner" || group.myRole == "admin"
        VStack(alignment: own ? .trailing : .leading, spacing: 2) {
            if !own {
                Text(msg.senderName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
            HStack {
                if own { Spacer(minLength: 40) }
                Group {
                    if msg.mediaType == "photo" {
                        // Фото рендерится картинкой (авторизованная загрузка)
                        VStack(alignment: own ? .trailing : .leading, spacing: 4) {
                            GroupPhotoView(groupId: group.id, messageId: msg.id)
                            if !msg.content.isEmpty {
                                Text(msg.content)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.horizontal, 4)
                            }
                        }
                    } else {
                        PlinkMessageBubble(
                            text: msg.content,
                            isOwn: own,
                            styleID: nil,
                            fontSize: 16,
                            isLastInGroup: true
                        )
                    }
                }
                .contextMenu {
                    // Быстрые реакции + удаление
                    ForEach(quickReactions, id: \.self) { emoji in
                        Button {
                            Task { await service.react(groupId: group.id, messageId: msg.id, emoji: emoji) }
                        } label: {
                            Text(emoji)
                        }
                    }
                    if canDelete {
                        Button(role: .destructive) {
                            Task { await service.deleteMessage(groupId: group.id, messageId: msg.id) }
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
                if !own { Spacer(minLength: 40) }
            }
            // Лента реакций под сообщением
            if let reactions = msg.reactions, !reactions.isEmpty {
                HStack(spacing: 4) {
                    ForEach(reactions.keys.sorted(), id: \.self) { emoji in
                        let users = reactions[emoji] ?? []
                        let mine = meId != nil && users.contains(meId!)
                        Button {
                            Task { await service.react(groupId: group.id, messageId: msg.id, emoji: emoji) }
                        } label: {
                            Text("\(emoji) \(users.count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(mine ? V4.accent.opacity(0.35) : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: own ? .trailing : .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: own ? .trailing : .leading)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            TextField("Сообщение…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            Button {
                Task { await sendText() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending ? V4.muted : theme.accentColor)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func sendText() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        service.errorMessage = nil
        let ok = await service.send(groupId: group.id, content: text)
        sending = false
        if ok { draft = "" }
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard !sending else { return }
        sending = true
        service.errorMessage = nil
        defer { sending = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        // Ужимаем под лимит бэкенда (2.25MB base64)
        var quality: CGFloat = 0.65
        var jpeg = image.jpegData(compressionQuality: quality)
        while let d = jpeg, d.count > 1_500_000, quality > 0.25 {
            quality -= 0.15
            jpeg = image.jpegData(compressionQuality: quality)
        }
        guard let finalData = jpeg else { return }
        let dataUrl = "data:image/jpeg;base64,\(finalData.base64EncodedString())"
        let caption = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = await service.send(groupId: group.id, content: caption, imageData: dataUrl)
        if ok { draft = "" }
    }
}
