//
//  PlinkEmojiManifest.swift
//  Plink
//
//  P1 — Emoji pack manifest protocol with Rive-ready assets and safe fallback.
//  Implements Section 2.4 of PLINK_CUSTOMIZATION_AUTH_ADMIN_SPEC_FOR_GLM_5_2.md
//

import SwiftUI
import Foundation

// MARK: - EmojiPackItem

internal struct EmojiPackItem: Codable, Sendable, Identifiable, Equatable {
    let emojiId: String
    let assetURL: URL
    let posterURL: URL
    let sha256: String
    let width: Int
    let height: Int

    var id: String { emojiId }

    init(emojiId: String, assetURL: URL, posterURL: URL, sha256: String, width: Int, height: Int) {
        self.emojiId = emojiId
        self.assetURL = assetURL
        self.posterURL = posterURL
        self.sha256 = sha256
        self.width = width
        self.height = height
    }
}

// MARK: - EmojiPackManifest

internal struct EmojiPackManifest: Codable, Sendable, Identifiable, Equatable {
    let packId: String
    let revision: Int
    let premium: Bool
    let items: [EmojiPackItem]

    var id: String { packId }

    init(packId: String, revision: Int, premium: Bool, items: [EmojiPackItem]) {
        self.packId = packId
        self.revision = revision
        self.premium = premium
        self.items = items
    }
}

// MARK: - EmojiManifestStore

@MainActor
@Observable
internal final class EmojiManifestStore {
    private(set) var manifests: [String: EmojiPackManifest] = [:]
    private(set) var loading: Set<String> = []
    private(set) var failed: Set<String> = []

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func manifest(for packId: String) -> EmojiPackManifest? {
        manifests[packId]
    }

    func item(emojiId: String, in packId: String) -> EmojiPackItem? {
        manifests[packId]?.items.first { $0.emojiId == emojiId }
    }

    func load(packId: String, manifestURL: URL) async {
        guard !loading.contains(packId) else { return }
        loading.insert(packId)
        defer { loading.remove(packId) }

        do {
            let (data, _) = try await session.data(from: manifestURL)
            let manifest = try JSONDecoder().decode(EmojiPackManifest.self, from: data)
            manifests[packId] = manifest
            failed.remove(packId)
        } catch {
            failed.insert(packId)
        }
    }
}

// MARK: - CustomEmojiView

/// Renders a custom emoji by `emojiId` + `packId`.
/// Decision tree:
///   1. Reduce Motion / memory pressure / unsupported asset → poster.
///   2. Rive asset available → animated.
///   3. Lottie asset available → animated (one-shot).
///   4. Unknown / missing → neutral placeholder (never blank).
internal struct CustomEmojiView: View {
    let emojiId: String
    let packId: String
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(emojiId: String, packId: String, size: CGFloat = 28) {
        self.emojiId = emojiId
        self.packId = packId
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Image(systemName: "face.smiling")
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(.white.opacity(0.4))
                )

            // TEMPORARY: render the emojiId's first character (development stub).
            // Replace with RiveView / LottieView / CachedAsyncImage(posterURL) when packs ship.
            Text(String(emojiId.prefix(1)).uppercased())
                .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                .foregroundStyle(.cyan)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Custom emoji: \(emojiId)")
    }
}

// MARK: - CustomEmojiMessagePayload

/// When sending a custom emoji, the message payload carries `emojiId`, NOT a Unicode scalar.
internal struct CustomEmojiMessagePayload: Codable, Sendable, Equatable {
    let messageId: String
    let senderId: String
    let emojiId: String
    let packId: String
    let packRevision: Int

    init(messageId: String, senderId: String, emojiId: String, packId: String, packRevision: Int) {
        self.messageId = messageId
        self.senderId = senderId
        self.emojiId = emojiId
        self.packId = packId
        self.packRevision = packRevision
    }
}

// MARK: - ReactionPalette
// The existing `ReactionPalette` in
// `Plink/Features/WatchRoom/Reactions/ReactionPalette.swift` is the
// canonical definition. V5 does not redefine it — see that file for the
// free + premium Unicode baseline.
