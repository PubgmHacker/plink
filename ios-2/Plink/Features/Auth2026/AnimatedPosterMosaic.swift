// Plink/Features/Auth2026/AnimatedPosterMosaic.swift — Auth 2026 redesign
//
// РЕДИЗАЙН: веер постеров удалён. Файл переиспользован под фирменный
// кино-фон авторизации — бархат зала + луч проектора + медленная
// «пыль в луче» (тихий teal-дрейф), и логотип «кадр в кадр».
//
// Доступность / энергия:
//   - Reduce Motion → статичный кадр (без TimelineView)
//   - Reduce Transparency → чистый бархат без свечений
//   - Low Power / термотроттлинг → статичный кадр
//   - Фон приложения (scenePhase) → статичный кадр

import SwiftUI

// MARK: - Палитра «кинозал» (auth-экраны)

enum PlinkTheatre {
    // Монохромный бренд-шелл (решение 26.07.2026): обёртка приложения —
    // чёрное с белым, как маркетинг Rave/Hearo. Цвет живёт ВНУТРИ продукта
    // (живые темы комнат), поэтому сплэш и вход не привязаны ни к одной теме.
    /// Глубочайший бархат — темнота зала.
    static let velvetDeep = Color(hex: 0x070809)
    /// Подсвеченная часть зала.
    static let velvet = Color(hex: 0x101314)
    /// Свет экрана — основной текст.
    static let screen = Color(hex: 0xF2F4F3)
    /// Вторичный текст, моно-подписи.
    static let muted = Color(hex: 0x98A3A0)
    /// Акцент шелла — свет проектора (бывший teal).
    static let teal = Color(hex: 0xF2F4F3)
    static let tealBright = Color.white
    /// Аудит 03.08.2026: был мятный #19E0C0 — последний след третьей палитры.
    /// Монохром шелла (решение 26.07.2026) сохранён, но точки, где цвет всё
    /// же появляется — фокус полей, градиент «пуска», — теперь совпадают с
    /// акцентом приложения, а не спорят с ним.
    static let tealDeep = Color(hex: 0x2E7BFF)
    /// Янтарь ламп — ТОЛЬКО ошибки и предупреждения, точечно.
    static let amber = Color(hex: 0xF5C26B)

    static let tealGradient = LinearGradient(
        colors: [tealBright, tealDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    /// Градиент «пуска» — единственное цветное пятно монохромного шелла.
    /// Белый переходит в акцент только к дальнему углу, поэтому кнопка
    /// читается как белая с подсветкой, а не как цветная плашка.
    static let ignitionGradient = LinearGradient(
        stops: [
            .init(color: .white, location: 0.0),
            .init(color: Color(hex: 0xEAF1FF), location: 0.42),
            .init(color: Color(hex: 0x9CC2FF), location: 0.78),
            .init(color: tealDeep, location: 1.0),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    /// Тонкая рамка стеклянных поверхностей.
    static let hairline = Color.white.opacity(0.08)
}

// MARK: - Фон: бархат + луч проектора

struct ProjectorBeamBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase

    private var animationEnabled: Bool {
        !reduceMotion
            && scenePhase == .active
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
            && ProcessInfo.processInfo.thermalState == .nominal
    }

    var body: some View {
        ZStack {
            // Бархатная база.
            LinearGradient(
                stops: [
                    .init(color: PlinkTheatre.velvetDeep, location: 0),
                    .init(color: PlinkTheatre.velvet, location: 0.40),
                    .init(color: PlinkTheatre.velvetDeep, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // «Пыль в луче» — медленный teal-дрейф по синусоидам.
            if !reduceTransparency {
                if animationEnabled {
                    TimelineView(.animation(minimumInterval: 1 / 24)) { timeline in
                        driftCanvas(t: timeline.date.timeIntervalSinceReferenceDate)
                    }
                } else {
                    driftCanvas(t: 40) // застывший, но выразительный кадр
                }
            }

            // Луч проектора — из-за верхней кромки экрана.
            GeometryReader { proxy in
                beam(in: proxy.size)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func driftCanvas(t: TimeInterval) -> some View {
        Canvas { ctx, size in
            ctx.addFilter(.blur(radius: 56))
            // (цвет, относительный диаметр, скорость, фаза, непрозрачность)
            let blobs: [(Color, CGFloat, Double, Double, Double)] = [
                (PlinkTheatre.teal,     0.62, 0.11, 0.0, 0.10),
                (PlinkTheatre.tealDeep, 0.52, 0.08, 2.4, 0.12),
                (PlinkTheatre.screen,   0.40, 0.10, 4.6, 0.035)
            ]
            for (color, r, speed, phase, opacity) in blobs {
                let x = size.width * (0.5 + 0.34 * cos(t * speed + phase))
                let y = size.height * (0.44 + 0.30 * sin(t * speed * 0.8 + phase))
                let d = size.width * r
                let rect = CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)
                ctx.fill(Ellipse().path(in: rect), with: .color(color.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
    }

    private func beam(in size: CGSize) -> some View {
        let apexX = size.width * 0.5
        let topY: CGFloat = -70
        let bottomY = size.height * 0.60

        var cone = Path()
        cone.move(to: CGPoint(x: apexX - 16, y: topY))
        cone.addLine(to: CGPoint(x: apexX + 16, y: topY))
        cone.addLine(to: CGPoint(x: apexX + size.width * 0.38, y: bottomY))
        cone.addLine(to: CGPoint(x: apexX - size.width * 0.38, y: bottomY))
        cone.closeSubpath()

        return ZStack {
            cone.fill(
                LinearGradient(
                    stops: [
                        .init(color: PlinkTheatre.screen.opacity(0.15), location: 0),
                        .init(color: PlinkTheatre.screen.opacity(0.05), location: 0.55),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .blur(radius: 26)
            .blendMode(.screen)

            // Свечение «объектива» у источника луча.
            Circle()
                .fill(PlinkTheatre.screen.opacity(0.18))
                .frame(width: 72, height: 72)
                .blur(radius: 32)
                .position(x: apexX, y: topY + 30)
                .blendMode(.screen)
        }
    }
}
