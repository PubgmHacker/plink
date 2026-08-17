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
            subtitle: "Войдите один раз. Сессия остаётся на этом iPhone — в комнате не придётся логиниться снова."
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
                    .foregroundStyle(connected ? V4.accent : V4.muted)
            }
            Spacer()
            Button {
                if connected {
                    account.disconnect()
                    tick += 1
                } else {
                    connecting = account
                }
            } label: {
                Text(connected ? "Отключить" : "Войти")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(connected ? V4.danger : V4.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(connected ? "Отключить \(account.title)" : "Войти в \(account.title)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 58)
        }
    }
}

private struct CinemaAccountLoginSheet: View {
    let account: LinkedExternalAccount
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var currentURL: URL?
    @State private var pageTitle = ""
    @State private var canGoBack = false
    @State private var canGoForward = false

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
                    Button("Я вошёл") {
                        onDone()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
