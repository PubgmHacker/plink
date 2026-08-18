//
// Compact density tokens for iPhone.

import SwiftUI

enum CompactPhoneMetrics {
    static let horizontalInset: CGFloat = 14
    static let sectionSpacing: CGFloat = 18
    static let railSpacing: CGFloat = 8

    static let posterWidth: CGFloat = 108
    static let posterAspect: CGFloat = 0.70
    static let posterRadius: CGFloat = 9

    static let landscapeCardWidth: CGFloat = 186
    static let landscapeCardHeight: CGFloat = 105
    static let landscapeRadius: CGFloat = 10

    static let roomCardHeight: CGFloat = 146
    static let roomCardRadius: CGFloat = 13
    static let rowHeight: CGFloat = 62

    static let regularControlVisual: CGFloat = 38
    static let minimumHitTarget: CGFloat = 44
    static let primaryButtonHeight: CGFloat = 50
}

// MARK: - Cinema2026 neutral palette

/// Palette for the cinematic screens: room, chat, onboarding, paywall and
/// room creation.
///
/// Every token here is an alias of `V4`, and must stay one. The app has a
/// single accent and a single background: tabs and "Appearance" are drawn
/// from the `V4` palette, and onboarding, the paywall and room creation are
/// drawn from this one. A second accent colour defined here reads as two
/// different apps — e.g. a mint "Next" button in onboarding followed by a
/// blue one immediately after sign-in.
///
/// The names and the structure are kept as-is: `Cinema2026` is referenced
/// around 430 times across dozens of files, so redefining the source is
/// safer than rewriting every call site.
enum Cinema2026 {
    static let background = V4.canvas
    static let surface = V4.surface
    static let raised = V4.raised
    static let text = V4.ink
    static let secondary = V4.muted
    static let divider = Color.oklch(0.30, 0.02, 240)
    static let accent = V4.accent
    static let amber = V4.amber
    static let danger = V4.danger

    // Aliases for back-compat with old PlinkRave refs
    static let accentAction = LinearGradient(
        colors: [accent, Color.oklch(0.55, 0.20, 250)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let outgoingBubble = accentAction
    static let timeline = LinearGradient(
        colors: [accent, secondary],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let ambientGlow = LinearGradient(
        colors: [accent.opacity(0.06), .clear],
        startPoint: .top,
        endPoint: .bottom
    )
    /// Alias for `background` — used by RoomCreationView / ConnectedServicesSettingsView.
    /// (FIX: "Type 'Cinema2026' has no member 'bg'")
    static let bg = background
    static let live = accent
    static let warning = amber
    static let tertiary = divider
    static let void = background
}
