//
//  PlinkLaunchAndBoot.swift
//  Plink
//
//  P1 — Launch Screen + AppBootView experience.
//  Implements Section 6 of PLINK_CUSTOMIZATION_AUTH_ADMIN_SPEC_FOR_GLM_5_2.md
//

import SwiftUI

// MARK: - PlinkLaunchScreen (static)

/// Visually identical to the first frame of AppBootView → no flash.
internal struct PlinkLaunchScreen: View {
    init() {}

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.cyan.opacity(0.18),
                    Color.cyan.opacity(0.0)
                ],
                center: .center,
                startRadius: 0,
                endRadius: 160
            )
            .frame(width: 320, height: 320)
            .ignoresSafeArea()

            Image(systemName: "circle.hexagonpath.fill")
                .font(.system(size: 56, weight: .black))
                .foregroundStyle(Color.cyan)
                .shadow(color: .cyan.opacity(0.6), radius: 24)
        }
    }
}

// MARK: - AppBootView

internal struct AppBootView: View {
    @State private var morphPhase: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var statusOpacity: Double = 0
    @State private var retryOpacity: Double = 0
    @State private var bootStartedAt: Date = .now
    @State private var bootFailed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {}

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                bootOrb
                    .frame(width: 96, height: 96)

                if statusOpacity > 0 {
                    Text("Подключаем Plink")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .opacity(statusOpacity)
                        .transition(.opacity)
                }

                Spacer()

                if retryOpacity > 0 {
                    VStack(spacing: 8) {
                        Text("Нет соединения")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                        Button("Повторить") {
                            Task { await runBoot() }
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    .opacity(retryOpacity)
                    .padding(.bottom, 60)
                }
            }
        }
        .task {
            await runBoot()
        }
    }

    // MARK: - Orb

    @ViewBuilder
    private var bootOrb: some View {
        if reduceMotion {
            Image(systemName: "circle.hexagonpath.fill")
                .font(.system(size: 96, weight: .black))
                .foregroundStyle(Color.cyan)
                .shadow(color: .cyan.opacity(0.6), radius: 18)
                .opacity(glowOpacity)
        } else {
            Canvas { g, size in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
                let path = morphPath(in: rect, phase: morphPhase)
                g.fill(path, with: .color(.cyan))
                g.stroke(path, with: .color(.white.opacity(0.4)), lineWidth: 1.5)
            }
            .shadow(color: .cyan.opacity(0.7), radius: 24)
            .opacity(glowOpacity)
            .scaleEffect(0.92 + 0.08 * morphPhase)
        }
    }

    // MARK: - Boot sequence

    private func runBoot() async {
        bootStartedAt = .now
        bootFailed = false
        statusOpacity = 0
        retryOpacity = 0
        glowOpacity = 0

        // 1. Reveal orb (700ms).
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.22)) { glowOpacity = 1 }
        } else {
            withAnimation(.easeOut(duration: 0.7)) {
                glowOpacity = 1
                morphPhase = 1.0
            }
        }

        // 2. Restore session from real AuthService.
        //    Authenticated fast path: skip remaining animation if token valid.
        let tokenOK = AuthService.shared.authToken != nil
        let userOK = AuthService.shared.currentUserValue != nil

        let elapsed = Date().timeIntervalSince(bootStartedAt)
        if elapsed < 0.7 {
            try? await Task.sleep(nanoseconds: UInt64((0.7 - elapsed) * 1_000_000_000))
        }

        if tokenOK && userOK {
            withAnimation(.easeOut(duration: 0.3)) { glowOpacity = 0 }
            NotificationCenter.default.post(name: .plinkBootCompleted, object: nil)
            return
        }

        // 3. Still loading — show status text.
        withAnimation(.easeIn(duration: 0.3)) { statusOpacity = 1 }

        // 4. Wait up to 4s total.
        let totalElapsed = Date().timeIntervalSince(bootStartedAt)
        let maxWait: TimeInterval = 4.0
        if totalElapsed > maxWait {
            showRetry()
            return
        }
        let remaining = maxWait - totalElapsed
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))

        // 5. Final check.
        let stillFailed = AuthService.shared.authToken == nil
        if stillFailed {
            showRetry()
        } else {
            NotificationCenter.default.post(name: .plinkBootCompleted, object: nil)
        }
    }

    private func showRetry() {
        bootFailed = true
        withAnimation(.easeIn(duration: 0.3)) {
            statusOpacity = 0
            retryOpacity = 1
        }
    }

    // MARK: - Morph path

    private func morphPath(in rect: CGRect, phase: Double) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let r = rect.width / 2

        let sides = 6
        var path = Path()
        let steps = 120
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let angle = t * 2 * .pi
            let hexR = r * (0.92 + 0.08 * cos(Double(sides) * angle))
            let blendR = r * (1.0 - phase) + hexR * phase
            let x = cx + CGFloat(blendR) * CGFloat(cos(angle))
            let y = cy + CGFloat(blendR) * CGFloat(sin(angle))
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Notifications

internal extension Notification.Name {
    static let plinkBootCompleted = Notification.Name("plink.bootCompleted")
}
