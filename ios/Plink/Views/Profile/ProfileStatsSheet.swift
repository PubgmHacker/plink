import SwiftUI

// Profile statistics — a full screen in the spirit of Apple Fitness and
// Telegram channel stats: a period pill, hero figures, a seven-day activity
// strip, the "what we watched" rail filtered by the period, achievements
// with progress and lifetime totals. Everything is tinted by the face
// accent (the cover colour), never by the app theme.

/// Period filter shared by the stats screen and the profile rail.
enum PlinkStatsPeriod: CaseIterable, Identifiable {
    case week, month, all
    var id: Self { self }

    @MainActor var title: String {
        switch self {
        case .week: return LocalizationManager.shared.string(.wrPeriodWeek)
        case .month: return LocalizationManager.shared.string(.wrPeriodMonth)
        case .all: return LocalizationManager.shared.string(.wrPeriodAll)
        }
    }

    @MainActor var caption: String {
        switch self {
        case .week: return LocalizationManager.shared.string(.stCaptionWeek)
        case .month: return LocalizationManager.shared.string(.stCaptionMonth)
        case .all: return LocalizationManager.shared.string(.stCaptionAll)
        }
    }

    /// Earliest `watchedAt` that still belongs to the period (nil — unbounded).
    func lowerBound(now: Date = Date()) -> Date? {
        switch self {
        case .week: return now.addingTimeInterval(-7 * 86_400)
        case .month: return now.addingTimeInterval(-30 * 86_400)
        case .all: return nil
        }
    }

    /// Entries inside the period. Entries without a date never make it into
    /// a bounded period — a missing timestamp is not evidence of recency.
    func filter(_ entries: [UserSocialProfile.WatchHistoryEntry], now: Date = Date()) -> [UserSocialProfile.WatchHistoryEntry] {
        guard let bound = lowerBound(now: now) else { return entries }
        return entries.filter { ($0.watchedAt ?? .distantPast) >= bound }
    }
}

/// Media kind → glyph / human title. Shared by tiles and the stats hero.
enum PlinkMediaKind {
    static func symbol(for kind: String?) -> String {
        switch kind {
        case "series": return "tv.fill"
        case "music": return "music.note"
        case "livestream": return "dot.radiowaves.left.and.right"
        case "video": return "play.rectangle.fill"
        default: return "film.fill"
        }
    }

    @MainActor static func title(for kind: String?) -> String? {
        switch kind {
        case "movie": return LocalizationManager.shared.string(.stKindMovie)
        case "series": return LocalizationManager.shared.string(.stKindSeries)
        case "music": return LocalizationManager.shared.string(.stKindMusic)
        case "video": return LocalizationManager.shared.string(.stKindVideo)
        case "livestream": return LocalizationManager.shared.string(.stKindLive)
        default: return nil
        }
    }
}

/// Russian-aware plural for "N films" (one / few / many forms).
@MainActor
enum PlinkPlural {
    static func films(_ n: Int) -> String {
        let l = LocalizationManager.shared
        let one = l.string(.stFilmOne), few = l.string(.stFilmFew), many = l.string(.stFilmMany)
        if l.currentLanguage == .russian {
            let mod10 = n % 10, mod100 = n % 100
            if mod10 == 1 && mod100 != 11 { return one }
            if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
            return many
        }
        return n == 1 ? one : many
    }
}

// MARK: - Period pill

/// Sliding segmented capsule (Telegram stats model): the accent thumb
/// glides between segments with a spring.
struct PlinkPeriodPill: View {
    @Binding var selection: PlinkStatsPeriod
    var accent: Color
    var accentInk: Color = .white
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PlinkStatsPeriod.allCases) { period in
                let selected = period == selection
                Button {
                    guard !selected else { return }
                    HapticManager.selection()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        selection = period
                    }
                } label: {
                    Text(period.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(selected ? accentInk : V4.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(accent)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .plinkGlass(.control, in: Capsule(style: .continuous))
    }
}

// MARK: - Stats sheet

struct ProfileStatsSheet: View {
    let profile: UserSocialProfile?
    var accent: Color
    var accentInk: Color = .white
    /// The viewer looks at their own profile — affects empty-state wording.
    var isSelf: Bool = true

    @Environment(\.dismiss) private var dismiss
    @State private var period: PlinkStatsPeriod = .week

    private struct Metric: Identifiable {
        let id: String
        let value: String
        let label: String
        let symbol: String
    }

    var body: some View {
        NavigationStack {
            ZStack {
                V4.canvas.ignoresSafeArea()
                RadialGradient(
                    colors: [accent.opacity(0.16), .clear],
                    center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 460
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        PlinkPeriodPill(selection: $period, accent: accent, accentInk: accentInk)
                            .padding(.top, 6)
                        heroCard
                        activityCard
                        watchedCard
                        achievementsCard
                        if period != .all {
                            totalsCard
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(LocalizationManager.shared.string(.stTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { V4SheetCloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: Data

    private var stats: UserSocialProfile.ActivityStats? { profile?.resolvedStats }

    private var metrics: [Metric] {
        let l = LocalizationManager.shared
        guard let profile else {
            return [Metric(id: "hero", value: "—", label: l.string(.stFilmMany), symbol: "film.fill")]
        }
        switch period {
        case .week:
            let films = stats?.weekFilms ?? 0
            return [
                Metric(id: "hero", value: "\(films)", label: PlinkPlural.films(films), symbol: "film.fill"),
                Metric(id: "streak", value: "\(stats?.streakDays ?? 0)", label: l.string(.stStreak), symbol: "flame.fill"),
                Metric(id: "kind", value: PlinkMediaKind.title(for: stats?.topKind) ?? "—",
                       label: l.string(.stTopKind), symbol: PlinkMediaKind.symbol(for: stats?.topKind))
            ]
        case .month:
            let films = stats?.monthFilms ?? 0
            return [
                Metric(id: "hero", value: "\(films)", label: PlinkPlural.films(films), symbol: "film.fill"),
                Metric(id: "time", value: UserSocialProfile.durationText(minutes: stats?.monthMinutes ?? 0),
                       label: l.string(.stTimeLabel), symbol: "clock.fill"),
                Metric(id: "streak", value: "\(stats?.streakDays ?? 0)", label: l.string(.stStreak), symbol: "flame.fill")
            ]
        case .all:
            return [
                Metric(id: "hero", value: "\(profile.filmsWatched)", label: PlinkPlural.films(profile.filmsWatched), symbol: "film.fill"),
                Metric(id: "time", value: profile.watchHoursText, label: l.string(.stTimeLabel), symbol: "clock.fill"),
                Metric(id: "rooms", value: "\(profile.roomsCreated)", label: l.string(.stRooms), symbol: "rectangle.stack.fill"),
                Metric(id: "friends", value: "\(profile.friendsCount)", label: l.string(.stFriends), symbol: "person.2.fill")
            ]
        }
    }

    private var periodEntries: [UserSocialProfile.WatchHistoryEntry] {
        period.filter(profile?.watchHistory ?? [])
    }

    private var achievements: [UserSocialProfile.Achievement] {
        (profile?.resolvedAchievements ?? []).filter { $0.badge != nil }
    }

    // MARK: Hero

    private var heroCard: some View {
        let all = metrics
        let hero = all.first
        let rest = Array(all.dropFirst())
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(hero?.value ?? "—")
                    .font(.system(size: 46, weight: .heavy))
                    .tracking(-1.6)
                    .foregroundStyle(V4.ink)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                VStack(alignment: .leading, spacing: 0) {
                    Text(hero?.label ?? "")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(V4.ink)
                    Text(period.caption)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(V4.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: hero?.symbol ?? "film.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .background(accent.opacity(0.16), in: Circle())
            }
            if !rest.isEmpty {
                HStack(spacing: 10) {
                    ForEach(rest) { metric in
                        metricTile(metric)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.26), accent.opacity(0.05)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .plinkGlass(.control, cornerRadius: 24)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: period)
        .accessibilityElement(children: .combine)
    }

    private func metricTile(_ metric: Metric) -> some View {
        HStack(spacing: 8) {
            Image(systemName: metric.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(metric.value)
                    .font(.system(size: 15, weight: .heavy))
                    .tracking(-0.3)
                    .foregroundStyle(V4.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(metric.label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(V4.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(V4.cardBG.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(V4.line))
    }

    // MARK: Activity

    private var activityCard: some View {
        let l = LocalizationManager.shared
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.string(.stActivity))
                        .font(.system(size: 16, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(V4.ink)
                    Text(l.string(.stLast7))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(V4.muted)
                }
                Spacer(minLength: 0)
                if let stats {
                    Text("\(stats.weekFilms)")
                        .font(.system(size: 20, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(accent)
                        .contentTransition(.numericText())
                }
            }
            if let stats, stats.week.count == 7 {
                activityBars(stats.week)
            } else {
                Text(profile == nil ? "…" : (isSelf ? l.string(.stNoActivity) : l.string(.stActivityHidden)))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(V4.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plinkGlass(.control, cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }

    private func activityBars(_ week: [Int]) -> some View {
        let maxValue = max(1, week.max() ?? 1)
        let trackHeight: CGFloat = 76
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(week.enumerated()), id: \.offset) { index, value in
                let isToday = index == week.count - 1
                VStack(spacing: 7) {
                    ZStack(alignment: .bottom) {
                        Capsule(style: .continuous)
                            .fill(V4.line.opacity(0.35))
                            .frame(height: trackHeight)
                        Capsule(style: .continuous)
                            .fill(isToday ? accent : accent.opacity(0.42))
                            .frame(height: value == 0 ? 5 : max(10, trackHeight * CGFloat(value) / CGFloat(maxValue)))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
                    }
                    .frame(maxWidth: .infinity)
                    Text(dayLetter(offsetFromToday: week.count - 1 - index))
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(isToday ? V4.ink : V4.muted)
                }
                .accessibilityLabel("\(dayLetter(offsetFromToday: week.count - 1 - index)): \(value)")
            }
        }
    }

    /// One-letter weekday in the app language (not the device locale).
    private func dayLetter(offsetFromToday: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: LocalizationManager.shared.currentLanguage.rawValue)
        let date = calendar.date(byAdding: .day, value: -offsetFromToday, to: Date()) ?? Date()
        let weekday = calendar.component(.weekday, from: date) // 1…7, Sunday first
        let symbols = calendar.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return "" }
        return symbols[weekday - 1].uppercased()
    }

    // MARK: Watched

    private var watchedCard: some View {
        let entries = periodEntries
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(LocalizationManager.shared.string(.stWatched))
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(-0.3)
                    .foregroundStyle(V4.ink)
                if !entries.isEmpty {
                    Text("\(entries.count)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(V4.muted)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)

            if entries.isEmpty {
                Text(LocalizationManager.shared.string(.stWatchedEmpty))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(V4.muted)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(entries.prefix(24)) { item in
                            PlinkWatchTile(item: item, accent: accent, width: 150, showsDate: true)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plinkGlass(.control, cornerRadius: 24)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: period)
    }

    // MARK: Achievements

    private var achievementsCard: some View {
        let list = achievements
        let earned = list.filter(\.earned).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(LocalizationManager.shared.string(.stAchievements))
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(-0.3)
                    .foregroundStyle(V4.ink)
                Spacer(minLength: 0)
                if !list.isEmpty {
                    Text(String(format: LocalizationManager.shared.string(.stAchievementsOf), earned, list.count))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(earned > 0 ? accent : V4.muted)
                }
            }
            if list.isEmpty {
                Text(LocalizationManager.shared.string(.vpAchievementsHint))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(V4.muted)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(list) { achievement in
                        achievementCard(achievement)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plinkGlass(.control, cornerRadius: 24)
    }

    @ViewBuilder private func achievementCard(_ achievement: UserSocialProfile.Achievement) -> some View {
        if let badge = achievement.badge {
            let earned = achievement.earned
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: badge.symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(earned ? accentInk : V4.muted)
                        .frame(width: 36, height: 36)
                        .background(earned ? accent : V4.cardBG, in: Circle())
                        .overlay(Circle().stroke(earned ? .clear : V4.line))
                    Spacer(minLength: 0)
                    if earned {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(accent)
                            .accessibilityLabel(LocalizationManager.shared.string(.stEarned))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(badge.title)
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(-0.2)
                        .foregroundStyle(V4.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(badge.hint)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(V4.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(V4.line.opacity(0.6))
                            Capsule()
                                .fill(earned ? accent : accent.opacity(0.7))
                                .frame(width: max(achievement.fraction > 0 ? 6 : 0, geo.size.width * achievement.fraction))
                        }
                    }
                    .frame(height: 5)
                    Text("\(min(achievement.progress, achievement.target))/\(achievement.target)")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(earned ? accent : V4.muted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (earned ? accent.opacity(0.13) : Color.clear),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(earned ? accent.opacity(0.55) : V4.line, lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(badge.title). \(badge.hint). \(min(achievement.progress, achievement.target)) / \(achievement.target)")
        }
    }

    // MARK: Totals

    private var totalsCard: some View {
        let l = LocalizationManager.shared
        let tiles: [Metric] = profile.map { p in
            [
                Metric(id: "t-time", value: p.watchHoursText, label: l.string(.stTimeLabel), symbol: "clock.fill"),
                Metric(id: "t-films", value: "\(p.filmsWatched)", label: PlinkPlural.films(p.filmsWatched), symbol: "film.fill"),
                Metric(id: "t-rooms", value: "\(p.roomsCreated)", label: l.string(.stRooms), symbol: "rectangle.stack.fill"),
                Metric(id: "t-friends", value: "\(p.friendsCount)", label: l.string(.stFriends), symbol: "person.2.fill")
            ]
        } ?? []
        return VStack(alignment: .leading, spacing: 12) {
            Text(l.string(.stTotals))
                .font(.system(size: 16, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(V4.ink)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(tiles) { metricTile($0) }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plinkGlass(.control, cornerRadius: 24)
    }
}
