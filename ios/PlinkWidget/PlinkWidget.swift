// PlinkWidget/PlinkWidget.swift — M13: home-screen widget «Ближайший сеанс».
//
// Reads the schedule mirrored by ScheduledSessionsService into the shared
// app-group container (group.com.syncwatch.plink). The payload is a plain
// JSON array of { "title": String, "dateEpoch": Double } — intentionally
// decoupled from the app's ScheduledSession model so the widget never breaks
// when the model grows new fields.
//
// NOTE: the App Group capability must be enabled for both targets when a
// paid Apple Developer account is available; in the simulator it works as-is.

import WidgetKit
import SwiftUI

private enum WidgetStore {
    static let suiteName = "group.com.syncwatch.plink"
    static let key = "plink_widget_sessions"

    static func nextSession(after now: Date = Date()) -> (title: String, date: Date)? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return nil }

        return array
            .compactMap { dict -> (String, Date)? in
                guard let title = dict["title"] as? String,
                      let epoch = dict["dateEpoch"] as? Double else { return nil }
                let date = Date(timeIntervalSince1970: epoch)
                return date > now ? (title, date) : nil
            }
            .min { $0.1 < $1.1 }
    }
}

struct NextSessionEntry: TimelineEntry {
    let date: Date
    let sessionTitle: String?
    let sessionDate: Date?
}

struct NextSessionProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextSessionEntry {
        NextSessionEntry(date: Date(), sessionTitle: "Киновечер с друзьями", sessionDate: Date().addingTimeInterval(3600))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextSessionEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextSessionEntry>) -> Void) {
        let entry = makeEntry()
        // Refresh when the session starts (its countdown becomes stale) or in 30 min.
        let refresh = entry.sessionDate ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(min(refresh, Date().addingTimeInterval(1800)))))
    }

    private func makeEntry() -> NextSessionEntry {
        let next = WidgetStore.nextSession()
        return NextSessionEntry(date: Date(), sessionTitle: next?.title, sessionDate: next?.date)
    }
}

struct NextSessionWidgetView: View {
    var entry: NextSessionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "play.tv.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Плинк")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                Spacer()
            }
            .foregroundStyle(Color(red: 0.55, green: 0.45, blue: 1.0))

            Spacer(minLength: 2)

            if let title = entry.sessionTitle, let date = entry.sessionDate {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(date, style: .relative)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Text(date, format: .dateTime.weekday(.wide).hour().minute())
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                Text("Нет запланированных сеансов")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Text("Запланируйте киновечер в приложении")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 0)
        }
        .padding(2)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.07, blue: 0.16), Color(red: 0.05, green: 0.05, blue: 0.09)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct PlinkNextSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PlinkNextSession", provider: NextSessionProvider()) { entry in
            NextSessionWidgetView(entry: entry)
        }
        .configurationDisplayName("Ближайший сеанс")
        .description("Показывает ближайший запланированный совместный просмотр.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PlinkWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlinkNextSessionWidget()
    }
}
