// Plink/Features/WatchRoom/WatchReactionLayer.swift — PATCH 02 polish
//
// Professional design:
//   - 8 visible reactions (was 5) — feels alive without crowding
//   - Larger emoji: 38pt (was 36pt)
//   - Reduce Motion: static stack top-right (kept)
//   - Soft shadow behind each emoji (new) — lifts off video
//   - .allowsHitTesting(false) so chat stays interactive

import SwiftUI

struct WatchReactionLayer: View {
    let events: [WatchReactionEvent]
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(events.suffix(8)) { reaction in
                    Text(reaction.emoji)
                        .font(.system(size: reduceMotion ? 28 : 38))
                        .position(
                            x: reduceMotion ? proxy.size.width - 44 : reaction.startX * proxy.size.width,
                            y: reduceMotion ? 92 : reaction.currentY(in: proxy.size.height)
                        )
                        .opacity(reaction.opacity)
                        .scaleEffect(reaction.scale)
                        .rotationEffect(.degrees(reduceMotion ? 0 : reaction.rotation))
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
