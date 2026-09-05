// Plink/Features/WatchRoom/PlayerControlLayer.swift
//
// Хром плеера комнаты: верхняя панель (закрыть, статус синхронизации, меню),
// центральная кнопка воспроизведения для хоста, индикаторы буферизации и
// расхождения, баннеры «догнать» и «просьба о паузе».
//
// Размеры: кнопки хрома 36 pt, центральная 64 pt — минимум по HIG.

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
    /// Название того, что идёт в комнате. Пока кадр закрыт заставкой, подпись
    /// рисует она, и сюда приходит nil — иначе название стояло бы дважды.
    var mediaTitle: String? = nil
    /// Вырез, домашняя полоса и ящик чата. Затемнение сверху рисует сам кадр
    /// и оно во всю ширину — отступ получает только содержимое.
    var chromeInsets: EdgeInsets = EdgeInsets()
    // Шит приглашения (QR + шер-линк)

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                // Место постоянного крестика. Сам он живёт оверлеем экрана —
                // выйти из комнаты можно и когда хром скрыт автотаймером,
                // поэтому вторая такая же кнопка здесь была бы дублем.
                Color.clear.frame(width: 40, height: 36)

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
                    .plinkHitTarget(36)
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
                    .plinkHitTarget(36)
                    .accessibilityLabel("Тема комнаты")
                }
            }
            .padding(.leading, 14 + chromeInsets.leading)
            .padding(.trailing, 14 + chromeInsets.trailing)
            .padding(.top, (variant == .landscape ? 12 : 8) + chromeInsets.top)

            if let mediaTitle, !mediaTitle.isEmpty {
                HStack {
                    Text(mediaTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.65), radius: 5, y: 1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 16 + chromeInsets.leading)
                .padding(.trailing, 16 + chromeInsets.trailing)
                .padding(.top, 2)
            }

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

// PlayerChromeButton удалён вместе со вторым крестиком: единственным его
// вызовом был дубль кнопки выхода, а постоянный крестик экрана рисуется
// собственным стилем. PlayerSmallButton удалён раньше по той же причине.

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
    /// Вырез, домашняя полоса и ширина ящика чата справа. Отступ получает
    /// содержимое, а не вся панель: затемнение под ней обязано доходить до
    /// краёв кадра, иначе посреди картинки висит чёрный прямоугольник.
    var chromeInsets: EdgeInsets = EdgeInsets()

    @State private var scrubValue: Double = 0
    @State private var showSpeedMenu = false
    @State private var showQualityMenu = false
    @State private var seekFlash: String?

    private var embedded: EmbeddedPlaybackController? {
        model.coordinator.currentController as? EmbeddedPlaybackController
    }

    /// Родной AVPlayer (mp4/HLS). Панель одна на всех провайдеров, поэтому
    /// каждый «локальный» параметр — буфер, звук — берётся у того контроллера,
    /// который сейчас живой.
    private var native: NativePlayerController? {
        model.coordinator.currentController as? NativePlayerController
    }

    private var bufferedFraction: Double {
        embedded?.buffered ?? native?.buffered ?? 0
    }

    private var isMuted: Bool {
        embedded?.isMuted ?? native?.isMuted ?? false
    }

    /// Скорость меняет ТОЛЬКО тот провайдер, у которого она локальна.
    /// У родного плеера `setRate` — это ручка синхронизатора: он правит ею
    /// расхождение и вернёт свою величину на ближайшем тике, а комната
    /// разъедется, потому что rate не входит в протокол sync. Поэтому у
    /// родного пути пилюли скорости нет вовсе — вместо неё врущей.
    private var canChangeRate: Bool { embedded != nil }

    private func toggleMute() {
        let next = !isMuted
        if let embedded {
            embedded.setMuted(next)
        } else {
            native?.setMuted(next)
        }
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
            // Одиночный тап здесь же переключает хром — раньше этим занимался
            // жест корневого стека комнаты, но он лежал НАД кнопками панели
            // и глотал их касания (см. WatchRoomScreen).
            //
            // Полосы сверху и снизу вырезаны намеренно: в них живут ряд
            // PlayerTopChrome и сама панель. Зоны занимали весь кадр и
            // лежали выше верхнего хрома — его кнопки были недоступны.
            HStack(spacing: 0) {
                seekZone(delta: -10, label: "−10")
                seekZone(delta: 10, label: "+10")
            }
            .padding(.top, Self.topBand(for: variant) + chromeInsets.top)
            .padding(.bottom, Self.bottomBand(for: variant) + chromeInsets.bottom)

            VStack(spacing: 0) {
                // Отступ сверху ровно под хром: в портрете сцена — всего
                // 16:9 (≈221 pt на 393-точечном экране), и центрирование по
                // всей высоте сажало кнопку play прямо на ряд «крестик —
                // пилюля синхрона — щит».
                //
                // Касаний распорка не принимает: `Color` — обычная заливка и
                // при прозрачности остаётся мишенью hit-test, а эта лежит
                // ровно поверх кнопок PlayerTopChrome.
                Color.clear
                    .frame(height: chromeInset + chromeInsets.top)
                    .allowsHitTesting(false)
                Spacer(minLength: 0)
                centerTransport
                    .padding(.leading, chromeInsets.leading)
                    .padding(.trailing, chromeInsets.trailing)
                Spacer(minLength: 0)
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
            // Порядок важен: двойной тап объявлен первым, иначе одиночный
            // срабатывает раньше и перемотки ±10 с не будет никогда.
            .onTapGesture {
                PlinkChromeTrace.log("seekZoneSingleTap")
                guard !ui.chatPresented else { return }
                withAnimation(.plinkControls) { ui.toggleControlsDebounced() }
            }
    }

    /// Высота верхней полосы кадра — ряд PlayerTopChrome. Одна величина на
    /// три места: отступ центрального транспорта, вырезанная у зон ±10 с
    /// полоса и гейт тапа встроенной поверхности (PlayerStage).
    static func topBand(for variant: WatchRoomLayoutState.Variant) -> CGFloat {
        variant == .landscape ? 60 : 50
    }

    /// Высота нижней панели: ряд кнопок плюс полоса перемотки под ним.
    static func bottomBand(for variant: WatchRoomLayoutState.Variant) -> CGFloat {
        variant == .landscape ? 96 : 88
    }

    // MARK: Центр — перемотка и play/pause

    /// Высота верхнего хрома вместе с названием — центральный ряд начинается
    /// под ней, а не от верхнего края кадра.
    private var chromeInset: CGFloat { Self.topBand(for: variant) }
    private var playSize: CGFloat { variant == .landscape ? 74 : 58 }
    private var sideSize: CGFloat { variant == .landscape ? 48 : 40 }
    private var transportSpacing: CGFloat { variant == .landscape ? 40 : 30 }

    private var centerTransport: some View {
        HStack(spacing: transportSpacing) {
            transportButton("gobackward.10", size: sideSize) {
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
                    .font(.system(size: playSize * 0.4, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: model.coordinator.isPlaying ? 0 : playSize * 0.04)
                    .frame(width: playSize, height: playSize)
                    .plinkGlass(.overlay, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.coordinator.isPlaying ? "Пауза" : "Смотреть")

            transportButton("goforward.10", size: sideSize) {
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
                .font(.system(size: size * 0.55, weight: .regular))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 6, y: 1)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Нижняя панель — время, перемотка, скорость, качество, экран

    private var bottomBar: some View {
        // Форма как у YouTube/Netflix на телефоне: сначала строка «время и
        // кнопки», под ней полоса перемотки во всю ширину. Прежняя раскладка
        // зажимала полосу между двумя таймкодами и уводила звук с полным
        // экраном в почти пустой второй ряд — в портрете, где под кадр
        // отведено всего 16:9, это съедало высоту зря.
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Text(Self.timeLabel(position) + " / " + Self.timeLabel(duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .accessibilityLabel(
                        "Прошло " + Self.timeLabel(position)
                        + ", осталось " + Self.timeLabel(max(0, duration - position))
                    )

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
                if canControl && canChangeRate {
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

                // Чат — в общем ряду с остальными кнопками. Раньше его
                // открывала плавающая кнопка у правого края кадра: она стояла
                // ровно поверх конца полосы перемотки и кнопки полного экрана,
                // так что нижние контролы было нечем нажать. Место кнопки —
                // здесь, рядом со звуком, как переключатель чата у ютуба.
                if variant == .landscape {
                    Button {
                        HapticManager.impact(.light)
                        withAnimation(.plinkDrawer) { ui.chatDrawerVisible.toggle() }
                    } label: {
                        Image(systemName: ui.chatDrawerVisible
                              ? "bubble.left.and.bubble.right.fill"
                              : "bubble.left.and.bubble.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .plinkGlass(.overlay, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .plinkHitTarget(32)
                    .accessibilityLabel(ui.chatDrawerVisible ? "Закрыть чат" : "Открыть чат")
                    .accessibilityIdentifier("player.chatToggle")
                }

                // Звук — локально у каждого участника, синхрон не трогает
                Button {
                    PlinkChromeTrace.log("muteButtonAction")
                    HapticManager.impact(.light)
                    toggleMute()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .plinkGlass(.overlay, in: Circle())
                }
                .buttonStyle(.plain)
                .plinkHitTarget(32)
                .accessibilityLabel(isMuted ? "Включить звук" : "Выключить звук")
                .accessibilityIdentifier("player.mute")

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
                .accessibilityIdentifier("player.fullscreen")
            }

            PlinkSeekBar(
                value: $scrubValue,
                buffered: bufferedFraction,
                duration: max(duration, 0.001),
                isScrubbing: $ui.isScrubbing,
                enabled: canControl && duration > 0,
                onCommit: { target in
                    Task { await model.sendSeekCommand(to: target) }
                }
            )
            .frame(height: 24)
            .accessibilityIdentifier("player.seek")
        }
        .padding(.leading, 14 + chromeInsets.leading)
        .padding(.trailing, 14 + chromeInsets.trailing)
        .padding(.bottom, (variant == .landscape ? 14 : 10) + chromeInsets.bottom)
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
                .plinkHitTarget(32)
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

