
// Plink/Views/Settings/ConnectedServicesSettingsView.swift
// M11: Manage saved logins for cinema services

import SwiftUI

struct ConnectedServicesSettingsView: View {
    @State private var refresh = false  // trigger re-render after logout

    private var cinemaServices: [VideoService] {
        VideoService.allCases.filter { $0.serviceType.requiresAuth }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Info banner
                HStack(spacing: 14) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Cinema2026.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Как это работает?")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Cinema2026.text)
                        Text("Войдите в кинотеатр один раз. Сессия сохраняется и при следующем создании комнаты входить заново не нужно.")
                            .font(.system(size: 12))
                            .foregroundStyle(Cinema2026.secondary)
                    }
                }
                .padding(16)
                .background(Cinema2026.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)

                // Service rows
                VStack(spacing: 0) {
                    ForEach(cinemaServices, id: \.self) { svc in
                        ConnectedServiceRow(service: svc, refresh: $refresh)
                        if svc != cinemaServices.last {
                            Divider()
                                .background(Cinema2026.surface)
                                .padding(.leading, 70)
                        }
                    }
                }
                .background(Cinema2026.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 20)
        }
        .background(Cinema2026.bg.ignoresSafeArea())
        .navigationTitle("Подключённые сервисы")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ConnectedServiceRow: View {
    let service: VideoService
    @Binding var refresh: Bool
    @State private var showAuth = false

    private var isAuthorized: Bool {
        ServiceAuthStore.hasAccess(to: service.serviceType)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Logo
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(service.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                ServiceLogoView(service: service, size: 34)
            }

            // Name + status
            VStack(alignment: .leading, spacing: 3) {
                Text(service.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                HStack(spacing: 5) {
                    Circle()
                        .fill(isAuthorized ? Color.green : Cinema2026.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(isAuthorized ? "Вход выполнен" : "Не авторизован")
                        .font(.system(size: 12))
                        .foregroundStyle(isAuthorized ? .green : Cinema2026.secondary)
                }
            }

            Spacer()

            // Action button
            if isAuthorized {
                Button("Выйти") {
                    ServiceAuthStore.logout(service.serviceType)
                    refresh.toggle()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Cinema2026.danger)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Cinema2026.danger.opacity(0.12), in: Capsule())
            } else {
                Button("Войти") {
                    showAuth = true
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Cinema2026.accent, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .sheet(isPresented: $showAuth) {
            ServiceAuthSheet(service: service) {
                ServiceAuthStore.markAuthorized(service.serviceType)
                refresh.toggle()
                showAuth = false
            }
        }
    }
}
