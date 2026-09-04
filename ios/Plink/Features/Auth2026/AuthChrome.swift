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

/// Кегль, который РЕАЛЬНО слушает Dynamic Type.
///
/// Во всём приложении шрифты заданы `.system(size:)` — а это ФИКСИРОВАННЫЙ
/// кегль: SwiftUI не двигает его системной настройкой «Размер текста».
/// Доказано побайтно: кадр 16-auth-large-type, снятый при
/// `.dynamicTypeSize(.accessibility2)`, совпал с обычным 12-auth-filled
/// (md5 ee44f389f6ab3f168f6168d95a00af9b) — человек, увеличивший шрифт
/// системно, на экране входа не получал НИЧЕГО.
///
/// ScaledMetric читает `\.dynamicTypeSize` из окружения и отдаёт множитель
/// относительно `.body`, поэтому все кегли экрана растут в СВОИХ пропорциях
/// (11 остаётся мельче 16.5), а не сплющиваются в один текстовый стиль.
/// Сделано модификатором, а не свойством вью: `ButtonStyle` — не `View` и
/// собственный `@ScaledMetric` в нём не обновляется, а `ViewModifier`
/// динамические свойства получает.
///
/// Высоты на экране входа уже заданы через `minHeight`, не `height`, —
/// то есть контейнеры готовы расти вместе с текстом.
struct AuthScaledFont: ViewModifier {
    let size: CGFloat
    var weight: Font.Weight = .regular

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight))
    }
}

extension View {
    /// Замена `.font(.system(size:weight:))` на масштабируемый кегль.
    func authFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(AuthScaledFont(size: size, weight: weight))
    }
}

struct AuthPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .authFont(16.5, weight: .heavy)
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
                .authFont(12, weight: .semibold)
            // Замер по кадру 13-auth-session-notice: «Сессия истекла.
            // Войдите заново — это защ…» — строка обрезалась на полуслове,
            // то есть пользователь НЕ читал, почему его выкинуло. Причина не
            // в lineLimit (его тут нет), а в том, что Text внутри HStack
            // отдаёт идеальную высоту в одну строку и обрезается по ширине.
            // fixedSize(vertical:) заставляет взять идеальную ВЫСОТУ при
            // предложенной ширине — текст переносится, плашка растёт.
            Text(text)
                .authFont(13, weight: .medium)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
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
                .authFont(11)
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
            .authFont(11, weight: .medium)
            .tint(PlinkShell.accentSoft)
        }
        .frame(maxWidth: .infinity)
    }
}
