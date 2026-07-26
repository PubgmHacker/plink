// PlinkTests/ReactionPaletteTests.swift — Commit Group 6
//
// Unit tests for ReactionPalette — free/premium tier classification,
// canSend entitlement gating, and membership queries.
//
// All synchronous, no UI, no async. Safe for CI.

import XCTest
@testable import Plink

final class ReactionPaletteTests: XCTestCase {

    // MARK: - Static palette sizes

    func testFreePalette_hasEightEmojis() {
        XCTAssertEqual(ReactionPalette.free.count, 8,
                       "Free palette must have exactly 8 emojis")
    }

    func testPremiumPalette_hasSixteenEmojis() {
        XCTAssertEqual(ReactionPalette.premium.count, 16,
                       "Premium palette must have exactly 16 emojis")
    }

    func testAllPalette_hasTwentyFourEmojis() {
        XCTAssertEqual(ReactionPalette.all.count, 24,
                       "All palette must have 24 emojis (8 free + 16 premium)")
    }

    func testAllPalette_isFreePlusPremium() {
        XCTAssertEqual(ReactionPalette.all, ReactionPalette.free + ReactionPalette.premium,
                       "all must equal free + premium in order")
    }

    // MARK: - No overlap between free and premium

    func testFreeAndPremiumPalettes_haveNoOverlap() {
        let freeSet = Set(ReactionPalette.free)
        let premiumSet = Set(ReactionPalette.premium)
        let intersection = freeSet.intersection(premiumSet)
        XCTAssertTrue(intersection.isEmpty,
                      "Free and premium palettes must not share emojis; overlap: \(intersection)")
    }

    // MARK: - No duplicates within each palette

    func testFreePalette_hasNoDuplicates() {
        let counts = Dictionary(grouping: ReactionPalette.free, by: { $0 })
        let dups = counts.filter { $0.value.count > 1 }
        XCTAssertTrue(dups.isEmpty,
                      "Free palette must have no duplicates: \(dups.keys)")
    }

    func testPremiumPalette_hasNoDuplicates() {
        let counts = Dictionary(grouping: ReactionPalette.premium, by: { $0 })
        let dups = counts.filter { $0.value.count > 1 }
        XCTAssertTrue(dups.isEmpty,
                      "Premium palette must have no duplicates: \(dups.keys)")
    }

    // MARK: - Known emojis present

    func testFreePalette_containsCoreReactions() {
        let expected = ["❤️", "😂", "😢", "😡", "😮", "🔥", "👏", "💜"]
        for emoji in expected {
            XCTAssertTrue(ReactionPalette.free.contains(emoji),
                          "Free palette must contain \(emoji)")
        }
    }

    func testPremiumPalette_containsPremiumReactions() {
        let expected = ["🎉", "🤩", "🥳", "😎", "👑", "🏆", "🚀", "🌈"]
        for emoji in expected {
            XCTAssertTrue(ReactionPalette.premium.contains(emoji),
                          "Premium palette must contain \(emoji)")
        }
    }

    // MARK: - Tier classification

    func testTier_returnsFreeForFreeEmoji() {
        XCTAssertEqual(ReactionPalette.tier(for: "❤️"), .free)
        XCTAssertEqual(ReactionPalette.tier(for: "🔥"), .free)
        XCTAssertEqual(ReactionPalette.tier(for: "💜"), .free)
    }

    func testTier_returnsPremiumForPremiumEmoji() {
        XCTAssertEqual(ReactionPalette.tier(for: "🎉"), .premium)
        XCTAssertEqual(ReactionPalette.tier(for: "👑"), .premium)
        XCTAssertEqual(ReactionPalette.tier(for: "🚀"), .premium)
    }

    func testTier_returnsNilForUnknownEmoji() {
        XCTAssertNil(ReactionPalette.tier(for: "🦄"),
                     "Unicorn is not in any palette, tier must be nil")
        XCTAssertNil(ReactionPalette.tier(for: "🌍"),
                     "Earth is not in any palette, tier must be nil")
        XCTAssertNil(ReactionPalette.tier(for: ""),
                     "Empty string is not in any palette, tier must be nil")
    }

    func testTier_returnsNilForNonEmojiString() {
        XCTAssertNil(ReactionPalette.tier(for: "hello"),
                     "Plain text must return nil tier")
        XCTAssertNil(ReactionPalette.tier(for: "❤️😂"),
                     "Multi-emoji string must return nil tier (palette is per-emoji)")
    }

    // MARK: - canSend entitlement gating

    func testCanSend_freeEmojiAlwaysSendableWithoutPremium() {
        XCTAssertTrue(ReactionPalette.canSend("❤️", hasPremium: false),
                      "Free emojis must be sendable without premium")
        XCTAssertTrue(ReactionPalette.canSend("🔥", hasPremium: false),
                      "Free emojis must be sendable without premium")
    }

    func testCanSend_freeEmojiSendableWithPremium() {
        XCTAssertTrue(ReactionPalette.canSend("❤️", hasPremium: true),
                      "Free emojis must be sendable with premium")
    }

    func testCanSend_premiumEmojiNotSendableWithoutPremium() {
        XCTAssertFalse(ReactionPalette.canSend("🎉", hasPremium: false),
                       "Premium emojis must NOT be sendable without premium")
        XCTAssertFalse(ReactionPalette.canSend("👑", hasPremium: false),
                       "Premium emojis must NOT be sendable without premium")
    }

    func testCanSend_premiumEmojiSendableWithPremium() {
        XCTAssertTrue(ReactionPalette.canSend("🎉", hasPremium: true),
                      "Premium emojis must be sendable with premium")
        XCTAssertTrue(ReactionPalette.canSend("👑", hasPremium: true),
                      "Premium emojis must be sendable with premium")
    }

    func testCanSend_unknownEmojiNotSendableEvenWithPremium() {
        XCTAssertFalse(ReactionPalette.canSend("🦄", hasPremium: true),
                       "Unknown emojis must not be sendable even with premium")
        XCTAssertFalse(ReactionPalette.canSend("🦄", hasPremium: false),
                       "Unknown emojis must not be sendable without premium")
    }

    func testCanSend_emptyStringNotSendable() {
        XCTAssertFalse(ReactionPalette.canSend("", hasPremium: true),
                       "Empty string must not be sendable")
        XCTAssertFalse(ReactionPalette.canSend("", hasPremium: false),
                       "Empty string must not be sendable")
    }

    // MARK: - Tier enum

    func testTierEnum_hasTwoCases() {
        XCTAssertEqual(ReactionPalette.Tier.allCases.count, 2)
        XCTAssertEqual(ReactionPalette.Tier.allCases, [.free, .premium])
    }

    func testTierEnum_rawValues() {
        XCTAssertEqual(ReactionPalette.Tier.free.rawValue, "free")
        XCTAssertEqual(ReactionPalette.Tier.premium.rawValue, "premium")
    }

    // MARK: - All emojis are single-grapheme clusters

    func testAllEmojisAreNonEmptyStrings() {
        for emoji in ReactionPalette.all {
            XCTAssertFalse(emoji.isEmpty,
                           "Every palette entry must be non-empty")
        }
    }

    func testAllEmojisAreSingleGraphemeClusters() {
        // Each emoji should be a single grapheme cluster (one Character).
        // Multi-emoji strings like "❤️😂" are not valid palette entries.
        for emoji in ReactionPalette.all {
            XCTAssertEqual(emoji.count, 1,
                           "Palette entry '\(emoji)' must be a single grapheme cluster, got \(emoji.count)")
        }
    }
}
