// Plink/Features/WatchRoom/WatchRoomScreen.swift
// Root view of a watch-together room: selects the layout variant, hosts the
// reaction / toast / poll / empty-state overlays, presents the chat and
// appearance sheets, and owns the controls auto-hide timer.
//
// Layout variant is derived purely from size classes — no
// OrientationCoordinator forcing, no .onAppear orientation lock. System
// rotation drives layout; the user's fullscreen action is a separate
// presentation, not a forced interface rotation.
//
// Player identity stability:
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
    @Environment(\.dismiss) private var dismiss  // Dismiss fullScreenCover on leave

    @State private var ui = WatchRoomUIState()
    @State private var controlsHideTask: Task<Void, Never>?
    // Room polls composer
    @State private var showPollComposer = false
    // Одноразовый хинт про контролы
    /// Сервис комнаты требует своего входа — открываем его настоящую страницу.
    @State private var loginAccount: LinkedExternalAccount?

    private var layoutVariant: WatchRoomLayoutState.Variant {
        if widthClass == .regular && heightClass != .compact { return .tablet }
        if heightClass == .compact { return .landscape }
        return .portrait
    }

    var body: some View {
        ZStack {
            // Ambient state now comes from model (driven by
            // AmbientVideoSampler). ui.ambient is no longer used.
            Cinema2026.background.ignoresSafeArea()

            // P1 5.11: живая тема комнаты (Plink+) — амбиентная подложка ПОД
            // всем контентом. Плеер, чат и управление рисуются поверх; слой
            // не ловит касания и ничего не перекрывает.
            // Ревью: в landscape подложку целиком перекрывает PlayerStage
            // (WatchLayouts.swift), а occlusion culling SwiftUI не делает —
            // без suppressed слой продолжал бы крутить 20 к/с полноэкранных
            // blur-фильтров в невидимом кадре, и именно в том режиме, где
            // смотрят дольше всего.
            RoomLiveThemeBackdrop(
                appearance: model.appearanceStore.appearance,
                suppressed: layoutVariant == .landscape
            )
            .ignoresSafeArea()

            switch layoutVariant {
            case .portrait:
                PortraitWatchLayout(model: model, ui: $ui,
                                    onPoll: { showPollComposer = true })
                    .transition(.opacity)
            case .landscape:
                LandscapeWatchLayout(model: model, ui: $ui)
                    .transition(.opacity)
            case .tablet:
                TabletWatchLayout(model: model, ui: $ui)
                    .transition(.opacity)
            }

            // Only an actionable notice stays over the video: the "everyone
            // uses their own account" line is explained before the room opens.
            if model.needsServiceLogin, let line = model.serviceNoticeLine {
                VStack {
                    Button {
                        guard model.needsServiceLogin,
                              let service = model.subscriptionService,
                              let account = LinkedExternalAccount(service: service) else { return }
                        HapticManager.impact(.light)
                        loginAccount = account
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: model.needsServiceLogin
                                  ? "person.crop.circle.badge.questionmark"
                                  : "person.2.badge.key.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text(line)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if model.needsServiceLogin {
                                Text("Войти")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Cinema2026.accent)
                            }
                        }
                        .foregroundStyle(Cinema2026.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Cinema2026.raised.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.top, 56)
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.needsServiceLogin)
                    Spacer()
                }
                .allowsHitTesting(model.needsServiceLogin)
                .transition(.opacity)
            }

            if let toast = ui.activeToast {
                RoomToastView(toast: toast)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(100)
            }

            // Rutube fallback toast — shown when source is .rutube
            // and the embedded player's JS API is unavailable. Tapping
            // "Open" launches SFSafariViewController with the Rutube video URL.
            if model.requiresRutubeFallback {
                RutubeFallbackToast(onOpen: {
                    model.openInRutubeExternal()
                })
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(101)
            }

            // P0 5.3: пустая комната — один участник и нет контента.
            // Крупное «Позвать друга» вместо чёрного экрана с иконкой за тапом.
            if model.participants.count <= 1,
               model.mediaSource == nil,
               model.coordinator.currentSource == nil {
                RoomEmptyStateView(model: model)
                    .zIndex(90)
                    .transition(.opacity)
            }

            // Offline / error state (P0)
            if case .failed = model.connectionState, let error = model.lastError {
                VStack {
                    Image(systemName: "wifi.slash")
                        .font(.largeTitle)
                    Text(LocalizationManager.shared.string(.connectionLost))
                    Text(error)
                        .font(.caption)
                    Button(LocalizationManager.shared.string(.offlineRetry)) {
                        Task { await model.connect() }
                    }
                }
                .padding()
                .background(Cinema2026.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .zIndex(200)
            }

            // Transient reconnect banner + queued message badge.
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
                    .plinkGlass(.overlay, in: Capsule(style: .continuous))
                    .padding(.top, 54)
                    Spacer()
                }
                .zIndex(300)
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            // Синхронный отсчёт 3-2-1 перед стартом
            if let countdownValue = model.countdownRemaining {
                RoomCountdownOverlay(value: countdownValue)
                    .zIndex(500)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            // Бар модерации — над чатом, под верхним хромом
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

        }
        .background(Cinema2026.background.ignoresSafeArea())
        // Единственная стабильная точка, по которой UI-смоук понимает,
        // что комната действительно открылась. Раньше идентификаторов
        // screen.* хватало на все табы, кроме самой комнаты — то есть ровно
        // на конце воронки, который важнее всех остальных.
        .accessibilityIdentifier("screen.room")
        .preferredColorScheme(.dark)
        .animation(.plinkLayout, value: layoutVariant)
        .onChange(of: layoutVariant) { _, newVariant in
            // Update danmaku lane count on rotation.
            let laneCount: Int
            switch newVariant {
            case .portrait:  laneCount = 5
            case .landscape: laneCount = 7
            case .tablet:    laneCount = 5
            }
            model.updateDanmakuLaneCount(laneCount)

            // Ящик чата на повороте не трогаем. Раньше вход в ландшафт
            // принудительно открывал его — фильм сразу терял 40 % ширины,
            // хотя человек шёл именно в полный экран. Состояние ящика —
            // выбор человека, переключатель в нижней панели плеера.
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
                    .plinkGlass(.overlay, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)
            .padding(.top, 10)
            .zIndex(500)
            .accessibilityLabel("Выйти из комнаты")
        }
        // Room polls — card overlay + composer entry point
        // Там же — просьба о паузе. Оба элемента лежат в ОДНОМ оверлее и
        // складываются в VStack: до этого баннер, поставленный отдельным
        // оверлеем с тем же выравниванием, наехал бы на карточку голосования.
        .overlay(alignment: .top) {
            VStack(spacing: 10) {
                if let poll = model.activePoll {
                    RoomPollCard(
                        poll: poll,
                        myUserId: model.currentUserId,
                        canClose: poll.createdBy == model.currentUserId,
                        onVote: { model.votePoll(optionIndex: $0) },
                        onClose: { model.closePoll() },
                        onDismiss: { model.dismissPoll() }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let request = model.pendingPauseRequest {
                    PauseRequestBanner(
                        request: request,
                        onPause: { model.resolvePauseRequest(pause: true) },
                        onDismiss: { model.resolvePauseRequest(pause: false) }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Карточка поверх poll/pause — опоздание важнее, чем
                // просьба о паузе в момент входа (паузу всё равно увидит хост).
                if let catchUp = model.catchUpPrompt {
                    CatchUpBanner(
                        prompt: catchUp,
                        loading: model.catchUpLoading,
                        onRequest: { model.requestCatchUp() },
                        onDismiss: { model.dismissCatchUp() }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 56)
            .padding(.horizontal, 24)
            .frame(maxWidth: 420)
            .zIndex(400)
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86),
                       value: model.pendingPauseRequest?.id)
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86),
                       value: model.catchUpPrompt?.sinceMs)
        }
        // Голосование. В портрете кнопка живёт в строке комнаты под кадром
        // (RoomHeaderBar) — оверлеем она садилась на ряд перемотки внутри
        // видео. В ландшафте и на планшете такой строки нет, там она
        // остаётся у левого края, ниже постоянного крестика.
        .overlay(alignment: .topLeading) {
            if layoutVariant != .portrait, model.activePoll == nil {
                Button {
                    showPollComposer = true
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .plinkGlass(.overlay, in: Circle())
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
        // Участник без подписки на сервис комнаты: плеер покажет его страницу
        // входа, поэтому даём войти прямо отсюда, не выходя из комнаты.
        .sheet(item: $loginAccount) { account in
            CinemaAccountLoginSheet(account: account) {
                account.markConnected()
                loginAccount = nil
                model.refreshServiceAccess()
            }
        }
        // P1 5.11 (ревью): панель живой темы презентуется С УРОВНЯ ЭКРАНА.
        // Раньше она жила в PlayerTopChrome внутри `if ui.controlsVisible` —
        // автоскрытие контролов через 4 с сносило хром, а вместе с ним и шит:
        // единственная точка входа в платную фичу закрывалась сама собой.
        .sheet(isPresented: $ui.appearancePanelPresented) {
            RoomAppearanceControlPanel(
                store: model.appearanceStore,
                onError: { model.reportRoomError($0) }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(Cinema2026.background)
        }
        .task { await model.connect() }
        .task {
            // Приватность комнаты + автопоказ бара модерации для хоста.
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
            // «Продолжить просмотр» — хост делает синхронный seek к таймкоду
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
            // Do NOT disconnect here — onDisappear fires on rotation, when
            // SwiftUI rebuilds the view. Disconnect only on explicit
            // leaveRoom (X button) or when fullScreenCover is dismissed.
            controlsHideTask?.cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                OrientationManager.shared.unlockOrientation()
            }
        }
        // lastError раньше был виден ТОЛЬКО внутри
        // карточки «Connection lost» — то есть при живом соединении ошибка
        // (отказ кика, мут, серверный reject) не доезжала до пользователя
        // вовсе. Показываем тостом; медиа-ошибки идут своим каналом
        // (mediaError) и остаются в плеере.
        //
        // Ревью 26.07.2026: тост — НЕ канал доставки ошибок панели темы. Панель
        // это .sheet поверх экрана, тост рисуется под ним и его не видно;
        // ошибки выбора темы показывает inlineError внутри самой панели.
        // Здесь же чиним вторую половину: lastError сбрасывается сразу после
        // показа, иначе повтор ОДНОГО И ТОГО ЖЕ текста не проходил
        // Equatable-сравнение onChange и второй тап не давал никакой реакции.
        .onChange(of: model.lastError) { _, newValue in
            guard let text = newValue, !text.isEmpty else { return }
            // Медиа-ошибку уже рисует плеер — вторым слоем тост не нужен.
            guard text != model.mediaError else { return }
            // В .failed текст нужен карточке «Connection lost» — не гасим его.
            if case .failed = model.connectionState { return }
            withAnimation(.easeOut(duration: 0.2)) {
                ui.activeToast = RoomToast(kind: .error, text: text)
            }
            model.clearLastError()
        }
        // Тост сам гаснет: раньше он висел до конца сессии (единственный
        // источник — подсказка про перемотку — так и оставался на экране).
        .task(id: ui.activeToast?.id) {
            guard ui.activeToast != nil else { return }
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { ui.activeToast = nil }
        }
        .onChange(of: model.connectionState) { _, newState in
            if newState == .idle && model.wantsDismiss {
                dismiss()
            }
        }
        .onChange(of: model.wantsDismiss) { _, wants in
            if wants { dismiss() }
        }
        // Жеста «тап по экрану → хром» здесь БОЛЬШЕ НЕТ, и это не упрощение.
        // Он висел на корневом стеке, то есть на предке всех кнопок панели,
        // и забирал их касания себе: тап по «Звук» или «Полный экран» гасил
        // хром вместо своего действия — из портрета было не выйти вовсе.
        // Живой кейс PlayerChromeLiveUITests ловил это как «кнопка исчезла
        // сразу после тапа». Переключение хрома переехало внутрь кадра
        // (PlayerStage.surfaceTapLayer и зоны ±10 с в PlinkPlayerControls),
        // где порядок ZStack сам отдаёт тап кнопкам, нарисованным выше.
        .onChange(of: ui.controlsVisible) { _, visible in
            PlinkChromeTrace.log("controlsVisible=\(visible)")
            // Covers the in-stage tap layer and taps reported by the
            // embedded web surface (PlayerSurfaceView.onSurfaceTap).
            if visible {
                scheduleControlsHide()
            } else {
                controlsHideTask?.cancel()
            }
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
            PlinkChromeTrace.log("autoHideFired")
            withAnimation(.plinkControls) {
                ui.controlsVisible = false
            }
        }
    }
}
