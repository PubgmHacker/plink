// Plink/Views/Settings/SettingsView.swift — simplified, no V4 deps
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let authService: AuthService

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    // Account
                    settingsGroup("Аккаунт") {
                        settingsRow("person.crop.circle", "Личные данные")
                        settingsRow("lock.shield", "Приватность")
                        settingsRow("person.crop.circle.badge.xmark", "Заблокированные")
                    }
                    // Connected services (NEW M11)
                    settingsGroup("Подключённые сервисы") {
                        NavigationLink(destination: ConnectedServicesSettingsView()) {
                            HStack(spacing: 12) {
                                Image(systemName: "play.rectangle.on.rectangle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Cinema2026.accent)
                                    .frame(width: 28)
                                Text("Кинотеатры и сервисы")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Cinema2026.text)
                                Spacer()
                                // Count badge
                                let authorized = ServiceType.allCases.filter { $0.requiresAuth && ServiceAuthStore.hasAccess(to: $0) }.count
                                if authorized > 0 {
                                    Text("\(authorized)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Cinema2026.accent, in: Capsule())
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Cinema2026.secondary)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                    }
                    // App
                    settingsGroup("Приложение") {
                        settingsRow("circle.lefthalf.filled", "Оформление")
                        settingsRow("bell", "Уведомления")
                        settingsRow("play.rectangle", "Воспроизведение")
                        settingsRow("globe", "Язык")
                    }
                    // Subscription
                    settingsGroup("Подписка") {
                        settingsRow("crown.fill", "Plink+ статус")
                    }
                    // Support
                    settingsGroup("Поддержка") {
                        settingsRow("questionmark.circle", "Помощь")
                        settingsRow("doc.text", "Условия использования")
                        settingsRow("shield", "Политика конфиденциальности")
                    }
                    // Danger
                    settingsGroup("Аккаунт") {
                        settingsRow("trash", "Удалить аккаунт", isDestructive: true)
                    }
                    Text("Plink v1.0")
                        .font(.system(size: 12))
                        .foregroundStyle(Cinema2026.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Готово") { dismiss() } } }
        }
    }

    private func settingsGroup(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Cinema2026.secondary).padding(.horizontal, 4)
            VStack(spacing: 0) { content() }
                .background(Cinema2026.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func settingsRow(_ icon: String, _ title: String, isDestructive: Bool = false) -> some View {
        Button {} label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isDestructive ? Cinema2026.danger : Cinema2026.accent)
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(isDestructive ? Cinema2026.danger : Cinema2026.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Cinema2026.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
        }
        .buttonStyle(.plain)
    }
}
