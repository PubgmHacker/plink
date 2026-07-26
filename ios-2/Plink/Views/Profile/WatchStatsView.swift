// Plink/Views/Profile/WatchStatsView.swift — M13: watch-party статистика.
//
// Считается локально по WatchHistory — бэкенд не нужен. Открывается
// из шапки истории просмотров в профиле. Есть шер-текст для друзей.

import SwiftUI

struct WatchStatsView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [WatchHistoryItem]

    private static let accent = Color(red: 0.55, green: 0.45, blue: 1.0)

    // MARK: - Aggregates

    private var totalSessions: Int { items.count }

    private var totalHours: Double {
        items.reduce(0) { $0 + $1.watchedDuration } / 3600
    }

    private var uniqueTitles: Int { Set(items.map(\.title)).count }

    private var topSource: (name: String, count: Int)? {
        let groups = Dictionary(grouping: items, by: \.source)
        guard let best = groups.max(by: { $0.value.count < $1.value.count }) else { return nil }
        return (Self.sourceDisplayName(best.key), best.value.count)
    }

    private var averageCompletion: Int? {
        let ratios = items.compactMap { item -> Double? in
            guard let total = item.totalDuration, total > 0 else { return nil }
            return min(1, item.watchedDuration / total)
        }
        guard !ratios.isEmpty else { return nil }
        return Int((ratios.reduce(0, +) / Double(ratios.count)) * 100)
    }

    private var topTitles: [WatchHistoryItem] {
        Array(items.sorted { $0.watchedDuration > $1.watchedDuration }.prefix(5))
    }

    private var maxTopDuration: TimeInterval {
        max(topTitles.first?.watchedDuration ?? 1, 1)
    }

    private var shareText: String {
        String(
            format: "Мой Плинк: %d сеансов, %.1f ч просмотра и %d разных видео 🍿 Смотрим вместе!",
            totalSessions, totalHours, uniqueTitles
        )
    }

    private static func sourceDisplayName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "youtube": return "YouTube"
        case "vk": return "VK Видео"
        case "rutube": return "Rutube"
        case "url", "browser": return "Ссылки и сервисы"
        default: return raw.capitalized
        }
    }

    private static func hoursLabel(_ hours: Double) -> String {
        hours >= 10 ? String(format: "%.0f ч", hours) : String(format: "%.1f ч", hours)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if items.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 36))
                                .foregroundStyle(.white.opacity(0.3))
                            Text("Посмотрите что-нибудь вместе — и здесь появится статистика")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 60)
                    } else {
                        statGrid
                        topList
                        ShareLink(item: shareText) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Поделиться статистикой")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Self.accent, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.1).ignoresSafeArea())
            .navigationTitle("Мы посмотрели")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            statCard(value: "\(totalSessions)", label: "сеансов", icon: "play.rectangle.fill")
            statCard(value: Self.hoursLabel(totalHours), label: "вместе у экрана", icon: "clock.fill")
            statCard(value: "\(uniqueTitles)", label: "разных видео", icon: "film.stack")
            if let completion = averageCompletion {
                statCard(value: "\(completion)%", label: "среднее досматривание", icon: "checkmark.seal.fill")
            } else if let source = topSource {
                statCard(value: source.name, label: "любимый источник", icon: "star.fill")
            }
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Self.accent)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private var topList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Топ просмотров")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            ForEach(topTitles) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Text(Self.hoursLabel(item.watchedDuration / 3600))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    GeometryReader { geo in
                        Capsule()
                            .fill(Self.accent.opacity(0.85))
                            .frame(width: max(6, geo.size.width * (item.watchedDuration / maxTopDuration)), height: 5)
                    }
                    .frame(height: 5)
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}
