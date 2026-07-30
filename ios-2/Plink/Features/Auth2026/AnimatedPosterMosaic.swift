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
    static let tealDeep = Color(hex: 0x19E0C0)
    /// Янтарь ламп — ТОЛЬКО ошибки и предупреждения, точечно.
    static let amber = Color(hex: 0xF5C26B)

    static let tealGradient = LinearGradient(
        colors: [tealBright, tealDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    /// Градиент «пуска» — единственное цветное пятно монохромного шелла.
    /// Белый переходит в teal только к дальнему углу, поэтому кнопка читается
    /// как белая с подсветкой, а не как цветная плашка.
    static let ignitionGradient = LinearGradient(
        stops: [
            .init(color: .white, location: 0.0),
            .init(color: Color(hex: 0xEAFBF7), location: 0.42),
            .init(color: Color(hex: 0x8FEEDC), location: 0.78),
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

// MARK: - Логотип «кадр в кадр» (двойной слоёный play-кадр)

/// Скруглённый play-треугольник — один «кадр» логотипа.
/// Совпадает с маркой на сплэше и лендинге.
struct PlinkPlayFrame: Shape {
    var cornerRadius: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        let vertices = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        var path = Path()
        // Старт с середины левой (плоской) грани, углы скругляются дугами.
        let first = vertices[0]
        let last = vertices[vertices.count - 1]
        path.move(to: CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2))
        for index in 0..<vertices.count {
            path.addArc(
                tangent1End: vertices[index],
                tangent2End: vertices[(index + 1) % vertices.count],
                radius: cornerRadius
            )
        }
        path.closeSubpath()
        return path
    }
}

/// Логотип: два play-кадра слоями — «кадр в кадр».
struct PlinkFrameMark: View {
    /// Высота переднего кадра (пропорции 62×70, как на сплэше/лендинге).
    var size: CGFloat = 70

    var body: some View {
        let width = size * 0.886
        let echo = size * 0.115
        let radius = size * 0.13

        ZStack {
            // Эхо-кадр: смещённый задний слой. Раньше он был ЗАЛИТ белым на 35% и
            // на чёрном фоне читался как грязная серая тень, а не как второй кадр.
            // Контур той же формы даёт нужное «кадр в кадр» и не пачкает бренд.
            PlinkPlayFrame(cornerRadius: radius)
                .stroke(PlinkTheatre.screen.opacity(0.28), lineWidth: max(1, size * 0.026))
                .frame(width: width, height: size)
                .offset(x: echo, y: echo)

            // Передний кадр: фирменный teal-градиент с мягким свечением.
            PlinkPlayFrame(cornerRadius: radius)
                .fill(PlinkTheatre.tealGradient)
                .frame(width: width, height: size)
                .shadow(color: PlinkTheatre.teal.opacity(0.45), radius: size * 0.31, y: size * 0.086)
        }
        .frame(width: width + echo, height: size + echo)
        .accessibilityHidden(true)
    }
}
