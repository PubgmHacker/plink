// Plink/DesignSystem/LivingThemes/PlinkLivingBackground.swift — GPT-5.6 §5
import SwiftUI

struct PlinkLivingBackground: View {
    enum Surface { case home, rooms, ai, friends, profile, room, chat }

    let theme: PlinkLivingTheme
    let surface: Surface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase

    private var intensity: Double {
        switch surface {
        case .home: 1.00; case .rooms: 0.82; case .ai: 0.90
        case .friends: 0.68; case .profile: 0.52; case .room: 0.72; case .chat: 0.44
        }
    }

    var body: some View {
        Group {
            if reduceTransparency {
                StaticThemeGradient(theme: theme, intensity: intensity)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                    LivingThemeCanvas(theme: theme, surface: surface, date: timeline.date,
                        animated: !reduceMotion && scenePhase == .active, intensity: intensity)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct StaticThemeGradient: View {
    let theme: PlinkLivingTheme; let intensity: Double
    var body: some View {
        LinearGradient(colors: [theme.colors[0].color, theme.colors[1].color.opacity(intensity * 0.5), theme.colors[0].color],
                       startPoint: .top, endPoint: .bottom)
    }
}

struct LivingThemeCanvas: View {
    let theme: PlinkLivingTheme; let surface: PlinkLivingBackground.Surface
    let date: Date; let animated: Bool; let intensity: Double

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [theme.colors[0].color, theme.colors[0].color.opacity(0.8)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let t = animated ? date.timeIntervalSinceReferenceDate : 0
            let blobs: [(Color, CGPoint, CGFloat, Double)] = [
                (theme.colors[1].color, CGPoint(x: 0.10, y: 0.12), 0.70, 0.393),
                (theme.colors[2].color, CGPoint(x: 0.88, y: 0.35), 0.65, 0.314),
                (theme.colors[2].color, CGPoint(x: 0.45, y: 0.90), 0.72, 0.349),
            ]
            for (i, blob) in blobs.enumerated() {
                let ox = sin(t * blob.3 + Double(i) * 1.7) * 0.10 * (animated ? 1 : 0)
                let oy = cos(t * blob.3 * 0.8 + Double(i)) * 0.08 * (animated ? 1 : 0)
                let d = max(size.width, size.height) * blob.2
                let c = CGPoint(x: size.width * (blob.1.x + ox), y: size.height * (blob.1.y + oy))
                let r = CGRect(x: c.x - d/2, y: c.y - d/2, width: d, height: d)
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: max(42, d * 0.12)))
                    layer.opacity = 0.34 * intensity
                    layer.fill(Path(ellipseIn: rect), with: .color(blob.0))
                    layer.fill(Path(ellipseIn: r), with: .color(blob.0))
                }
            }
            // Vignette
            context.fill(Path(rect), with: .linearGradient(
                Gradient(stops: [.init(color: .clear, location: 0.34),
                                 .init(color: theme.colors[0].color.opacity(0.28 * intensity), location: 0.68),
                                 .init(color: theme.colors[0].color.opacity(0.92), location: 1)]),
                startPoint: CGPoint(x: size.width/2, y: 0), endPoint: CGPoint(x: size.width/2, y: size.height)))
        }
    }
}
