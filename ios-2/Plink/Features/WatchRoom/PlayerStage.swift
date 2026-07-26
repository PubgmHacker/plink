// Plink/Features/WatchRoom/PlayerStage.swift — GPT-5.6 V4 Rescue §7
//
// Neutral player stage. NO decoration: no glow, no border, no glass,
// no theme stroke, no theme shadow, no theme corner radius.
// Background: plain black. Provider owns controls.

import SwiftUI

struct PlayerStage: View {
    @Bindable var model: WatchRoomModel
    @Binding var ui: WatchRoomUIState
    let variant: WatchRoomLayoutState.Variant

    var body: some View {
        ZStack {
            // GPT-5.6 §3: plain black background, nothing else
            Color.black

            // Player surface — never decorated
            PlayerSurfaceView(
                coordinator: model.coordinator,
                roomError: model.lastError,
                expectMedia: model.mediaSource != nil || model.lastError == nil
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Danmaku layer (above video, below chrome)
            DanmakuCanvasLayer(
                placements: model.danmakuPlacements,
                laneCount: model.danmakuLaneCount,
                opacity: model.danmakuOpacity
            )
            .padding(.horizontal, 8)
            .padding(.top, 60)
            .padding(.bottom, 80)

            // Loading overlay only when we still have no player surface.
            // Once WKWebView is attached, never cover it with a full-screen spinner
            // (that was the "eternal loading" symptom: 1 in room + black spinner).
            let hasSurface = model.coordinator.embeddedView != nil
                || model.coordinator.nativePlayer != nil
            if model.coordinator.isPreparing && !hasSurface {
                PlayerLoadingView()
                    .transition(.opacity)
            }
            // Soft buffering chip — only mid-playback, never blocks hit testing
            // and never shown for the whole prepare period.
            if model.coordinator.isBuffering
                && hasSurface
                && model.coordinator.isPlaying == false
                && model.coordinator.isPreparing == false
            {
                BufferingOverlay()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            // Top chrome only (functional, not decorative)
            if ui.controlsVisible {
                LinearGradient(
                    colors: [Color.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .transition(.opacity)

                PlayerTopChrome(model: model, variant: variant)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                // Host sync control — ensures multi-device play/pause even when
                // YouTube chrome events are missed (MVP reliability).
                if model.isHost {
                    PlayerCenterControl(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        // FORBIDDEN: PlinkLivingBackground, glassCard, neonGlow, theme stroke,
        // theme shadow, theme corner radius. None of these appear here.
    }
}
