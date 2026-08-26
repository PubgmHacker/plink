// Plink/Design/Glass/PlinkGlass.swift
//
// Единый слой Liquid Glass для всего приложения.
//
// Deployment target проекта — iOS 17.0, поэтому нативные API iOS 26
// (glassEffect / GlassEffectContainer / .buttonStyle(.glass)) доступны только
// под `if #available`. Ниже — адаптивная обёртка: на iOS 26 включается
// системное стекло с рефракцией и морфингом, на iOS 17–25 рисуется ручная
// аппроксимация (материал + градиентная обводка + верхний блик + тень).
//
// Правило Apple HIG, которому здесь следуем: стекло живёт только на слое
// навигации и управления (таб-бар, кнопки, чипы, плавающая хром-панель),
// но не на слое контента. Карточки постеров стеклом не заливаем.

import SwiftUI

// MARK: - Роль стеклянной поверхности

/// Насколько «плотное» стекло нужно поверхности.
enum PlinkGlassRole {
    /// Основная навигация: таб-бар, тулбар. Максимальная читаемость.
    case navigation
    /// Интерактивный контрол: кнопка, чип, круглая иконка.
    case control
    /// Плавающая панель поверх видео — прозрачнее, кадр должен просвечивать.
    case overlay

    /// Прозрачность подложки для ручного фолбэка (iOS 17–25).
    var fallbackFill: Double {
        switch self {
        case .navigation: return 0.10
        case .control:    return 0.08
        case .overlay:    return 0.05
        }
    }

    /// Радиус и смещение тени: крупные поверхности «толще» и дают мягче тень.
    var shadow: (radius: CGFloat, y: CGFloat, opacity: Double) {
        switch self {
        case .navigation: return (22, 10, 0.34)
        case .control:    return (10, 4, 0.22)
        case .overlay:    return (16, 8, 0.30)
        }
    }
}

// MARK: - Доступность

// MARK: - Основной модификатор

private struct PlinkGlassSurface<S: InsettableShape>: ViewModifier {
    let role: PlinkGlassRole
    let shape: S
    let tint: Color?
    let isInteractive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(opaqueFallback, in: shape).overlay(hairline)
        } else {
            // Нативное стекло iOS 26 (Glass / glassEffect) существует только в
            // SDK Xcode 26 (Swift 6.2). Под более старым тулчейном (CI — Xcode
            // 16.4 / Swift 6.1) этого символа в SDK нет, поэтому весь путь скрыт
            // за compile-time проверкой версии компилятора. `if #available` тут
            // не спасает: он гейтит рантайм, но не подставляет отсутствующий в
            // SDK тип, и сборка падает с `cannot find type 'Glass'`.
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.modifier(NativeGlass(role: role, shape: shape, tint: tint, isInteractive: isInteractive))
            } else {
                content.modifier(HandRolledGlass(role: role, shape: shape, tint: tint))
            }
            #else
            content.modifier(HandRolledGlass(role: role, shape: shape, tint: tint))
            #endif
        }
    }

    /// При Reduce Transparency стекло заменяется непрозрачной поверхностью:
    /// прозрачность убрана, но иерархия и контур сохранены.
    private var opaqueFallback: Color {
        guard let tint else { return V4.raised }
        return tint.opacity(0.24)
    }

    private var hairline: some View {
        shape.strokeBorder(V4.line, lineWidth: 1)
    }
}

#if compiler(>=6.2)
@available(iOS 26.0, *)
private struct NativeGlass<S: InsettableShape>: ViewModifier {
    let role: PlinkGlassRole
    let shape: S
    let tint: Color?
    let isInteractive: Bool

    func body(content: Content) -> some View {
        let shadow = role.shadow
        return content
            .glassEffect(glass, in: shape)
            .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
    }

    private var glass: Glass {
        // .clear заметно прозрачнее и предназначен для насыщенного медийного
        // фона — ровно случай плавающей хром-панели поверх видео в комнате.
        var base: Glass = role == .overlay ? .clear : .regular
        if let tint { base = base.tint(tint) }
        if isInteractive { base = base.interactive() }
        return base
    }
}
#endif

/// Ручная аппроксимация Liquid Glass для iOS 17–25.
///
/// Собрана из четырёх слоёв, повторяющих оптику системного стекла:
/// размытие материала, цветовая подложка, верхний блик (имитация источника
/// света сверху-слева) и градиентная кромка вместо плоской обводки.
private struct HandRolledGlass<S: InsettableShape>: ViewModifier {
    let role: PlinkGlassRole
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        let shadow = role.shadow
        return content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.white.opacity(role.fallbackFill))
                    if let tint {
                        shape.fill(tint.opacity(0.18))
                    }
                    // Блик смещён к верхней кромке, а не размазан по всей
                    // площади — иначе поверхность читается плоской.
                    shape
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.30), .white.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .blendMode(.overlay)
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.55),
                            .white.opacity(0.06),
                            .white.opacity(0.22),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
    }
}

// MARK: - Публичный API

extension View {
    /// Стеклянная поверхность произвольной формы.
    func plinkGlass<S: InsettableShape>(
        _ role: PlinkGlassRole = .control,
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(PlinkGlassSurface(role: role, shape: shape, tint: tint, isInteractive: interactive))
    }

    /// Стеклянная капсула — форма по умолчанию для контролов в iOS 26.
    func plinkGlass(
        _ role: PlinkGlassRole = .control,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        plinkGlass(role, in: Capsule(style: .continuous), tint: tint, interactive: interactive)
    }

    /// Стеклянный прямоугольник со скруглением.
    func plinkGlass(
        _ role: PlinkGlassRole = .control,
        cornerRadius: CGFloat,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        plinkGlass(
            role,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint,
            interactive: interactive
        )
    }
}

// MARK: - Контейнер морфинга

/// Обёртка над `GlassEffectContainer`.
///
/// Внутри контейнера соседние стеклянные формы сливаются и перетекают друг в
/// друга при анимации. Вне контейнера каждое стекло рендерится независимо и
/// морфинга не будет. На iOS 17–25 контейнер прозрачно вырождается в группу.
struct PlinkGlassGroup<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Стили кнопок

/// Основное действие экрана. Одна такая кнопка на видимую область.
struct PlinkProminentButtonStyle: ButtonStyle {
    var tint: Color
    var textColor: Color = .white
    var height: CGFloat = 52
    var cornerRadius: CGFloat = 18
    var fillsWidth: Bool = true

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(textColor)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, fillsWidth ? 0 : 22)
            .background {
                ZStack {
                    shape.fill(tint)
                    // Тонкий вертикальный блик даёт объём без градиентной
                    // заливки двумя цветами, которая читается как шаблон.
                    shape.fill(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .blendMode(.overlay)
                }
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
            .clipShape(shape)
            .shadow(
                color: tint.opacity(configuration.isPressed ? 0.18 : 0.34),
                radius: configuration.isPressed ? 8 : 16,
                y: configuration.isPressed ? 3 : 8
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(pressScale(configuration.isPressed))
            .animation(pressAnimation, value: configuration.isPressed)
    }

    private func pressScale(_ pressed: Bool) -> CGFloat {
        guard pressed, !reduceMotion else { return 1 }
        return 0.97
    }

    private var pressAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72)
    }
}

/// Вторичное действие — стеклянная кнопка без заливки акцентом.
struct PlinkGlassButtonStyle: ButtonStyle {
    var tint: Color?
    var height: CGFloat = 52
    var cornerRadius: CGFloat = 18
    var fillsWidth: Bool = true

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(V4.ink)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, fillsWidth ? 0 : 22)
            .plinkGlass(.control, cornerRadius: cornerRadius, tint: tint, interactive: true)
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72),
                       value: configuration.isPressed)
    }
}

/// Круглая иконочная кнопка поверх контента (плеер, хедеры).
struct PlinkGlassIconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 44
    var role: PlinkGlassRole = .control
    var tint: Color?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(V4.ink)
            .frame(width: diameter, height: diameter)
            .plinkGlass(role, in: Circle(), tint: tint, interactive: true)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PlinkGlassButtonStyle {
    /// Вторичная стеклянная кнопка во всю ширину.
    static var plinkGlass: PlinkGlassButtonStyle { PlinkGlassButtonStyle() }
}
