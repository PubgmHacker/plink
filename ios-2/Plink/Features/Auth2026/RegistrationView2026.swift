// Plink/Features/Auth2026/RegistrationView2026.swift — Auth 2026 redesign
//
// Регистрация в языке «кинозал»: бархат + луч проектора, компактный
// «кадр в кадр», стеклянные капсулы-поля, teal-CTA, янтарные ошибки.

import SwiftUI

struct RegistrationView2026: View {
    @EnvironmentObject private var apiClient: APIClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var displayName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var acceptsTerms = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    let onRegistered: () -> Void
    let onLogin: () -> Void

    private var spring: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)
    }

    private var canRegister: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        usernameIssues.isEmpty &&
        email.contains("@") &&
        passwordIssues.isEmpty &&
        acceptsTerms
    }

    /// Аудит 26.07.2026 P2: чек-лист и `canRegister` разъезжались — пункт
    /// «МИНИМУМ 1 ЦИФРА» горел, а кнопка была активна. Требования сведены
    /// к серверной zod-схеме (signupBody: password min 6, цифра не нужна).
    private var passwordIssues: [String] {
        var issues: [String] = []
        if password.count < 6 { issues.append("МИНИМУМ 6 СИМВОЛОВ") }
        return issues
    }

    /// Username по серверному правилу: `^[A-Za-z][A-Za-z0-9_]{4,31}$`.
    /// Раньше клиент пускал 3 символа и точки — сервер отвечал 400 уже
    /// после нажатия кнопки.
    private var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
    }

    private var usernameIssues: [String] {
        let name = normalizedUsername
        var issues: [String] = []
        if name.count < 5 || name.count > 32 { issues.append("USERNAME: 5–32 СИМВОЛА") }
        if let first = name.first, !(first.isASCII && first.isLetter) {
            issues.append("USERNAME НАЧИНАЕТСЯ С БУКВЫ")
        }
        if name.contains(where: { !($0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_")) }) {
            issues.append("USERNAME: A–Z, 0–9, _")
        }
        return issues
    }

    var body: some View {
        ZStack {
            // ═══ Бархат зала + луч проектора ═══
            ProjectorBeamBackground()

            ScrollView {
                VStack(spacing: 0) {
                    // ── Герой: компактный «кадр в кадр» ──
                    PlinkFrameMark(size: 56)
                        .padding(.top, 36)
                        .padding(.bottom, 16)

                    Text("Создать аккаунт")
                        .font(.system(size: 26, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(PlinkTheatre.screen)
                        .padding(.bottom, 8)

                    AuthMonoTag(text: "НОВЫЙ БИЛЕТ · PLINK")
                        .padding(.bottom, 28)

                    // ── Поля ──
                    VStack(spacing: 12) {
                        CompactAuthField(
                            title: "Имя",
                            text: $displayName,
                            icon: "person",
                            contentType: .name,
                            capitalization: .words
                        )
                        // Group — чтобы не выйти за 10 вьюх ViewBuilder'а VStack.
                        Group {
                            CompactAuthField(
                                title: "Username",
                                text: $username,
                                icon: "at",
                                contentType: .username
                            )

                            // Подсказку показываем и при пустом поле: username
                            // обязателен, иначе кнопка неактивна без объяснений.
                            if !usernameIssues.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(usernameIssues, id: \.self) { issue in
                                        AuthMonoTag(text: issue)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 6)
                                .transition(.opacity)
                            }
                        }

                        CompactAuthField(
                            title: "Email",
                            text: $email,
                            icon: "envelope",
                            contentType: .emailAddress,
                            keyboard: .emailAddress
                        )
                        CompactAuthField(
                            title: "Пароль",
                            text: $password,
                            icon: "lock",
                            contentType: .newPassword,
                            secure: true,
                            submitLabel: .done
                        )

                        if !password.isEmpty && !passwordIssues.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(passwordIssues, id: \.self) { issue in
                                    AuthMonoTag(text: issue)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 6)
                            .transition(.opacity)
                        }

                        Toggle(isOn: $acceptsTerms) {
                            Text("Принимаю Условия и Политику")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(PlinkTheatre.muted)
                        }
                        .tint(PlinkTheatre.tealDeep)
                        .padding(.horizontal, 6)
                        .padding(.top, 4)
                        .onChange(of: acceptsTerms) { _, _ in
                            HapticManager.selection()
                        }

                        if let errorMessage {
                            AuthInlineNotice(text: errorMessage)
                                .transition(.opacity)
                        }

                        // ── Главная кнопка: сплошной teal ──
                        Button {
                            HapticManager.impact(.medium)
                            Task { await register() }
                        } label: {
                            ZStack {
                                if isLoading {
                                    ProgressView()
                                        .tint(PlinkTheatre.velvetDeep)
                                } else {
                                    Text("Создать аккаунт")
                                }
                            }
                        }
                        .buttonStyle(AuthPrimaryButtonStyle())
                        .disabled(!canRegister || isLoading)
                        .padding(.top, 8)
                        .accessibilityLabel("Создать аккаунт")

                        // ── Вторичная: стеклянная ──
                        Button {
                            HapticManager.selection()
                            onLogin()
                        } label: {
                            Text("У меня уже есть аккаунт")
                        }
                        .buttonStyle(AuthProviderButtonStyle())
                        // Пока идёт регистрация — уйти на вход нельзя,
                        // иначе ответ приходит в уже закрытый экран.
                        .disabled(isLoading)

                        LegalConsentFooter()
                            .padding(.top, 10)
                    }
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: 430)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .animation(spring, value: passwordIssues)
        .animation(spring, value: usernameIssues)
        .animation(spring, value: errorMessage)
    }

    private func register() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Всегда через общий AuthService — сессия видна всему приложению.
        let authService = AuthService.shared

        let cleanUsername = normalizedUsername
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard canRegister else {
            errorMessage = "Заполни все поля и прими условия"
            return
        }

        do {
            // cleanUsername уже прошёл проверку canRegister (серверное правило),
            // поэтому подстановка из email больше не нужна — она давала
            // невалидные имена вроде «ab» и 400 от сервера.
            _ = try await authService.signUp(
                email: cleanEmail,
                password: password,
                username: cleanUsername
            )
            // Имя профиля — best-effort после регистрации.
            if !cleanName.isEmpty {
                _ = try? await authService.updateProfile(displayName: cleanName)
            }
            if let token = authService.authToken {
                APIClient.shared.authToken = token
            }
            HapticManager.notification(.success)
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
