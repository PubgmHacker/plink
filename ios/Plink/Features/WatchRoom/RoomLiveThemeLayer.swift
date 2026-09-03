// Plink/Features/WatchRoom/RoomLiveThemeLayer.swift
//
// P1 5.11 — живые темы комнаты (Plink+) наконец-то видны.
//
// Пять тем каталога AppearanceCatalog.roomLive рисуются РАЗНЫМИ мотивами:
// пыль в холодном зале, неоновый дождь, полярные ленты, каустика глубины,
// расфокусированные пятна афтепати. Иначе платить за них не за что.
//
// Где живёт слой: амбиентная подложка комнаты — ПОД контентом (плеер, чат,
// управление рисуются поверх). Слой никогда не перекрывает видео и не ловит
// касания.
//
// Энергия и доступность (образец — PlinkShellBackground, фон шелла
// сплэша/входа/онбординга):
//   - Reduce Motion            → статичный кадр
//   - Low Power Mode           → статичный кадр
//   - thermalState != .nominal → статичный кадр
//   - сцена не .active         → статичный кадр (никакого рендера в фоне)
//   - Reduce Transparency      → интенсивность режется, мотив не рисуется
//   - motionEnabled = false у самой темы → статичный кадр
//   - suppressed (landscape)   → слой не рисуется вовсе
// Ни Metal, ни CADisplayLink: только SwiftUI Canvas на 20 к/с.
//
// Ревью 26.07.2026:
//   - Low Power / thermalState теперь ОТСЛЕЖИВАЮТСЯ (раньше читались снимком
//     при вычислении body, и уже запущенная анимация не останавливалась).
//   - В landscape подложку целиком перекрывает PlayerStage.ignoresSafeArea()
//     (WatchLayouts.swift), а SwiftUI не делает occlusion culling — поэтому
//     там слой не рисуется вообще (`suppressed`), а не крутит невидимый
//     TimelineView с полноэкранными blur-фильтрами.

import SwiftUI
import Combine

// MARK: - Стили

/// Живые темы комнаты. rawValue = id из AppearanceCatalog.roomLive.
/// Тема, которой здесь нет, рендерится как «нет живой темы».
enum RoomLiveThemeStyle: String, CaseIterable, Sendable {
    case cinemaDust = "room-cinema-dust"
    case neonRain   = "room-neon-rain"
    case aurora     = "room-aurora"
    case deepSea    = "room-deep-sea"
    case afterparty = "room-afterparty"
}

// MARK: - Палитра

/// Три цвета темы из каталога: глубина, средний тон, блик.
struct RoomLiveThemePalette: Equatable {
    let deep: Color
    let mid: Color
    let hi: Color

    static func forTheme(_ themeId: String) -> RoomLiveThemePalette {
        // Ревью: без модульного Array[safe:] — явная проверка indices здесь
        // локальна и не создаёт общего расширения-ловушки на весь проект.
        let hexes = RoomAppearanceRegistry.resolve(themeId: themeId)?.previewColors ?? []
        func hex(_ index: Int) -> String? {
            hexes.indices.contains(index) ? hexes[index] : nil
        }
        return RoomLiveThemePalette(
            deep: Color(hex: hex(0) ?? "#0A0E1A"),
            mid: Color(hex: hex(1) ?? "#1A1F3A"),
            hi: Color(hex: hex(2) ?? hex(1) ?? "#3FE8C8")
        )
    }
}

// MARK: - Публичные помощники для соседних поверхностей

enum RoomLiveTheme {
    /// Живая тема реально выбрана и её умеет рисовать этот слой.
    static func isActive(_ appearance: RoomAppearance) -> Bool {
        appearance.isLiveTheme && RoomLiveThemeStyle(rawValue: appearance.themeId) != nil
    }

    /// Плотность скрима над подложкой для поверхностей с текстом (чат,
    /// пресенс-бар). Читаемость важнее темы: чем ярче тема, тем плотнее скрим.
    ///
    /// Ревью 26.07.2026 — скрим обязан знать окружение:
    ///   - `reduceTransparency`: «Уменьшение прозрачности» просит НЕПРОЗРАЧНЫЙ
    ///     фон под текстом. Раньше учитывалась только подложка, а скрим всё
    ///     равно уходил в 0.50…0.72 — ровно наоборот тому, что просит настройка.
    ///   - `backdropVisible`: в landscape подложки за поверхностью нет (её
    ///     перекрывает PlayerStage), и полупрозрачный чат показывал бы ВИДЕО
    ///     под текстом. Нет подложки — нет и скрима.
    /// 1.0 означает «рисуй обычный непрозрачный фон, как без живой темы».
    static func scrimOpacity(
        _ appearance: RoomAppearance,
        reduceTransparency: Bool = false,
        backdropVisible: Bool = true
    ) -> Double {
        guard isActive(appearance), !reduceTransparency, backdropVisible else { return 1.0 }
        return 0.72 - min(max(appearance.intensity, 0), 0.44) * 0.5   // 0.72…0.50
    }
}

// MARK: - Подложка

struct RoomLiveThemeBackdrop: View {
    let appearance: RoomAppearance
    /// Слой полностью перекрыт другим контентом (landscape: PlayerStage на весь
    /// холст) — рисовать нечего и незачем.
    var suppressed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase

    /// Энергосбережение и перегрев — НАБЛЮДАЕМОЕ состояние, а не снимок при
    /// вычислении body: иначе уже запущенная анимация продолжала бы крутиться
    /// до следующей случайной перерисовки.
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermalThrottled = ProcessInfo.processInfo.thermalState != .nominal

    /// Кадр, который показывается вместо анимации. Не ноль — чтобы застывшая
    /// картинка была выразительной, а не «всё в одну линию».
    private static let frozenPhase: TimeInterval = 12

    private var style: RoomLiveThemeStyle? {
        RoomLiveThemeStyle(rawValue: appearance.themeId)
    }

    private var animationEnabled: Bool {
        appearance.motionEnabled
            && !reduceMotion
            && scenePhase == .active
            && !lowPower
            && !thermalThrottled
    }

    /// 0…0.44 из RoomAppearance, при Reduce Transparency режем ещё сильнее.
    private var effectiveIntensity: Double {
        let base = min(max(appearance.intensity, 0), 0.44)
        return reduceTransparency ? min(base, 0.20) : base
    }

    var body: some View {
        if let style, !suppressed {
            ZStack {
                baseGradient(style)
                if !reduceTransparency {
                    if animationEnabled {
                        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
                            motif(style, t: timeline.date.timeIntervalSinceReferenceDate)
                        }
                    } else {
                        motif(style, t: Self.frozenPhase)
                    }
                }
                // Виньетка — держит центр экрана (плеер) тёмным.
                RadialGradient(
                    colors: [.clear, Color.black.opacity(0.45)],
                    center: .center,
                    startRadius: 60,
                    endRadius: 620
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: ProcessInfo.thermalStateDidChangeNotification
                )
            ) { _ in
                let throttled = ProcessInfo.processInfo.thermalState != .nominal
                if thermalThrottled != throttled { thermalThrottled = throttled }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: Notification.Name.NSProcessInfoPowerStateDidChange
                )
            ) { _ in
                let saving = ProcessInfo.processInfo.isLowPowerModeEnabled
                if lowPower != saving { lowPower = saving }
            }
            .onAppear {
                // Состояние могло смениться, пока слой был снят с иерархии
                // (например, в landscape) — при возврате синхронизируемся.
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                thermalThrottled = ProcessInfo.processInfo.thermalState != .nominal
            }
        }
    }

    // MARK: База

    private func baseGradient(_ style: RoomLiveThemeStyle) -> some View {
        let palette = RoomLiveThemePalette.forTheme(appearance.themeId)
        let k = effectiveIntensity
        return LinearGradient(
            stops: [
                .init(color: palette.deep, location: 0),
                .init(color: palette.mid.opacity(0.35 + k), location: style == .aurora ? 0.30 : 0.55),
                .init(color: palette.deep, location: 1)
            ],
            startPoint: style == .neonRain ? .top : .topLeading,
            endPoint: style == .neonRain ? .bottom : .bottomTrailing
        )
    }

    // MARK: Мотивы

    @ViewBuilder
    private func motif(_ style: RoomLiveThemeStyle, t: TimeInterval) -> some View {
        let palette = RoomLiveThemePalette.forTheme(appearance.themeId)
        let k = effectiveIntensity
        switch style {
        case .cinemaDust: RoomThemeCanvas.cinemaDust(t: t, palette: palette, intensity: k)
        case .neonRain:   RoomThemeCanvas.neonRain(t: t, palette: palette, intensity: k)
        case .aurora:     RoomThemeCanvas.aurora(t: t, palette: palette, intensity: k)
        case .deepSea:    RoomThemeCanvas.deepSea(t: t, palette: palette, intensity: k)
        case .afterparty: RoomThemeCanvas.afterparty(t: t, palette: palette, intensity: k)
        }
    }
}

// MARK: - Canvas-мотивы

/// Чистые функции рисования: одинаковый вход → одинаковый кадр.
/// Никакого состояния, никаких таймеров — фаза приходит снаружи.
enum RoomThemeCanvas {

    /// Детерминированный «шум» вместо random(): кадр не должен дёргаться.
    private static func hash01(_ i: Int, _ salt: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    // 1. Cinema Dust — холодный зал, пыль в луче.
    static func cinemaDust(t: TimeInterval, palette: RoomLiveThemePalette, intensity: Double) -> some View {
        Canvas { ctx, size in
            var beam = Path()
            beam.move(to: CGPoint(x: size.width * 0.5 - 18, y: -40))
            beam.addLine(to: CGPoint(x: size.width * 0.5 + 18, y: -40))
            beam.addLine(to: CGPoint(x: size.width * 1.05, y: size.height))
            beam.addLine(to: CGPoint(x: -size.width * 0.05, y: size.height))
            beam.closeSubpath()
            ctx.fill(beam, with: .linearGradient(
                Gradient(colors: [palette.hi.opacity(intensity * 0.5), .clear]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))

            var dust = ctx
            dust.addFilter(.blur(radius: 1.6))
            for i in 0..<26 {
                let sx = hash01(i, 1)
                let sy = hash01(i, 2)
                let speed = 0.010 + hash01(i, 3) * 0.020
                let raw = (sy - t * speed).truncatingRemainder(dividingBy: 1.0)
                let yy = raw < 0 ? raw + 1 : raw
                let x = sx + 0.03 * sin(t * 0.18 + Double(i))
                let d = 1.6 + hash01(i, 4) * 3.4
                let rect = CGRect(
                    x: x * size.width - d / 2,
                    y: yy * size.height - d / 2,
                    width: d,
                    height: d
                )
                dust.fill(
                    Ellipse().path(in: rect),
                    with: .color(palette.hi.opacity(intensity * (0.35 + hash01(i, 5) * 0.65)))
                )
            }
        }
    }

    // 2. Neon Rain — вертикальные неоновые следы.
    static func neonRain(t: TimeInterval, palette: RoomLiveThemePalette, intensity: Double) -> some View {
        Canvas { ctx, size in
            ctx.addFilter(.blur(radius: 2.2))
            for i in 0..<28 {
                let x = hash01(i, 11) * size.width
                let speed = 0.10 + hash01(i, 12) * 0.26
                let len = size.height * (0.10 + hash01(i, 13) * 0.22)
                let phase = (hash01(i, 14) + t * speed).truncatingRemainder(dividingBy: 1.0)
                let y = phase * (size.height + len) - len
                let color = hash01(i, 15) > 0.55 ? palette.hi : palette.mid
                let rect = CGRect(x: x, y: y, width: 1.6, height: len)
                ctx.fill(
                    Path(roundedRect: rect, cornerRadius: 0.8),
                    with: .linearGradient(
                        Gradient(colors: [.clear, color.opacity(min(1, intensity * 1.5))]),
                        startPoint: CGPoint(x: rect.minX, y: rect.minY),
                        endPoint: CGPoint(x: rect.minX, y: rect.maxY)
                    )
                )
            }
        }
    }

    // 3. Aurora — медленные широкие ленты.
    static func aurora(t: TimeInterval, palette: RoomLiveThemePalette, intensity: Double) -> some View {
        Canvas { ctx, size in
            ctx.addFilter(.blur(radius: 42))
            let ribbons: [(Color, Double, Double, Double)] = [
                (palette.hi,  0.26, 0.055, 0.0),
                (palette.mid, 0.42, 0.038, 1.7),
                (palette.hi,  0.62, 0.047, 3.4)
            ]
            for (color, yBase, speed, phase) in ribbons {
                var path = Path()
                let steps = 22
                let amp = size.height * 0.09
                path.move(to: CGPoint(x: -20, y: size.height * yBase))
                for s in 0...steps {
                    let px = Double(s) / Double(steps)
                    let y = size.height * yBase + amp * sin(px * 3.1 + t * speed * 6 + phase)
                    path.addLine(to: CGPoint(x: px * size.width + 20, y: y))
                }
                for s in stride(from: steps, through: 0, by: -1) {
                    let px = Double(s) / Double(steps)
                    let y = size.height * yBase
                        + amp * sin(px * 3.1 + t * speed * 6 + phase)
                        + size.height * 0.10
                    path.addLine(to: CGPoint(x: px * size.width + 20, y: y))
                }
                path.closeSubpath()
                ctx.fill(path, with: .color(color.opacity(intensity * 0.9)))
            }
        }
    }

    // 4. Deep Sea — каустика: пересекающиеся световые нити.
    static func deepSea(t: TimeInterval, palette: RoomLiveThemePalette, intensity: Double) -> some View {
        Canvas { ctx, size in
            ctx.addFilter(.blur(radius: 14))
            for i in 0..<7 {
                var path = Path()
                let steps = 26
                let yBase = (Double(i) + 0.6) / 7.5
                let amp = size.height * (0.02 + hash01(i, 21) * 0.05)
                let speed = 0.20 + hash01(i, 22) * 0.35
                for s in 0...steps {
                    let px = Double(s) / Double(steps)
                    let y = size.height * yBase
                        + amp * sin(px * 6.0 + t * speed + Double(i))
                        + amp * 0.6 * cos(px * 2.4 - t * speed * 0.7)
                    let point = CGPoint(x: px * size.width, y: y)
                    if s == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                ctx.stroke(
                    path,
                    with: .color(palette.hi.opacity(intensity * (0.30 + hash01(i, 23) * 0.5))),
                    lineWidth: 1.0 + hash01(i, 24) * 2.2
                )
            }
            ctx.fill(
                Path(CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height * 0.5))),
                with: .linearGradient(
                    Gradient(colors: [palette.mid.opacity(intensity * 0.8), .clear]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height * 0.5)
                )
            )
        }
    }

    // 5. Afterparty — расфокусированные цветные пятна.
    static func afterparty(t: TimeInterval, palette: RoomLiveThemePalette, intensity: Double) -> some View {
        Canvas { ctx, size in
            ctx.addFilter(.blur(radius: 38))
            for i in 0..<9 {
                let speed = 0.05 + hash01(i, 31) * 0.09
                let phase = hash01(i, 32) * 6.28
                let x = size.width * (0.12 + 0.76 * hash01(i, 33) + 0.06 * sin(t * speed + phase))
                let y = size.height * (0.10 + 0.80 * hash01(i, 34) + 0.05 * cos(t * speed * 1.3 + phase))
                let d = size.width * (0.12 + hash01(i, 35) * 0.20)
                let pulse = 0.75 + 0.25 * sin(t * (0.35 + hash01(i, 36) * 0.4) + phase)
                let color = hash01(i, 37) > 0.5 ? palette.hi : palette.mid
                ctx.fill(
                    Ellipse().path(in: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)),
                    with: .color(color.opacity(intensity * 0.85 * pulse))
                )
            }
        }
    }
}
