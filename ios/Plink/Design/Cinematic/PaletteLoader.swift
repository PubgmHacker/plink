// Plink/Design/Cinematic/PaletteLoader.swift — Brain Revision 3 Step 8
//
// Async palette loader for artwork-driven living ambience.
//
// Brain: "Palette extraction must run off the main actor on a downsampled
// image, then publish the final small value on main. Cache by thumbnail URL.
// Never sample YouTube/WKWebView/DRM frames."
//
// Usage:
//   @State private var palette: LivingBackdropPalette = .cinema2026
//   .task(id: model.mediaThumbnailURL) {
//       palette = await paletteLoader.palette(for: model.mediaThumbnailURL)
//   }
//
// The loader downsamples the thumbnail to 64x64 before extraction to keep
// memory + CPU low. Palette is cached by URL string in memory.

import SwiftUI
import UIKit

actor PaletteLoader {
    static let shared = PaletteLoader()

    /// In-memory cache: thumbnailURL → LivingBackdropPalette.
    private var cache: [String: LivingBackdropPalette] = [:]

    /// Load thumbnail and extract palette.
    /// - Parameter urlString: Thumbnail URL (nil or empty → .cinema2026 default).
    /// - Returns: LivingBackdropPalette extracted from the downsampled image,
    ///   or .cinema2026 on any failure.
    func palette(for urlString: String?) async -> LivingBackdropPalette {
        guard let urlString, !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return .cinema2026
        }

        // Cache hit.
        if let cached = cache[urlString] {
            return cached
        }

        // Load + downsample off the main actor.
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                return .cinema2026
            }

            // Downsample to 64x64 max for fast palette extraction.
            let downsampled = downsample(image: image, maxDimension: 64)
            let palette = LivingBackdropPalette.extract(from: downsampled)

            // Cache.
            cache[urlString] = palette
            return palette
        } catch {
            return .cinema2026
        }
    }

    /// Downsample a UIImage to fit within maxDimension×maxDimension.
    private func downsample(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Clear the cache (e.g. on memory warning).
    func clearCache() {
        cache.removeAll()
    }
}
