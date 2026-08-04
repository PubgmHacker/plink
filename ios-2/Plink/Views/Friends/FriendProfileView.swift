import SwiftUI

/// Friend / public social profile: stats, badges, watch history, Watch Together.
/// Deleted peers show a Telegram-style tombstone (no PII, no messaging actions).
struct FriendProfileView: View {
    let userId: String
    var usernameHint: String = ""
    var onWatchTogether: (() -> Void)? = nil

    @State private var profile: UserSocialProfile?
    @State private var error: String?
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    private var isDeleted: Bool {
        profile?.deleted == true || usernameHint.hasPrefix("deleted_")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if isDeleted {
                    deletedBanner
                } else {
                    statsGrid
                    badgesSection
                    historySection
                    if let onWatchTogether {
                        Button {
                            onWatchTogether()
                        } label: {
                            Label("Смотреть вместе", systemImage: "play.rectangle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Cinema2026.background)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 52)
                                .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Смотреть вместе")
                    }
                }
            }
            .padding(20)
        }
        .background(Cinema2026.background.ignoresSafeArea())
        .navigationTitle(profile?.displayTitle ?? (isDeleted ? "Удалённый аккаунт" : usernameHint))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Group {
                if isDeleted {
                    PlinkDeletedAvatar(size: 64)
                } else if let url = PlinkAvatarURL.resolve(userId: userId, stored: profile?.avatarURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            avatarLetter
                        }
                    }
                } else {
                    avatarLetter
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            .overlay(
                Circle().stroke(
                    isDeleted ? Color.white.opacity(0.12) : Cinema2026.accent.opacity(0.4),
                    lineWidth: 2
                )
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(profile?.displayTitle ?? (isDeleted ? "Удалённый аккаунт" : usernameHint))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                if isDeleted {
                    Text(LocalizationManager.shared.string(.fpUnavailable))
                        .font(.system(size: 14))
                        .foregroundStyle(Cinema2026.secondary)
                } else if let u = profile?.username {
                    Text("@\(u)")
                        .font(.system(size: 14))
                        .foregroundStyle(Cinema2026.secondary)
                }
                if let p = profile {
                    Text(p.presenceText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            isDeleted
                                ? Cinema2026.secondary
                                : (p.isOnline == true ? Cinema2026.accent : Cinema2026.secondary)
                        )
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var deletedBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Аккаунт удалён", systemImage: "person.crop.circle.badge.xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(LocalizationManager.shared.string(.fpUnavailableSub))
                .font(.system(size: 13))
                .foregroundStyle(Cinema2026.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var avatarLetter: some View {
        ZStack {
            Circle().fill(Cinema2026.accent.opacity(0.25))
            Text(String((profile?.username ?? usernameHint).prefix(1)).uppercased())
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var statsGrid: some View {
        let p = profile
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statCard("Часы в Plink", p?.watchHoursText ?? "—")
            statCard("Фильмов", p.map { "\($0.filmsWatched)" } ?? "—")
            statCard("Друзей", p.map { "\($0.friendsCount)" } ?? "—")
            statCard("Комнат", p.map { "\($0.roomsCreated)" } ?? "—")
        }
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Cinema2026.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Cinema2026.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Cinema2026.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    @ViewBuilder
    private var badgesSection: some View {
        if let badges = profile?.badges, !badges.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizationManager.shared.string(.fpAchievements))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                FlowBadgeRow(codes: badges)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if let history = profile?.watchHistory, !history.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizationManager.shared.string(.fpRecentlyWatched))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                ForEach(history.prefix(10)) { item in
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(Cinema2026.accent)
                        Text(item.title)
                            .font(.system(size: 14))
                            .foregroundStyle(Cinema2026.text)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if isLoading {
            ProgressView().tint(Cinema2026.accent)
        } else if let error {
            Text(error)
                .font(.caption)
                .foregroundStyle(Cinema2026.secondary)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await SocialProfileService.fetch(userId: userId)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct FlowBadgeRow: View {
    let codes: [String]

    var body: some View {
        FlexibleWrap(spacing: 8) {
            ForEach(codes, id: \.self) { code in
                let badge = ProfileBadge.from(code: code)
                HStack(spacing: 4) {
                    Image(systemName: badge?.symbol ?? "star")
                        .font(.system(size: 11, weight: .semibold))
                    Text(badge?.title ?? code)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Cinema2026.accent.opacity(0.35), in: Capsule())
                .accessibilityLabel(badge?.title ?? code)
            }
        }
    }
}

/// Minimal wrap layout for badges without external deps.
struct FlexibleWrap<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        // Simple horizontal scroll if many badges — keeps layout stable on all sizes
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) { content }
        }
    }
}
