import SwiftUI
import UIKit

// MARK: - Stable avatar (no flicker on poll / historyEpoch)

/// Loads remote avatar into memory and keeps it — avoids AsyncImage
/// flashing letter ↔ photo every few seconds when chat re-renders.
/// When a friend's avatar version (`?v=`) changes, reloads immediately.
struct PlinkStableAvatar: View {
    let url: URL?
    let letter: String
    var size: CGFloat = 28
    /// Optional — enables targeted invalidation when this user changes photo.
    var userId: String? = nil
    /// Show admin ring (scarlet→maroon rotating) — priority over premium.
    var isAdmin: Bool = false
    /// Show Plink+ / premium ring (gold→bronze rotating).
    var isPremium: Bool = false

    @State private var image: UIImage?
    @State private var loadedKey: String?

    private var ringLineWidth: CGFloat {
        max(1.4, size * 0.07)
    }

    var body: some View {
        ZStack {
            letterView
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .modifier(RingModifier(isPremium: isPremium, isAdmin: isAdmin, lineWidth: ringLineWidth))
        .task(id: url?.absoluteString ?? letter) {
            await loadIfNeeded(force: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkUserAvatarDidChange)) { note in
            guard let uid = userId, let changed = note.object as? String, changed == uid else { return }
            // Drop current image and force network refetch for new ?v=
            image = nil
            loadedKey = nil
            Task { await loadIfNeeded(force: true) }
        }
    }

    private var letterView: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Cinema2026.accent.opacity(0.75), Color.purple.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(letter)
                .font(.system(size: max(10, size * 0.38), weight: .bold))
                .foregroundColor(.white)
        }
    }

    @MainActor
    private func loadIfNeeded(force: Bool) async {
        let key = url?.absoluteString ?? ""
        if !force, key == loadedKey, image != nil { return }
        guard let url, !key.isEmpty else {
            image = nil
            loadedKey = nil
            return
        }
        // Memory cache (skip when force-reload after avatar change)
        if !force, let cached = PlinkAvatarImageCache.shared.image(for: key) {
            image = cached
            loadedKey = key
            return
        }
        do {
            var req = URLRequest(url: url)
            // Always hit network for avatar bytes — HTTP cache was keeping old photos
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return
            }
            guard let ui = UIImage(data: data) else { return }
            PlinkAvatarImageCache.shared.store(ui, for: key)
            // Only apply if still the same URL
            if url.absoluteString == key {
                image = ui
                loadedKey = key
            }
        } catch {
            // Keep letter fallback — do not thrash
        }
    }
}

/// In-memory avatar bitmaps — thread-safe for MainActor UI + friend poll callbacks.
final class PlinkAvatarImageCache: @unchecked Sendable {
    static let shared = PlinkAvatarImageCache()
    private var map: [String: UIImage] = [:]
    private let maxEntries = 120
    private let lock = NSLock()

    func image(for key: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return map[key]
    }

    func store(_ image: UIImage, for key: String) {
        lock.lock(); defer { lock.unlock() }
        if map.count >= maxEntries, let first = map.keys.first {
            map.removeValue(forKey: first)
        }
        map[key] = image
    }

    func remove(for key: String) {
        lock.lock(); defer { lock.unlock() }
        map.removeValue(forKey: key)
    }

    /// Drop every cached entry for this user's avatar endpoint (any ?v=).
    func removeAll(matchingUserId userId: String) {
        guard !userId.isEmpty else { return }
        let needle = "/users/\(userId)/avatar"
        lock.lock(); defer { lock.unlock() }
        map = map.filter { !$0.key.contains(needle) }
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        map.removeAll()
    }
}
