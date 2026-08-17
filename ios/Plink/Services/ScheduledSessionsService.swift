// Plink/Services/ScheduledSessionsService.swift
// M12: планирование совместных сеансов — локальное хранение,
// пуш-напоминания (UserNotifications) и опциональное добавление
// в календарь (EventKit). Бэкенд не требуется.

import Foundation
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(EventKit)
import EventKit
#endif

struct ScheduledSession: Codable, Identifiable {
    let id: String
    var title: String
    var serviceName: String?
    var contentURL: String?
    var startsAt: Date
    var note: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        serviceName: String? = nil,
        contentURL: String? = nil,
        startsAt: Date,
        note: String? = nil
    ) {
        self.id = id
        self.title = title
        self.serviceName = serviceName
        self.contentURL = contentURL
        self.startsAt = startsAt
        self.note = note
    }
}

@MainActor
final class ScheduledSessionsService: ObservableObject {
    static let shared = ScheduledSessionsService()

    @Published private(set) var sessions: [ScheduledSession] = []

    private static let storageKey = "plink_scheduled_sessions"

    private init() {
        load()
        pruneExpired()
    }

    // MARK: - Public API

    /// Запланировать сеанс: сохраняет, ставит напоминания и (опционально)
    /// добавляет событие в календарь.
    func schedule(
        _ session: ScheduledSession,
        remindMinutesBefore: Int = 15,
        addToCalendar: Bool = false
    ) async {
        sessions.append(session)
        sessions.sort { $0.startsAt < $1.startsAt }
        persist()
        await scheduleNotifications(for: session, remindMinutesBefore: remindMinutesBefore)
        if addToCalendar {
            await addCalendarEvent(for: session)
        }
    }

    func cancel(_ id: String) {
        sessions.removeAll { $0.id == id }
        persist()
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [
                "plink.session.\(id).reminder",
                "plink.session.\(id).start",
            ]
        )
    }

    /// Удаляет сеансы, начавшиеся более часа назад.
    func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-3600)
        let before = sessions.count
        sessions.removeAll { $0.startsAt < cutoff }
        if sessions.count != before { persist() }
    }

    // MARK: - Notifications

    private func scheduleNotifications(for session: ScheduledSession, remindMinutesBefore: Int) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        // Напоминание за N минут
        let reminderDate = session.startsAt.addingTimeInterval(-Double(remindMinutesBefore) * 60)
        if reminderDate > Date() {
            let content = UNMutableNotificationContent()
            content.title = "Скоро совместный просмотр"
            content.body = "«\(session.title)» начнётся через \(remindMinutesBefore) мин. Собирай компанию!"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: reminderDate
                ),
                repeats: false
            )
            try? await center.add(UNNotificationRequest(
                identifier: "plink.session.\(session.id).reminder",
                content: content,
                trigger: trigger
            ))
        }

        // Уведомление в момент старта
        if session.startsAt > Date() {
            let content = UNMutableNotificationContent()
            content.title = "Время смотреть вместе 🎬"
            content.body = "«\(session.title)» начинается прямо сейчас. Создай комнату в Plink!"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: session.startsAt
                ),
                repeats: false
            )
            try? await center.add(UNNotificationRequest(
                identifier: "plink.session.\(session.id).start",
                content: content,
                trigger: trigger
            ))
        }
    }

    // MARK: - Calendar (EventKit)

    private func addCalendarEvent(for session: ScheduledSession) async {
        #if canImport(EventKit)
        let store = EKEventStore()
        var granted = false
        if #available(iOS 17.0, *) {
            granted = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        } else {
            granted = (try? await store.requestAccess(to: .event)) ?? false
        }
        guard granted else { return }

        let event = EKEvent(eventStore: store)
        event.title = "Plink · \(session.title)"
        event.startDate = session.startsAt
        event.endDate = session.startsAt.addingTimeInterval(2 * 3600)
        event.notes = session.note ?? "Совместный просмотр в Plink"
        event.calendar = store.defaultCalendarForNewEvents
        try? store.save(event, span: .thisEvent)
        #endif
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let items = try? JSONDecoder().decode([ScheduledSession].self, from: data)
        else { return }
        sessions = items.sorted { $0.startsAt < $1.startsAt }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        mirrorToWidget()
    }

    /// M13: mirror a simplified schedule into the shared app-group container
    /// so the home-screen widget can show the next session. The payload is
    /// intentionally decoupled from the ScheduledSession model (title + epoch
    /// only), so the widget never breaks when the model grows new fields.
    private func mirrorToWidget() {
        if let defaults = UserDefaults(suiteName: "group.com.syncwatch.plink") {
            let payload: [[String: Any]] = sessions.map {
                ["title": $0.title, "dateEpoch": $0.startsAt.timeIntervalSince1970]
            }
            if let data = try? JSONSerialization.data(withJSONObject: payload) {
                defaults.set(data, forKey: "plink_widget_sessions")
            }
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "PlinkNextSession")
        #endif
    }
}
