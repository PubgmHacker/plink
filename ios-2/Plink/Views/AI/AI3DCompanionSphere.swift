// Plink/Views/AI/AI3DCompanionSphere.swift
// Siri/Sber-style 3D glass sphere for Plink AI companion.
// Color + motion depend on AIOrbState (idle / listening / thinking / speaking / error).

import SwiftUI
import SceneKit
import UIKit

// MARK: - State palette

struct AISpherePalette {
    let core: UIColor
    let mid: UIColor
    let rim: UIColor
    let glow: Color
    let particle: UIColor
    let pulseSpeed: Float
    let spinSpeed: Float
    let scaleAmp: Float

    static func forState(_ state: AIOrbState, themeAccent: Color) -> AISpherePalette {
        switch state {
        case .idle:
            return AISpherePalette(
                core: UIColor(red: 0.55, green: 0.95, blue: 0.98, alpha: 1),
                mid: UIColor(red: 0.18, green: 0.78, blue: 0.92, alpha: 1),
                rim: UIColor(red: 0.08, green: 0.35, blue: 0.55, alpha: 1),
                glow: Color(red: 0.18, green: 0.85, blue: 0.95),
                particle: UIColor(red: 0.6, green: 0.95, blue: 1, alpha: 0.9),
                pulseSpeed: 0.9,
                spinSpeed: 0.35,
                scaleAmp: 0.04
            )
        case .listening:
            return AISpherePalette(
                core: UIColor(red: 0.75, green: 0.85, blue: 1.0, alpha: 1),
                mid: UIColor(red: 0.35, green: 0.45, blue: 1.0, alpha: 1),
                rim: UIColor(red: 0.25, green: 0.15, blue: 0.75, alpha: 1),
                glow: Color(red: 0.45, green: 0.55, blue: 1.0),
                particle: UIColor(red: 0.7, green: 0.75, blue: 1, alpha: 0.95),
                pulseSpeed: 1.8,
                spinSpeed: 0.9,
                scaleAmp: 0.08
            )
        case .thinking:
            return AISpherePalette(
                core: UIColor(red: 0.95, green: 0.7, blue: 1.0, alpha: 1),
                mid: UIColor(red: 0.75, green: 0.25, blue: 0.95, alpha: 1),
                rim: UIColor(red: 0.35, green: 0.05, blue: 0.55, alpha: 1),
                glow: Color(red: 0.85, green: 0.35, blue: 1.0),
                particle: UIColor(red: 0.95, green: 0.6, blue: 1, alpha: 1),
                pulseSpeed: 3.2,
                spinSpeed: 2.4,
                scaleAmp: 0.1
            )
        case .speaking:
            return AISpherePalette(
                core: UIColor(red: 0.7, green: 1.0, blue: 0.85, alpha: 1),
                mid: UIColor(red: 0.15, green: 0.9, blue: 0.65, alpha: 1),
                rim: UIColor(red: 0.05, green: 0.4, blue: 0.35, alpha: 1),
                glow: Color(red: 0.2, green: 0.95, blue: 0.7),
                particle: UIColor(red: 0.55, green: 1, blue: 0.8, alpha: 1),
                pulseSpeed: 2.6,
                spinSpeed: 1.4,
                scaleAmp: 0.12
            )
        case .error:
            return AISpherePalette(
                core: UIColor(red: 1.0, green: 0.75, blue: 0.7, alpha: 1),
                mid: UIColor(red: 0.95, green: 0.3, blue: 0.35, alpha: 1),
                rim: UIColor(red: 0.45, green: 0.05, blue: 0.1, alpha: 1),
                glow: Color(red: 1.0, green: 0.35, blue: 0.4),
                particle: UIColor(red: 1, green: 0.55, blue: 0.55, alpha: 1),
                pulseSpeed: 1.2,
                spinSpeed: 0.5,
                scaleAmp: 0.05
            )
        }
    }
}

// MARK: - SwiftUI wrapper

/// Drop-in 3D companion used by V4 AI tab (header + hero).
struct AI3DCompanionSphere: View {
    let theme: V4Theme
    var size: CGFloat = 220
    var glow: CGFloat = 48
    var state: AIOrbState = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: AISpherePalette {
        AISpherePalette.forState(state, themeAccent: theme.accentColor)
    }

    var body: some View {
        ZStack {
            // Outer atmospheric glow (SwiftUI — soft and cheap)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            palette.glow.opacity(state == .idle ? 0.35 : 0.55),
                            palette.glow.opacity(0.12),
                            .clear,
                        ],
                        center: .center,
                        startRadius: size * 0.12,
                        endRadius: size * 0.62
                    )
                )
                .frame(width: size * 1.35, height: size * 1.35)
                .blur(radius: reduceMotion ? 8 : 18)
                .scaleEffect(reduceMotion ? 1 : pulseScale)
                .animation(
                    reduceMotion
                        ? .default
                        : .easeInOut(duration: Double(1.2 / max(palette.pulseSpeed, 0.4)))
                        .repeatForever(autoreverses: true),
                    value: state
                )

            // Real SceneKit sphere
            AISceneSphereRepresentable(
                palette: palette,
                reduceMotion: reduceMotion,
                state: state
            )
            .frame(width: size, height: size)
            .clipShape(Circle())
            .shadow(color: palette.glow.opacity(0.55), radius: glow * 0.45)
            .shadow(color: palette.glow.opacity(0.25), radius: glow)

            // Specular glass highlight (2D overlay for “liquid glass”)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.12),
                            .clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .frame(width: size * 0.72, height: size * 0.72)
                .offset(x: -size * 0.06, y: -size * 0.1)
                .blur(radius: 1.5)
                .allowsHitTesting(false)

            // State ring
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            palette.glow.opacity(0.05),
                            palette.glow.opacity(0.85),
                            palette.glow.opacity(0.15),
                            palette.glow.opacity(0.7),
                            palette.glow.opacity(0.05),
                        ],
                        center: .center
                    ),
                    lineWidth: state == .thinking ? 2.5 : 1.5
                )
                .frame(width: size * 1.08, height: size * 1.08)
                .rotationEffect(.degrees(ringAngle))
                .opacity(state == .idle ? 0.45 : 0.9)
        }
        .frame(width: size * 1.4, height: size * 1.4)
        .accessibilityLabel(accessibilityLabel)
    }

    private var pulseScale: CGFloat {
        switch state {
        case .idle: return 1.05
        case .listening: return 1.12
        case .thinking: return 1.18
        case .speaking: return 1.15
        case .error: return 1.06
        }
    }

    private var ringAngle: Double {
        // Driven by TimelineView-less continuous animation via state change
        // Use a constant spin via Animation on appear — SceneKit handles main spin.
        0
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: return "Plink AI, готов"
        case .listening: return "Plink AI, слушает"
        case .thinking: return "Plink AI, думает"
        case .speaking: return "Plink AI, отвечает"
        case .error: return "Plink AI, ошибка"
        }
    }
}

// MARK: - SceneKit sphere

private struct AISceneSphereRepresentable: UIViewRepresentable {
    var palette: AISpherePalette
    var reduceMotion: Bool
    var state: AIOrbState

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = makeScene()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = reduceMotion ? 30 : 60
        context.coordinator.view = view
        context.coordinator.apply(palette: palette, reduceMotion: reduceMotion, state: state, animated: false)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.apply(palette: palette, reduceMotion: reduceMotion, state: state, animated: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 40
        cameraNode.position = SCNVector3(0, 0, 3.2)
        scene.rootNode.addChildNode(cameraNode)

        // Soft lights
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 900
        key.light?.color = UIColor.white
        key.position = SCNVector3(-1.2, 1.6, 2.2)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 400
        fill.light?.color = UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1)
        fill.position = SCNVector3(1.4, -0.8, 1.5)
        scene.rootNode.addChildNode(fill)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 500
        rim.light?.color = UIColor.white
        rim.eulerAngles = SCNVector3(-0.6, 0.8, 0)
        scene.rootNode.addChildNode(rim)

        // Core sphere — glass / metal hybrid
        let sphere = SCNSphere(radius: 1.0)
        sphere.segmentCount = 64
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.metalness.contents = 0.55
        mat.roughness.contents = 0.18
        mat.diffuse.contents = UIColor(red: 0.2, green: 0.75, blue: 0.9, alpha: 1)
        mat.emission.contents = UIColor(red: 0.1, green: 0.5, blue: 0.7, alpha: 1)
        mat.transparent.contents = UIColor(white: 1, alpha: 0.92)
        mat.transparencyMode = .dualLayer
        mat.fresnelExponent = 1.8
        mat.isDoubleSided = false
        sphere.materials = [mat]

        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.name = "core"
        scene.rootNode.addChildNode(sphereNode)

        // Inner energy core (smaller)
        let inner = SCNSphere(radius: 0.55)
        inner.segmentCount = 48
        let innerMat = SCNMaterial()
        innerMat.lightingModel = .constant
        innerMat.diffuse.contents = UIColor.white
        innerMat.emission.contents = UIColor(red: 0.6, green: 0.95, blue: 1, alpha: 1)
        inner.materials = [innerMat]
        let innerNode = SCNNode(geometry: inner)
        innerNode.name = "inner"
        sphereNode.addChildNode(innerNode)

        // Particle shell
        let particleNode = SCNNode()
        particleNode.name = "particles"
        let system = SCNParticleSystem()
        system.birthRate = 28
        system.particleLifeSpan = 2.2
        system.particleSize = 0.035
        system.particleColor = UIColor.cyan
        system.emitterShape = SCNSphere(radius: 1.05)
        system.spreadingAngle = 360
        system.particleVelocity = 0.08
        system.blendMode = .additive
        system.isLocal = true
        particleNode.addParticleSystem(system)
        scene.rootNode.addChildNode(particleNode)

        // Ambient fog-ish: second translucent shell
        let shell = SCNSphere(radius: 1.08)
        shell.segmentCount = 48
        let shellMat = SCNMaterial()
        shellMat.lightingModel = .constant
        shellMat.diffuse.contents = UIColor(white: 1, alpha: 0.08)
        shellMat.transparent.contents = UIColor(white: 1, alpha: 0.15)
        shellMat.transparencyMode = .dualLayer
        shellMat.writesToDepthBuffer = false
        shell.materials = [shellMat]
        let shellNode = SCNNode(geometry: shell)
        shellNode.name = "shell"
        scene.rootNode.addChildNode(shellNode)

        return scene
    }

    final class Coordinator {
        weak var view: SCNView?
        private var currentState: AIOrbState = .idle

        func apply(palette: AISpherePalette, reduceMotion: Bool, state: AIOrbState, animated: Bool) {
            guard let scene = view?.scene else { return }
            guard let core = scene.rootNode.childNode(withName: "core", recursively: false),
                  let mat = core.geometry?.firstMaterial else { return }

            let duration: CFTimeInterval = animated ? 0.45 : 0

            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            mat.diffuse.contents = palette.mid
            mat.emission.contents = palette.core.withAlphaComponent(0.85)
            mat.metalness.contents = state == .thinking ? 0.75 : 0.5
            mat.roughness.contents = state == .listening ? 0.12 : 0.2

            if let inner = core.childNode(withName: "inner", recursively: false),
               let im = inner.geometry?.firstMaterial {
                im.emission.contents = palette.core
                im.diffuse.contents = palette.core
            }

            if let shell = scene.rootNode.childNode(withName: "shell", recursively: false),
               let sm = shell.geometry?.firstMaterial {
                sm.diffuse.contents = palette.mid.withAlphaComponent(0.12)
            }

            if let particles = scene.rootNode.childNode(withName: "particles", recursively: false),
               let sys = particles.particleSystems?.first {
                sys.particleColor = palette.particle
                switch state {
                case .idle:
                    sys.birthRate = reduceMotion ? 8 : 22
                    sys.particleVelocity = 0.06
                case .listening:
                    sys.birthRate = reduceMotion ? 14 : 48
                    sys.particleVelocity = 0.12
                case .thinking:
                    sys.birthRate = reduceMotion ? 18 : 70
                    sys.particleVelocity = 0.18
                case .speaking:
                    sys.birthRate = reduceMotion ? 16 : 55
                    sys.particleVelocity = 0.14
                case .error:
                    sys.birthRate = 12
                    sys.particleVelocity = 0.05
                }
            }

            SCNTransaction.commit()

            // Spin / pulse actions
            core.removeAllActions()
            if !reduceMotion {
                let spin = SCNAction.repeatForever(
                    SCNAction.rotateBy(x: 0, y: CGFloat(palette.spinSpeed * .pi), z: CGFloat(palette.spinSpeed * 0.3), duration: 2.0)
                )
                let pulseUp = SCNAction.scale(to: CGFloat(1.0 + palette.scaleAmp), duration: TimeInterval(0.55 / max(palette.pulseSpeed, 0.3)))
                let pulseDown = SCNAction.scale(to: CGFloat(1.0 - palette.scaleAmp * 0.5), duration: TimeInterval(0.55 / max(palette.pulseSpeed, 0.3)))
                pulseUp.timingMode = .easeInEaseOut
                pulseDown.timingMode = .easeInEaseOut
                let pulse = SCNAction.repeatForever(SCNAction.sequence([pulseUp, pulseDown]))
                core.runAction(SCNAction.group([spin, pulse]), forKey: "live")
            } else {
                core.scale = SCNVector3(1, 1, 1)
            }

            // Tint key light toward palette
            for node in scene.rootNode.childNodes where node.light != nil {
                if node.light?.type == .omni {
                    node.light?.color = palette.mid
                }
            }

            currentState = state
        }
    }
}

// MARK: - Compatibility alias used by V4AIViewLive

/// Keeps existing call sites working: AICompanionModel → 3D sphere.
struct AICompanionModel: View {
    let theme: V4Theme
    var size: CGFloat = 150
    var glow: CGFloat = 42
    var state: AIOrbState = .idle

    var body: some View {
        AI3DCompanionSphere(theme: theme, size: size, glow: glow, state: state)
    }
}
