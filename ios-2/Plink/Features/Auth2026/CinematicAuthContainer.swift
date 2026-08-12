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
            PlinkBrandMark(size: 76)
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

/// Главное действие — ЕДИНСТВЕННАЯ светлая плашка на экране.
///
/// Ответ на вопрос «а нужны ли цветные кнопки или сделать всё стеклянное»
/// (аудит 04.08.2026): всё стеклянное — нельзя. Экран, где поля, переключатель
/// и кнопка сделаны из одного полупрозрачного материала, теряет фокус: у всех
/// элементов один вес, и глазу не за что зацепиться. Это и есть механика
/// «выглядит дешёво» — не отсутствие цвета, а отсутствие иерархии. Плюс сам
/// Apple описывает обычную стеклянную кнопку как второстепенную («её плохо
/// видно — нормально, если кнопка не так важна»), а для главного действия
/// предлагает выраженную заливку.
///
/// Поэтому: поля — плотные и тёмные, переключатель — утопленный, кнопка —
/// светлая. Ровно один яркий элемент, и это то самое действие, за которым
/// человек пришёл. Цвет кнопке не нужен: на тёмном экране свет и есть самый
/// сильный акцент, а любой конкретный цвет тут же присвоил бы шеллу одну из
/// тем продукта — ту самую проблему, из-за которой синий и убрали.
struct AuthPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16.5, weight: .heavy))
            .foregroundStyle(isEnabled ? Color(hex: 0x101013) : PlinkTheatre.muted)
            .frame(maxWidth: .infinity)
            // minHeight: при крупном Dynamic Type подпись не влезала в 56 pt.
            .frame(minHeight: 56)
            .background {
                if isEnabled {
                    // Тёплый уход книзу, а не в холодный: кнопка освещена тем
                    // же лучом, что знак. Холодно-голубой низ (как было) читался
                    // «синей темой», а не светом.
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white, Color(hex: 0xF0E7D8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                } else {
                    // Выключенная кнопка — НЕ полупрозрачная белая: прозрачность
                    // на тёмном даёт ровно тот серый, от которого уходим.
                    // Плотная поверхность на ступень ниже поля: кнопка явно
                    // неактивна, но остаётся частью экрана.
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(PlinkTheatre.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(PlinkTheatre.hairline, lineWidth: 1)
                        }
                }
            }
            // Тёплое гало: кнопка выглядит источником света, а не наклейкой.
            .shadow(
                color: PlinkTheatre.warm.opacity(
                    isEnabled ? (configuration.isPressed ? 0.12 : 0.26) : 0
                ),
                radius: configuration.isPressed ? 10 : 24,
                y: 8
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                value: configuration.isPressed
            )
            .animation(.easeOut(duration: 0.2), value: isEnabled)
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
            .frame(height: 56)
            .plinkGlass(.control, cornerRadius: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(PlinkTheatre.hairline, lineWidth: 1)
            )
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

    /// UI-тесты (аудит 30.07.2026): системный шит «Надёжный пароль?»
    /// от .newPassword перехватывает ввод в симуляторе и делает воронку
    /// непроходимой для XCUITest. Флаг выключает ТОЛЬКО autofill-подсказку,
    /// поведение для реальных пользователей не меняется.
    private var uiTestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-plink.uitest")
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(focused ? PlinkTheatre.warm : PlinkTheatre.muted)
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
            .textContentType(uiTestMode ? nil : contentType)
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
            .focused($focused)
            .foregroundStyle(PlinkTheatre.screen)
            .tint(PlinkTheatre.warm)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        // Плотная заливка, не стекло — см. разбор в AuthField
        // (PlinkAuthScreen): поле ввода это слой контента, а не управления.
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(focused ? PlinkTheatre.surfaceLift : PlinkTheatre.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    focused ? PlinkTheatre.warm.opacity(0.55) : PlinkTheatre.hairline,
                    lineWidth: focused ? 1.4 : 1
                )
        )
        .shadow(color: PlinkTheatre.warm.opacity(focused ? 0.14 : 0), radius: 12)
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
                if let terms = PlinkLegal.terms {
                    Link(L.string(.plusTerms), destination: terms)
                }
                Text("·")
                    .foregroundStyle(PlinkTheatre.muted.opacity(0.6))
                if let privacy = PlinkLegal.privacy {
                    Link(L.string(.plusPrivacy), destination: privacy)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .tint(PlinkTheatre.warmSoft)
        }
    }
}
