import SwiftUI

// MARK: - Настройки уведомлений
//
// Экран собран на общем каркасе настроек (SettingsScaffold + SettingsCard +
// SettingsToggleRow из PlinkProfileRows): раньше он носил собственный
// сине-серый градиент и плоские карточки — при переходе из «Общих настроек»
// палитра заметно менялась. Теперь фон, карточки, строки и переключатели —
// побайтово те же, что в «Приватности» и «Воспроизведении».

struct NotificationsView: View {
    @ObservedObject private var loc = LocalizationManager.shared

    @AppStorage("notif_push_enabled") private var pushNotifications = true
    @AppStorage("notif_sounds_enabled") private var notificationSounds = true
    @AppStorage("notif_friends_online") private var friendsOnline = false
    @AppStorage("notif_new_rooms") private var newRooms = true
    @AppStorage("notif_friend_requests") private var friendRequests = true
    @AppStorage("notif_room_invites") private var roomInvites = true
    @AppStorage("notif_mentions") private var mentions = true
    @AppStorage("notif_do_not_disturb") private var doNotDisturb = false

    var body: some View {
        SettingsScaffold(
            title: "Уведомления",
            subtitle: "Push, звуки и события от друзей",
            eyebrow: "Общие настройки"
        ) {
            if doNotDisturb {
                infoBanner(
                    icon: "moon.fill",
                    text: "Режим «Не беспокоить» — все уведомления отключены."
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Общие")
                SettingsCard {
                    SettingsToggleRow(
                        icon: "moon.fill",
                        title: "Не беспокоить",
                        subtitle: "Отключить все уведомления",
                        iconColor: Color(hex: 0x6366F1),
                        isOn: $doNotDisturb
                    )
                    SettingsToggleRow(
                        icon: "bell.badge.fill",
                        title: loc.string(.notifPush),
                        subtitle: "Системные push-уведомления",
                        isOn: $pushNotifications,
                        enabled: !doNotDisturb
                    )
                    SettingsToggleRow(
                        icon: "speaker.wave.2.fill",
                        title: loc.string(.notifSounds),
                        subtitle: "Звук при входящих событиях",
                        isOn: $notificationSounds,
                        enabled: !doNotDisturb
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Друзья")
                SettingsCard {
                    SettingsToggleRow(
                        icon: "person.badge.plus",
                        title: "Запросы в друзья",
                        subtitle: "Новые заявки",
                        isOn: $friendRequests,
                        enabled: !doNotDisturb
                    )
                    SettingsToggleRow(
                        icon: "envelope.fill",
                        title: "Приглашения в комнаты",
                        subtitle: "Когда зовут смотреть вместе",
                        isOn: $roomInvites,
                        enabled: !doNotDisturb
                    )
                    SettingsToggleRow(
                        icon: "person.wave.2",
                        title: "Друзья онлайн",
                        subtitle: "Когда друзья появляются в сети",
                        iconColor: Color(hex: 0x22C55E),
                        isOn: $friendsOnline,
                        enabled: !doNotDisturb
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Комнаты")
                SettingsCard {
                    SettingsToggleRow(
                        icon: "plus.circle.fill",
                        title: "Новые комнаты",
                        subtitle: "Активность в публичных комнатах",
                        isOn: $newRooms,
                        enabled: !doNotDisturb
                    )
                    SettingsToggleRow(
                        icon: "at",
                        title: "Упоминания",
                        subtitle: "Когда вас упоминают в чате",
                        isOn: $mentions,
                        enabled: !doNotDisturb
                    )
                }
            }

            Text("Настройки хранятся на устройстве. Push доставляется через APNs.")
                .font(.system(size: 11))
                .foregroundStyle(V4.muted)
                .padding(.top, 4)
        }
    }
}
