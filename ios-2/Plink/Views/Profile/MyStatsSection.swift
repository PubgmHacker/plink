import SwiftUI

/// "Моя статистика" block for Profile (legacy ProfileView + embeddable).
struct MyStatsSection: View {
    @State private var profile: UserSocialProfile?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Моя статистика")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Cinema2026.text)

            if let p = profile {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    mini("Часы", p.watchHoursText)
                    mini("Фильмы", "\(p.filmsWatched)")
                    mini("Друзья", "\(p.friendsCount)")
                    mini("Комнаты", "\(p.roomsCreated)")
                }

                if !p.badges.isEmpty {
                    FlowBadgeRow(codes: p.badges)
                }

                if !p.watchHistory.isEmpty {
                    Text("История просмотров")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Cinema2026.secondary)
                        .padding(.top, 4)
                    ForEach(p.watchHistory.prefix(5)) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                                .foregroundStyle(Cinema2026.secondary)
                            Text(item.title)
                                .font(.system(size: 13))
                                .foregroundStyle(Cinema2026.text)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            } else if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Cinema2026.secondary)
            } else {
                ProgressView().tint(Cinema2026.accent)
            }
        }
        .padding(16)
        .background(Cinema2026.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .task {
            do {
                profile = try await SocialProfileService.fetchMe()
            } catch {
                self.error = "Не удалось загрузить статистику"
            }
        }
    }

    private func mini(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Cinema2026.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Cinema2026.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Cinema2026.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}
