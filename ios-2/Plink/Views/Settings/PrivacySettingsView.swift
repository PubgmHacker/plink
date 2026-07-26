import SwiftUI

// MARK: - Privacy Settings View (Premium)
/// 🔧 Pack v3: Убран NavigationStack (используется родительский из SettingsView).
struct PrivacySettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared

    // Persisted state (UserDefaults-backed)
    @AppStorage("privacy_profile_visible") private var profileVisibility = true
    @AppStorage("privacy_online_status") private var onlineStatus = true
    @AppStorage("privacy_read_receipts") private var readReceipts = true
    @AppStorage("privacy_show_in_search") private var showInSearch = true
    @AppStorage("privacy_allow_dm_from") private var allowDMFrom = "everyone"
    @AppStorage("privacy_allow_invites_from") private var allowInvitesFrom = "everyone"

    var body: some View {
        ZStack {
            Cinema2026.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // ── Visibility Section ──
                    VStack(alignment: .leading, spacing: 6) {
                        PlinkSectionHeader(text: "Видимость")
                        PlinkSettingsCard {
                            PlinkToggleRow(
                                icon: "eye.fill",
                                title: loc.string(.privacyProfileVisibility),
                                subtitle: loc.string(.privacyProfileVisibilitySubtitle),
                                iconColor: Cinema2026.accent,
                                isOn: $profileVisibility
                            )
                            PlinkToggleRow(
                                icon: "circle.fill",
                                title: loc.string(.privacyOnlineStatus),
                                subtitle: loc.string(.privacyOnlineStatusSubtitle),
                                iconColor: Cinema2026.accent,
                                isOn: $onlineStatus
                            )
                            PlinkToggleRow(
                                icon: "magnifyingglass",
                                title: "Показывать в поиске",
                                subtitle: "Другие пользователи могут найти вас по имени",
                                iconColor: Cinema2026.accent,
                                isOn: $showInSearch
                            )
                        }
                    }

                    // ── Messages & Invites Section ──
                    VStack(alignment: .leading, spacing: 6) {
                        PlinkSectionHeader(text: "Сообщения и приглашения")
                        PlinkSettingsCard {
                            PlinkToggleRow(
                                icon: "checkmark.circle.fill",
                                title: loc.string(.privacyReadReceipts),
                                subtitle: loc.string(.privacyReadReceiptsSubtitle),
                                iconColor: Cinema2026.accent,
                                isOn: $readReceipts
                            )
                            privacyPickerRow(
                                icon: "envelope.fill",
                                title: "Кто может писать ЛС",
                                subtitle: "Получать личные сообщения от",
                                value: $allowDMFrom,
                                options: [("everyone", "Все"), ("friends", "Только друзья"), ("nobody", "Никто")]
                            )
                            privacyPickerRow(
                                icon: "rectangle.stack.fill.badge.plus",
                                title: "Кто может звать в комнаты",
                                subtitle: "Приглашения в совместный просмотр",
                                value: $allowInvitesFrom,
                                options: [("everyone", "Все"), ("friends", "Только друзья"), ("nobody", "Никто")]
                            )
                        }
                    }

                    // ── Data Section ──
                    VStack(alignment: .leading, spacing: 6) {
                        PlinkSectionHeader(text: "Данные")
                        PlinkSettingsCard {
                            Button {
                                clearCache()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                        .frame(width: 28, height: 28)
                                        .background(Cinema2026.danger.opacity(0.18))
                                        .clipShape(RoundedRectangle(cornerRadius: 7))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(loc.string(.privacyClearCache))
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(Cinema2026.text)
                                        Text(loc.string(.privacyClearCacheSubtitle))
                                            .font(.system(size: 12))
                                            .foregroundColor(Cinema2026.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Cinema2026.tertiary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // ── Info Footer ──
                    Text(loc.string(.privacyInfo))
                        .font(.system(size: 11))
                        .foregroundColor(Cinema2026.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Конфиденциальность")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    // MARK: - Privacy Picker Row

    @ViewBuilder
    private func privacyPickerRow(
        icon: String,
        title: String,
        subtitle: String,
        value: Binding<String>,
        options: [(String, String)]
    ) -> some View {
        Menu {
            ForEach(options, id: \.0) { option in
                Button {
                    value.wrappedValue = option.0
                } label: {
                    if value.wrappedValue == option.0 {
                        Label(option.1, systemImage: "checkmark")
                    } else {
                        Text(option.1)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Cinema2026.accent.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Cinema2026.text)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Cinema2026.secondary)
                }

                Spacer()

                Text(options.first(where: { $0.0 == value.wrappedValue })?.1 ?? "")
                    .font(.system(size: 14))
                    .foregroundColor(Cinema2026.accent)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Cinema2026.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func clearCache() {
        HapticManager.impact(.medium)
        URLCache.shared.removeAllCachedResponses()
        let tempDir = FileManager.default.temporaryDirectory
        try? FileManager.default.removeItem(at: tempDir)
    }
}
