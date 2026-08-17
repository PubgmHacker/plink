// Plink/Features/WatchRoom/PlinkSeekBar.swift — PATCH 02 polish
//
// Professional sizing:
//   - Track: 6pt idle (was 2pt), 8pt scrubbing (was 4pt)
//   - Thumb: 14pt idle (was 10pt), 18pt scrubbing (was 16pt)
//   - Played portion: solid magenta (was gradient) — cleaner
//   - Buffered: white opacity 0.22 (was 0.25)
//   - Subtle thumb glow when scrubbing
//   - Haptic on commit
//
// Touch zone is the full 28pt frame (set by caller), so the visible track
// can stay slim while the gesture target stays generous.

import SwiftUI
import UIKit

struct PlinkSeekBar: View {
    @Binding var value: Double
    let buffered: Double
    let duration: Double
    @Binding var isScrubbing: Bool
    let enabled: Bool
    let onCommit: (Double) -> Void

    @State private var haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let trackHeight: CGFloat = isScrubbing ? 8 : 6
            let thumbSize: CGFloat = isScrubbing ? 18 : 14
            let played = max(0, min(1, value / duration))
            let loaded = max(0, min(1, buffered))

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(height: trackHeight)

                // Buffered portion
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(width: width * loaded, height: trackHeight)

                // Played portion
                Capsule()
                    .fill(Cinema2026.accent)
                    .frame(width: width * played, height: trackHeight)

                // Thumb
                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(
                        color: Cinema2026.accent.opacity(isScrubbing ? 0.6 : 0),
                        radius: isScrubbing ? 8 : 0
                    )
                    .offset(x: max(0, min(width - thumbSize, width * played - thumbSize / 2)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard enabled else { return }
                        if !isScrubbing {
                            isScrubbing = true
                            haptic.impactOccurred()
                        }
                        value = max(0, min(duration, Double(gesture.location.x / width) * duration))
                    }
                    .onEnded { _ in
                        guard enabled else { return }
                        isScrubbing = false
                        haptic.impactOccurred(intensity: 0.7)
                        onCommit(value)
                    }
            )
        }
        .opacity(enabled ? 1 : 0.45)
    }
}
