// Plink/Features/Auth2026/RegistrationView2026.swift — §8 Final Unified
//
// Registration with clean background (no posters). Compact living backdrop only.

import SwiftUI

struct RegistrationView2026: View {
    @EnvironmentObject private var apiClient: APIClient
    @State private var displayName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var acceptsTerms = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    let onRegistered: () -> Void
    let onLogin: () -> Void

    private var canRegister: Bool {
        !displayName.isEmpty &&
        username.count >= 3 &&
        email.contains("@") &&
        password.count >= 6 &&
        acceptsTerms
    }

    private var passwordIssues: [String] {
        var issues: [String] = []
        if password.count < 6 { issues.append("Минимум 6 символов") }
        if !password.contains(where: { $0.isNumber }) { issues.append("Минимум 1 цифра") }
        return issues
    }

    var body: some View {
        // PATCH: posters visible at top, but form has solid surface card
        // so fields are readable. Best of both worlds.
        ZStack {
            Cinema2026.background.ignoresSafeArea()

            // Poster mosaic at top — same as login but shorter
            VStack(spacing: 0) {
                AnimatedPosterMosaic()
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 0))

                Spacer()
            }

            // Scrollable form with semi-opaque surface card
            ScrollView {
                VStack(spacing: 14) {
                    // Title overlaps poster bottom
                    // Plink branding
                    VStack(spacing: 4) {
                        Text("Plink")
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundStyle(Cinema2026.text)
                        Text("Создать аккаунт")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Cinema2026.secondary)
                    }
                    .padding(.top, 10)
                    .shadow(color: Cinema2026.background.opacity(0.8), radius: 8)

                    // Form card — solid surface, readable
                    VStack(spacing: 12) {
                        CompactAuthField(title: "Имя", text: $displayName, contentType: .name)
                        CompactAuthField(title: "Username", text: $username, contentType: .username)
                        CompactAuthField(title: "Email", text: $email, contentType: .emailAddress)
                        CompactAuthField(title: "Пароль", text: $password, contentType: .newPassword, secure: true)

                        if !passwordIssues.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(passwordIssues, id: \.self) { issue in
                                    HStack(spacing: 4) {
                                        Image(systemName: "circle")
                                            .font(.system(size: 8))
                                        Text(issue)
                                            .font(.system(size: 11))
                                    }
                                    .foregroundStyle(Cinema2026.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Toggle(isOn: $acceptsTerms) {
                            Text("Принимаю Условия и Политику")
                                .font(.caption)
                                .foregroundStyle(Cinema2026.secondary)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Cinema2026.danger)
                        }

                        Button {
                            Task { await register() }
                        } label: {
                            HStack {
                                if isLoading { ProgressView().tint(Cinema2026.background) }
                                Text("Создать аккаунт")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(Cinema2026.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: CompactPhoneMetrics.primaryButtonHeight)
                            .background(
                                (canRegister && !isLoading) ? Cinema2026.accent : Cinema2026.accent.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .disabled(!canRegister || isLoading)
                        .accessibilityLabel("Создать аккаунт")

                        HStack(spacing: 4) {
                            Text("Уже есть аккаунт?")
                                .foregroundStyle(Cinema2026.secondary)
                            Button("Войти", action: onLogin)
                                .fontWeight(.semibold)
                                .foregroundStyle(Cinema2026.accent)
                        }
                        .font(.footnote)

                        LegalConsentFooter()
                            .padding(.top, 4)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Cinema2026.surface.opacity(0.96))
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
                .padding(.top, 180) // overlap poster mosaic
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Cinema2026.text)
    }

    private func register() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Always use shared AuthService so session is visible app-wide
        let authService = AuthService.shared
        // Prefer EnvironmentObject client if token plumbing differs
        if APIClient.shared.authToken == nil {
            // leave nil until signup returns token
        }

        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard canRegister else {
            errorMessage = "Заполни все поля и прими условия"
            return
        }

        do {
            _ = try await authService.signUp(
                email: cleanEmail,
                password: password,
                username: cleanUsername.isEmpty ? cleanEmail.split(separator: "@").first.map(String.init) ?? "user" : cleanUsername
            )
            // Save display name after signup (optional, best-effort)
            if !cleanName.isEmpty {
                _ = try? await authService.updateProfile(displayName: cleanName)
            }
            if let token = authService.authToken {
                APIClient.shared.authToken = token
            }
            HapticManager.impact(.medium)
            await MainActor.run {
                onRegistered()
            }
        } catch {
            errorMessage = error.localizedDescription.isEmpty
                ? "Ошибка регистрации. Попробуйте другой username или email."
                : error.localizedDescription
            HapticManager.errorOccurred()
        }
    }
}
