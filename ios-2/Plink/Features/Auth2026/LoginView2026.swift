// Plink/Features/Auth2026/LoginView2026.swift
// Premium, content-first authentication: one quiet screen, one job, one CTA.

import SwiftUI

struct LoginView2026: View {
    @EnvironmentObject private var apiClient: APIClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var appeared = false

    var sessionMessage: String? = nil
    let onAuthenticated: () -> Void
    let onRegister: () -> Void

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        trimmedEmail.contains("@") && password.count >= 6 && !isLoading
    }

    var body: some View {
        ZStack {
            AuthBackdrop()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 72)
                    brand
                        .padding(.bottom, 46)

                    VStack(spacing: 14) {
                        if let errorMessage {
                            AuthInlineNotice(text: errorMessage)
                                .transition(.opacity)
                        } else if let sessionMessage {
                            AuthInlineNotice(text: sessionMessage, icon: "clock.badge.exclamationmark")
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
                            contentType: .password,
                            secure: true,
                            submitLabel: .go,
                            onSubmit: {
                                if canSubmit { Task { await authenticate() } }
                            }
                        )

                        Button {
                            HapticManager.impact(.medium)
                            Task { await authenticate() }
                        } label: {
                            ZStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Войти")
                                }
                            }
                        }
                        .buttonStyle(AuthPrimaryButtonStyle())
                        .disabled(!canSubmit)
                        .padding(.top, 6)
                        .accessibilityIdentifier("auth.primary")

                        Button("Создать аккаунт") {
                            HapticManager.selection()
                            onRegister()
                        }
                        .buttonStyle(AuthProviderButtonStyle())
                        .disabled(isLoading)
                        .accessibilityIdentifier("auth.openRegistration")

                        HStack(spacing: 6) {
                            Text("Продолжая, вы принимаете")
                            Link("Условия", destination: URL(string: "https://plink.app/terms")!)
                            Text("и")
                            Link("Политику", destination: URL(string: "https://plink.app/privacy")!)
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PlinkTheatre.muted.opacity(0.82))
                        .tint(PlinkTheatre.tealDeep)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                    }
                    .frame(maxWidth: 410)
                    .padding(.horizontal, 24)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)

                    Spacer(minLength: 36)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: UIScreen.main.bounds.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.65, dampingFraction: 0.86).delay(0.08)) {
                    appeared = true
                }
            }
        }
    }

    private var brand: some View {
        VStack(spacing: 0) {
            PlinkFrameMark(size: 82)
                .padding(.bottom, 20)

            Text("PLINK")
                .font(.system(size: 37, weight: .black, design: .rounded))
                .tracking(7)
                .foregroundStyle(.white)
                .padding(.bottom, 14)

            Text("Смотрите вместе. Где угодно.")
                .font(.system(size: 21, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(.white)

            Text("Видео, голос и реакции — в одном моменте.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PlinkTheatre.muted)
                .padding(.top, 7)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
    }

    private func authenticate() async {
        guard !isLoading else { return }
        guard trimmedEmail.contains("@") else {
            errorMessage = "Проверьте адрес электронной почты"
            HapticManager.errorOccurred()
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Пароль должен содержать не меньше 6 символов"
            HapticManager.errorOccurred()
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            _ = try await AuthService.shared.signIn(email: trimmedEmail, password: password)
            HapticManager.notification(.success)
            onAuthenticated()
        } catch {
            HapticManager.errorOccurred()
            errorMessage = AuthErrorCopy.message(for: error)
        }
    }
}

private struct AuthBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.018, green: 0.025, blue: 0.045)
            RadialGradient(
                colors: [Color(red: 0.05, green: 0.32, blue: 0.78).opacity(0.56), .clear],
                center: UnitPoint(x: 0.13, y: 0.04),
                startRadius: 8,
                endRadius: 520
            )
            RadialGradient(
                colors: [Color(red: 0.33, green: 0.08, blue: 0.50).opacity(0.22), .clear],
                center: UnitPoint(x: 0.94, y: 0.82),
                startRadius: 0,
                endRadius: 460
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.58)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

enum AuthErrorCopy {
    static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .invalidCredentials:
                return "Неверная почта или пароль"
            case .conflict:
                return "Аккаунт с такими данными уже существует"
            case .unauthorized, .unauthorizedNeedsRefresh:
                return "Сессия завершена. Войдите снова"
            case .notFound:
                return "Не удалось найти нужные данные"
            // 402 и 503 на экране входа означают проблему не с подпиской, а с
            // самим сервисом: покупать здесь нечего, поэтому отдаём текст
            // сервера, если он есть, и нейтральную формулировку иначе.
            case .subscriptionRequired(_, _, let message):
                return message.isEmpty ? "Эта возможность доступна в Плинк+" : message
            case .unavailable(_, let message):
                return message.isEmpty ? "Функция скоро появится" : message
            case .invalidURL, .invalidResponse, .decodingError, .serverError, .networkError:
                return "Plink сейчас недоступен. Попробуйте ещё раз чуть позже"
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "Нет подключения к интернету"
            case .timedOut:
                return "Сервис отвечает слишком долго. Попробуйте ещё раз"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Не удалось подключиться к Plink. Проверьте интернет и повторите"
            default:
                return "Не удалось выполнить действие. Попробуйте ещё раз"
            }
        }
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("invalid credentials") ||
            text.localizedCaseInsensitiveContains("неверный email") {
            return "Неверная почта или пароль"
        }
        if text.localizedCaseInsensitiveContains("server") ||
            text.localizedCaseInsensitiveContains("host") ||
            text.localizedCaseInsensitiveContains("сервер") {
            return "Plink сейчас недоступен. Попробуйте ещё раз чуть позже"
        }
        return "Не удалось выполнить действие. Попробуйте ещё раз"
    }
}
