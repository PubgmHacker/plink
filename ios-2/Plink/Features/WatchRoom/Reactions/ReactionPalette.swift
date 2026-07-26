// Plink/Features/WatchRoom/Reactions/ReactionPalette.swift — Commit Group 6
//
// Reaction emoji palette with free and premium tiers.
//
// Free tier (8 emojis): universally available to all users.
// Premium tier (16 emojis): requires Plink+ subscription; the picker UI
// shows them with a small star badge and gates tap-to-send behind
// StoreKit entitlement check.
//
// Palette choices:
//   - Free: 8 high-frequency reactions covering the common emotional
//     responses (love, laugh, sad, angry, surprised, fire, clap, heart).
//     These match the universal emoji set used by Twitch, Discord, and
//     YouTube Live — users already know what they mean.
//   - Premium: 16 additional emojis including animals, gestures, and
//     seasonal items. Premium emojis are larger in the picker and have
//     a subtle star badge.
//
// Backend contract: the backend accepts ANY single emoji codepoint in
// reaction.send — the palette gate is client-side only. This means
// premium users keep their reactions visible to free users (no
// interop penalty), and the gate exists purely to drive subscription
// value.
//
// Validation:
//   - Free emojis: validated against a static set on send.
//   - Premium emojis: validated against premium set + entitlement.
//   - Unknown emojis: rejected client-side with telemetry.
//
// Testing:
//   - ReactionPaletteTests covers free/premium membership, tier
//     classification, and entitlement gating.

import Foundation

enum ReactionPalette {
    /// Free tier — available to all users.
    static let free: [String] = [
        "❤️",   // love
        "😂",   // laugh
        "😢",   // sad
        "😡",   // angry
        "😮",   // surprised
        "🔥",   // fire
        "👏",   // clap
        "💜"    // heart (brand-aligned, magenta)
    ]

    /// Premium tier — requires Plink+ subscription.
    static let premium: [String] = [
        "🎉",   // party
        "🤩",   // star-struck
        "🥳",   // partying face
        "😎",   // cool
        "🤔",   // thinking
        "🥺",   // pleading
        "😭",   // sobbing
        "🤣",   // ROFL
        "💯",   // hundred points
        "✨",   // sparkles
        "🌟",   // glowing star
        "💫",   // dizzy
        "👑",   // crown (host appreciation)
        "🏆",   // trophy
        "🚀",   // rocket
        "🌈"    // rainbow
    ]

    /// All emojis (free + premium). Used by the picker to render the full grid.
    static var all: [String] { free + premium }

    /// Returns the tier for a given emoji, or nil if unknown.
    static func tier(for emoji: String) -> Tier? {
        if free.contains(emoji) { return .free }
        if premium.contains(emoji) { return .premium }
        return nil
    }

    /// Returns true iff the user can send this emoji, given their
    /// entitlement. Free emojis are always sendable; premium emojis
    /// require `hasPremium == true`.
    static func canSend(_ emoji: String, hasPremium: Bool) -> Bool {
        guard let tier = tier(for: emoji) else { return false }
        switch tier {
        case .free:   return true
        case .premium: return hasPremium
        }
    }

    enum Tier: String, Sendable, Equatable, CaseIterable {
        case free
        case premium
    }
}
