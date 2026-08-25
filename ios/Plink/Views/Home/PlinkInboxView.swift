// Plink/Views/Home/PlinkInboxView.swift — M17
// Центр уведомлений (колокольчик на главной): непрочитанные личные сообщения
// и беседы с бейджами. Тап открывает конкретный чат.

import SwiftUI

struct PlinkInboxView: View {
    @ObservedObject private var dm = DMChatService.shared
    @ObservedObject private var groups = GroupChatService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let unreadFriendIds = dm.unreadByFriend
                    .filter { $0.value > 0 }
                    .map(\.key)
                    .sorted()
                let unreadGroups = groups.groups.filter { ($0.unreadCount ?? 0) > 0 }

                if unreadFriendIds.isEmpty && unreadGroups.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.green.opacity(0.8))
                        Text(L.string(.inboxAllRead))
                            .font(.system(size: 16, weight: .semibold))
                        Text(L.string(.inboxEmptySubtitle))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                }

                if !unreadFriendIds.isEmpty {
                    Section("Личные сообщения") {
                        ForEach(unreadFriendIds, id: \.self) { friendId in
                            Button {
                                openChat(.dm(friendId: friendId))
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "bubble.left.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(V4.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name(forFriendId: friendId))
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(V4.ink)
                                        Text("Открыть переписку")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    badge(dm.unreadCount(for: friendId))
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !unreadGroups.isEmpty {
                    Section("Беседы") {
                        ForEach(unreadGroups) { group in
                            Button {
                                openChat(.group(groupId: group.id))
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(LinearGradient(colors: [V4.accent.opacity(0.9), V4.accent.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "person.3.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(V4.accentInk)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(V4.ink)
                                            .lineLimit(1)
                                        if let last = group.lastMessageText {
                                            Text("\(group.lastMessageSender ?? ""): \(last)")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    badge(group.unreadCount ?? 0)
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Уведомления")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                V4SheetCloseToolbarItem { dismiss() }
            }
            .task {
                await groups.loadGroups()
                await dm.refreshUnread()
            }
            .refreshable {
                await groups.loadGroups()
                await dm.refreshUnread()
            }
        }
    }

    private func name(forFriendId id: String) -> String {
        if let friend = FriendManager.shared.friends.first(where: { $0.id == id }) {
            return friend.displayTitle
        }
        if let conversation = dm.lastMessages.first(where: { $0.participant.id == id }) {
            return conversation.displayName
        }
        return "Чат"
    }

    private func openChat(_ target: PlinkChatTarget) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            DeepLinkRouter.shared.openChat(target)
        }
    }

    @ViewBuilder
    private func badge(_ count: Int) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(V4.accentInk)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(V4.accent))
    }
}
