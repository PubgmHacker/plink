// Plink/Features/Auth2026/CinematicAuthContainer.swift — Auth 2026 redesign
//
// Общие компоненты авторизации в языке «кинозал»: стеклянные капсулы-поля
// (teal при фокусе), сплошная teal-кнопка с мягким свечением, стеклянная
// вторичная кнопка, янтарные инлайн-уведомления, моно-микроподписи.

import SwiftUI

struct CinematicAuthContainer<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 760 {
                // iPad/Mac: герой слева, форма справа.
                HStack(spacing: 0) {
                    hero
                        .frame(width: proxy.size.width * 0.5)
                    form
                }
            } else {
                // iPhone: вертикальный скролл.
                ScrollView {
                    VStack(spacing: 0) {
                        hero
                            .frame(height: min(300, proxy.size.height * 0.36))
                        form
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(ProjectorBeamBackground())
        .foregroundStyle(PlinkTheatre.screen)
    }

    private var hero: some View {
        VStack(spacing: 18) {
            PlinkFrameMark(size: 72)
            Text(title)
                .font(.system(size: 24, weight: .heavy))
                .tracking(-0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var form: some View {
        content
            .frame(maxWidth: 430)
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Стили кнопок

/// Главная кнопка: единственное цветное пятно чёрно-белого шелла.
///
/// Решение владельца 26.07.2026: обёртка приложения монохромная (как маркетинг
/// Rave/Hearo), но кнопка «пуск» получает каплю цвета — тот же градиент
/// белый → teal, что на play-кадре иконки, чтобы вход и иконка читались как одна
/// вещь. Тёмный текст остаётся контрастным на обоих концах градиента
/// (#070809 на #FFFFFF ≈ 20:1, на #19E0C0 ≈ 12:1).
struct AuthPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(PlinkTheatre.velvetDeep)
            .frame(maxWidth: .infinity)
            .frame(height: CompactPhoneMetrics.primaryButtonHeight)
            .background(PlinkTheatre.ignitionGradient, in: Capsule())
            .overlay(Capsule().strokeBorder(PlinkTheatre.tealBright.opacity(0.55), lineWidth: 1))
            .shadow(
                color: PlinkTheatre.tealDeep.opacity(configuration.isPressed ? 0.16 : 0.34),
                radius: configuration.isPressed ? 8 : 20,
                y: 6
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

/// Вторичная кнопка: стеклянная капсула с тонкой рамкой.
struct AuthProviderButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(PlinkTheatre.screen)
            .frame(maxWidth: .infinity)
            .frame(height: CompactPhoneMetrics.primaryButtonHeight)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(PlinkTheatre.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

// MARK: - Поле ввода: стеклянная капсула, teal при фокусе

struct CompactAuthField: View {
    let title: String
    @Binding var text: String
    var icon: String? = nil
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never
    var secure: Bool = false
    var submitLabel: SubmitLabel = .next
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(focused ? PlinkTheatre.teal : PlinkTheatre.muted)
                    .frame(width: 18)
            }
            Group {
                if secure {
                    SecureField("", text: $text, prompt: prompt)
                } else {
                    TextField("", text: $text, prompt: prompt)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(capitalization)
                        .autocorrectionDisabled()
                }
            }
            .textContentType(contentType)
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
            .focused($focused)
            .foregroundStyle(PlinkTheatre.screen)
            .tint(PlinkTheatre.teal)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                focused ? PlinkTheatre.teal.opacity(0.75) : PlinkTheatre.hairline,
                lineWidth: focused ? 1.2 : 1
            )
        )
        .shadow(color: PlinkTheatre.teal.opacity(focused ? 0.16 : 0), radius: 12)
        .animation(.easeOut(duration: 0.18), value: focused)
        .accessibilityLabel(title)
    }

    private var prompt: Text {
        Text(title).foregroundStyle(PlinkTheatre.muted.opacity(0.85))
    }
}

// MARK: - Янтарное инлайн-уведомление (ошибки, сессия)

struct AuthInlineNotice: View {
    let text: String
    var icon: String = "exclamationmark.triangle.fill"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(PlinkTheatre.amber)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PlinkTheatre.amber.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PlinkTheatre.amber.opacity(0.28), lineWidth: 1)
        )
    }
}

// MARK: - Моно-микроподпись («таймкод»)

struct AuthMonoTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(2.2)
            .foregroundStyle(PlinkTheatre.muted)
    }
}

// MARK: - Разделитель

struct AuthDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(PlinkTheatre.hairline).frame(height: 0.5)
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(PlinkTheatre.muted)
            Rectangle().fill(PlinkTheatre.hairline).frame(height: 0.5)
        }
    }
}

// MARK: - Юридический футер

struct LegalConsentFooter: View {
    var body: some View {
        VStack(spacing: 5) {
            Text("Продолжая, вы принимаете")
                .font(.system(size: 11))
                .foregroundStyle(PlinkTheatre.muted.opacity(0.8))
            HStack(spacing: 6) {
                Link("Условия", destination: URL(string: "https://plink.app/terms")!)
                Text("·")
                    .foregroundStyle(PlinkTheatre.muted.opacity(0.6))
                Link("Конфиденциальность", destination: URL(string: "https://plink.app/privacy")!)
            }
            .font(.system(size: 11, weight: .medium))
            .tint(PlinkTheatre.tealDeep)
        }
    }
}
