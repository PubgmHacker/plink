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

    // Ревью P2: короткие всплески буферизации показывать нельзя — любой seek
    // (жёсткая коррекция дрифта, ±10 с, перемотка хостом) на 200-800 мс
    // выставляет isBuffering, и спиннер мигал бы посреди кадра. Показываем
    // только когда буферизация держится дольше порога; скрываем мгновенно.
    @State private var showBufferingChip = false
    private static let bufferingChipDelayNs: UInt64 = 500_000_000

    var body: some View {
        ZStack {
            // GPT-5.6 §3: plain black background, nothing else
            Color.black

            // Player surface — never decorated
            // P0-фикс аудита: в плеер идёт только mediaError — прочие lastError
            // показываются тостами и не должны закрывать видео чёрным экраном.
            PlayerSurfaceView(
                coordinator: model.coordinator,
                roomError: model.mediaError,
                expectMedia: model.mediaSource != nil || model.mediaError == nil
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
            // P2-фикс аудита: раньше здесь стояло ещё isPlaying == false, из-за
            // чего оверлей не появлялся при ребуфере на ходу (YouTube state 3
            // ставит isBuffering, но isPlaying не сбрасывает) — то есть именно
            // в том случае, для которого чип и сделан.
            if showBufferingChip
                && hasSurface
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

                PlayerTopChrome(
                    model: model,
                    variant: variant,
                    // Панель темы презентует WatchRoomScreen — здесь только
                    // запрос на открытие (хром гаснет по таймеру автоскрытия).
                    onOpenAppearance: { ui.appearancePanelPresented = true }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))

                // M40: своя полноценная панель управления вместо родной панели
                // YouTube — перемотка с буфером, время, ±10 с, скорость,
                // качество, звук и полный экран. Раньше здесь была только
                // кнопка play для хоста, а всё остальное рисовал YouTube.
                //
                // Показываем её только для встроенных провайдеров (YouTube и
                // подобные). У родного AVPlayer свои системные контролы.
                if model.coordinator.embeddedView != nil {
                    PlinkPlayerControls(model: model, ui: $ui, variant: variant)
                        .transition(.opacity)
                } else if model.isHost {
                    PlayerCenterControl(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
        }
        .clipped()
        // Дебаунс спиннера буферизации: при isBuffering ждём порог и только
        // потом показываем; на сброс флага задача перезапускается и гасит чип.
        .task(id: model.coordinator.isBuffering) {
            guard model.coordinator.isBuffering else {
                showBufferingChip = false
                return
            }
            try? await Task.sleep(nanoseconds: Self.bufferingChipDelayNs)
            guard !Task.isCancelled else { return }
            showBufferingChip = true
        }
        .accessibilityElement(children: .contain)
        // FORBIDDEN: PlinkLivingBackground, glassCard, neonGlow, theme stroke,
        // theme shadow, theme corner radius. None of these appear here.
    }
}
