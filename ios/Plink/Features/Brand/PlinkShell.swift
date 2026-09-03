// Plink/Features/Brand/PlinkShell.swift
//
// Палитра и фон бренд-шелла: сплэш, онбординг, вход. Шелл живёт ВНЕ тем
// приложения — цвета здесь постоянные и совпадают с иконкой на домашнем
// экране (brand/source/reference.png → PlinkBrandPalette). Внутри продукта
// цвет принадлежит живым темам; здесь — только бренду.
//
// Здесь же лежат переменные окружения доступности, которыми шелл и
// снимки дизайна замораживают анимации и имитируют Reduce Motion /
// Reduce Transparency. Раньше они жили в AnimatedPosterMosaic.swift вместе
// с «бархатным» фоном и лучом проектора; тот файл ушёл вместе с палитрой.

import SwiftUI

// MARK: - Палитра шелла

enum PlinkShell {
    /// Фон иконки и всего шелла — #010008.
    static let background = PlinkBrandPalette.background
    /// Чуть поднятый фон для верхней части экрана — тот же оттенок, светлее.
    static let backgroundLift = Color(hex: 0x0B0620)

    /// Поверхности карточек и полей: полупрозрачный фиолетовый на чёрном.
    static let surface = Color(hex: 0x14102B)
    static let surfaceLift = Color(hex: 0x1D1740)

    /// Текст: белый экрана и приглушённый лавандовый.
    static let text = Color(hex: 0xF4F4F5)
    static let muted = Color(hex: 0x9C95B8)

    /// Акцент — светлая стрелка знака. Мягкий вариант — для фокуса полей.
    static let accent = PlinkBrandPalette.violetLight
    static let accentSoft = Color(hex: 0xB693FF)
    /// Глубокий синий конца градиента стрелки.
    static let deep = PlinkBrandPalette.violetDeep

    /// Предупреждение/ошибка — тёплый на фиолетовом читается лучше красного.
    static let warning = Color(hex: 0xFFB169)

    /// Волосяная линия и блик кромки.
    static let hairline = Color.white.opacity(0.08)
    static let specular = Color.white.opacity(0.18)

    /// Градиент главной кнопки — тот же, что у стрелки знака.
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [PlinkBrandPalette.violetLight, PlinkBrandPalette.violetDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Окружение доступности

struct PlinkAccessibilityOverride: Equatable {
    var reduceTransparency = false
    var reduceMotion = false
}

struct PlinkFreezeAnimationsKey: EnvironmentKey {
    static let defaultValue = false
}

private struct PlinkAccessibilityOverrideKey: EnvironmentKey {
    static let defaultValue = PlinkAccessibilityOverride()
}

extension EnvironmentValues {
    /// Снимки дизайна: все бесконечные анимации шелла стоят на месте.
    var plinkFreezeAnimations: Bool {
        get { self[PlinkFreezeAnimationsKey.self] }
        set { self[PlinkFreezeAnimationsKey.self] = newValue }
    }

    /// Имитация системных настроек доступности для снимков.
    var plinkAccessibilityOverride: PlinkAccessibilityOverride {
        get { self[PlinkAccessibilityOverrideKey.self] }
        set { self[PlinkAccessibilityOverrideKey.self] = newValue }
    }
}

// MARK: - Фон шелла

/// Фон сплэша, онбординга и входа: чёрный #010008 с фиолетовым сиянием у
/// верхней трети — там, где стоит знак. Сияние медленно дышит, при Reduce
/// Motion, замороженных снимках и низком заряде стоит на месте.
struct PlinkShellBackground: View {
    /// Куда смотрит сияние (в долях экрана). Вход держит его выше формы,
    /// онбординг — за телефоном.
    var glowCenter = UnitPoint(x: 0.5, y: 0.28)
    var glowStrength: Double = 1

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.plinkFreezeAnimations) private var frozen
    @Environment(\.plinkAccessibilityOverride) private var override

    private var reduceMotion: Bool { systemReduceMotion || override.reduceMotion || frozen }
    private var reduceTransparency: Bool { systemReduceTransparency || override.reduceTransparency }

    var body: some View {
        ZStack {
            PlinkShell.background

            if reduceMotion {
                glow(phase: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: ProcessInfo.processInfo.isLowPowerModeEnabled)) { context in
                    glow(phase: context.date.timeIntervalSinceReferenceDate)
                }
            }

            // Виньетка: края темнее, знак и форма читаются на чистом чёрном.
            RadialGradient(
                colors: [.clear, PlinkShell.background.opacity(0.85)],
                center: .center,
                startRadius: 180,
                endRadius: 620
            )
            .blendMode(.multiply)
            .allowsHitTesting(false)
        }
        .compositingGroup()
        .accessibilityHidden(true)
    }

    private func glow(phase: TimeInterval) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let breathe = reduceMotion ? 0 : sin(phase / 3.4) * 0.5 + 0.5
            let drift = reduceMotion ? 0 : sin(phase / 5.1) * 14
            let radius = size.width * (0.62 + 0.06 * breathe)
            let center = CGPoint(
                x: size.width * glowCenter.x + drift,
                y: size.height * glowCenter.y
            )

            ZStack {
                // Основное сияние — цвет светлой стрелки.
                Circle()
                    .fill(PlinkBrandPalette.violetLight.opacity((0.34 + 0.06 * breathe) * glowStrength))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                    .blur(radius: reduceTransparency ? 0 : 90)

                // Глубокое ядро — тёмный хвост знака, чуть ниже и левее.
                Circle()
                    .fill(PlinkBrandPalette.plum.opacity(0.55 * glowStrength))
                    .frame(width: radius * 1.3, height: radius * 1.3)
                    .position(x: center.x - size.width * 0.16, y: center.y + size.width * 0.18)
                    .blur(radius: reduceTransparency ? 0 : 70)

                // Холодный синий отблеск справа — третий цвет теглайна.
                Circle()
                    .fill(PlinkBrandPalette.violetDeep.opacity((0.22 + 0.05 * breathe) * glowStrength))
                    .frame(width: radius * 1.1, height: radius * 1.1)
                    .position(x: center.x + size.width * 0.22, y: center.y - size.width * 0.08)
                    .blur(radius: reduceTransparency ? 0 : 80)
            }
            .opacity(reduceTransparency ? 0.55 : 1)
        }
        .ignoresSafeArea()
    }
}
