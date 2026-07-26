// Plink/Design/Cinematic/CompactPhoneMetrics.swift — §5 Final Architecture
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

// MARK: - Cinema2026 neutral palette (§5)

enum Cinema2026 {
    static let background = Color(red: 0.055, green: 0.067, blue: 0.075)
    static let surface = Color(red: 0.092, green: 0.108, blue: 0.118)
    static let raised = Color(red: 0.135, green: 0.153, blue: 0.163)
    static let text = Color(red: 0.925, green: 0.918, blue: 0.890)
    static let secondary = Color(red: 0.650, green: 0.675, blue: 0.680)
    static let divider = Color(red: 0.205, green: 0.225, blue: 0.232)
    static let accent = Color(red: 0.355, green: 0.690, blue: 0.610)
    static let amber = Color(red: 0.845, green: 0.655, blue: 0.315)
    static let danger = Color(red: 0.820, green: 0.295, blue: 0.270)

    // Aliases for back-compat with old PlinkRave refs
    static let accentAction = LinearGradient(
        colors: [accent, Color(red: 0.285, green: 0.550, blue: 0.488)],
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
    static let live = accent
    static let warning = amber
    static let tertiary = divider
    static let void = background
}
