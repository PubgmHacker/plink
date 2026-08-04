// Plink/V4/V4FriendsChatsList.swift
//
// 03.08.2026. V4FriendsView.swift разросся до 2007 строк: один тип держал
// три сегмента, строки чатов, строки людей, недавние комнаты и два шита.
// Разрезано на extension'ы — блоки опираются на приватные члены
// V4FriendsViewLive, поэтому вынести их в отдельные типы нельзя без
// протаскивания десятка зависимостей через инициализатор. Поведение не
// менялось: это перенос кода, а не переписывание.

import SwiftUI
import PhotosUI
import UIKit
import Foundation

extension V4FriendsViewLive {
    // MARK: - Чаты / Общение

    // MARK: - M21/M22 Unified Inbox helpers

    // Аудит 26.07.2026: `id` обязан быть nonisolated — Identifiable требует
    // синхронного доступа вне актора. Изоляцию несут только те геттеры,
    // что дёргают DMChatService и FriendPinStore (оба @MainActor).
    private enum InboxItem: Identifiable {
        case dm(Friend)
        case group(GroupChatDTO)
        var id: String {
            switch self { case .dm(let f): return "dm-\(f.id)"; case .group(let g): return "grp-\(g.id)" }
        }
        @MainActor
        var lastActivity: Date {
            switch self {
            case .dm(let f): return DMChatService.shared.lastActivityAt(for: f.id) ?? .distantPast
            case .group(let g): return g.lastMessageDate ?? .distantPast
            }
        }
        @MainActor
        var isPinned: Bool {
            switch self {
            case .dm(let f): return FriendPinStore.shared.isPinned(f.id)
            case .group: return false
            }
        }
    }

    private var unifiedInbox: [InboxItem] {
        let _ = dmService.inboxEpoch
        let _ = pinStore.orderedPinnedIds
        let dms = orderedFriends.map { InboxItem.dm($0) }
        let groups = groupService.groups
            .sorted { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }
            .map { InboxItem.group($0) }
        let pinned  = dms.filter { $0.isPinned }
        let unpinned = (dms.filter { !$0.isPinned } + groups)
            .sorted { $0.lastActivity > $1.lastActivity }
        return pinned + unpinned
    }

    var chatsBlock: some View {
        let totalCount = (store?.friends.count ?? 0) + groupService.groups.count
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Чаты",
                icon: "bubble.left.and.bubble.right.fill",
                count: totalCount > 0 ? totalCount : nil,
                actionTitle: LocalizationManager.shared.string(.frAdd),
                action: { showAddFriend = true }
            )

            // M34: быстрое создание групповой беседы
            Button {
                HapticManager.impact(.light)
                showCreateGroupSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                    Text("Создать беседу")
                    Spacer()
                    Image(systemName: "plus")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.accentColor)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(theme.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.accentColor.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Создать групповую беседу")

            if unifiedInbox.isEmpty {
                sectionCard {
                    emptyInside(
                        icon: "bubble.left.and.bubble.right",
                        title: "Пока нет чатов",
                        subtitle: "Добавь друга или создай беседу — всё появится здесь",
                        cta: "Найти друга"
                    ) { showAddFriend = true }
                }
            } else {
                sectionCard {
                    ForEach(unifiedInbox) { item in
                        switch item {
                        case .dm(let friend):   friendChatRow(friend)
                        case .group(let group): groupChatRow(group)
                        }
                    }
                }
            }
        }
        // M21: открыть беседу из unified inbox
        .sheet(item: $openGroup) { group in
            NavigationStack {
                GroupsListView(friends: store?.friends ?? [], meId: dmService.currentUserId)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Закрыть") { openGroup = nil }
                        }
                    }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// M21/M22: Telegram-style group chat row (unified inbox)
    @ViewBuilder
    private func groupChatRow(_ group: GroupChatDTO) -> some View {
        let unread  = group.unreadCount ?? 0
        let muteKey = "grp-\(group.id)"
        let muted   = muteStore.isMuted(muteKey)
        Button {
            HapticManager.selection()
            openGroup = group
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [theme.accentColor.opacity(0.85), theme.accentColor.opacity(0.42)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 48, height: 48)
                        V4GlyphIcon(glyph: .people3, size: 15, filled: true, weight: .regular)
                            .foregroundStyle(theme.buttonTextColor)
                    }
                    // 👥 group marker
                    Circle().fill(V4.surface)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Image(systemName: muted ? "bell.slash.fill" : "person.3.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(muted ? .orange : theme.accentColor)
                        }
                        .offset(x: 2, y: 2)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(group.title)
                            .font(.system(size: 15.5, weight: unread > 0 ? .heavy : .semibold))
                            .foregroundStyle(V4.ink)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        if let lastAt = group.lastMessageDate {
                            Text(Self.chatListTime(lastAt))
                                .font(.system(size: 12, weight: unread > 0 ? .semibold : .regular))
                                .foregroundStyle(unread > 0 ? theme.accentColor : V4.muted)
                        }
                    }
                    HStack(spacing: 6) {
                        if let last = group.lastMessageText, !last.isEmpty {
                            Text(last)
                                .font(.system(size: 13, weight: unread > 0 ? .medium : .regular))
                                .foregroundStyle(unread > 0 ? V4.ink.opacity(0.85) : V4.muted)
                                .lineLimit(1)
                        } else {
                            Text("\(group.memberCount) участника")
                                .font(.system(size: 13))
                                .foregroundStyle(V4.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if muted {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                        if unread > 0 {
                            Text(unread > 99 ? "99+" : "\(unread)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(muted ? Color.gray : theme.accentColor, in: Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Состояние «без звука» и счётчик непрочитанных передавались только
        // цветом иконки и цифрой — для VoiceOver это была просто «кнопка» с
        // названием беседы. Собираем строку целиком и озвучиваем состояние.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Беседа \(group.title)")
        .accessibilityValue(
            [
                unread > 0 ? "непрочитанных: \(unread)" : nil,
                muted ? "уведомления выключены" : nil
            ].compactMap { $0 }.joined(separator: ", ")
        )
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(unread > 0 && !muted ? theme.accentColor.opacity(0.05) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V4.line.opacity(0.45)).frame(height: 0.5).padding(.leading, 74)
        }
        // Аудит 26.07.2026 P1: swipeActions удалены — работают только в List,
        // строки лежат в VStack/ScrollView (свайпы не срабатывали). Действия — в contextMenu.
        // M22: контекстное меню (долгий тап)
        .contextMenu {
            Button { openGroup = group } label: {
                Label("Открыть беседу", systemImage: "person.3.fill")
            }
            Button {
                Task { await groupService.markRead(groupId: group.id) }
                toast = "Отмечено как прочитанное"
            } label: { Label("Отметить как прочитанное", systemImage: "checkmark.message.fill") }
            Button {
                muteStore.toggle(muteKey)
                toast = muteStore.isMuted(muteKey) ? "Беседа заглушена" : "Уведомления включены"
            } label: {
                Label(muted ? "Включить уведомления" : "Выключить уведомления",
                      systemImage: muted ? "bell.fill" : "bell.slash.fill")
            }
            Divider()
            Button(role: .destructive) {
                Task { await groupService.leave(groupId: group.id) }
                toast = "Беседа удалена"
            } label: { Label("Удалить беседу", systemImage: "trash") }
        }
    }

}
