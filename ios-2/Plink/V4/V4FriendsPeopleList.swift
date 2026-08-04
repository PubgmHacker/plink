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
    /// M14: карточка «друг смотрит» с кнопкой присоединения.
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
            // M14: «Друг сейчас смотрит — присоединиться»
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
                sectionHeader(
                    title: LocalizationManager.shared.string(.frAllFriends),
                    icon: "person.2.fill",
                    count: store?.friends.count,
                    actionTitle: LocalizationManager.shared.string(.frAdd),
                    action: { showAddFriend = true }
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
                    case .failed(let err):
                        sectionCard {
                            emptyInside(
                                icon: "wifi.exclamationmark",
                                title: "Не удалось загрузить друзей",
                                subtitle: err,
                                cta: "Повторить"
                            ) { Task { await store?.load() } }
                        }
                    case .idle:
                        Color.clear.frame(height: 1)
                    case .loaded, .empty:
                        if s.friends.isEmpty {
                            sectionCard {
                                VStack(spacing: 4) {
                                    emptyInside(
                                        icon: "person.badge.plus",
                                        title: LocalizationManager.shared.string(.frEmptyTitle),
                                        subtitle: LocalizationManager.shared.string(.frEmptySub),
                                        cta: LocalizationManager.shared.string(.frFind)
                                    ) { showAddFriend = true }
                                    // M26 UX: инвайт-ссылка прямо из пустого состояния
                                    if let myId = AuthService.shared.currentUserValue?.id,
                                       let inviteURL = URL(string: "https://plink.app/u/\(myId)") {
                                        ShareLink(item: inviteURL) {
                                            Label(LocalizationManager.shared.string(.frInviteLink), systemImage: "square.and.arrow.up")
                                                .font(.system(size: 13.5, weight: .semibold))
                                                .foregroundStyle(theme.accentColor)
                                                .padding(.vertical, 8)
                                        }
                                    }
                                }
                                .padding(.bottom, 10)
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
                    Label("��мотреть вместе", systemImage: "film.fill")
                }
            }
        }
    }

}
