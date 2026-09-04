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
#if canImport(UIKit)
import UIKit
#endif

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

    /// «Требование выполнено» у правил пароля. Мятный, а не чистый зелёный:
    /// #34C759 на фиолетовом фоне шелла давал 3,4:1 и не проходил 4,5:1 для
    /// мелкого текста, этот — проходит.
    static let ok = Color(hex: 0x7FE7B0)

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

// MARK: - Гнездо под лого-блоком

/// Чернота под лого-блоком: возвращает знаку чистый #010008, на котором он
/// читается как иконка на домашнем экране, а сияние шелла оставляет кольцом
/// вокруг — не заливкой под.
///
/// Зачем вообще: знак стоял ровно в ярчайшей точке сияния, и тёмная плоскость
/// хвоста (#2C0688) шла по фиолетовому фону. Замер на сплэше давал 1,00–1,49:1
/// — второго плана логотипа при таком контрасте не существует, глаз видит одну
/// светлую стрелку и грязное пятно под ней. С гнездом там же выходит 1,58–1,60:1,
/// а 1,60 — предел для #2C0688 на #010008, то есть ровно иконка.
///
/// Профиль спада подобран по лок-апу, а не на глаз: чернота нужна плотной там,
/// где стоит сам знак (хвост укладывается в 48 pt от центра — это опора 0,96),
/// и обязана быстро отпускать дальше, иначе душит сияние и на периферии.
struct PlinkLockupNest: View {
    /// Центр черноты внутри своей рамки.
    var center: UnitPoint = .center
    /// Радиус, на котором чернота отпускает полностью. 300 pt — при знаке 96 pt;
    /// для меньшего знака масштабируется пропорционально.
    var radius: CGFloat = 300

    static let stops: [Gradient.Stop] = [
        Gradient.Stop(color: PlinkShell.background, location: 0),
        Gradient.Stop(color: PlinkShell.background.opacity(0.96), location: 0.20),
        Gradient.Stop(color: PlinkShell.background.opacity(0.60), location: 0.45),
        Gradient.Stop(color: PlinkShell.background.opacity(0.16), location: 0.75),
        Gradient.Stop(color: PlinkShell.background.opacity(0), location: 1),
    ]

    var body: some View {
        RadialGradient(stops: Self.stops, center: center, startRadius: 0, endRadius: radius)
            .allowsHitTesting(false)
    }
}

extension View {
    /// Гнездо ровно под этим знаком: центр черноты совпадает с центром вида,
    /// поэтому геометрию не нужно повторять константой в каждом экране.
    func plinkLockupNest(radius: CGFloat = 300) -> some View {
        background {
            PlinkLockupNest(radius: radius)
                .frame(width: radius * 2, height: radius * 2)
        }
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
    @Environment(\.displayScale) private var displayScale
    @Environment(\.plinkDeviceTierOverride) private var tierOverride

    private var reduceMotion: Bool { systemReduceMotion || override.reduceMotion || frozen }
    private var reduceTransparency: Bool { systemReduceTransparency || override.reduceTransparency }

    /// Этот фон — самый дорогой кадр в приложении и стоит он на первом экране.
    /// На классике он рисуется дешевле: см. PlinkDeviceTier.
    private var tier: PlinkDeviceTier {
        PlinkDeviceTier.resolve(displayScale: displayScale, override: tierOverride)
    }

    var body: some View {
        ZStack {
            PlinkShell.background

            if reduceMotion {
                glow(phase: 0)
            } else {
                TimelineView(.animation(minimumInterval: tier.decorativeFrameInterval,
                                        paused: ProcessInfo.processInfo.isLowPowerModeEnabled)) { context in
                    glow(phase: context.date.timeIntervalSinceReferenceDate)
                }
            }

            // Виньетка: края темнее, знак и форма читаются на чистом чёрном.
            // Центр — по сиянию, не по геометрическому центру экрана: сияние
            // стоит в верхней трети (y 0.28), и виньетка с center: .center
            // расходилась с ним примерно на 85 pt — светлое пятно было выше
            // прозрачного окна виньетки, и та подъедала знак сверху.
            RadialGradient(
                colors: [.clear, PlinkShell.background.opacity(0.85)],
                center: glowCenter,
                startRadius: 180,
                endRadius: 620
            )
            .blendMode(.multiply)
            .allowsHitTesting(false)

            PlinkDither()
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

            // Три орба СКЛАДЫВАЮТ свет (plusLighter), а не кладутся друг на
            // друга обычным source-over. При обычном режиме тёмный plum-орб
            // лежал поверх светлого и выгрызал в сиянии тёмное пятно — то
            // самое «чёрное пятно вместо градиента». Складывать свет физически
            // верно: источники света не заслоняют друг друга, и plum теперь
            // добавляет глубину цвета вместо того, чтобы гасить яркость.
            ZStack {
                // Основное сияние — цвет светлой стрелки.
                orb(
                    color: PlinkBrandPalette.violetLight,
                    opacity: (0.34 + 0.06 * breathe) * glowStrength,
                    diameter: radius * 2,
                    blur: 90,
                    at: center
                )

                // Глубокое ядро — тёмный хвост знака, чуть ниже и левее.
                orb(
                    color: PlinkBrandPalette.plum,
                    opacity: 0.55 * glowStrength,
                    diameter: radius * 1.3,
                    blur: 70,
                    at: CGPoint(x: center.x - size.width * 0.16, y: center.y + size.width * 0.18)
                )

                // Холодный синий отблеск справа — третий цвет теглайна. На
                // классике его нет: даёт он меньше всех, а стоит столько же,
                // сколько главное сияние.
                if tier.decorativeOrbCount >= 3 {
                    orb(
                        color: PlinkBrandPalette.violetDeep,
                        opacity: (0.22 + 0.05 * breathe) * glowStrength,
                        diameter: radius * 1.1,
                        blur: 80,
                        at: CGPoint(x: center.x + size.width * 0.22, y: center.y - size.width * 0.08)
                    )
                }
            }
            .compositingGroup()
            .opacity(reduceTransparency ? 0.55 : 1)
        }
        .ignoresSafeArea()
    }

    /// Один источник света.
    ///
    /// Современный класс рисует его так, как задумано оптически: плотный диск
    /// под гауссовым размытием — размытие даёт правильный, чуть «жирный» к
    /// центру спад, который градиентом точно не повторить.
    ///
    /// Классике то же самое рисуется БЕЗ размытия — радиальным градиентом по
    /// диску, растянутым на диаметр размытого пятна. Причина не только в цене:
    /// урезать радиус размытия нельзя. Первая версия правки просто множила
    /// радиус на 0,6, и на снимке `21-device-tier` у левого орба проступила
    /// дуга — кромка самого круга. Дешевле и честнее убрать гауссов проход
    /// целиком: у градиента кромки нет по определению, а офскрин-буфера под
    /// размытие он не просит вовсе.
    private func orb(color: Color, opacity: Double, diameter: CGFloat,
                     blur: CGFloat, at point: CGPoint) -> some View {
        let tinted = color.opacity(opacity)
        return Group {
            if reduceTransparency {
                Circle()
                    .fill(tinted)
                    .frame(width: diameter, height: diameter)
                    .position(point)
            } else if !tier.usesBlurredOrbs {
                // Диаметр = диск плюс размытие с обеих сторон: пятно должно
                // накрыть ту же площадь, что и размытый вариант.
                let spread = diameter + blur * 2
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                Gradient.Stop(color: tinted, location: 0),
                                Gradient.Stop(color: color.opacity(opacity * 0.62), location: 0.42),
                                Gradient.Stop(color: color.opacity(opacity * 0.20), location: 0.70),
                                Gradient.Stop(color: color.opacity(0), location: 1),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: spread / 2
                        )
                    )
                    .frame(width: spread, height: spread)
                    .position(point)
            } else {
                Circle()
                    .fill(tinted)
                    .frame(width: diameter, height: diameter)
                    .position(point)
                    .blur(radius: blur)
            }
        }
        .blendMode(.plusLighter)
    }
}

// MARK: - Дизеринг

/// Тонкий шум поверх фона шелла.
///
/// Плавный фиолетовый по почти-чёрному на восьми битах ложится ступенями:
/// на живом кадре сплэша мерили вертикальный скан — попадались площадки до
/// 108 пикселей (36 pt) одного значения, и переход между ними виден глазу
/// кольцом. Это классический бандинг больших размытых градиентов, лечится он
/// не размытием, а дизерингом: шум амплитудой в один-два уровня разбивает
/// ступень, а сам на глаз не читается.
///
/// Плитка строится один раз и детерминированно (свой LCG, а не
/// `random(in:)`): офскрин-снимки дизайна обязаны совпадать байт в байт.
struct PlinkDither: View {
    /// Насколько сильно шум подсвечивает пиксель. 1 = один уровень из 255.
    var amplitude: Double = 2.2

    var body: some View {
        Image(uiImage: Self.tile)
            .resizable(resizingMode: .tile)
            // Без этого шум бесполезен. Плитка нарисована в масштабе 1, экран
            // рисует в 2–3×, и сглаживание при растяжении усредняет соседей:
            // замер по столбцу входа показывал площадки в 96, 78, 65 px —
            // ровно тот бандинг, ради которого шум и добавлен.
            .interpolation(.none)
            .blendMode(.plusLighter)
            // Амплитуда — В УРОВНЯХ ВОСЬМИБИТНОГО КАНАЛА, отсюда деление на
            // 255. Альфа в плитке равномерна на [0,1), значит пиксель
            // подсвечивается не более чем на `amplitude` уровня. Ошибиться
            // тут — не мелочь: делитель 3 вместо 255 даёт до 136 уровней
            // белого, и вместо дизеринга на экране лежит снег.
            .opacity(amplitude / 255.0)
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }

    /// 96×96 белых точек со случайной альфой. Отрисовывается в нативном
    /// масштабе экрана, чтобы на @3x одна точка шума ложилась в один пиксель,
    /// а не в блок 3×3.
    private static let tile: UIImage = {
        let side = 96
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            // xorshift64*: короткий, детерминированный, без зависимости от
            // системного генератора (у него нет стабильного зерна).
            seed ^= seed >> 12
            seed ^= seed << 25
            seed ^= seed >> 27
            return Double((seed &* 2685821657736338717) >> 40) / Double(1 << 24)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            for y in 0..<side {
                for x in 0..<side {
                    UIColor(white: 1, alpha: next()).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()
}
