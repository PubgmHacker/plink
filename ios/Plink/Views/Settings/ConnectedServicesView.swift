import SwiftUI
import WebKit

/// Профиль → Кинотеатры: Яндекс ID и подписки кинотеатров.
/// Cookies живут в `CinemaSessionStore` — повторный логин на Кинопоиске не нужен.
struct ConnectedServicesView: View {
    @State private var connecting: LinkedExternalAccount?
    @State private var tick = 0

    var body: some View {
        SettingsScaffold(
            title: "Кинотеатры",
            subtitle: "Войдите один раз. Сессия остаётся на этом iPhone — в комнате не придётся логиниться снова.",
            eyebrow: "Данные и доступ"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Яндекс")
                SettingsCard {
                    accountRow(.yandex)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Кинотеатры")
                SettingsCard {
                    ForEach(LinkedExternalAccount.allCases.filter { $0 != .yandex }) { account in
                        accountRow(account)
                    }
                }
            }
        }
        .id(tick)
        .task {
            // Протухшая сессия больше не показывается как «Подключён».
            if !(await LinkedExternalAccount.revalidateConnected()).isEmpty { tick += 1 }
        }
        .sheet(item: $connecting) { account in
            CinemaAccountLoginSheet(account: account) {
                account.markConnected()
                connecting = nil
                tick += 1
            }
        }
    }

    private func accountRow(_ account: LinkedExternalAccount) -> some View {
        let connected = account.isConnected
        let accent = V4Theme.saved.accentColor
        return HStack(spacing: 12) {
            if let svc = account.videoService {
                ServiceLogoView(service: svc, size: 22)
                    .frame(width: 32, height: 32)
                    .background(svc.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            } else {
                SettingsIconBadge(systemName: account.symbol, color: Color(hex: 0xFC3F1D))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(account.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(V4.ink)
                Text(connected ? "Подключён" : "Не подключён")
                    .font(.system(size: 12))
                    .foregroundStyle(connected ? accent : V4.muted)
            }
            Spacer()
            Button {
                HapticManager.selection()
                if connected {
                    account.disconnect()
                    tick += 1
                } else {
                    connecting = account
                }
            } label: {
                Text(connected ? "Отключить" : "Войти")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(connected ? V4.danger : accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(connected ? "Отключить \(account.title)" : "Войти в \(account.title)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Разделители между строками рисует SettingsCard — свой оверлей
        // оставлял линию и под последней строкой карты.
    }
}

/// Вход в сервис настоящей страницей самого сервиса.
/// Используется и профилем, и мастером комнаты, и подсказкой в комнате.
struct CinemaAccountLoginSheet: View {
    let account: LinkedExternalAccount
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var currentURL: URL?
    @State private var pageTitle = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var noSessionYet = false

    var body: some View {
        NavigationStack {
            ServiceWebView(
                initialURL: account.loginURL,
                currentURL: $currentURL,
                pageTitle: $pageTitle,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                persistCookies: true
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(account.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        // Кнопка не «верит на слово»: сессия засчитывается,
                        // только если сервис реально поставил куки.
                        Task {
                            let signedIn = await CinemaSessionStore.hasCookies(forHosts: account.cookieHosts)
                            await MainActor.run {
                                if signedIn {
                                    onDone()
                                    dismiss()
                                } else {
                                    noSessionYet = true
                                }
                            }
                        }
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("Вход не завершён", isPresented: $noSessionYet) {
            Button("Продолжить вход", role: .cancel) {}
        } message: {
            Text("\(account.title) ещё не открыл сессию на этом iPhone. Войдите на странице сервиса и нажмите «Готово».")
        }
    }
}
