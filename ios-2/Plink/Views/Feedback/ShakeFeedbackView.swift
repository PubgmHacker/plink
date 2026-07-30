import SwiftUI
import UIKit

// MARK: - Shake to Report (M20)
// Добавь .shakeToReport() на корневой View чтобы включить shake-фич.

// Аудит 26.07.2026: PlinkShakeWindow (UIWindow-сабкласс) удалён — его никто
// не инстанцировал, поэтому .plinkShakeDetected никогда не постился и
// shake-to-report был мёртв. Вместо этого перехватываем motionEnded прямо
// в extension UIWindow: SwiftUI-окно приложения наследует этот override,
// и встряска доходит до ShakeDetectorModifier без кастомного окна.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: .plinkShakeDetected, object: nil)
        }
    }
}

// MARK: - ShakeDetector ViewModifier
struct ShakeDetectorModifier: ViewModifier {
    @State private var showFeedback = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .plinkShakeDetected)) { _ in
                HapticManager.impact(.medium)
                showFeedback = true
            }
            .sheet(isPresented: $showFeedback) {
                FeedbackSheetView()
                    .presentationDetents([.medium])
            }
    }
}

extension Notification.Name {
    static let plinkShakeDetected = Notification.Name("plinkShakeDetected")
}

extension View {
    func shakeToReport() -> some View {
        modifier(ShakeDetectorModifier())
    }
}

// MARK: - Feedback Sheet
struct FeedbackSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackText = ""
    @State private var selectedType: FeedbackType = .bug
    @State private var isSending = false
    @State private var sent = false

    enum FeedbackType: String, CaseIterable {
        case bug = "Ошибка"
        case suggestion = "Предложение"
        case other = "Другое"

        var icon: String {
            switch self {
            case .bug: return "ladybug.fill"
            case .suggestion: return "lightbulb.fill"
            case .other: return "ellipsis.bubble.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Type picker
                HStack(spacing: 10) {
                    ForEach(FeedbackType.allCases, id: \.self) { type in
                        Button {
                            selectedType = type
                            HapticManager.selection()
                        } label: {
                            Label(type.rawValue, systemImage: type.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedType == type ? V4.accent.opacity(0.15) : Color(.secondarySystemBackground))
                                .foregroundStyle(selectedType == type ? V4.accent : .secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Text field
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                    if feedbackText.isEmpty {
                        Text("Опиши что случилось... ")
                            .foregroundStyle(.tertiary)
                            .padding(14)
                    }
                    TextEditor(text: $feedbackText)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                }
                .frame(height: 130)

                // Send button
                if sent {
                    Label("Отправлено! Спасибо ❤️", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 15, weight: .semibold))
                        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() } }
                } else {
                    Button {
                        sendFeedback()
                    } label: {
                        Group {
                            if isSending {
                                ProgressView().tint(.white)
                            } else {
                                Text("Отправить")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(feedbackText.trimmingCharacters(in: .whitespaces).isEmpty ? V4.accent.opacity(0.4) : V4.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(feedbackText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Обратная связь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }

    private func sendFeedback() {
        isSending = true
        HapticManager.impact(.medium)
        Task {
            let payload: [String: Any] = [
                "type": selectedType.rawValue,
                "text": feedbackText,
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
                "osVersion": UIDevice.current.systemVersion,
                "device": UIDevice.current.model,
                "userId": UserDefaults.standard.string(forKey: "plink_current_user_id") ?? "anon"
            ]
            if let url = URL(string: PlinkConfig.apiURLString + "/telemetry/feedback"),
               let body = try? JSONSerialization.data(withJSONObject: payload) {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let token = AuthTokenStore.shared.token {
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                req.httpBody = body
                _ = try? await URLSession.shared.data(for: req)
            }
            await MainActor.run {
                isSending = false
                sent = true
            }
        }
    }
}
