// Plink/Features/WatchRoom/PlayerControlLayer.swift
//
// Extracted from PlayerStage.swift.
//
// Contains:
//   - PlayerTopChrome     (close, sync pill, more menu)
//   - PlayerCenterControl (play/pause for host)
//   - PlayerChromeButton  (36pt touch target, .ultraThinMaterial bg)

//   - PlayerLoadingView   (initial buffer spinner)
//   - BufferingOverlay    (mid-playback rebuffer)
//   - SyncHealthPill      (drift indicator)
//   - RoomVoiceButton     (микрофон в комнате — функция Плинк+)
//
// Professional sizing:
//   - Chrome buttons: 36pt (was 32pt) — meets 36pt min touch target.
//   - Center control: 64pt (was 52pt) — Apple TV app parity.
//   - Sync pill: 12pt font (was 11pt), proper internal padding.
//   - All chrome uses .ultraThinMaterial over void for depth.

import SwiftUI

// MARK: - Top chrome

struct PlayerTopChrome: View {
    let model: WatchRoomModel
    let variant: WatchRoomLayoutState.Variant
    /// P1 5.11 (ревью): открыть панель живой темы. Сам шит презентует
    /// WatchRoomScreen — хром живёт внутри `if ui.controlsVisible` и исчезает
    /// по таймеру автоскрытия, унося с собой любой презентованный отсюда шит.
    /// Дефолт — no-op, чтобы превью/снапшоты рисовали хром без контекста экрана.
    var onOpenAppearance: () -> Void = {}
    // Шит приглашения (QR + шер-линк)
    @State private var showInvite = false

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                PlayerChromeButton(systemName: "xmark") {
                    model.leaveRoom()
                }
                .accessibilityLabel("Выйти из комнаты")

                Spacer()

                SyncHealthPill(
                    driftMs: model.lastDriftMs,
                    connected: model.connectionState == .connected
                )

                Spacer()

                // Бар модерации — повторный вызов (только хост)
                if model.isHost {
                    Button {
                        HapticManager.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            model.moderationBarVisible.toggle()
                        }
                    } label: {
                        V4GlyphIcon(glyph: .shield, size: 14, weight: .regular)
                            .foregroundStyle(model.moderationBarVisible ? PlinkRoomAccent.current : Color.white.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .plinkGlass(.overlay, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Модерация комнаты")

                    // P1 5.11: живая тема комнаты. Кнопки нет ни у кого, кроме
                    // хоста — тема host-authoritative, зритель её только видит.
                    Button {
                        HapticManager.impact(.light)
                        onOpenAppearance()
                    } label: {
                        V4GlyphIcon(glyph: .appearance, size: 14, filled: true, weight: .regular)
                            .foregroundStyle(
                                RoomLiveTheme.isActive(model.appearanceStore.appearance)
                                    ? PlinkRoomAccent.current
                                    : Color.white.opacity(0.85)
                            )
                            .frame(width: 36, height: 36)
                            .plinkGlass(.overlay, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Тема комнаты")
                }

                // Полноценное приглашение: QR-код + шер-линк + копирование
                Button {
                    HapticManager.impact(.light)
                    showInvite = true
                } label: {
                    V4GlyphIcon(glyph: .plus, size: 14, weight: .regular)
                        .foregroundStyle(PlinkRoomAccent.current)
                        .frame(width: 36, height: 36)
                        .plinkGlass(.overlay, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Пригласить в комнату")
                .sheet(isPresented: $showInvite) {
                    RoomInviteSheet(model: model)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, variant == .landscape ? 12 : 8)
            Spacer()
        }
    }
}

// MARK: - Center control

struct PlayerCenterControl: View {
    let model: WatchRoomModel

    var body: some View {
        Button {
            if model.coordinator.isPlaying {
                model.sendPauseCommand()
            } else {
                // Синхронный отсчёт 3-2-1, когда в комнате есть зрители
                model.sendPlayWithCountdown()
            }
        } label: {
            Image(systemName: model.coordinator.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: model.coordinator.isPlaying ? 0 : 1.5)
                .frame(width: 64, height: 64)
                .plinkGlass(.overlay, in: Circle())
                .overlay(
                    // Акцент выбранной V4-темы продолжается в комнате
                    Circle().stroke(PlinkRoomAccent.current.opacity(0.65), lineWidth: 1.2)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!model.isHost || model.connectionState != .connected || model.countdownRemaining != nil)
        .opacity(model.isHost ? 1 : 0)
        .accessibilityLabel(model.coordinator.isPlaying ? "Pause" : "Play")
    }
}

// MARK: - Chrome buttons

struct PlayerChromeButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Cinema2026.text)
                .frame(width: 36, height: 36)
                .plinkGlass(.overlay, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// Неиспользуемый PlayerSmallButton удалён
// (задумывался под PiP/fullscreen, но нигде не инстанцировался).

// MARK: - Loading & buffering

struct PlayerLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Cinema2026.accent)
                .scaleEffect(1.15)
            Text("Загрузка…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Cinema2026.secondary)
        }
        .padding(20)
        .plinkGlass(.overlay, cornerRadius: 14)
    }
}

struct BufferingOverlay: View {
    var body: some View {
        ProgressView()
            .tint(.white)
            .scaleEffect(0.95)
            .padding(18)
            .plinkGlass(.overlay, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 0.5))
    }
}

// MARK: - Полноценная панель управления Plink
//
// Раньше контролы рисовал сам YouTube (`controls=1`), а Plink показывал только
// крестик, пилюлю синхрона и кнопку play для хоста. Полосы перемотки, времени,
// скорости, качества и полного экрана не было вовсе — при этом готовый
// `PlinkSeekBar` лежал в проекте неподключённым.
//
// Теперь обёртка плеера отдаётся с `controls=0`, а всё управление здесь.
//
// Важное продуктовое правило: перемотку и play/pause выполняет ТОЛЬКО хост —
// иначе рассинхронизируется вся комната. Гость видит те же элементы, но они
// неактивны и объясняют почему, вместо того чтобы молча не срабатывать.

struct PlinkPlayerControls: View {
    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState
    let variant: WatchRoomLayoutState.Variant

    @State private var scrubValue: Double = 0
    @State private var showSpeedMenu = false
    @State private var showQualityMenu = false
    @State private var seekFlash: String?

    private var embedded: EmbeddedPlaybackController? {
        model.coordinator.currentController as? EmbeddedPlaybackController
    }

    private var canControl: Bool {
        model.isHost && model.connectionState == .connected && model.countdownRemaining == nil
    }

    private var duration: Double { max(model.coordinator.duration, 0) }
    private var position: Double {
        ui.isScrubbing ? scrubValue : model.coordinator.position
    }

    var body: some View {
        ZStack {
            // Жесты двойного тапа: −10 с слева, +10 с справа (как в YouTube).
            HStack(spacing: 0) {
                seekZone(delta: -10, label: "−10")
                seekZone(delta: 10, label: "+10")
            }

            VStack {
                Spacer()
                centerTransport
                Spacer()
                bottomBar
            }

            if let seekFlash {
                Text(seekFlash)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .plinkGlass(.overlay, in: Capsule(style: .continuous))
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: model.coordinator.position) { _, new in
            if !ui.isScrubbing { scrubValue = new }
        }
    }

    // MARK: Зоны двойного тапа

    private func seekZone(delta: Double, label: String) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard canControl else { return showHostHint() }
                let target = max(0, min(duration > 0 ? duration : .greatestFiniteMagnitude,
                                        model.coordinator.position + delta))
                HapticManager.impact(.light)
                flash("\(label) с")
                Task { await model.sendSeekCommand(to: target) }
            }
    }

    // MARK: Центр — перемотка и play/pause

    private var centerTransport: some View {
        HStack(spacing: 28) {
            transportButton("gobackward.10", size: 44) {
                let target = max(0, model.coordinator.position - 10)
                Task { await model.sendSeekCommand(to: target) }
            }

            Button {
                guard canControl else { return showHostHint() }
                HapticManager.impact(.medium)
                if model.coordinator.isPlaying {
                    model.sendPauseCommand()
                } else {
                    model.sendPlayWithCountdown()
                }
            } label: {
                Image(systemName: model.coordinator.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: model.coordinator.isPlaying ? 0 : 2)
                    .frame(width: 68, height: 68)
                    .plinkGlass(.overlay, in: Circle())
                    .overlay(Circle().stroke(PlinkRoomAccent.current.opacity(0.65), lineWidth: 1.2))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.coordinator.isPlaying ? "Пауза" : "Смотреть")

            transportButton("goforward.10", size: 44) {
                let target = min(duration > 0 ? duration : .greatestFiniteMagnitude,
                                 model.coordinator.position + 10)
                Task { await model.sendSeekCommand(to: target) }
            }
        }
        .opacity(canControl ? 1 : 0.5)
    }

    private func transportButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            guard canControl else { return showHostHint() }
            HapticManager.impact(.light)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .plinkGlass(.overlay, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Нижняя панель — время, перемотка, скорость, качество, экран

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(Self.timeLabel(position))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))

                PlinkSeekBar(
                    value: $scrubValue,
                    buffered: embedded?.buffered ?? 0,
                    duration: max(duration, 0.001),
                    isScrubbing: $ui.isScrubbing,
                    enabled: canControl && duration > 0,
                    onCommit: { target in
                        Task { await model.sendSeekCommand(to: target) }
                    }
                )
                .frame(height: 28)

                Text(Self.timeLabel(duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }

            HStack(spacing: 10) {
                if !model.isHost {
                    // Раньше здесь стояла только подпись «Управляет хост» —
                    // констатация без выхода. Гость, которому надо отойти на
                    // минуту, мог лишь написать в чат и надеяться, что хост его
                    // прочитает, а не смотрит в кадр. Пока идёт воспроизведение,
                    // на этом же месте живая кнопка; на паузе останавливать
                    // нечего, и подпись возвращается.
                    if model.coordinator.isPlaying {
                        Button {
                            HapticManager.impact(.light)
                            askForPause()
                        } label: {
                            pillLabel(
                                LocalizationManager.shared.string(.pauseAskAction),
                                icon: "hand.raised.fill"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("room.requestPause")
                    } else {
                        Label(
                            LocalizationManager.shared.string(.roomHostControls),
                            systemImage: "lock.fill"
                        )
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                    }
                }

                Spacer()

                // Скорость
                // Меню только при canControl — rate не входит
                // в протокол sync.command, поэтому гость с 2× ломал себе синхрон
                // (циклический жёсткий seek от OrderedSyncController). Для хоста
                // скорость остаётся локальной, пока rate не добавлен в протокол.
                if canControl {
                    Menu {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                            Button {
                                guard canControl else { return showHostHint() }
                                embedded?.setRate(Float(rate))
                            } label: {
                                Label(Self.rateLabel(rate),
                                      systemImage: abs(Double(embedded?.playbackRate ?? 1) - rate) < 0.01
                                          ? "checkmark" : "")
                            }
                        }
                    } label: {
                        pillLabel(Self.rateLabel(Double(embedded?.playbackRate ?? 1)), icon: "speedometer")
                    }
                }

                // Качество — список приходит от YouTube
                if let levels = embedded?.availableQualities, !levels.isEmpty {
                    Menu {
                        ForEach(levels, id: \.self) { level in
                            Button {
                                embedded?.setQuality(level)
                            } label: {
                                Label(Self.qualityLabel(level),
                                      systemImage: level == embedded?.currentQuality ? "checkmark" : "")
                            }
                        }
                    } label: {
                        pillLabel(Self.qualityLabel(embedded?.currentQuality ?? ""), icon: "slider.horizontal.3")
                    }
                }

                // Звук
                Button {
                    guard let embedded else { return }
                    HapticManager.impact(.light)
                    embedded.setMuted(!embedded.isMuted)
                } label: {
                    Image(systemName: (embedded?.isMuted ?? false) ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .plinkGlass(.overlay, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel((embedded?.isMuted ?? false) ? "Включить звук" : "Выключить звук")

                // Микрофон комнаты — функция Плинк+ (02.08.2026).
                // В личных сообщениях голос бесплатен и живёт в другом экране —
                // этот компонент намеренно только для комнаты.
                RoomVoiceButton(model: model, ui: $ui)

                // Полный экран
                Button {
                    HapticManager.impact(.medium)
                    if variant == .landscape {
                        model.exitFullscreen()
                    } else {
                        model.enterFullscreen()
                    }
                } label: {
                    Image(systemName: variant == .landscape
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .plinkGlass(.overlay, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(variant == .landscape ? "Выйти из полного экрана" : "Полный экран")
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, variant == .landscape ? 14 : 10)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.65)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        )
    }

    private func pillLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .plinkGlass(.overlay, in: Capsule(style: .continuous))
    }

    // MARK: Вспомогательное

    /// Просьба о паузе. Результат обязательно показываем — тихий провал
    /// здесь худший из возможных: человек уйдёт от экрана, уверенный, что его
    /// просьбу увидели.
    private func askForPause() {
        let l = LocalizationManager.shared
        switch model.requestPause() {
        case .sent:
            ui.activeToast = RoomToast(kind: .success, text: l.string(.pauseAskSent))
        case .offline:
            ui.activeToast = RoomToast(kind: .warning, text: l.string(.pauseAskOffline))
        case .throttled:
            ui.activeToast = RoomToast(kind: .info, text: l.string(.pauseAskThrottled))
        case .redundantForHost:
            // Кнопки у хоста нет — ветка недостижима, но исчерпывающий switch
            // заставит вернуться сюда, если роль когда-нибудь начнут менять
            // на живом экране (миграция хоста).
            break
        }
    }

    private func showHostHint() {
        ui.activeToast = RoomToast(
            kind: .info,
            text: LocalizationManager.shared.string(.roomHostControlsHint)
        )
    }

    private func flash(_ text: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { seekFlash = text }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeOut(duration: 0.2)) { seekFlash = nil }
        }
    }

    static func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    static func rateLabel(_ rate: Double) -> String {
        rate == 1 ? "1×" : String(format: "%g×", rate)
    }

    /// YouTube отдаёт технические имена уровней — показываем человеческие.
    static func qualityLabel(_ raw: String) -> String {
        switch raw {
        case "highres", "hd2880", "hd2160": return "4K"
        case "hd1440": return "1440p"
        case "hd1080": return "1080p"
        case "hd720": return "720p"
        case "large": return "480p"
        case "medium": return "360p"
        case "small": return "240p"
        case "tiny": return "144p"
        case "auto", "": return "Авто"
        default: return raw
        }
    }
}

// MARK: - Микрофон в комнате — пэйволл Плинк+ (02.08.2026)
//
// Решение продукта: голос и видеочат В КОМНАТЕ — платные, голос в ЛИЧНЫХ
// СООБЩЕНИЯХ — бесплатный для всех. Поэтому замок рисуется только здесь,
// в панели комнаты, и никогда — на экране переписки.
//
// Право решает СЕРВЕР, а не клиент. Локальный isPremium используется только
// для внешнего вида замка: показать замок или нет — косметика, а пустить ли
// в эфир — решает POST /rtc/token. Поэтому тап всегда идёт на сервер,
// даже если клиент думает, что подписки нет — иначе человек с только что
// оформленной подпиской упирался бы в старый кэш.

struct RoomVoiceButton: View {
    let model: WatchRoomModel
    @Binding var ui: WatchRoomUIState

    @ObservedObject private var premium = PremiumStatusManager.shared
    @State private var isRequesting = false
    @State private var micLive = false

    private var showsLock: Bool { !premium.isPremium && !micLive }

    var body: some View {
        Button {
            guard !isRequesting else { return }
            HapticManager.impact(.light)
            Task { await handleTap() }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: micLive ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(micLive ? PlinkRoomAccent.current : .white)
                    .frame(width: 32, height: 32)
                    .plinkGlass(.overlay, in: Circle())

                if showsLock {
                    V4GlyphIcon(glyph: .lock, size: 8, filled: true, weight: .regular)
                        .foregroundStyle(PlinkRoomAccent.ink)
                        .padding(3)
                        .background(PlinkRoomAccent.current, in: Circle())
                        .offset(x: 3, y: -3)
                }

                if isRequesting {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isRequesting)
        .accessibilityLabel(showsLock
            ? "Микрофон в комнате — функция Плинк плюс"
            : (micLive ? "Выключить микрофон" : "Включить микрофон"))
    }

    @MainActor
    private func handleTap() async {
        // Выключение не требует ни подписки, ни сети.
        if micLive {
            micLive = false
            return
        }

        let roomId = model.shareRoomId
        guard !roomId.isEmpty else {
            ui.activeToast = RoomToast(kind: .info, text: "Комната ещё не готова, попробуйте через секунду")
            return
        }

        isRequesting = true
        defer { isRequesting = false }

        do {
            let _: RTCTokenResponse = try await APIClient.shared.request(
                "rtc/token",
                method: .post,
                body: RTCTokenRequest(roomId: roomId)
            )

            // Право есть. Разрешение на микрофон спрашиваем ТОЛЬКО здесь — после
            // того как сервер подтвердил доступ. Спрашивать системное разрешение
            // у человека, которому сейчас покажут экран покупки — верный способ
            // получить отказ навсегда: повторно iOS его не покажет.
            let granted = await PlinkPermissions.requestMicrophoneIfNeeded()
            guard granted else {
                ui.activeToast = RoomToast(kind: .info, text: "Разрешите доступ к микрофону в настройках")
                return
            }

            micLive = true
            AnalyticsService.shared.voiceChatStarted()
            ui.activeToast = RoomToast(kind: .info, text: "Микрофон включён")
        } catch APIError.subscriptionRequired {
            // 402 — штатный путь обычного пользователя. Открываем экран покупки
            // через штатную нотификацию: её уже слушает WatchRoomContainer и держит
            // шит выше хрома плеера. Собственный .sheet здесь умирал бы вместе
            // с автоскрытием контролов через несколько секунд.
            AnalyticsService.shared.track("paywall_view", parameters: [
                "source": "mic_room",
                "feature": "room_rtc",
            ])
            NotificationCenter.default.post(
                name: .showPlinkPlusPaywall,
                object: nil,
                userInfo: ["trigger": PlinkPlusPaywall.Trigger.voiceChat]
            )
        } catch APIError.unavailable(let reason, let message) {
            // 503 — функция ещё не включена (нет ключей LiveKit). Это не ошибка
            // и НЕ повод продавать подписку: подписчик должен увидеть честное
            // «скоро», а не молчаливый отказ.
            let text = reason == "not_configured"
                ? "Голос в комнате скоро появится"
                : message
            ui.activeToast = RoomToast(kind: .info, text: text)
        } catch {
            ui.activeToast = RoomToast(kind: .info, text: "Не удалось включить микрофон")
        }
    }
}

/// Тело запроса POST /api/rtc/token.
struct RTCTokenRequest: Encodable {
    let roomId: String
}

/// Ответ POST /api/rtc/token. Поля url/roomName опциональные намеренно:
/// контракт будет расширяться при реальном включении LiveKit, и жёсткий
/// декодер ломал бы клиент на первом же новом поле.
struct RTCTokenResponse: Decodable {
    let token: String
    let url: String?
    let roomName: String?
    let identity: String?
    let expiresInSec: Int?
}

// MARK: - Просьба о паузе (баннер хоста)
//
// Живёт НЕ внутри хрома плеера намеренно. Хром скрывается по таймеру
// автоскрытия через несколько секунд — просьба, уехавшая вместе с ним, ничем
// не отличалась бы от неотправленной. Поэтому баннер рисует сам экран
// (WatchRoomScreen), рядом с карточкой голосования.
//
// Кнопки две и обе честные: «Пауза» действительно ставит паузу штатной
// sync.command (кадр совпадёт у всей комнаты), «Не сейчас» — отказ, а не
// откладывание. Гость получит ответ самим фактом: видео либо встало, либо нет.

/// Карточка «что я пропустил». Появляется сама при опоздании;
/// LLM-запрос — только по тапу, чтобы не тратить дневной лимит втихую.
struct CatchUpBanner: View {
    let prompt: WatchRoomModel.CatchUpPrompt
    let loading: Bool
    let onRequest: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        let l = LocalizationManager.shared
        let titleKey: L10n.Key = prompt.kind == .lateJoin
            ? .catchUpTitleLateJoin
            : .catchUpTitleReconnect

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PlinkRoomAccent.current)

                Text(String(format: l.string(titleKey), prompt.missedMinutes))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)
            }

            Text(l.string(.catchUpBody))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    HapticManager.impact(.medium)
                    onRequest()
                } label: {
                    Group {
                        if loading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(PlinkRoomAccent.ink)
                        } else {
                            Text(l.string(.catchUpAction))
                        }
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PlinkRoomAccent.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(PlinkRoomAccent.current, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(loading)
                .accessibilityIdentifier("room.catchUp.request")

                Button {
                    HapticManager.impact(.light)
                    onDismiss()
                } label: {
                    Text(l.string(.catchUpDismiss))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .plinkGlass(.control, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(loading)
                .accessibilityIdentifier("room.catchUp.dismiss")
            }
        }
        .padding(14)
        .plinkGlass(.overlay, cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(PlinkRoomAccent.current.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room.catchUp")
    }
}

struct PauseRequestBanner: View {
    let request: WatchRoomModel.PauseRequestPrompt
    let onPause: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        let l = LocalizationManager.shared

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PlinkRoomAccent.current)

                Text(String(format: l.string(.pauseAskPrompt), request.username))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)
            }

            if let reason = request.reason, !reason.isEmpty {
                Text(reason)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    HapticManager.impact(.medium)
                    onPause()
                } label: {
                    Text(l.string(.pauseAskAccept))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PlinkRoomAccent.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(PlinkRoomAccent.current, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("room.pauseRequest.accept")

                Button {
                    HapticManager.impact(.light)
                    onDismiss()
                } label: {
                    Text(l.string(.pauseAskDismiss))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .plinkGlass(.control, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("room.pauseRequest.dismiss")
            }
        }
        .padding(14)
        .plinkGlass(.overlay, cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(PlinkRoomAccent.current.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room.pauseRequest")
    }
}

// MARK: - Sync health pill

/// Пороги здоровья синхрона — единственный источник истины.
///
/// Раньше числа 80/250/750 были зашиты прямо в `SyncHealthPill.color` и
/// `SyncHealthPill.label`. Как только появился поясняющий текст, это стало
/// опасно: маркетинговое «держим в пределах 50 мс» из UX-ревью разошлось бы с
/// реальным порогом 80 мс, и интерфейс начал бы врать. Теперь и цвет, и
/// подпись, и текст пояснения читают одни и те же константы.
enum SyncThresholds {
    /// До этого расхождения считаем, что участники смотрят один кадр.
    static let inSyncMs: Double = 80
    /// До этого — подтягиваем, но это ещё рабочее состояние.
    static let syncingMs: Double = 250
    /// До этого — заметное отставание. Выше — принудительный пересинхрон.
    static let laggingMs: Double = 750
}

/// Индикатор расхождения кадра — главное видимое отличие Plink от Rave и Hearo.
///
/// UX-ревью 26.07.2026 назвало этот элемент сильнейшей вещью в продукте, но по
/// факту он показывал только цветную точку и слово: `driftMs` приходил во вью и
/// использовался ИСКЛЮЧИТЕЛЬНО для выбора цвета и подписи. То есть те самые
/// «12 мс», которых нет ни у одного конкурента, на экран не выводились.
///
/// Закрыто 11.08.2026: число на экране, тап открывает пояснение, подписи ушли в
/// LocalizationManager.
struct SyncHealthPill: View {
    let driftMs: Double
    let connected: Bool

    @State private var showExplainer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color {
        guard connected else { return Cinema2026.danger }
        if driftMs < SyncThresholds.inSyncMs { return Cinema2026.accent }
        if driftMs < SyncThresholds.syncingMs { return Cinema2026.secondary }
        if driftMs < SyncThresholds.laggingMs { return Cinema2026.amber }
        return Cinema2026.danger
    }

    private var label: String {
        let l = LocalizationManager.shared
        guard connected else { return l.string(.syncOffline) }
        if driftMs < SyncThresholds.inSyncMs { return l.string(.syncInSync) }
        if driftMs < SyncThresholds.syncingMs { return l.string(.syncSyncing) }
        if driftMs < SyncThresholds.laggingMs { return l.string(.syncLagging) }
        return l.string(.syncResync)
    }

    var body: some View {
        Button {
            HapticManager.impact(.light)
            showExplainer = true
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .shadow(color: color.opacity(0.6), radius: 3)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Cinema2026.text)
                if connected {
                    // Разделитель, а не пробел: без него «В синхроне 12 мс»
                    // читается как одна фраза, и число теряется.
                    Text(SyncHealthPill.formatDrift(driftMs))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        // Моноширинные цифры обязательны: дрейф пересчитывается
                        // несколько раз в секунду, и на пропорциональных цифрах
                        // пилюля дёргалась бы по ширине при каждом обновлении.
                        .monospacedDigit()
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .plinkGlass(.overlay, in: Capsule(style: .continuous))
            .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.5))
            // Сама пилюля остаётся компактной (высота ~28 pt), но зона нажатия
            // расширена до минимума HIG в 44 pt по вертикали.
            .contentShape(Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: driftMs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(connected ? SyncHealthPill.formatDrift(driftMs) : "")
        .accessibilityHint(LocalizationManager.shared.string(.syncPillHint))
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $showExplainer) {
            SyncExplainerSheet(driftMs: driftMs, connected: connected)
        }
    }

    /// Формат расхождения. Ниже миллисекунды показываем «<1 мс», а не «0 мс»:
    /// ноль читается как «датчик не работает», а не как идеальный синхрон.
    static func formatDrift(_ ms: Double) -> String {
        let l = LocalizationManager.shared
        let value = abs(ms)
        if value < 1 { return l.string(.syncSubMs) }
        if value < 1000 { return "\(Int(value.rounded())) \(l.string(.syncUnitMs))" }
        return String(format: "%.1f %@", value / 1000, l.string(.syncUnitSec))
    }
}

/// Пояснение к пилюле синхрона.
///
/// UX-ревью: «стоит сделать его заметнее, добавить тап с пояснением». Здесь же
/// закрывается вопрос доверия — пользователь видит не только вердикт, но и
/// порог, по которому этот вердикт выносится.
struct SyncExplainerSheet: View {
    let driftMs: Double
    let connected: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let l = LocalizationManager.shared

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Text(l.string(.syncExplainerTitle))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                Spacer()
                Button { dismiss() } label: {
                    V4GlyphIcon(glyph: .close, size: 13, weight: .regular)
                        .foregroundStyle(Cinema2026.secondary)
                        .frame(width: 32, height: 32)
                        .plinkGlass(.control, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l.string(.close))
            }

            Text(l.string(.syncExplainerBody))
                .font(.system(size: 15))
                .foregroundStyle(Cinema2026.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                metricRow(
                    title: l.string(.syncExplainerCurrent),
                    value: connected
                        ? SyncHealthPill.formatDrift(driftMs)
                        : l.string(.syncExplainerNoData),
                    highlighted: connected
                )
                metricRow(
                    title: l.string(.syncExplainerThreshold),
                    value: SyncHealthPill.formatDrift(SyncThresholds.inSyncMs),
                    highlighted: false
                )
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Cinema2026.bg.ignoresSafeArea())
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
    }

    private func metricRow(title: String, value: String, highlighted: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Cinema2026.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(highlighted ? Cinema2026.accent : Cinema2026.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

