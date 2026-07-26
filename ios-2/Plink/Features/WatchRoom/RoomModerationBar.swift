import SwiftUI

// MARK: - Wire protocol (M15)
/// События модерации едут по чат-протоколу — тот же трюк, что RoomPolls (M13)
/// и RoomCountdown (M14). Изменения протокола бэкенда не требуются.
enum RoomModerationWire {
    static let marker = "\u{2063}plink.priv\u{2063}"

    struct Event: Codable {
        let privacy: String
    }

    static func encode(_ event: Event) -> String {
        guard let data = try? JSONEncoder().encode(event),
              let json = String(data: data, encoding: .utf8) else { return marker }
        return marker + json
    }

    static func decode(_ text: String) -> Event? {
        guard text.hasPrefix(marker) else { return nil }
        let json = String(text.dropFirst(marker.count))
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Event.self, from: data)
    }
}

// MARK: - Moderation bar
/// Верхний бар модерации комнаты (как у Rave): хост выбирает, кто может войти.
/// Появляется автоматически после создания комнаты, затем скрывается, чтобы
/// не мешать; повторный вызов — кнопка-щит в верхнем хроме (только хост).
struct RoomModerationBar: View {
    let model: WatchRoomModel

    @State private var passwordDraft: String = ""
    @State private var showPasswordField = false

    private var accent: Color { PlinkRoomAccent.current }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accent)
                    Text("Кто может войти")
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { model.moderationBarVisible = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Скрыть настройки модерации")
            }

            HStack(spacing: 8) {
                ForEach(RoomPrivacy.allCases) { mode in
                    modeChip(mode)
                }
            }

            if showPasswordField {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(accent)
                    SecureField("Пароль комнаты", text: $passwordDraft)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.never)
                    Button("Готово") {
                        model.setPrivacy(.privateRoom, password: passwordDraft.isEmpty ? nil : passwordDraft)
                        withAnimation { showPasswordField = false }
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(passwordDraft.isEmpty ? Color.white.opacity(0.3) : accent)
                    .disabled(passwordDraft.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func modeChip(_ mode: RoomPrivacy) -> some View {
        let selected = model.roomPrivacy == mode
        Button {
            HapticManager.selection()
            if mode == .privateRoom {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showPasswordField = true }
            } else {
                withAnimation { showPasswordField = false }
                model.setPrivacy(mode, password: nil)
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(mode.shortTitle)
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? .black : .white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selected ? accent : Color.white.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
    }
}

extension RoomPrivacy {
    /// Короткое имя для чипов бара модерации.
    var shortTitle: String {
        switch self {
        case .publicRoom: return "Публичная"
        case .privateRoom: return "Закрытая"
        case .byLink: return "По ссылке"
        case .friendsRoom: return "Друзья"
        }
    }
}
