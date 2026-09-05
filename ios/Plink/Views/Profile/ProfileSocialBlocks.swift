import SwiftUI

// Соцблоки профиля (модель ВК): рельса просмотров с постерами, рельса
// друзей с круглыми аватарками и никами, карта закрытого профиля и полный
// список друзей. Общие для своего профиля (V4ProfileViewLive) и чужого
// (FriendProfileView) — одно лицо на обеих страницах.

// MARK: - Рельса просмотров

/// "What we watched" — a proper expandable carousel (VK / Kinopoisk model).
/// Collapsed: a horizontal rail of the latest posters. Expanded (chevron
/// on the right): a period pill and a three-column grid of everything in
/// that period. The title is the door to the full history screen.
struct ProfileWatchRailCard: View {
    let history: [UserSocialProfile.WatchHistoryEntry]
    var accent: Color
    var accentInk: Color = .white
    /// Tap on the title (nil — the title is not a button).
    var onHeader: (() -> Void)? = nil

    @State private var expanded = false
    @State private var period: PlinkStatsPeriod = .all

    private var periodEntries: [UserSocialProfile.WatchHistoryEntry] {
        period.filter(history)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    PlinkPeriodPill(selection: $period, accent: accent, accentInk: accentInk)
                    let entries = periodEntries
                    if entries.isEmpty {
                        Text(LocalizationManager.shared.string(.stWatchedEmpty))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(V4.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                            alignment: .leading,
                            spacing: 12
                        ) {
                            ForEach(entries.prefix(30)) { item in
                                PlinkWatchTile(item: item, accent: accent, showsDate: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(history.prefix(12)) { item in
                            PlinkWatchTile(item: item, accent: accent, width: 150)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
        .plinkGlass(.control, cornerRadius: 20)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: expanded)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: period)
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            let title = HStack(spacing: 6) {
                Text(LocalizationManager.shared.string(.stWatched))
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(-0.3)
                    .foregroundStyle(V4.ink)
                Text("\(history.count)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(V4.muted)
                if onHeader != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(V4.muted)
                }
            }
            if let onHeader {
                Button {
                    HapticManager.selection()
                    onHeader()
                } label: { title.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel("Что смотрели. Открыть всю историю")
            } else {
                title
            }

            Spacer(minLength: 0)

            Button {
                HapticManager.impact(.light)
                expanded.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(V4.ink)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .frame(width: 30, height: 30)
                    .plinkGlass(.control, in: Circle())
            }
            .buttonStyle(.plain)
            .plinkHitTarget(30)
            .accessibilityLabel(LocalizationManager.shared.string(.wrExpand))
            .accessibilityValue(expanded ? "развёрнуто" : "свёрнуто")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

/// One poster tile: 16:9 art with rounded corners, a kind glyph in the
/// corner, the title up to two lines and an optional relative date. A fixed
/// `width` makes a rail tile; nil lets the tile fill a grid cell.
struct PlinkWatchTile: View {
    let item: UserSocialProfile.WatchHistoryEntry
    var accent: Color
    var width: CGFloat? = nil
    var showsDate: Bool = false
    /// Local playback progress 0…1 (device history only).
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            poster
            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(V4.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsDate, let date = item.watchedAt {
                Text(date.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(V4.muted)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
    }

    private var poster: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let thumb = item.thumb, let url = URL(string: thumb) {
                    Color.clear
                        .overlay(
                            // Форма с `phase`, а не двухзамыкательная: у той
                            // `placeholder` показывается и при ошибке, и не
                            // пришедший постер оставался пустым навсегда.
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                case .empty:
                                    // Пока кадр летит — только тон: монограмма
                                    // во весь просмотр, мигающая на каждой
                                    // быстрой загрузке, читается сбоем.
                                    PlinkArtlessPoster(
                                        seed: item.title.isEmpty ? item.id : item.title,
                                        showsMonogram: false)
                                default:
                                    placeholderCanvas
                                }
                            }
                        )
                        .clipped()
                } else {
                    placeholderCanvas
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                Image(systemName: PlinkMediaKind.symbol(for: item.kind))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.black.opacity(0.55), in: Circle())
                    .padding(6)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .bottomLeading)

            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.28))
                        Capsule()
                            .fill(accent)
                            .frame(width: max(4, geo.size.width * progress))
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(V4.line, lineWidth: 1)
        )
    }

    /// Обложка, которой нет: тон и монограмма из названия. Раньше здесь был
    /// один и тот же тёмный градиент с одним и тем же значком вида — рельса
    /// из трёх вещей без постеров выглядела тремя копиями одной плитки.
    private var placeholderCanvas: some View {
        PlinkArtlessPoster(seed: item.title.isEmpty ? item.id : item.title)
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
