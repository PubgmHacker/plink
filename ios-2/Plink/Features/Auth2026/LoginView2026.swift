//  Plink/Features/Auth2026/LoginView2026.swift
//  Auth 2026 redesign — «кинозал»: бархат + луч проектора, герой
//  «кадр в кадр», стеклянные капсулы-поля, сплошная teal-кнопка.
//  Один фирменный элемент на экран — луч проектора над логотипом.

import SwiftUI

struct LoginView2026: View {
    @EnvironmentObject private var apiClient: APIClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var isSignUp = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var appeared = false
    // Аудит 26.07.2026 P1: явное согласие с условиями при регистрации
    // (раньше было только в недостижимом RegistrationView2026).
    @State private var acceptsTerms = false

    @Namespace private var segmentNamespace

    var sessionMessage: String? = nil
    let onAuthenticated: () -> Void
    let onRegister: () -> Void

    private var spring: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)
    }

    private var canSubmit: Bool {
        // Аудит 26.07.2026 P1: регистрация — только с принятыми условиями.
        // Аудит 26.07.2026 P2: email триммится, а username сверяется с
        // серверным правилом — иначе запрос улетал и возвращался 400.
        trimmedEmail.contains("@") && password.count >= 6 && !isLoading
            && (!isSignUp || (acceptsTerms && usernameIssue == nil))
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
    }

    /// Серверная zod-схема signupBody: `^[A-Za-z][A-Za-z0-9_]{4,31}$`.
    private var usernameIssue: String? {
        let name = normalizedUsername
        guard name.count >= 5, name.count <= 32,
              let first = name.first, first.isASCII, first.isLetter,
              name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
        else {
            return "ИМЯ: 5–32 СИМВОЛА, С БУКВЫ, A–Z 0–9 _"
        }
        return nil
    }

    var body: some View {
        ZStack {
            // ═══ Бархат зала + луч проектора ═══
            ProjectorBeamBackground()

            ScrollView {
                VStack(spacing: 0) {
                    hero
                        .padding(.top, 38)
                        .padding(.bottom, 26)

                    modeSegment
                        .padding(.bottom, 22)

                    fields

                    notices

                    primaryButton
                        .padding(.top, 20)

                    LegalConsentFooter()
                        .padding(.top, 26)
                        .padding(.bottom, 40)
                }
                .frame(maxWidth: 430)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.65, dampingFraction: 0.85).delay(0.08)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: - Герой: логотип «кадр в кадр» + слоган

    private var hero: some View {
        VStack(spacing: 0) {
            PlinkFrameMark(size: 88)
                .padding(.bottom, 22)

            Text("PLINK")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .tracking(6.4)
                .foregroundStyle(PlinkTheatre.screen)
                .shadow(color: PlinkTheatre.tealDeep.opacity(0.18), radius: 18)
                .padding(.bottom, 14)

            Text("Твой экран. Твои люди. Один момент.")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PlinkTheatre.screen)
                .multilineTextAlignment(.center)

            Text("Видео, комнаты и реакции идут синхронно — где бы вы ни были.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PlinkTheatre.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 8)
                .frame(maxWidth: 320)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
    }

    // MARK: - Сегмент Вход / Регистрация

    private var modeSegment: some View {
        HStack(spacing: 0) {
            segmentButton(title: "Вход", signUp: false)
            segmentButton(title: "Регистрация", signUp: true)
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(PlinkTheatre.hairline, lineWidth: 1))
        .opacity(appeared ? 1 : 0)
    }

    private func segmentButton(title: String, signUp: Bool) -> some View {
        let selected = isSignUp == signUp
        return Button {
            // Аудит 26.07.2026 P2: во время запроса режим не переключаем —
            // иначе ответ приходил уже в другой ветке экрана.
            guard !selected, !isLoading else { return }
            HapticManager.selection()
            withAnimation(spring) {
                isSignUp = signUp
                errorMessage = nil
            }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? PlinkTheatre.teal : PlinkTheatre.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background {
                    if selected {
                        Capsule()
                            .fill(PlinkTheatre.teal.opacity(0.14))
                            .overlay(
                                Capsule().strokeBorder(PlinkTheatre.teal.opacity(0.45), lineWidth: 1)
                            )
                            .matchedGeometryEffect(id: "authSegment", in: segmentNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(signUp ? "auth.mode.signup" : "auth.mode.signin")
    }

    // MARK: - Поля: стеклянные капсулы

    private var fields: some View {
        VStack(spacing: 12) {
            AuthMonoTag(text: isSignUp ? "НОВЫЙ БИЛЕТ" : "ВХОД В ЗАЛ")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
                .padding(.bottom, 2)
                .id(isSignUp)

            if isSignUp {
                CompactAuthField(
                    title: "Имя пользователя",
                    text: $username,
                    icon: "person",
                    contentType: .username
                )
                .transition(fieldTransition)

                // Подсказку показываем и при пустом поле: имя обязательно, а без
                // неё кнопка «Создать аккаунт» выглядела заблокированной без причины.
                if let usernameIssue {
                    AuthMonoTag(text: usernameIssue)
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
                contentType: isSignUp ? .newPassword : .password,
                secure: true,
                submitLabel: .go,
                onSubmit: {
                    if canSubmit { Task { await authenticate() } }
                }
            )

            if isSignUp {
                AuthMonoTag(text: "МИНИМУМ 6 СИМВОЛОВ")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 6)
                    .transition(.opacity)

                // Аудит 26.07.2026 P1: тот же чекбокс, что в RegistrationView2026 —
                // без него кнопка «Создать аккаунт» неактивна.
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
                .transition(.opacity)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
    }

    private var fieldTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity
            )
    }

    // MARK: - Уведомления: янтарь, инлайн

    @ViewBuilder
    private var notices: some View {
        if let errorMessage {
            AuthInlineNotice(text: errorMessage)
                .padding(.top, 14)
                .transition(.opacity)
        } else if let sessionMessage {
            AuthInlineNotice(text: sessionMessage, icon: "clock.badge.exclamationmark")
                .padding(.top, 14)
        }
    }

    // MARK: - Главная кнопка: сплошной teal со свечением

    private var primaryButton: some View {
        Button {
            HapticManager.impact(.medium)
            Task { await authenticate() }
        } label: {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(PlinkTheatre.velvetDeep)
                } else {
                    Text(isSignUp ? "Создать аккаунт" : "Войти")
                }
            }
        }
        .buttonStyle(AuthPrimaryButtonStyle())
        .disabled(!canSubmit)
        .opacity(appeared ? 1 : 0)
        .accessibilityLabel(isSignUp ? "Создать аккаунт" : "Войти")
        .accessibilityIdentifier("auth.primary")
    }

    // MARK: - Auth Logic

    private func authenticate() async {
        guard !isLoading else { return }

        // Аудит 26.07.2026 P2: клиентская проверка до сети. Раньше запрос
        // уходил с непроверенными полями (пробелы в email, короткий username),
        // и пользователь получал 400 вместо понятной подсказки.
        let cleanEmail = trimmedEmail
        let cleanUsername = normalizedUsername
        guard cleanEmail.contains("@"), !password.isEmpty else {
            HapticManager.errorOccurred()
            withAnimation(spring) { errorMessage = "Введите email и пароль" }
            return
        }
        guard password.count >= 6 else {
            HapticManager.errorOccurred()
            withAnimation(spring) { errorMessage = "Пароль — минимум 6 символов" }
            return
        }
        if isSignUp {
            guard usernameIssue == nil else {
                HapticManager.errorOccurred()
                withAnimation(spring) {
                    errorMessage = "Имя пользователя: 5–32 символа, начинается с буквы, только A–Z, 0–9 и _"
                }
                return
            }
            guard acceptsTerms else {
                HapticManager.errorOccurred()
                withAnimation(spring) { errorMessage = "Примите Условия и Политику" }
                return
            }
        }

        isLoading = true
        errorMessage = nil

        do {
            let authService = AuthService.shared
            if isSignUp {
                _ = try await authService.signUp(
                    email: cleanEmail,
                    password: password,
                    username: cleanUsername
                )
            } else {
                _ = try await authService.signIn(email: cleanEmail, password: password)
            }
            HapticManager.notification(.success)
            onAuthenticated()
        } catch {
            HapticManager.errorOccurred()
            withAnimation(spring) {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
}
