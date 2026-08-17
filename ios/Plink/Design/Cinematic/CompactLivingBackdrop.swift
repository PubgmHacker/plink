// Plink/Design/Cinematic/CompactLivingBackdrop.swift — §7 Final Unified + Brain Phase 8
//
// Subtle ambient backdrop with accessibility + power gating.
//
// Brain Phase 8: backdrop is driven by an artwork palette (extracted from
// a thumbnail) when available, falling back to a flat color pair when not.
// Never captures YouTube/WKWebView/DRM frames — palette comes from a
// separate thumbnail AsyncImage load.
//
// Accessibility:
//   - Reduce Motion: animation disabled, palette shown static.
//   - Reduce Transparency: blurred circles removed, only base color.
//   - Low Power Mode: animation disabled (processInfo.isLowPowerModeEnabled).
//   - Thermal state: animation disabled when processInfo.thermalState >= .fair.
//
// The animation uses .task(id: scenePhase) so it pauses when backgrounded.

import SwiftUI
import UIKit

/// Precomputed palette extracted from artwork (e.g. movie poster thumbnail).
/// Built by `LivingBackdropPalette.extract(from:)` on a background thread.
struct LivingBackdropPalette: Sendable, Equatable {
    let primary: Color
    let secondary: Color
    let accent: Color

    /// Default Cinema2026 palette when no artwork is available.
    static let cinema2026 = LivingBackdropPalette(
        primary: Cinema2026.accent,
        secondary: Cinema2026.amber,
        accent: Cinema2026.accent
    )

    /// Extract a 3-color palette from a UIImage.
    /// Samples 9 points on a 3×3 grid, picks the most saturated, the
    /// second-most-saturated, and the average as accent.
    static func extract(from image: UIImage) -> LivingBackdropPalette {
        let cgImage = image.cgImage
        guard let cgImage else { return .cinema2026 }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .cinema2026 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Sample 9 points on a 3×3 grid (avoid edges).
        let samplePoints: [(Int, Int)] = [
            (width / 4, height / 4),
            (width / 2, height / 4),
            (3 * width / 4, height / 4),
            (width / 4, height / 2),
            (width / 2, height / 2),
            (3 * width / 4, height / 2),
            (width / 4, 3 * height / 4),
            (width / 2, 3 * height / 4),
            (3 * width / 4, 3 * height / 4),
        ]

        var samples: [(r: Double, g: Double, b: Double, saturation: Double, brightness: Double)] = []
        for (x, y) in samplePoints {
            let offset = (y * bytesPerRow) + (x * bytesPerPixel)
            guard offset + 2 < pixelData.count else { continue }
            let r = Double(pixelData[offset]) / 255.0
            let g = Double(pixelData[offset + 1]) / 255.0
            let b = Double(pixelData[offset + 2]) / 255.0
            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            let delta = maxC - minC
            let brightness = maxC
            let saturation = brightness > 0 ? delta / brightness : 0
            samples.append((r, g, b, saturation, brightness))
        }

        guard samples.count >= 2 else { return .cinema2026 }

        // Sort by saturation desc — pick most saturated as primary.
        let sortedBySat = samples.sorted { $0.saturation > $1.saturation }
        let primarySample = sortedBySat[0]
        let secondarySample = sortedBySat[1]
        // Accent = average of all samples.
        let avgR = samples.map(\.r).reduce(0, +) / Double(samples.count)
        let avgG = samples.map(\.g).reduce(0, +) / Double(samples.count)
        let avgB = samples.map(\.b).reduce(0, +) / Double(samples.count)

        return LivingBackdropPalette(
            primary: Color(red: primarySample.r, green: primarySample.g, blue: primarySample.b),
            secondary: Color(red: secondarySample.r, green: secondarySample.g, blue: secondarySample.b),
            accent: Color(red: avgR, green: avgG, blue: avgB)
        )
    }
}

struct CompactLivingBackdrop: View {
    /// Artwork-driven palette (preferred). Falls back to Cinema2026 defaults.
    let palette: LivingBackdropPalette

    init(palette: LivingBackdropPalette = .cinema2026) {
        self.palette = palette
    }

    /// Legacy initializer — accepts raw colors and builds a palette.
    init(primary: Color, secondary: Color) {
        self.palette = LivingBackdropPalette(primary: primary, secondary: secondary, accent: primary)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = false

    /// Brain Phase 8: respect Low Power Mode and thermal state.
    private var isLowPower: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    private var isThermalStressed: Bool {
        ProcessInfo.processInfo.thermalState == .fair
            || ProcessInfo.processInfo.thermalState == .serious
            || ProcessInfo.processInfo.thermalState == .critical
    }
    private var animationEnabled: Bool {
        !reduceMotion && !isLowPower && !isThermalStressed
    }

    var body: some View {
        ZStack {
            Cinema2026.background
            if !reduceTransparency {
                Circle()
                    .fill(palette.primary.opacity(0.18))
                    .frame(width: 260, height: 260)
                    .blur(radius: 68)
                    .offset(x: phase ? 82 : -68, y: phase ? -90 : 44)

                Circle()
                    .fill(palette.secondary.opacity(0.13))
                    .frame(width: 230, height: 230)
                    .blur(radius: 76)
                    .offset(x: phase ? -76 : 90, y: phase ? 110 : -56)

                // Accent dot — subtle third color for depth.
                Circle()
                    .fill(palette.accent.opacity(0.08))
                    .frame(width: 180, height: 180)
                    .blur(radius: 90)
                    .offset(x: phase ? 40 : -40, y: phase ? 60 : -60)
            }
        }
        .task(id: "\(scenePhase)-\(animationEnabled)") {
            guard scenePhase == .active, animationEnabled else {
                phase = false
                return
            }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }
}
