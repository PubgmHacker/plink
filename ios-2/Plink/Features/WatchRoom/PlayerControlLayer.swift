// Plink/Features/WatchRoom/PlayerControlLayer.swift — PATCH 02
//
// Extracted from PlayerStage.swift per PATCH 02 spec.
//
// Contains:
//   - PlayerTopChrome     (close, sync pill, more menu)
//   - PlayerCenterControl (play/pause for host)
//   - PlayerChromeButton  (36pt touch target, .ultraThinMaterial bg)

//   - PlayerLoadingView   (initial buffer spinner)
//   - BufferingOverlay    (mid-playback rebuffer)
//   - SyncHealthPill      (drift indicator)
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
    // M14: шит приглашения (QR + шер-линк)
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

                // M15: бар модерации — повторный вызов (только хост)
                if model.isHost {
                    Button {
                        HapticManager.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            model.moderationBarVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(model.moderationBarVisible ? PlinkRoomAccent.current : Color.white.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
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
                        Image(systemName: "paintbrush.pointed.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(
                                RoomLiveTheme.isActive(model.appearanceStore.appearance)
                                    ? PlinkRoomAccent.current
                                    : Color.white.opacity(0.85)
                            )
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Тема комнаты")
                }

                // M14: полноценное приглашение: QR-код + шер-линк + копирование
                Button {
                    HapticManager.impact(.light)
                    showInvite = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PlinkRoomAccent.current)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
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
                // M14: синхронный отсчёт 3-2-1, когда в комнате есть зрители
                model.sendPlayWithCountdown()
            }
        } label: {
            Image(systemName: model.coordinator.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: model.coordinator.isPlaying ? 0 : 1.5)
                .frame(width: 64, height: 64)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    // M14: акцент выбранной V4-темы продолжается в комнате
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
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// Аудит 26.07.2026 (P1 5.5): неиспользуемый PlayerSmallButton удалён
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct BufferingOverlay: View {
    var body: some View {
        ProgressView()
            .tint(.white)
            .scaleEffect(0.95)
            .padding(18)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 0.5))
    }
}

// MARK: - M40: полноценная панель управления Plink
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
                    .background(.ultraThinMaterial, in: Capsule())
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
                    .background(.ultraThinMaterial, in: Circle())
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
                .background(.ultraThinMaterial, in: Circle())
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
                    Label("Управляет хост", systemImage: "lock.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                // Скорость
                // Аудит 26.07.2026 P1: меню только при canControl — rate не входит
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
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel((embedded?.isMuted ?? false) ? "Включить звук" : "Выключить звук")

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
                        .background(.ultraThinMaterial, in: Circle())
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
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: Вспомогательное

    private func showHostHint() {
        ui.activeToast = RoomToast(kind: .info, text: "Перемоткой управляет хост комнаты")
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

// MARK: - Sync health pill

struct SyncHealthPill: View {
    let driftMs: Double
    let connected: Bool

    private var color: Color {
        guard connected else { return Cinema2026.danger }
        if driftMs < 80 { return Cinema2026.accent }
        if driftMs < 250 { return Cinema2026.secondary }
        if driftMs < 750 { return Cinema2026.amber }
        return Cinema2026.danger
    }

    private var label: String {
        // Аудит 26.07.2026: подписи были на английском в русскоязычном
        // интерфейсе. Это главный видимый элемент нашего отличия от конкурентов —
        // он не должен выглядеть недоделанным.
        guard connected else { return "Нет связи" }
        if driftMs < 80 { return "В синхроне" }
        if driftMs < 250 { return "Синхронизация" }
        if driftMs < 750 { return "Отставание" }
        return "Пересинхрон"
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.6), radius: 3)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Cinema2026.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.5))
    }
}
