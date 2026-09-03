// Plink/Features/Auth2026/AuthChrome.swift
//
// Общая хрома шелла входа и онбординга: главная кнопка, инлайн-уведомление,
// юридический футер. Всё на палитре PlinkShell — цвета те же, что у знака на
// иконке, темы приложения сюда не доходят.
//
// Раньше эти типы жили в CinematicAuthContainer.swift вместе с «бархатной»
// палитрой кинозала и белой кнопкой с тёплым уходом. Кнопка теперь залита
// градиентом стрелки знака (#8F44F0 → #4016EA): единственный насыщенный
// элемент на экране — действие, а не переключатель и не фон.

import SwiftUI

// MARK: - Главная кнопка

struct AuthPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16.5, weight: .heavy))
            .foregroundStyle(isEnabled ? PlinkShell.text : PlinkShell.muted)
            .frame(maxWidth: .infinity)
            // minHeight: при крупном Dynamic Type подпись не влезала в 56 pt.
            .frame(minHeight: 56)
            .background {
                if isEnabled {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(PlinkShell.accentGradient)
                        .overlay {
                            // Блик по верхней кромке: кнопка «поймала свет»,
                            // а не наклеена плоским прямоугольником.
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
                                .mask {
                                    LinearGradient(
                                        colors: [.white, .clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                }
                        }
                        .overlay {
                            // Нажатие затемняет, а не осветляет: на градиенте
                            // белая вуаль читалась как «кнопка выключилась».
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.black.opacity(configuration.isPressed ? 0.18 : 0))
                        }
                } else {
                    // Выключенная кнопка — плотная поверхность, не прозрачная:
                    // прозрачность на чёрном даёт грязный серый.
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(PlinkShell.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(PlinkShell.hairline, lineWidth: 1)
                        }
                }
            }
            // Фиолетовое гало — кнопка источник света, как знак на сплэше.
            .shadow(
                color: PlinkShell.accent.opacity(
                    isEnabled ? (configuration.isPressed ? 0.16 : 0.38) : 0
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

// MARK: - Инлайн-уведомление (ошибки, сессия, письмо отправлено)

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
        .foregroundStyle(PlinkShell.warning)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PlinkShell.warning.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PlinkShell.warning.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Юридический футер

struct LegalConsentFooter: View {
    var body: some View {
        VStack(spacing: 5) {
            Text(L10n.text(.authConsentPrefix))
                .font(.system(size: 11))
                .foregroundStyle(PlinkShell.muted.opacity(0.8))
            HStack(spacing: 6) {
                if let terms = PlinkLegal.terms {
                    Link(L.string(.plusTerms), destination: terms)
                }
                Text("·")
                    .foregroundStyle(PlinkShell.muted.opacity(0.6))
                if let privacy = PlinkLegal.privacy {
                    Link(L.string(.plusPrivacy), destination: privacy)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .tint(PlinkShell.accentSoft)
        }
        .frame(maxWidth: .infinity)
    }
}
