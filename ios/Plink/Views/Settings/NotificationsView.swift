import SwiftUI

// MARK: - Notifications Settings (V4 polished)

struct NotificationsView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss

    @AppStorage("notif_push_enabled") private var pushNotifications = true
    @AppStorage("notif_sounds_enabled") private var notificationSounds = true
    @AppStorage("notif_friends_online") private var friendsOnline = false
    @AppStorage("notif_new_rooms") private var newRooms = true
    @AppStorage("notif_friend_requests") private var friendRequests = true
    @AppStorage("notif_room_invites") private var roomInvites = true
    @AppStorage("notif_mentions") private var mentions = true
    @AppStorage("notif_do_not_disturb") private var doNotDisturb = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0B1018), Color(hex: 0x0A0D12), Color(hex: 0x0E1520)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(V4.accent.opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 55)
                .offset(x: 100, y: -160)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Уведомления")
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(V4.ink)
                        Text("Push, звуки и события от друзей")
                            .font(.system(size: 14))
                            .foregroundStyle(V4.muted)
                    }
                    .padding(.top, 8)

                    if doNotDisturb {
                        HStack(spacing: 12) {
                            Image(systemName: "moon.fill")
                                .foregroundStyle(V4.accent)
                            Text("Режим «Не беспокоить» — все уведомления отключены.")
                                .font(.system(size: 13))
                                .foregroundStyle(V4.muted)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(V4.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(V4.accent.opacity(0.2)))
                    }

                    notifSection("Общие") {
                        notifToggle("moon.fill", "Не беспокоить", "Отключить все уведомления", Color(hex: 0x6366F1), $doNotDisturb, true)
                        notifToggle("bell.badge.fill", loc.string(.notifPush), "Системные push-уведомления", V4.accent, $pushNotifications, !doNotDisturb)
                        notifToggle("speaker.wave.2.fill", loc.string(.notifSounds), "Звук при входящих событиях", V4.accent, $notificationSounds, !doNotDisturb)
                    }

                    notifSection("Друзья") {
                        notifToggle("person.badge.plus", "Запросы в друзья", "Новые заявки", V4.accent, $friendRequests, !doNotDisturb)
                        notifToggle("envelope.fill", "Приглашения в комнаты", "Когда зовут смотреть вместе", V4.accent, $roomInvites, !doNotDisturb)
                        notifToggle("person.wave.2", "Друзья онлайн", "Когда друзья появляются в сети", V4.accent, $friendsOnline, !doNotDisturb)
                    }

                    notifSection("Комнаты") {
                        notifToggle("plus.circle.fill", "Новые комнаты", "Активность в публичных комнатах", V4.accent, $newRooms, !doNotDisturb)
                        notifToggle("at", "Упоминания", "Когда тебя упоминают в чате", V4.accent, $mentions, !doNotDisturb)
                    }

                    Text("Настройки хранятся на устройстве. Push доставляется через APNs.")
                        .font(.system(size: 11))
                        .foregroundStyle(V4.muted)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(V4.muted)
                        .frame(width: 32, height: 32)
                        .background(V4.surface.opacity(0.9), in: Circle())
                        .overlay(Circle().stroke(V4.line))
                }
                .buttonStyle(.plain)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func notifSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(1)
                .foregroundStyle(V4.muted)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(V4.surface.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(V4.line))
        }
    }

    private func notifToggle(
        _ icon: String,
        _ title: String,
        _ subtitle: String,
        _ color: Color,
        _ binding: Binding<Bool>,
        _ enabled: Bool
    ) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.16))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(enabled ? V4.ink : V4.muted)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(V4.muted)
            }
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(V4.accent)
                .disabled(!enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(enabled ? 1 : 0.55)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 58)
        }
    }
}
