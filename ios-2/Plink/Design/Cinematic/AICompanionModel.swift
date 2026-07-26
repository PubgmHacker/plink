// Plink/Design/Cinematic/AICompanionModel.swift
//
// Premium Siri/Sber-style AI Companion orb — pure SwiftUI Canvas/TimelineView.
// No video asset, no pixel model, no UIKit dependency.

import SwiftUI

// MARK: - AI Companion State

enum AICompanionState: String, CaseIterable, Codable, Equatable {
    case idle
    case listening
    case thinking
    case speaking
}

// MARK: - Premium glowing orb

struct SiriGlowingOrbView: View {
    let state: AICompanionState
    var size: CGFloat = 180

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                outerGlow(t)
                fluidCanvas(t)
                    .frame(width: size, height: size)
                    .compositingGroup()
                    .blur(radius: 0.2)
                glassHighlights(t)
                stateWaveform(t)
            }
            .frame(width: size * 1.55, height: size * 1.55)
            .scaleEffect(1 + pulse(t) * palette.scale)
            .animation(.easeInOut(duration: 0.35), value: state)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func outerGlow(_ t: TimeInterval) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            palette.primary.opacity(palette.glowOpacity),
                            palette.secondary.opacity(0.22),
                            .clear,
                        ],
                        center: .center,
                        startRadius: size * 0.08,
                        endRadius: size * 0.82
                    )
                )
                .frame(width: size * 1.45, height: size * 1.45)
                .blur(radius: size * 0.08)

            Circle()
                .stroke(
                    AngularGradient(colors: palette.ringColors, center: .center),
                    lineWidth: state == .idle ? 1.2 : 2.4
                )
                .frame(width: size * 1.08, height: size * 1.08)
                .rotationEffect(.degrees(t * palette.rotation * 20))
                .opacity(state == .idle ? 0.42 : 0.85)
                .blur(radius: 0.4)
        }
    }

    private func fluidCanvas(_ t: TimeInterval) -> some View {
        Canvas { ctx, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(canvasSize.width, canvasSize.height) * 0.43

            let body = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))

            ctx.addFilter(.blur(radius: state == .idle ? 8 : 11))
            for i in 0..<7 {
                let fi = Double(i)
                let speed = palette.speed * (0.65 + fi * 0.11)
                let angle = t * speed + fi * .pi * 0.44
                let wobble = radius * (0.12 + 0.035 * sin(t * 1.7 + fi))
                let blobCenter = CGPoint(
                    x: center.x + cos(angle) * wobble,
                    y: center.y + sin(angle * 1.23) * wobble
                )
                let blobRadius = radius * CGFloat(0.58 + 0.12 * sin(t * 2.1 + fi))
                let color = palette.blobs[i % palette.blobs.count]
                ctx.fill(
                    Path(ellipseIn: CGRect(
                        x: blobCenter.x - blobRadius,
                        y: blobCenter.y - blobRadius,
                        width: blobRadius * 2,
                        height: blobRadius * 2
                    )),
                    with: .radialGradient(
                        Gradient(colors: [color.opacity(0.95), color.opacity(0.0)]),
                        center: blobCenter,
                        startRadius: 0,
                        endRadius: blobRadius
                    )
                )
            }

            ctx.addFilter(.blur(radius: 0))
            ctx.clip(to: body)
            ctx.fill(
                body,
                with: .radialGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.48),
                        palette.primary.opacity(0.7),
                        palette.secondary.opacity(0.58),
                        palette.deep.opacity(0.88),
                    ]),
                    center: CGPoint(x: center.x - radius * 0.25, y: center.y - radius * 0.28),
                    startRadius: 0,
                    endRadius: radius * 1.35
                )
            )

            let rim = Path(ellipseIn: CGRect(
                x: center.x - radius * 0.98,
                y: center.y - radius * 0.98,
                width: radius * 1.96,
                height: radius * 1.96
            ))
            ctx.stroke(rim, with: .color(Color.white.opacity(0.30)), lineWidth: 1.4)
        }
        .clipShape(Circle())
        .shadow(color: palette.primary.opacity(0.55), radius: size * 0.10)
        .shadow(color: palette.secondary.opacity(0.32), radius: size * 0.20)
    }

    private func glassHighlights(_ t: TimeInterval) -> some View {
        ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.72), Color.white.opacity(0.12), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.42, height: size * 0.25)
                .offset(x: -size * 0.17, y: -size * 0.23)
                .rotationEffect(.degrees(-24 + sin(t * 0.7) * 4))
                .blur(radius: 1.1)

            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                .frame(width: size * 0.92, height: size * 0.92)
                .offset(y: -size * 0.01)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func stateWaveform(_ t: TimeInterval) -> some View {
        if state == .speaking || state == .listening || state == .thinking {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(palette.primary.opacity(0.32 - Double(i) * 0.07), lineWidth: 1.6)
                        .frame(
                            width: size * (1.08 + CGFloat(i) * 0.18 + CGFloat(max(0, sin(t * palette.speed + Double(i))) * 0.08)),
                            height: size * (1.08 + CGFloat(i) * 0.18 + CGFloat(max(0, sin(t * palette.speed + Double(i))) * 0.08))
                        )
                        .blur(radius: CGFloat(i) * 0.8)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func pulse(_ t: TimeInterval) -> CGFloat {
        CGFloat((sin(t * palette.speed) + 1) * 0.5)
    }

    private var palette: OrbPalette { OrbPalette(state: state) }

    private var accessibilityLabel: String {
        switch state {
        case .idle: return "Plink AI, готов"
        case .listening: return "Plink AI, слушает"
        case .thinking: return "Plink AI, думает"
        case .speaking: return "Plink AI, отвечает"
        }
    }
}

private struct OrbPalette {
    let primary: Color
    let secondary: Color
    let deep: Color
    let blobs: [Color]
    let ringColors: [Color]
    let speed: Double
    let rotation: Double
    let glowOpacity: Double
    let scale: CGFloat

    init(state: AICompanionState) {
        switch state {
        case .idle:
            primary = Color(red: 0.20, green: 0.76, blue: 1.0)
            secondary = Color(red: 0.43, green: 0.28, blue: 1.0)
            deep = Color(red: 0.08, green: 0.05, blue: 0.30)
            speed = 0.85
            rotation = 0.55
            glowOpacity = 0.46
            scale = 0.035
        case .listening:
            primary = Color(red: 0.15, green: 0.92, blue: 1.0)
            secondary = Color(red: 1.0, green: 0.27, blue: 0.82)
            deep = Color(red: 0.06, green: 0.08, blue: 0.42)
            speed = 2.1
            rotation = 1.25
            glowOpacity = 0.62
            scale = 0.075
        case .thinking:
            primary = Color(red: 1.0, green: 0.25, blue: 0.86)
            secondary = Color(red: 0.24, green: 0.82, blue: 1.0)
            deep = Color(red: 0.22, green: 0.03, blue: 0.38)
            speed = 3.4
            rotation = 2.2
            glowOpacity = 0.70
            scale = 0.10
        case .speaking:
            primary = Color(red: 0.28, green: 1.0, blue: 0.72)
            secondary = Color(red: 0.20, green: 0.66, blue: 1.0)
            deep = Color(red: 0.03, green: 0.25, blue: 0.24)
            speed = 2.7
            rotation = 1.75
            glowOpacity = 0.72
            scale = 0.12
        }
        blobs = [primary, secondary, Color.white.opacity(0.82), primary.mix(with: secondary, by: 0.5)]
        ringColors = [.clear, primary, secondary, Color.white.opacity(0.8), primary, .clear]
    }
}

private extension Color {
    func mix(with other: Color, by amount: Double) -> Color {
        if amount < 0.5 { return self }
        return other
    }
}

// MARK: - Backwards-compatible compact orb

struct AICompanionOrb: View {
    let state: AICompanionState
    var size: CGFloat = 120

    var body: some View {
        SiriGlowingOrbView(state: state, size: size)
            .frame(width: size * 1.55, height: size * 1.55)
    }
}

#if DEBUG
#Preview("Siri Glowing Orb") {
    VStack(spacing: 28) {
        SiriGlowingOrbView(state: .idle, size: 150)
        HStack(spacing: 22) {
            SiriGlowingOrbView(state: .listening, size: 86)
            SiriGlowingOrbView(state: .thinking, size: 86)
            SiriGlowingOrbView(state: .speaking, size: 86)
        }
    }
    .padding(40)
    .background(Cinema2026.background)
    .preferredColorScheme(.dark)
}
#endif
