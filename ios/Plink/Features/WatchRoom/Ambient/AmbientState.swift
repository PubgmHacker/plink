// Plink/Features/WatchRoom/Ambient/AmbientState.swift
//
// GPT-5.6 SOL fix: AmbientState was previously in PurpleAmbientBackdrop.swift
// which was deleted. Recreated here as a minimal struct for back-compat.
// Used by WatchRoomUIState.ambient and AmbientVideoSampler.ambientState.

import SwiftUI

/// Ambient palette state for living background.
/// Driven by AmbientVideoSampler — colors come from native player frame sampling
/// (HLS/MP4 only) or fallback Cinema2026 palette (YouTube/Rutube use WKWebView).
struct AmbientState: Equatable {
    var intensity: Double
    var primaryColor: Color
    var secondaryColor: Color

    init(intensity: Double = 0.0, primaryColor: Color = Cinema2026.accent, secondaryColor: Color = Cinema2026.amber) {
        self.intensity = intensity
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
    }

    static let `default` = AmbientState()
}
