// Plink/Features/Auth2026/AnimatedPosterMosaic.swift — §8 Final Unified
//
// Three-column animated poster mosaic using real movie/streaming posters.
// Posters are loaded via AsyncImage from public CDN URLs (YouTube
// thumbnails, TMDB posters). Middle column offset upward for depth.

import SwiftUI

struct AnimatedPosterMosaic: View {
    // Real popular movie/streaming poster URLs — public CDNs.
    // YouTube video thumbnails: https://img.youtube.com/vi/ID/maxresdefault.jpg
    // TMDB posters: https://image.tmdb.org/t/p/w500/...
    private let posterURLs: [String] = [
        // Popular movie posters (TMDB)
        "https://image.tmdb.org/t/p/w500/8Vt6mWEReuy4Of61Lnj5Xj704m8.jpg", // Dune
        "https://image.tmdb.org/t/p/w500/qNBAXBIQlnOThrVvA6mA2B5ggV6.jpg", // Oppenheimer
        "https://image.tmdb.org/t/p/w500/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg", // Barbie
        "https://image.tmdb.org/t/p/w500/aDQZHvI3rGdtzZ2nFGzJXWL7X5m.jpg", // Joker
        "https://image.tmdb.org/t/p/w500/8Gxv8gSFCU0XGDykEGv7clRv7wq.jpg", // Interstellar
        "https://image.tmdb.org/t/p/w500/kXfqcdQKsToO0OUXHcrrNCHDBzO.jpg", // Shutter Island
        "https://image.tmdb.org/t/p/w500/9gk7adHYeDvHkCSEqAvQNLV5Uge.jpg", // Blade Runner 2049
        "https://image.tmdb.org/t/p/w500/b41qXmtBtZQ3hU2rL3mJ8mFnFk.jpg", // The Dark Knight
        "https://image.tmdb.org/t/p/w500/7Hfi13FfRTIfEYFiQXiIuV2xV8a.jpg", // Inception
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var shifted = false

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 9
            let width = (proxy.size.width - gap * 2) / 3

            HStack(alignment: .top, spacing: gap) {
                posterColumn(index: 0, width: width)
                posterColumn(index: 1, width: width)
                    .offset(y: shifted ? -82 : -58)
                posterColumn(index: 2, width: width)
            }
            .offset(y: shifted ? -16 : 0)
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.48),
                        .init(color: Cinema2026.background.opacity(0.24), location: 0.70),
                        .init(color: Cinema2026.background, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
            .task(id: scenePhase) {
                guard scenePhase == .active, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                    shifted = true
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func posterColumn(index: Int, width: CGFloat) -> some View {
        LazyVStack(spacing: 9) {
            ForEach(Array(posterURLs.enumerated()).filter { $0.offset % 3 == index }, id: \.offset) { _, url in
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .empty:
                        Rectangle().fill(Cinema2026.surface)
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Rectangle().fill(Cinema2026.raised)
                    @unknown default:
                        Rectangle().fill(Cinema2026.surface)
                    }
                }
                .frame(width: width, height: width * 1.42)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}
