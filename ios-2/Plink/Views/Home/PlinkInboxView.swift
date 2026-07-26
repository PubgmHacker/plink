// Plink/Views/Home/PlinkInboxView.swift — M17
// Центр уведомлений (колокольчик на главной): непрочитанные личные сообщения
// и беседы с бейджами. Без remote push — всё через существующие сервисы (in-app).

import SwiftUI

struct PlinkInboxView: View {
    @ObservedObject private var dm = DMChatService.shared
    @ObservedObject private var groups = GroupChatService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let dmUnread = dm.totalUnread
                let unreadGroups = groups.groups.filter { ($0.unreadCount ?? 0) > 0 }

                if dmUnread == 0 && unreadGroups.isEmpty {
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

                if dmUnread > 0 {
                    Section("Личные сообщения") {
                        HStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(V4.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L.string(.inboxUnreadMessages))
                                    .font(.system(size: 15, weight: .semibold))
                                Text(L.string(.inboxOpenFriendsHint))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            badge(dmUnread)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if !unreadGroups.isEmpty {
                    Section("Беседы") {
                        ForEach(unreadGroups) { group in
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        // M18: акцентная палитра V4 вместо purple/blue
                                        .fill(LinearGradient(colors: [V4.accent.opacity(0.9), V4.accent.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "person.3.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(V4.accentInk)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.title)
                                        .font(.system(size: 15, weight: .semibold))
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
                    }
                }
            }
            .navigationTitle("Уведомления")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
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

    @ViewBuilder
    private func badge(_ count: Int) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(V4.accent))
    }
}
