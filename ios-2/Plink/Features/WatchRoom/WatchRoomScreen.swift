// Plink/Features/WatchRoom/WatchRoomScreen.swift — PATCH 02 + 04
//
// Commit Group 2: full PATCH 02 view hierarchy split + PATCH 04 stable
// rotation.
//
// Layout variant is derived purely from size classes — no
// OrientationCoordinator forcing, no .onAppear orientation lock. System
// rotation drives layout; the user's fullscreen action is a separate
// presentation, not a forced interface rotation.
//
// Player identity stability (PATCH 04):
//   - PlaybackCoordinator owns the AVPlayer; EmbeddedPlaybackController
//     owns the WKWebView. SwiftUI may rebuild PlayerStage's view tree on
//     layout switch, but the underlying player is NEVER recreated.
//   - PlayerStage uses .id("plink.player.stage") so SwiftUI's diff treats
//     it as the same view across layout switches where possible.
//   - prepare() is only called once by the coordinator, never by the view.
//
// Animation: .plinkLayout (0.42s smooth spring, damping 0.92).

import SwiftUI

struct WatchRoomScreen: View {
    @Bindable var model: WatchRoomModel

    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.verticalSizeClass) private var heightClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss  // PATCH 26: dismiss fullScreenCover on leave

    @State private var ui = WatchRoomUIState()
    @State private var controlsHideTask: Task<Void, Never>?
    // M13: room polls composer
    @State private var showPollComposer = false
    // M14: одноразовый хинт про контролы
    @AppStorage("plink.roomControlsHintShown") private var roomControlsHintShown = false
    @State private var showControlsHint = false

    private var layoutVariant: WatchRoomLayoutState.Variant {
        if widthClass == .regular && heightClass != .compact { return .tablet }
        if heightClass == .compact { return .landscape }
        return .portrait
    }

    var body: some View {
        ZStack {
            // PATCH 14: ambient state now comes from model (driven by
            // AmbientVideoSampler). ui.ambient is no longer used.
            Cinema2026.background.ignoresSafeArea()

            switch layoutVariant {
            case .portrait:
                PortraitWatchLayout(model: model, ui: $ui)
                    .transition(.opacity)
            case .landscape:
                LandscapeWatchLayout(model: model, ui: $ui)
                    .transition(.opacity)
            case .tablet:
                TabletWatchLayout(model: model, ui: $ui)
                    .transition(.opacity)
            }

            WatchReactionLayer(events: model.reactions, reduceMotion: reduceMotion)
                .allowsHitTesting(false)

            if let toast = ui.activeToast {
                RoomToastView(toast: toast)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(100)
            }

            // PATCH 14: Rutube fallback toast — shown when source is .rutube
            // and the embedded player's JS API is unavailable. Tapping
            // "Open" launches SFSafariViewController with the Rutube video URL.
            if model.requiresRutubeFallback {
                RutubeFallbackToast(onOpen: {
                    model.openInRutubeExternal()
                })
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(101)
            }

            // Offline / error state (P0)
            if case .failed = model.connectionState, let error = model.lastError {
                VStack {
                    Image(systemName: "wifi.slash")
                        .font(.largeTitle)
                    Text("Connection lost")
                    Text(error)
                        .font(.caption)
                    Button("Retry") {
                        Task { await model.connect() }
                    }
                }
                .padding()
                .background(Cinema2026.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .zIndex(200)
            }

            // M13: transient reconnect banner + queued message badge.
            // The offline queue in RealtimeClient keeps user chat safe; this
            // just makes the process visible so the room never feels broken.
            if case .reconnecting = model.connectionState {
                VStack {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.7)
                        Text(model.queuedMessageCount > 0
                             ? "Переподключение… \(model.queuedMessageCount) сообщ. в очереди"
                             : "Переподключение…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 54)
                    Spacer()
                }
                .zIndex(300)
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            // M14: синхронный отсчёт 3-2-1 перед стартом
            if let countdownValue = model.countdownRemaining {
                RoomCountdownOverlay(value: countdownValue)
                    .zIndex(500)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            // M15: бар модерации — над чатом, под верхним хромом
            if model.moderationBarVisible {
                VStack {
                    RoomModerationBar(model: model)
                        .padding(.horizontal, 16)
                        .padding(.top, 104)
                    Spacer()
                }
                .zIndex(480)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // M14: одноразовый хинт для первой комнаты
            if showControlsHint {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Тапни по экрану — появятся контролы")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 120)
                }
                .zIndex(490)
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .background(Cinema2026.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .animation(.plinkLayout, value: layoutVariant)
        .onChange(of: layoutVariant) { _, newVariant in
            // PATCH 14: update danmaku lane count on rotation.
            let laneCount: Int
            switch newVariant {
            case .portrait:  laneCount = 5
            case .landscape: laneCount = 7
            case .tablet:    laneCount = 5
            }
            model.updateDanmakuLaneCount(laneCount)

            // P0.3: in landscape, show chat drawer by default for YouTube
            if newVariant == .landscape && !ui.chatDrawerVisible {
                ui.chatDrawerVisible = true
            }
        }
        // Permanent close — always hit-testable (not only when chrome is visible)
        .overlay(alignment: .topLeading) {
            Button {
                model.leaveRoom()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)
            .padding(.top, 10)
            .zIndex(500)
            .accessibilityLabel("Выйти из комнаты")
        }
        // M13: room polls — card overlay + composer entry point
        .overlay(alignment: .top) {
            if let poll = model.activePoll {
                RoomPollCard(
                    poll: poll,
                    myUserId: model.currentUserId,
                    canClose: poll.createdBy == model.currentUserId,
                    onVote: { model.votePoll(optionIndex: $0) },
                    onClose: { model.closePoll() },
                    onDismiss: { model.dismissPoll() }
                )
                .padding(.top, 56)
                .padding(.horizontal, 24)
                .frame(maxWidth: 420)
                .zIndex(400)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topLeading) {
            if model.activePoll == nil {
                Button {
                    showPollComposer = true
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .padding(.leading, 14)
                .padding(.top, 58)
                .zIndex(499)
                .accessibilityLabel("Создать голосование")
            }
        }
        .sheet(isPresented: $showPollComposer) {
            PollComposerSheet { question, options in
                model.sendPoll(question: question, options: options)
            }
        }
        .task { await model.connect() }
        .task {
            // M15: приватность комнаты + автопоказ бара модерации для хоста.
            // Показываем один раз на комнату, через 8 с прячем, чтобы не мешать.
            // Повторный вызов — кнопка-щит в верхнем хроме.
            await model.loadPrivacy()
            guard model.isHost, let roomId = model.roomId else { return }
            let key = "plink.modBarShown.\(roomId)"
            guard !UserDefaults.standard.bool(forKey: key) else { return }
            UserDefaults.standard.set(true, forKey: key)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { model.moderationBarVisible = true }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard model.moderationBarVisible else { return }
            withAnimation(.easeOut(duration: 0.3)) { model.moderationBarVisible = false }
        }
        .task {
            // M14: одноразовый хинт «тапни по экрану» — только при первом входе
            if !roomControlsHintShown {
                roomControlsHintShown = true
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation(.easeOut(duration: 0.25)) { showControlsHint = true }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                withAnimation(.easeOut(duration: 0.4)) { showControlsHint = false }
            }
        }
        .task {
            // M14: «Продолжить просмотр» — хост делает синхронный seek к таймкоду
            guard let resume = PlinkPendingResume.take() else { return }
            for _ in 0..<40 {
                if model.isHost, model.connectionState == .connected, model.coordinator.currentSource != nil { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard model.isHost, model.connectionState == .connected else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await model.sendSeekCommand(to: resume.seconds)
        }
        .onDisappear {
            // PATCH: do NOT disconnect here — onDisappear fires on rotation
            // when SwiftUI rebuilds the view. Disconnect only on explicit
            // leaveRoom (X button) or when fullScreenCover is dismissed.
            controlsHideTask?.cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                OrientationManager.shared.unlockOrientation()
            }
        }
        .onChange(of: model.connectionState) { _, newState in
            if newState == .idle && model.wantsDismiss {
                dismiss()
            }
        }
        .onChange(of: model.wantsDismiss) { _, wants in
            if wants { dismiss() }
        }
        .onTapGesture {
            guard !ui.chatPresented else { return }
            withAnimation(.plinkControls) {
                ui.controlsVisible.toggle()
            }
            scheduleControlsHide()
        }
        .sheet(isPresented: $ui.chatPresented) {
            WatchChatSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Cinema2026.background)
        }
    }

    private func scheduleControlsHide() {
        controlsHideTask?.cancel()
        guard ui.controlsVisible, model.coordinator.isPlaying, !ui.isScrubbing else { return }

        controlsHideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.plinkControls) {
                ui.controlsVisible = false
            }
        }
    }
}
