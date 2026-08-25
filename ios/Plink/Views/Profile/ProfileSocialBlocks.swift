import SwiftUI

// Соцблоки профиля (модель ВК): рельса просмотров с постерами, рельса
// друзей с круглыми аватарками и никами, карта закрытого профиля и полный
// список друзей. Общие для своего профиля (V4ProfileViewLive) и чужого
// (FriendProfileView) — одно лицо на обеих страницах.

// MARK: - Рельса просмотров

/// «Недавно смотрел» как в ВК/Кинопоиске: горизонтальная рельса баннеров
/// с названиями, а не текстовые строки. Без арта — жанровое полотно
/// с иконкой типа медиа, чтобы рельса не разваливалась на старой истории.
struct ProfileWatchRailCard: View {
    let history: [UserSocialProfile.WatchHistoryEntry]
    var accent: Color
    /// Тап по заголовку/шеврону (nil — заголовок не кнопка).
    var onHeader: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(history.prefix(12)) { item in
                        WatchRailTile(item: item, accent: accent)
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 14)
        }
        .plinkGlass(.control, cornerRadius: 20)
    }

    @ViewBuilder private var header: some View {
        let title = HStack(spacing: 6) {
            Text(LocalizationManager.shared.string(.fpRecentlyWatched))
                .font(.system(size: 16, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(V4.ink)
            if onHeader != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(V4.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)

        if let onHeader {
            Button {
                HapticManager.selection()
                onHeader()
            } label: { title }
            .buttonStyle(.plain)
            .accessibilityLabel("Недавно смотрел. Открыть всю историю")
        } else {
            title
        }
    }
}

/// Один баннер рельсы: постер 138×78 со скруглением, название до двух строк.
private struct WatchRailTile: View {
    let item: UserSocialProfile.WatchHistoryEntry
    let accent: Color

    private var kindSymbol: String {
        switch item.kind {
        case "series": return "tv.fill"
        case "music": return "music.note"
        case "livestream": return "dot.radiowaves.left.and.right"
        case "video": return "play.rectangle.fill"
        default: return "film.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                if let thumb = item.thumb, let url = URL(string: thumb) {
                    Color.clear
                        .overlay(
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                placeholderCanvas
                            }
                        )
                        .clipped()
                } else {
                    placeholderCanvas
                }
            }
            .frame(width: 138, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(V4.line, lineWidth: 1)
            )

            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(V4.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 138, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
    }

    /// Полотно без арта: тёмный градиент + иконка типа медиа в акценте.
    private var placeholderCanvas: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#232838"), Color(hex: "#141824")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: kindSymbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent.opacity(0.75))
        }
    }
}

// MARK: - Рельса друзей

/// «Друзья N» как в ВК: круглые аватарки с никами. Тап по другу — его
/// профиль (рекурсивный просмотр), тап по заголовку — полный список.
struct ProfileFriendsRailCard: View {
    let friends: [ProfileFriendPreview]
    let friendsCount: Int
    var onFriend: (ProfileFriendPreview) -> Void
    /// Тап по заголовку (nil — заголовок не кнопка).
    var onHeader: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(friends) { friend in
                        FriendRailTile(friend: friend) { onFriend(friend) }
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 14)
        }
        .plinkGlass(.control, cornerRadius: 20)
    }

    @ViewBuilder private var header: some View {
        let title = HStack(spacing: 6) {
            Text("Друзья")
                .font(.system(size: 16, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(V4.ink)
            Text("\(friendsCount)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(V4.muted)
            if onHeader != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(V4.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)

        if let onHeader {
            Button {
                HapticManager.selection()
                onHeader()
            } label: { title }
            .buttonStyle(.plain)
            .accessibilityLabel("Друзья: \(friendsCount). Открыть весь список")
        } else {
            title
        }
    }
}

/// Один друг рельсы: аватар 56 с точкой присутствия + ник в одну строку.
private struct FriendRailTile: View {
    let friend: ProfileFriendPreview
    var action: () -> Void

    var body: some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            VStack(spacing: 6) {
                PlinkStableAvatar(
                    url: PlinkAvatarURL.stable(userId: friend.id, stored: friend.avatarURL),
                    letter: String(friend.displayTitle.prefix(1)).uppercased(),
                    size: 56,
                    userId: friend.id
                )
                .clipShape(Circle())
                // Вырез под точку присутствия — сквозь сам аватар, как на
                // большом аватаре профиля (никаких рисованных колец).
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .frame(width: 20, height: 20)
                        .offset(x: 1, y: 1)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(friend.isOnline == true ? Color(hex: "#23A55A") : Color(hex: "#80848E"))
                        .frame(width: 14, height: 14)
                        .offset(x: -2, y: -2)
                }

                Text(friend.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(V4.ink)
                    .lineLimit(1)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(friend.displayTitle)\(friend.isOnline == true ? ", в сети" : ""). Открыть профиль")
    }
}

// MARK: - Закрытый профиль

/// Замок как в ВК: статистику, просмотры и друзей видят только друзья.
/// Идентичность (имя, аватар, обложка, статус) остаётся видимой.
struct ProfileClosedCard: View {
    var accent: Color

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.14))
                    .frame(width: 64, height: 64)
                Image(systemName: "lock.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text("Закрытый профиль")
                .font(.system(size: 16, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(V4.ink)
            Text("Статистику, просмотры и друзей видят только друзья")
                .font(.system(size: 13))
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .plinkGlass(.control, cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Закрытый профиль. Статистику, просмотры и друзей видят только друзья")
    }
}

// MARK: - Полный список друзей

/// Полный список друзей пользователя (дверь из рельсы). Грузится с
/// /users/:id/friends; на 403 показывает замок — профиль закрыли,
/// пока список был открыт.
struct ProfileFriendListSheet: View {
    let userId: String
    let title: String
    var accent: Color
    var onFriend: (ProfileFriendPreview) -> Void

    @State private var friends: [ProfileFriendPreview]?
    @State private var failedClosed = false
    @State private var errorText: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let friends {
                    if friends.isEmpty {
                        emptyState
                    } else {
                        listCard(friends)
                    }
                } else if failedClosed {
                    ProfileClosedCard(accent: accent)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                } else if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(V4.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    HStack {
                        Spacer()
                        ProgressView().tint(accent)
                        Spacer()
                    }
                    .padding(.top, 60)
                }
            }
            .padding(.bottom, 40)
        }
        .background(V4.canvas.ignoresSafeArea())
        .foregroundStyle(V4.ink)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func listCard(_ friends: [ProfileFriendPreview]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                if index > 0 {
                    Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 70)
                }
                Button {
                    HapticManager.selection()
                    onFriend(friend)
                } label: {
                    HStack(spacing: 12) {
                        PlinkStableAvatar(
                            url: PlinkAvatarURL.stable(userId: friend.id, stored: friend.avatarURL),
                            letter: String(friend.displayTitle.prefix(1)).uppercased(),
                            size: 44,
                            userId: friend.id
                        )
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.displayTitle)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(V4.ink)
                                .lineLimit(1)
                            Text(friend.isOnline == true
                                 ? "в сети"
                                 : FriendPresence.displayText(isOnline: false, lastSeenAt: friend.lastSeenAt))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(friend.isOnline == true ? Color(hex: "#23A55A") : V4.muted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(V4.muted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(friend.displayTitle). Открыть профиль")
            }
        }
        .padding(.vertical, 6)
        .plinkGlass(.control, cornerRadius: 20)
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(V4.muted)
            Text("Пока нет друзей")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(V4.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func load() async {
        do {
            friends = try await SocialProfileService.fetchFriends(userId: userId)
        } catch {
            // 403 «closed» — владелец закрыл профиль между открытием
            // рельсы и списка.
            if case APIError.serverError(let status, _) = error, status == 403 {
                failedClosed = true
            } else {
                errorText = error.localizedDescription
            }
        }
    }
}
