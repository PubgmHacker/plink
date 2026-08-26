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

/// Обёртка над id беседы: `.sheet(item:)` требует Identifiable, а строка им
/// не является. Нужна только дизайн-рельсе настроек беседы.
struct PlinkDesignGroupID: Identifiable, Equatable {
    let id: String
}

extension V4FriendsViewLive {
    // MARK: - Чаты / Общение

    // MARK: - M21/M22 Unified Inbox helpers

    // `id` обязан быть nonisolated — Identifiable требует
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
        // Инбокс — только реальные разговоры. Раньше сюда попадали ВСЕ
        // друзья (и список чатов превращался в дубль списка друзей со
        // строками «был(а) N минут назад»); новый разговор начинается
        // через ✎ в шапке, а не через мёртвую строку в инбоксе.
        let dms = orderedFriends
            .filter { friend in
                dmService.lastActivityAt(for: friend.id) != nil
                    || dmService.unreadCount(for: friend.id) > 0
                    || (dmService.lastPreviewByFriend[friend.id]?.isEmpty == false)
                    || pinStore.isPinned(friend.id)
            }
            .map { InboxItem.dm($0) }
        let groups = groupService.groups
            .sorted { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }
            .map { InboxItem.group($0) }
        let pinned  = dms.filter { $0.isPinned }
        let unpinned = (dms.filter { !$0.isPinned } + groups)
            .sorted { $0.lastActivity > $1.lastActivity }
        return pinned + unpinned
    }

    /// Пока сторы молчат, пустое состояние врёт: «Пока нет чатов» успевало
    /// мигнуть над беседой, которая просто ещё не приехала. Инбокс кормят два
    /// источника — люди и беседы, поэтому ждём ответа обоих.
    private var inboxIsLoading: Bool {
        switch store?.state {
        case .none, .idle, .loading: return true
        default: return groupService.isLoading || !groupService.didLoadOnce
        }
    }

    /// Геометрия скелета повторяет строку чата (аватар 48, имя, превью,
    /// время справа), чтобы приезд данных не дёргал экран. Ширины разной
    /// длины — четыре одинаковые полосы читаются как таблица, а не как имена.
    var chatsLoadingSkeleton: some View {
        let widths: [(CGFloat, CGFloat)] = [(132, 176), (104, 138), (156, 192), (118, 160)]
        return VStack(spacing: 0) {
            ForEach(Array(widths.enumerated()), id: \.offset) { idx, w in
                HStack(spacing: 12) {
                    SkeletonCircle(size: 48)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonRect(width: w.0, height: 13, cornerRadius: 6)
                        SkeletonRect(width: w.1, height: 10, cornerRadius: 5)
                    }
                    Spacer(minLength: 0)
                    SkeletonRect(width: 34, height: 10, cornerRadius: 5)
                }
                .padding(.vertical, 10)
                if idx < widths.count - 1 {
                    Rectangle().fill(V4.line.opacity(0.5)).frame(height: 0.5)
                        .padding(.leading, 60)
                }
            }
        }
    }

    var chatsBlock: some View {
        let inbox = unifiedInbox
        return VStack(alignment: .leading, spacing: 12) {
            // Без текстового «Добавить» в заголовке: входы — ✎ и «+» в шапке
            // хаба, дубль здесь путал.
            sectionHeader(
                title: "Чаты",
                icon: "bubble.left.and.bubble.right.fill",
                count: inbox.isEmpty ? nil : inbox.count,
                actionTitle: nil,
                action: nil
            )

            sectionCard {
                if inbox.isEmpty && inboxIsLoading {
                    chatsLoadingSkeleton
                } else if inbox.isEmpty {
                    if (store?.friends.isEmpty ?? true) {
                        emptyInside(
                            icon: "bubble.left.and.bubble.right.fill",
                            title: "Пока нет чатов",
                            subtitle: "Добавь друга — переписки появятся здесь",
                            // Лупа, как у той же кнопки на сегменте «Друзья»:
                            // одно действие — одна иконка.
                            ctaIcon: "magnifyingglass",
                            cta: "Найти друга",
                            // Чаты — мир людей: сцена-орбита, как у друзей.
                            style: .orbit
                        ) { showAddFriend = true }
                    } else {
                        // Друзья есть, переписок нет — зовём написать первым.
                        emptyInside(
                            icon: "square.and.pencil",
                            title: "Пока нет переписок",
                            subtitle: "Друзья уже здесь — напиши первым, с этого всё и начинается",
                            ctaIcon: "square.and.pencil",
                            cta: "Написать",
                            style: .orbit
                        ) { showCompose = true }
                    }
                } else {
                    ForEach(inbox) { item in
                        switch item {
                        case .dm(let friend):   friendChatRow(friend)
                        case .group(let group): groupChatRow(group)
                        }
                    }
                }
            }
        }
        // Открыть беседу из unified inbox
        .sheet(item: $openGroup) { group in
            NavigationStack {
                GroupChatView(group: group, meId: dmService.currentUserId)
                    .toolbar {
                        V4SheetCloseToolbarItem { openGroup = nil }
                    }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // Настройки беседы для QA без тапов: -plink.designgroupinfo
        .sheet(item: Binding(
            get: { designGroupInfo.map { PlinkDesignGroupID(id: $0) } },
            set: { designGroupInfo = $0?.id }
        )) { target in
            GroupInfoView(groupId: target.id, titleHint: "Беседа")
                .preferredColorScheme(.dark)
        }
        .task(id: groupService.groups.count) {
            guard ProcessInfo.processInfo.arguments.contains("-plink.designgroupinfo"),
                  designGroupInfo == nil,
                  let first = groupService.groups.first else { return }
            designGroupInfo = first.id
        }
    }

    // «Создать беседу»-строки в инбоксе больше нет: создание переехало в
    // компоуз (✎ в шапке → «Новая беседа») — список только про разговоры.

    /// Telegram-style group chat row (unified inbox)
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
                    // Лицо беседы: фото группы либо буква на палитре её id.
                    // Акцент темы тут больше не участвует — беседы должны
                    // отличаться друг от друга, а не повторять фон.
                    PlinkGroupAvatar(
                        groupId: group.id,
                        title: group.title,
                        avatarVersion: group.avatarVersion,
                        size: 48
                    )
                    // 👥 group marker
                    Circle().fill(V4.surface)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Image(systemName: muted ? "bell.slash.fill" : "person.3.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(muted ? V4.amber : V4.muted)
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
                            Text(GroupCopy.members(group.memberCount))
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
        // swipeActions удалены — работают только в List,
        // строки лежат в VStack/ScrollView (свайпы не срабатывали). Действия — в contextMenu.
        // Контекстное меню (долгий тап)
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
