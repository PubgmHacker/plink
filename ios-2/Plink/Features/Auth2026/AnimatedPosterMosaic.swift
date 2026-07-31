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
    /// Height of the optical frame. The enclosing "screen" gives the mark a
    /// silhouette that remains recognizable at App Icon and compact sizes.
    var size: CGFloat = 70

    var body: some View {
        let width = size * 1.12
        let radius = size * 0.27
        let inset = size * 0.22

        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), Color.white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(1, size * 0.018)
                        )
                )

            // Projected frame: a second, offset outline gives Plink its shared-
            // screen idea without looking like a generic standalone play icon.
            RoundedRectangle(cornerRadius: radius * 0.72, style: .continuous)
                .trim(from: 0.04, to: 0.80)
                .stroke(PlinkTheatre.tealDeep.opacity(0.74), style: StrokeStyle(lineWidth: max(1.5, size * 0.026), lineCap: .round))
                .padding(size * 0.10)
                .offset(x: size * 0.055, y: size * 0.045)
                .blur(radius: size * 0.015)

            PlinkPlayFrame(cornerRadius: size * 0.09)
                .fill(PlinkTheatre.ignitionGradient)
                .frame(width: size * 0.42, height: size * 0.49)
                .offset(x: size * 0.025)
                .shadow(color: PlinkTheatre.tealDeep.opacity(0.38), radius: size * 0.18)

            Ellipse()
                .fill(Color.white.opacity(0.34))
                .frame(width: size * 0.36, height: size * 0.08)
                .blur(radius: size * 0.035)
                .offset(x: -size * 0.16, y: -size * 0.25)
        }
        .frame(width: width, height: size)
        .padding(inset * 0.12)
        .shadow(color: .black.opacity(0.48), radius: size * 0.22, y: size * 0.12)
        .accessibilityHidden(true)
    }
}

/// App-icon artwork: the mark fills the square and reads at small sizes.
/// No iOS-style rounded mask is drawn into the bitmap; the system owns it.
struct AppIconBrandArtwork: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x101B25), Color(hex: 0x05070A), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [PlinkTheatre.tealDeep.opacity(0.35), .clear],
                center: UnitPoint(x: 0.34, y: 0.23),
                startRadius: 0,
                endRadius: 430
            )
            RoundedRectangle(cornerRadius: 235, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 12)
                .padding(82)
            PlinkFrameMark(size: 430)
        }
        .frame(width: 1024, height: 1024)
    }
}

#if DEBUG
#Preview("Plink App Icon") {
    AppIconBrandArtwork()
        .frame(width: 320, height: 320)
}
#endif
