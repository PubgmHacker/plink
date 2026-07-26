import Foundation
import SwiftUI

// MARK: - Room Countdown Wire (M14: отсчёт 3-2-1 перед стартом)
// Ездит по чат-каналу с invisible-separator маркером — как RoomPollWire.
// Бэкенд менять не нужно: обычный chat.send / chat.broadcast.

enum RoomCountdownWire {
    static let marker = "\u{2063}plink.count\u{2063}"

    struct Event: Codable {
        /// Момент старта воспроизведения (epoch ms) — общий для всех клиентов.
        let startAtMs: Int64
    }

    static func encode(_ event: Event) -> String? {
        guard let data = try? JSONEncoder().encode(event),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return marker + json
    }

    static func decode(_ text: String) -> Event? {
        guard text.hasPrefix(marker) else { return nil }
        let json = String(text.dropFirst(marker.count))
        return try? JSONDecoder().decode(Event.self, from: Data(json.utf8))
    }
}

// MARK: - Countdown Overlay

struct RoomCountdownOverlay: View {
    let value: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            Text("\(value)")
                .font(.system(size: 120, weight: .black, design: .rounded))
                .foregroundStyle(PlinkRoomAccent.current)
                .shadow(color: PlinkRoomAccent.current.opacity(0.55), radius: 26)
                .id(value)
                .transition(.scale(scale: 1.35).combined(with: .opacity))
        }
        .animation(.spring(duration: 0.28), value: value)
        .accessibilityLabel("Старт через \(value)")
    }
}

// MARK: - Room Accent (M14: V4-тема продолжается в комнате)
/// Комната читает акцент выбранной V4-темы — интерфейс перестаёт «прыгать»
/// между двумя дизайн-мирами при входе в просмотр.
enum PlinkRoomAccent {
    static var current: Color {
        if let raw = UserDefaults.standard.string(forKey: "plink.v4ThemeName"),
           let theme = V4Theme(rawValue: raw) {
            return theme.accentColor
        }
        return Cinema2026.accent
    }
}
