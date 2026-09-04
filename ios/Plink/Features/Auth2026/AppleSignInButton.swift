// Sign in with Apple — thin wrapper around ASAuthorizationController.
// Requires paid Apple Developer + entitlement; backend: POST /auth/apple.

import SwiftUI
import AuthenticationServices

struct AppleSignInButton: View {
    /// Подпись кнопки. HIG: она обязана называть действие — «Войти через
    /// Apple» на входе и «Регистрация через Apple» на регистрации.
    var title: String = L10n.text(.authAppleButton)
    var onSuccess: () -> Void
    var onError: (String) -> Void

    @State private var isLoading = false

    var body: some View {
        Button {
            guard !isLoading else { return }
            isLoading = true
            AppleSignInCoordinator.shared.signIn { result in
                Task { @MainActor in
                    isLoading = false
                    switch result {
                    case .success(let payload):
                        do {
                            _ = try await AuthService.shared.signInWithApple(
                                identityToken: payload.identityToken,
                                fullName: payload.fullName
                            )
                            onSuccess()
                        } catch {
                            onError(error.localizedDescription)
                        }
                    case .failure(let error):
                        if (error as? ASAuthorizationError)?.code == .canceled {
                            return
                        }
                        onError(error.localizedDescription)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo")
                    // 19 pt при кегле 16,5: HIG задаёт знак чуть крупнее
                    // прописной высоты подписи, иначе он читается точкой.
                    .authFont(19, weight: .medium)
                    .baselineOffset(-1)
                Text(isLoading ? L10n.text(.authAppleSigningIn) : title)
                    .authFont(16.5, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Color(hex: 0x101013))
            .frame(maxWidth: .infinity)
            // 56/16 — та же геометрия, что у главной кнопки. Было 50/14: две
            // полноширинные кнопки разной высоты и разного радиуса читались
            // как элементы из двух разных приложений.
            .frame(minHeight: 56)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isLoading ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityIdentifier("auth.signInWithApple")
        .accessibilityLabel(title)
    }
}

fileprivate struct AppleSignInPayload {
    let identityToken: String
    let fullName: String?
}

@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = AppleSignInCoordinator()

    private var continuation: CheckedContinuation<Result<AppleSignInPayload, Error>, Never>?

    fileprivate func signIn(completion: @escaping (Result<AppleSignInPayload, Error>) -> Void) {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.continuation = nil

        Task {
            let result: Result<AppleSignInPayload, Error> = await withCheckedContinuation { cont in
                self.continuation = cont
                controller.performRequests()
            }
            completion(result)
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.first(where: { $0.activationState == .foregroundActive })?.windows.first(where: \.isKeyWindow) {
                return window
            }
            return scenes.first?.windows.first ?? ASPresentationAnchor()
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            Task { @MainActor in
                continuation?.resume(returning: .failure(
                    NSError(domain: "PlinkApple", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: L10n.text(.authAppleNoToken),
                    ])
                ))
                continuation = nil
            }
            return
        }

        var name: String?
        if let full = cred.fullName {
            let parts = [full.givenName, full.familyName].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { name = parts.joined(separator: " ") }
        }

        Task { @MainActor in
            continuation?.resume(returning: .success(AppleSignInPayload(identityToken: token, fullName: name)))
            continuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            continuation?.resume(returning: .failure(error))
            continuation = nil
        }
    }
}
