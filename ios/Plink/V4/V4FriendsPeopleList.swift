// Plink/V4/V4FriendsPeopleList.swift
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
    // MARK: - Друзья (people only — no chat previews)

    @ViewBuilder
    /// Карточка «друг смотрит» с кнопкой присоединения.
    private func friendWatchingCard(_ friend: Friend, _ room: Room) -> some View {
        Button {
            HapticManager.impact(.medium)
            NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
        } label: {
            HStack(spacing: 12) {
                V4Avatar(letter: String(friend.displayTitle.prefix(1)).uppercased(), theme: theme, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(friend.displayTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(V4.ink)
                        .lineLimit(1)
                    Text("смотрит «\(room.name)»")
                        .font(.system(size: 12))
                        .foregroundStyle(V4.muted)
                        .lineLimit(1)
                }
                Spacer()
                Text(LocalizationManager.shared.string(.frJoin))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(Capsule().stroke(theme.accentColor.opacity(0.6), lineWidth: 1))
            }
            .padding(12)
            .background(V4.cardBG.opacity(0.55))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    var friendsPeopleBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            // «Друг сейчас смотрит — присоединиться»
            if !friendsWatchingNow.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(
                        title: LocalizationManager.shared.string(.frWatchingNow),
                        icon: "play.tv.fill",
                        count: friendsWatchingNow.count,
                        actionTitle: nil,
                        action: nil
                    )
                    VStack(spacing: 8) {
                        ForEach(friendsWatchingNow, id: \.room.id) { pair in
                            friendWatchingCard(pair.friend, pair.room)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }

            // Online carousel
            if !onlineFriends.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(
                        title: LocalizationManager.shared.string(.frOnline),
                        icon: "circle.fill",
                        count: onlineFriends.count,
                        actionTitle: nil,
                        action: nil
                    )
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(onlineFriends) { friend in
                                onlineFriendChip(friend)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 4)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                // Без текстового «Добавить»: вход один — «+» в шапке хаба,
                // дубль в заголовке секции путал и выглядел старомодно.
                sectionHeader(
                    title: LocalizationManager.shared.string(.frAllFriends),
                    icon: "person.2.fill",
                    count: store?.friends.count,
                    actionTitle: nil,
                    action: nil
                )

                if let s = store {
                    switch s.state {
                    case .loading:
                        sectionCard {
                            ProgressView().tint(theme.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 36)
                                .accessibilityLabel("Загрузка друзей")
                        }
                    case .failed:
                        // Сырой текст ошибки (NSURLErrorDomain и т.п.) наружу
                        // не выходит — офлайн-состояние говорит человеческим
                        // языком и даёт одно действие.
                        sectionCard {
                            emptyInside(
                                icon: "wifi.exclamationmark",
                                title: "Друзья не загрузились",
                                subtitle: "Похоже, нет соединения. Проверь интернет — и попробуй ещё раз.",
                                ctaIcon: "arrow.clockwise",
                                cta: "Повторить",
                                style: .plain
                            ) { Task { await store?.load() } }
                        }
                    case .idle:
                        Color.clear.frame(height: 1)
                    case .loaded, .empty:
                        if s.friends.isEmpty {
                            // Формула из референсов инвайт-экранов: медальон →
                            // заголовок → выгода → «Найти друга» + второй канал
                            // «Пригласить по ссылке» тем же парным рядом кнопок,
                            // что и на лице профиля.
                            sectionCard {
                                V4EmptyState(
                                    icon: "person.2.fill",
                                    title: LocalizationManager.shared.string(.frEmptyTitle),
                                    subtitle: LocalizationManager.shared.string(.frEmptySub),
                                    accent: theme.accentColor,
                                    accentInk: theme.buttonTextColor,
                                    // Мир людей — своя сцена-орбита, луч
                                    // проектора остаётся кино-экранам.
                                    style: .orbit,
                                    primary: .init(
                                        title: LocalizationManager.shared.string(.frFind),
                                        icon: "magnifyingglass",
                                        a11yID: "friends.emptyFind"
                                    ) { showAddFriend = true }
                                ) {
                                    // Инвайт-ссылка — по нику (так же, как
                                    // «Поделиться» на профиле); id в /u/ не вёл
                                    // на публичную страницу.
                                    if let me = AuthService.shared.currentUserValue,
                                       let inviteURL = PlinkURLs.profileLink(
                                        me.username.isEmpty ? me.id : me.username
                                       ) {
                                        ShareLink(item: inviteURL) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "square.and.arrow.up")
                                                    .font(.system(size: 13, weight: .bold))
                                                Text(LocalizationManager.shared.string(.frInviteLink))
                                                    .font(.system(size: 14, weight: .semibold))
                                            }
                                            .padding(.horizontal, 18)
                                        }
                                        // Без tint: на нативном стекле tint
                                        // красит кнопку почти в заливку, и
                                        // вторичный канал спорил с primary.
                                        // Геометрия — один в один с primary
                                        // (высота 48, радиус 16): разнокали-
                                        // берные кнопки читались криво.
                                        // Полоса до 300 pt — та же, что у
                                        // primary в V4EmptyState: по-контентная
                                        // ширина делала вторичную кнопку шире
                                        // главной, иерархия переворачивалась.
                                        .buttonStyle(PlinkGlassButtonStyle(
                                            tint: nil,
                                            height: 48, cornerRadius: 16, fillsWidth: true
                                        ))
                                        .frame(maxWidth: 300)
                                        .padding(.top, 10)
                                    }
                                }
                                .padding(.vertical, 30)
                                .padding(.horizontal, 12)
                            }
                        } else {
                            // 2-column grid of friend cards
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ],
                                spacing: 12
                            ) {
                                ForEach(peopleFriends) { friend in
                                    friendPersonCard(friend)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                } else {
                    sectionCard {
                        ProgressView().tint(theme.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                    }
                }
            }
        }
    }

    private func onlineFriendChip(_ friend: Friend) -> some View {
        Button {
            HapticManager.selection()
            profileFriend = friend
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    friendAvatar(friend, size: 64)
                    if !friend.deleted {
                        Circle()
                            .fill(Color(red: 0.3, green: 0.9, blue: 0.55))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(V4.surface.opacity(0.95), lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                }
                Text(friend.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(V4.ink)
                    .lineLimit(1)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !friend.deleted {
                Button { dmFriend = friend } label: {
                    Label("Написать", systemImage: "message.fill")
                }
                Button {
                    watchWithFriend = friend
                    showCreateRoom = true
                } label: {
                    Label("Смотреть вместе", systemImage: "film.fill")
                }
            }
        }
    }

    @ViewBuilder
    func friendAvatar(_ friend: Friend, size: CGFloat) -> some View {
        if friend.deleted {
            PlinkDeletedAvatar(size: size)
        } else {
            PlinkStableAvatar(
                url: PlinkAvatarURL.stable(userId: friend.id, stored: friend.avatarURL),
                letter: friend.initials,
                size: size,
                userId: friend.id
            )
        }
    }

    private func friendPersonCard(_ friend: Friend) -> some View {
        VStack(spacing: 10) {
            Button {
                HapticManager.selection()
                profileFriend = friend
            } label: {
                VStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        friendAvatar(friend, size: 56)
                        if friend.isOnline && !friend.deleted {
                            Circle()
                                .fill(Color(red: 0.3, green: 0.9, blue: 0.55))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(V4.surface.opacity(0.95), lineWidth: 2))
                                .offset(x: 1, y: 1)
                        }
                    }
                    Text(friend.displayTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(V4.ink)
                        .lineLimit(1)
                    Text(friend.presenceText)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            friend.isOnline && !friend.deleted
                            ? Color(red: 0.3, green: 0.9, blue: 0.55)
                            : V4.muted
                        )
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if friend.deleted {
                Text(LocalizationManager.shared.string(.frCantMessage))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(V4.muted)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 34)
                    .background(V4.raised.opacity(0.4), in: Capsule())
            } else {
                HStack(spacing: 8) {
                    Button {
                        HapticManager.selection()
                        dmFriend = friend
                    } label: {
                        V4GlyphIcon(glyph: .chat, size: 13, filled: true, weight: .regular)
                            .foregroundStyle(V4.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(V4.raised.opacity(0.75), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Чат с \(friend.displayTitle)")

                    Button {
                        HapticManager.impact(.light)
                        watchWithFriend = friend
                        showCreateRoom = true
                    } label: {
                        V4GlyphIcon(glyph: .film, size: 13, filled: true, weight: .regular)
                            .foregroundStyle(theme.buttonTextColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(theme.accentColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Смотреть вместе с \(friend.displayTitle)")
                }
            }
        }
        .padding(12)
        .background(V4.surface.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(V4.line.opacity(0.55), lineWidth: 1)
        )
        .contextMenu {
            Button { profileFriend = friend } label: {
                Label("Профиль", systemImage: "person.crop.circle")
            }
            if !friend.deleted {
                Button { dmFriend = friend } label: {
                    Label("Написать", systemImage: "message.fill")
                }
                Button {
                    watchWithFriend = friend
                    showCreateRoom = true
                } label: {
                    Label("Смотреть вместе", systemImage: "film.fill")
                }
            }
        }
    }

}
