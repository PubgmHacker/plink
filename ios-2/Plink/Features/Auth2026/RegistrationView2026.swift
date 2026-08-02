// Plink/Features/Auth2026/RegistrationView2026.swift
// Focused account creation: one route, plain-language validation, one consent.

import SwiftUI

struct RegistrationView2026: View {
    @State private var displayName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var acceptsTerms = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    let onRegistered: () -> Void
    let onLogin: () -> Void

    private var cleanUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
    }

    private var usernameIsValid: Bool {
        cleanUsername.count >= 5 && cleanUsername.count <= 32 &&
        cleanUsername.first.map { $0.isASCII && $0.isLetter } == true &&
        cleanUsername.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    private var canRegister: Bool {
        // Display name is optional: the backend accepts username/email/password,
        // and the profile name can be filled after registration.
        usernameIsValid &&
        email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@") &&
        password.count >= 6 &&
        acceptsTerms &&
        !isLoading
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            registrationBackdrop

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 64)
                        .padding(.bottom, 32)

                    VStack(spacing: 13) {
                        if let errorMessage {
                            AuthInlineNotice(text: errorMessage)
                                .transition(.opacity)
                        }

                        CompactAuthField(
                            title: "Как вас называть",
                            text: $displayName,
                            icon: "person",
                            contentType: .name,
                            capitalization: .words
                        )

                        CompactAuthField(
                            title: "Имя пользователя",
                            text: $username,
                            icon: "at",
                            contentType: .username
                        )

                        if !username.isEmpty && !usernameIsValid {
                            Text("5–32 символа, первая — буква; можно использовать A–Z, 0–9 и _")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(PlinkTheatre.amber)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                        }

                        CompactAuthField(
                            title: "Email",
                            text: $email,
                            icon: "envelope",
                            contentType: .emailAddress,
                            keyboard: .emailAddress
                        )

                        CompactAuthField(
                            title: "Пароль — не меньше 6 символов",
                            text: $password,
                            icon: "lock",
                            contentType: .newPassword,
                            secure: true,
                            submitLabel: .done,
                            onSubmit: {
                                if canRegister { Task { await register() } }
                            }
                        )

                        consent
                            .padding(.top, 2)

                        Button {
                            HapticManager.impact(.medium)
                            Task { await register() }
                        } label: {
                            ZStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Создать аккаунт")
                                }
                            }
                        }
                        .buttonStyle(AuthPrimaryButtonStyle())
                        .disabled(!canRegister)
                        .padding(.top, 6)
                        .accessibilityIdentifier("auth.register")

                        Button("Уже есть аккаунт? Войти") {
                            HapticManager.selection()
                            onLogin()
                        }
                        .buttonStyle(AuthProviderButtonStyle())
                        .disabled(isLoading)
                    }
                    .frame(maxWidth: 410)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)

            Button {
                HapticManager.selection()
                onLogin()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .plinkGlass(.control, in: Circle())
                    .overlay(Circle().stroke(PlinkTheatre.hairline))
            }
            .buttonStyle(.plain)
            .padding(.leading, 18)
            .padding(.top, 12)
            .accessibilityLabel("Вернуться ко входу")
        }
        .preferredColorScheme(.dark)
    }

    private var registrationBackdrop: some View {
        ZStack {
            Color(red: 0.018, green: 0.025, blue: 0.045)
            RadialGradient(
                colors: [Color(red: 0.08, green: 0.29, blue: 0.78).opacity(0.52), .clear],
                center: UnitPoint(x: 0.08, y: 0.0),
                startRadius: 0,
                endRadius: 520
            )
            LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 0) {
            PlinkFrameMark(size: 66)
                .padding(.bottom, 18)
            Text("Присоединяйтесь к просмотру")
                .font(.system(size: 28, weight: .black))
                .tracking(-0.8)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Создайте профиль — это займёт меньше минуты.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PlinkTheatre.muted)
                .padding(.top, 8)
        }
        .padding(.horizontal, 24)
    }

    private var consent: some View {
        Button {
            acceptsTerms.toggle()
            HapticManager.selection()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: acceptsTerms ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(acceptsTerms ? PlinkTheatre.tealDeep : PlinkTheatre.muted)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Я принимаю правила Plink")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Text("Условия")
                        Text("и")
                        Text("Политику конфиденциальности")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PlinkTheatre.muted)
                }
                .padding(.top, 5)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("auth.consent")
        .accessibilityLabel("Принять условия")
        .accessibilityValue(acceptsTerms ? "Принято" : "Не принято")
        .accessibilityAddTraits(acceptsTerms ? [.isSelected] : [])
    }

    private func register() async {
        guard !isLoading else { return }
        guard canRegister else {
            errorMessage = "Проверьте поля и примите правила Plink"
            HapticManager.errorOccurred()
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let authService = AuthService.shared
            Logger.api.info("[AuthUI] signUp started username=\(cleanUsername) email=\(cleanEmail)")
            _ = try await authService.signUp(email: cleanEmail, password: password, username: cleanUsername)
            Logger.api.info("[AuthUI] signUp succeeded user=\(authService.currentUserValue?.id ?? "nil") token=\(authService.authToken != nil)")
            if !cleanName.isEmpty {
                _ = try? await authService.updateProfile(displayName: cleanName)
            }
            APIClient.shared.authToken = authService.authToken
            HapticManager.notification(.success)
            // Always hop back to the main actor after the async auth request.
            // SwiftUI state transitions must not be scheduled from the URLSession
            // continuation's executor.
            await MainActor.run {
                onRegistered()
            }
        } catch {
            Logger.api.error("[AuthUI] signUp failed: \(error.localizedDescription)")
            HapticManager.errorOccurred()
            errorMessage = AuthErrorCopy.message(for: error)
        }
    }
}
