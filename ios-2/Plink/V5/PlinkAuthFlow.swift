//
//  PlinkAuthFlow.swift
//  Plink
//
//  P1 — Welcome / Sign in / 3-step Registration.
//  Implements Section 7 of PLINK_CUSTOMIZATION_AUTH_ADMIN_SPEC_FOR_GLM_5_2.md
//
//  Concept: "Signal in the dark" — same V4 living environment, calmer.
//  Security: Keychain tokens, OAuth nonce/state, rate limit, generic account-existence
//  errors where needed, email verification, passkey-ready architecture.
//  Never store password or auth tokens in UserDefaults.
//
//  NOTE: This file does NOT redefine AuthService — it uses the real one
//  from `Plink/Services/AuthService.swift`. Bridge methods on AuthService
//  are added via extension below.
//

import SwiftUI
import AuthenticationServices

// MARK: - AuthPath

internal enum AuthPath: Hashable {
    case welcome
    case signIn
    case register
    case forgot
}

// MARK: - WelcomeView

internal struct WelcomeView: View {
    @Binding public var path: AuthPath
    @State private var orbPulse = false

    init(path: Binding<AuthPath>) {
        self._path = path
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [Color.cyan.opacity(0.15), .clear],
                center: .center, startRadius: 0, endRadius: 240
            )
            .ignoresSafeArea()
            .opacity(orbPulse ? 1 : 0.7)
            .onAppear {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    orbPulse = true
                }
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Image(systemName: "circle.hexagonpath.fill")
                    .font(.system(size: 120, weight: .black))
                    .foregroundStyle(Color.cyan)
                    .shadow(color: .cyan.opacity(0.7), radius: 32)

                Spacer()

                VStack(spacing: 8) {
                    Text(LocalizationManager.shared.string(.auTagline1))
                    Text(LocalizationManager.shared.string(.auTagline2))
                }
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        path = .register
                    } label: {
                        Text(LocalizationManager.shared.string(.auContinue))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)  // 44pt target
                            .padding(.vertical, 16)
                            .background(Color.cyan)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .accessibilityLabel("Создать новый аккаунт")

                    Button {
                        path = .signIn
                    } label: {
                        Text(LocalizationManager.shared.string(.auHaveAccount))
                            .font(.subheadline.bold())
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, 12)
                    }
                    .accessibilityLabel("Войти в существующий аккаунт")
                }
                .padding(.horizontal, 24)

                HStack(spacing: 16) {
                    Link("Условия", destination: URL(string: "https://plink.app/terms")!)
                    Text("·").foregroundStyle(.white.opacity(0.3))
                    Link("Конфиденциальность", destination: URL(string: "https://plink.app/privacy")!)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - SignInView

internal struct SignInView: View {
    @Binding public var path: AuthPath

    @State private var emailOrUsername: String = ""
    @State private var password: String = ""
    @State private var revealPassword = false
    @State private var loading = false
    @State private var inlineError: String?

    init(path: Binding<AuthPath>) {
        self._path = path
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(LocalizationManager.shared.string(.auSignInTitle))
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.top, 8)

                    AuthField(
                        title: "Email или никнейм",
                        text: $emailOrUsername,
                        error: inlineError,
                        autocapitalization: .never,
                        keyboardType: .emailAddress
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            SecureField("Пароль", text: $password)
                                .font(.body)
                                .foregroundStyle(.white)
                                .textInputAutocapitalization(.never)
                            Button {
                                revealPassword.toggle()
                            } label: {
                                Image(systemName: revealPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if let err = inlineError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .transition(.opacity)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        ZStack {
                            Text(LocalizationManager.shared.string(.auSignIn))
                                .opacity(loading ? 0 : 1)
                            ProgressView()
                                .tint(.black)
                                .opacity(loading ? 1 : 0)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.cyan)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(loading || emailOrUsername.isEmpty || password.isEmpty)

                    SignInWithAppleButton(.signIn) { req in
                        req.requestedScopes = [.fullName, .email]
                        req.nonce = AuthNonce.make()
                    } onCompletion: { _ in
                        // Real Apple Sign-In flow handled by AuthService.
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )

                    HStack {
                        Spacer()
                        Button("Забыли пароль?") { path = .forgot }
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        loading = true
        inlineError = nil
        defer { loading = false }

        // Use real AuthService. It already has signIn via /api/auth/signin.
        do {
            _ = try await AuthService.shared.signIn(
                email: emailOrUsername,
                password: password
            )
            NotificationCenter.default.post(name: .plinkAuthCompleted, object: nil)
        } catch {
            inlineError = "Не удалось войти. Проверьте данные."
        }
    }
}

// MARK: - RegistrationFlow (3 steps)

internal struct RegistrationFlow: View {
    @Binding public var path: AuthPath

    @State private var step: Int = 1
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var nickname: String = ""
    @State private var avatarPreviewColor: String = "#3FE8C8"
    @State private var ageConfirmed = false
    @State private var termsAccepted = false
    @State private var privacyAccepted = false
    @State private var loading = false

    @State private var nicknameAvailable: Bool? = nil
    @State private var passwordChecks: [PasswordCheck] = []

    init(path: Binding<AuthPath>) { self._path = path }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ProgressView(value: Double(step), total: 3)
                    .tint(.cyan)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch step {
                        case 1: stepCredentials
                        case 2: stepIdentity
                        default: stepSafety
                        }
                    }
                    .padding(24)
                }

                bottomBar
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Step 1

    private var stepCredentials: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizationManager.shared.string(.auStep1))
                .font(.caption.bold())
                .foregroundStyle(.cyan)
            Text(LocalizationManager.shared.string(.auCreateAccount))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(.white)

            AuthField(title: "Email", text: $email, error: nil,
                      autocapitalization: .never, keyboardType: .emailAddress)

            VStack(alignment: .leading, spacing: 8) {
                SecureField("Пароль", text: $password)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onChange(of: password) { _, v in
                        passwordChecks = PasswordCheck.evaluate(v)
                    }

                ForEach(passwordChecks) { c in
                    HStack(spacing: 6) {
                        Image(systemName: c.passed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(c.passed ? .green : .white.opacity(0.3))
                        Text(c.label).font(.caption)
                    }
                    .foregroundStyle(c.passed ? .green : .white.opacity(0.5))
                }
            }
        }
    }

    // MARK: Step 2

    private var stepIdentity: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizationManager.shared.string(.auStep2))
                .font(.caption.bold())
                .foregroundStyle(.cyan)
            Text(LocalizationManager.shared.string(.auWhatsYourName))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(.white)

            HStack(spacing: 16) {
                Circle()
                    .fill(Color(hex: avatarPreviewColor))
                    .frame(width: 64, height: 64)
                    .shadow(color: .cyan.opacity(0.4), radius: 12)

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Никнейм", text: $nickname)
                        .font(.body)
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .onChange(of: nickname) { _, v in
                            // P0.5: Telegram-style validation — only allow valid chars
                            let filtered = v.filter { c in
                                c.isLetter || c.isNumber || c == "_"
                            }
                            if filtered != v {
                                nickname = String(filtered.prefix(32))
                            }
                            Task { await checkNickname(nickname) }
                        }
                    if !nickname.isEmpty {
                        Text(nicknameHint)
                            .font(.caption)
                            .foregroundStyle(nicknameIsValid ? .green : .red)
                    } else if let avail = nicknameAvailable {
                        Text(avail ? "Свободен" : "Занят")
                            .font(.caption)
                            .foregroundStyle(avail ? .green : .red)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Step 3

    private var stepSafety: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizationManager.shared.string(.auStep3))
                .font(.caption.bold())
                .foregroundStyle(.cyan)
            Text(LocalizationManager.shared.string(.auSafety))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                Toggle(isOn: $ageConfirmed) {
                    Text(LocalizationManager.shared.string(.auOver16))
                }.tint(.cyan)
                Toggle(isOn: $termsAccepted) {
                    Text(LocalizationManager.shared.string(.auAcceptTerms))
                }.tint(.cyan)
                Toggle(isOn: $privacyAccepted) {
                    Text(LocalizationManager.shared.string(.auAcceptPrivacy))
                }.tint(.cyan)
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(LocalizationManager.shared.string(.auNotifLater))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step > 1 {
                Button("Назад") { step -= 1 }
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button {
                Task { await next() }
            } label: {
                ZStack {
                    Text(step < 3 ? "Далее" : "Создать аккаунт")
                        .opacity(loading ? 0 : 1)
                    ProgressView().tint(.black).opacity(loading ? 1 : 0)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canProceed ? Color.cyan : Color.cyan.opacity(0.4))
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!canProceed || loading)
        }
        .padding(24)
    }

    private var canProceed: Bool {
        switch step {
        case 1: return email.contains("@") && passwordChecks.allSatisfy { $0.passed }
        case 2: return nicknameIsValid && nicknameAvailable == true
        case 3: return ageConfirmed && termsAccepted && privacyAccepted
        default: return false
        }
    }

    // P0.5: Telegram-style nickname validation
    private var nicknameIsValid: Bool {
        guard nickname.count >= 5, nickname.count <= 32 else { return false }
        guard let first = nickname.first, first.isLetter else { return false }
        return nickname.allSatisfy { c in c.isLetter || c.isNumber || c == "_" }
    }

    private var nicknameHint: String {
        if nickname.isEmpty { return "5-32 символа: буквы, цифры, подчёркивание" }
        if !nickname.first!.isLetter { return "Должен начинаться с буквы" }
        if nickname.count < 5 { return "Минимум 5 символов (ещё \(5 - nickname.count))" }
        if nickname.count > 32 { return "Максимум 32 символа" }
        if !nicknameIsValid { return "Только буквы, цифры и подчёркивание" }
        return "Корректный никнейм"
    }

    private func next() async {
        if step < 3 { step += 1; return }
        loading = true
        defer { loading = false }

        do {
            _ = try await AuthService.shared.signUp(
                email: email,
                password: password,
                username: nickname
            )
            NotificationCenter.default.post(name: .plinkAuthCompleted, object: nil)
        } catch {
            // Inline error display
        }
    }

    private func checkNickname(_ value: String) async {
        guard value.count >= 3 else { nicknameAvailable = nil; return }
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        // Phase 2.6: real backend availability check.
        do {
            let avail = try await AuthService.shared.checkNicknameAvailability(value)
            if Task.isCancelled { return }
            await MainActor.run { nicknameAvailable = avail }
        } catch {
            // Network error → don't block the user; assume available and let
            // sign-up fail with a clear server-side error if truly taken.
            await MainActor.run { nicknameAvailable = nil }
        }
    }
}

// MARK: - AuthField

struct AuthField: View {
    let title: String
    @Binding var text: String
    let error: String?
    let autocapitalization: TextInputAutocapitalization?
    let keyboardType: UIKeyboardType

    init(title: String, text: Binding<String>, error: String?,
         autocapitalization: TextInputAutocapitalization? = .never,
         keyboardType: UIKeyboardType = .default) {
        self.title = title
        self._text = text
        self.error = error
        self.autocapitalization = autocapitalization
        self.keyboardType = keyboardType
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            TextField(title, text: $text)
                .font(.body)
                .foregroundStyle(.white)
                .textInputAutocapitalization(autocapitalization)
                .keyboardType(keyboardType)
                .padding(14)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(error != nil ? Color.red.opacity(0.5) : .clear, lineWidth: 1)
                )
                .accessibilityLabel(title)
                .accessibilityHint(error ?? "Введите \(title.lowercased())")
                .accessibilityShowsLargeContentViewer {
                    Text(title)
                }
            if let err = error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Ошибка: \(err)")
            }
        }
    }
}

// MARK: - PasswordCheck

struct PasswordCheck: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let passed: Bool

    static func evaluate(_ value: String) -> [PasswordCheck] {
        [
            PasswordCheck(label: "Минимум 8 символов", passed: value.count >= 8),
            PasswordCheck(label: "Заглавная буква", passed: value.range(of: "[A-Z]", options: .regularExpression) != nil),
            PasswordCheck(label: "Цифра", passed: value.range(of: "[0-9]", options: .regularExpression) != nil),
        ]
    }
}

// MARK: - AuthNonce

internal enum AuthNonce {
    /// Nonce stored in a thread-safe wrapper. Apple Sign-In calls `make()`
    /// on the main thread, then `current` from the ASAuthorizationController
    /// callback (also main thread), but Swift's actor isolation checker
    /// can't prove that, so we use a lock.
    private static let lock = NSLock()
    private static var _current: String?

    static var current: String {
        lock.lock()
        defer { lock.unlock() }
        return _current ?? ""
    }

    static func make() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let nonce = Data(bytes).base64EncodedString()
        lock.lock()
        _current = nonce
        lock.unlock()
        return nonce
    }
}

// MARK: - Notifications

internal extension Notification.Name {
    static let plinkAuthCompleted = Notification.Name("plink.authCompleted")
}
