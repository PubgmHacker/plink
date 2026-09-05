// Plink/V4/V4AIView.swift — вкладка «ИИ» и голосовой ввод
//
// 02.08.2026, решение владельца: вкладка «ИИ» — это развлечение, а текстовый
// чат — способ найти фильм, поэтому он живёт отдельным экраном поверх вкладок.
//
// 03.08.2026, голос перестал быть режимом. Раньше вкладка делилась сегментом
// на «Рилсы» и «Голос», и голосовой экран умел только говорить. Теперь голос —
// способ ввода: нажимаешь микрофон, снизу поднимается сфера, отпускаешь —
// распознанный текст уходит запросом, ответ приходит текстом в чат.
//
// 03.08.2026, эргономика. Микрофон и чат стояли в шапке справа — до верхнего
// угла экрана 6.9" большим пальцем не дотянуться. Обе кнопки съехали вниз,
// в плавающий док над таб-баром. Запись не гасит экран: вместо полноэкранного
// слоя снизу поднимается компактная панель с мини-сферой, как у Siri.
//
// 03.08.2026, разделение сущностей. Трейлеры — это трейлеры: лента занимает весь
// экран и листается свайпом (V4ReelsView.swift), а чат живёт в V4AIChatView.swift.
// Шапка и док просто плавают поверх ленты.
//
// Следствие: приложение не произносит ответы вслух нигде. AISpeaker и
// AVSpeechSynthesizer удалены — чат остаётся чатом, голос остаётся вводом.
//
// Цвет: акцент всегда из активной темы (theme.accentColor), не зашивается в экран.
//
// 21.08.2026, чистка витрины. Крупный заголовок «ИИ» на чёрной подложке и
// полноэкранный дизмер «Будет доступно скоро» сняты: титул наезжал на
// карточку, подложка обрывалась полосой и читалась вторым экраном, а текст
// плашки ложился на кнопки под дизмером. Теперь лента в превью-режиме
// (V4ReelsPanel isPreview) — без мёртвых контролов, с тихим бейджем «Скоро»
// на кадре; сверху только микро-метка «ТРЕЙЛЕРЫ», скрим живёт в фоне ленты.
//
// 23.08.2026, онбординг вместо тихого бейджа. Решение владельца: «скоро»
// должно быть крупным онбордингом на весь раздел, а не подписью слева, при
// этом позади должна угадываться лента, и уже работающие чат с ИИ и голос
// должны быть видны сразу. Раздел закрывает слой на фросте: живая Metal-сфера
// ассистента (AssistantOrbView.swift), «Скоро» крупно и два рабочих входа —
// «Чат с ИИ» и «Голосовой ввод». Док и метка «ТРЕЙЛЕРЫ» на время онбординга
// не рисуются (их роли выполняют кнопки слоя) и вернутся вместе с живой
// лентой, когда подключится каталог.

import SwiftUI
import UIKit
import Combine
import Foundation

extension Notification.Name {
    /// Открыть текстовый чат с ИИ поверх любого экрана.
    static let plinkOpenAIChat = Notification.Name("plinkOpenAIChat")
    /// Открыть чат с сразу включённым микрофоном (бывший «голосовой режим»).
    static let plinkOpenAIVoice = Notification.Name("plinkOpenAIVoice")
}

// MARK: - Захват голоса

/// Один контроллер записи на обе поверхности — док вкладки «ИИ» и композер
/// чата. Поведение обязано совпадать до мелочей, поэтому логика жеста живёт
/// здесь, а не дублируется в двух экранах.
///
/// Три сценария нажатия:
/// 1. Удержание — пишем, пока палец на кнопке, отпустили — отправили.
/// 2. Короткий тап — запись «залипает», руки свободны, следующее нажатие
///    отправляет. Без этого случайное касание обрывало бы фразу на первом слове.
/// 3. Сдвиг пальца вверх на 80 pt — отпускание отменяет запрос.
@MainActor
final class V4VoiceCapture: ObservableObject {
    @Published private(set) var isCapturing = false
    @Published private(set) var isLocked = false
    @Published private(set) var cancelArmed = false
    @Published private(set) var heard = ""
    @Published private(set) var errorMessage: String?

    private let speech = V4SpeechRecognizer()
    private var bag = Set<AnyCancellable>()
    private var pressStartedAt = Date.distantPast

    /// Ниже этого порога нажатие считается тапом, а не удержанием.
    private let tapThreshold: TimeInterval = 0.35
    /// Насколько нужно увести палец вверх, чтобы отменить запрос.
    private let cancelDistance: CGFloat = -80

    init() {
        speech.$transcript
            .sink { [weak self] text in self?.heard = text }
            .store(in: &bag)
        speech.$errorMessage
            .sink { [weak self] message in
                guard let message, !message.isEmpty else { return }
                self?.fail(message)
            }
            .store(in: &bag)
    }

    func pressBegan(surface: String) {
        guard !isCapturing else { return }
        pressStartedAt = Date()
        heard = ""
        errorMessage = nil
        cancelArmed = false
        isLocked = false
        isCapturing = true
        HapticManager.impact(.medium)
        speech.start()
        AnalyticsService.shared.track("voice_input_started", parameters: ["surface": surface])
    }

    /// Запись без удержания — для входа «спросить голосом» с других экранов.
    func startLocked(surface: String) {
        guard !isCapturing else { return }
        pressBegan(surface: surface)
        isLocked = true
    }

    func pressMoved(_ translationHeight: CGFloat) {
        guard isCapturing, !isLocked else { return }
        let armed = translationHeight < cancelDistance
        if armed != cancelArmed {
            HapticManager.selection()
            cancelArmed = armed
        }
    }

    func pressEnded(complete: @escaping (String) -> Void) {
        guard isCapturing else { return }
        if cancelArmed { cancel(); return }
        if isLocked { finish(complete: complete); return }
        if Date().timeIntervalSince(pressStartedAt) < tapThreshold {
            isLocked = true
            HapticManager.impact(.light)
            return
        }
        finish(complete: complete)
    }

    func cancel() {
        guard isCapturing else { return }
        speech.stop()
        isCapturing = false
        isLocked = false
        cancelArmed = false
        heard = ""
        HapticManager.impact(.medium)
    }

    func dismissError() {
        errorMessage = nil
    }

    private func fail(_ message: String) {
        isCapturing = false
        isLocked = false
        cancelArmed = false
        heard = ""
        errorMessage = message
        HapticManager.errorOccurred()
    }

    private func finish(complete: @escaping (String) -> Void) {
        // Движок глушим сразу, а задачу распознавания оставляем дожить: финальная
        // расшифровка приходит с задержкой, и без неё теряется последнее слово.
        speech.finish()
        isCapturing = false
        isLocked = false
        cancelArmed = false
        HapticManager.impact(.light)

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self else { return }
            let text = self.speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            self.speech.stop()
            self.heard = ""
            guard !text.isEmpty else { return }
            complete(text)
        }
    }
}

// MARK: - Кнопка микрофона

enum V4MicChrome {
    /// Голая иконка — для строки ввода в чате.
    case bare
    /// Крупная круглая кнопка 58 pt — главный голосовой вход в доке вкладки.
    case dock
}

struct V4VoiceMicButton: View {
    @ObservedObject var capture: V4VoiceCapture
    let theme: V4Theme
    let surface: String
    var chrome: V4MicChrome = .bare
    var onResult: (String) -> Void

    private var active: Bool { capture.isCapturing }

    var body: some View {
        icon
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !capture.isCapturing { capture.pressBegan(surface: surface) }
                        capture.pressMoved(value.translation.height)
                    }
                    .onEnded { _ in
                        capture.pressEnded(complete: onResult)
                    }
            )
            .accessibilityLabel("Голосовой ввод")
            .accessibilityHint("Удерживайте и говорите. Короткое нажатие включает запись, следующее отправляет запрос.")
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var icon: some View {
        switch chrome {
        case .bare:
            V4GlyphIcon(glyph: .mic, size: 17, filled: active, weight: .regular)
                .foregroundStyle(active ? theme.accentColor : V4.muted)
                .frame(width: 44, height: 44)
        case .dock:
            V4GlyphIcon(glyph: .mic, size: 22, filled: active, weight: .regular)
                .foregroundStyle(theme.buttonTextColor)
                .frame(width: 58, height: 58)
                .background(Circle().fill(dockFill))
                .overlay(
                    Circle()
                        .stroke(dockFill.opacity(0.35), lineWidth: active ? 8 : 0)
                        .scaleEffect(active ? 1.16 : 1)
                )
                .shadow(color: dockFill.opacity(0.4), radius: active ? 18 : 10, y: 6)
                .scaleEffect(active ? 1.05 : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.7), value: active)
        }
    }

    private var dockFill: Color {
        capture.cancelArmed ? V4.danger : theme.accentColor
    }
}

// MARK: - Панель записи снизу (мини-сфера, как у Siri)

/// Раньше запись гасила весь экран матовым стеклом. Это ломало главный смысл
/// голоса: пользователь терял из виду то, о чём спрашивает, а в чате исчезала
/// переписка. Теперь запись — компактная панель над кнопкой микрофона.
struct V4VoiceDock: View {
    @ObservedObject var capture: V4VoiceCapture
    let theme: V4Theme
    var onSend: () -> Void
    var onCancel: () -> Void

    private var orbState: AIOrbState {
        capture.cancelArmed ? .error : .listening
    }

    private var accent: Color {
        capture.cancelArmed ? V4.danger : theme.accentColor
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.opacity(0.30), .clear],
                            center: .center,
                            startRadius: 6,
                            endRadius: 52
                        )
                    )
                    .frame(width: 86, height: 86)
                    .allowsHitTesting(false)

                AICompanionModel(theme: theme, size: 54, glow: 24, state: orbState)
                    .frame(width: 54, height: 54)
                    .clipped()
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text(capture.heard.isEmpty ? "Слушаю…" : capture.heard)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(capture.heard.isEmpty ? V4.muted : V4.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: 0.12), value: capture.heard)

                Text(hint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(capture.cancelArmed ? V4.danger : V4.muted)
                    .lineLimit(2)
            }

            if capture.isLocked {
                HStack(spacing: 8) {
                    V4GlyphButton(
                        glyph: .close,
                        theme: theme,
                        kind: .glass,
                        diameter: 44,
                        iconSize: 14,
                        accessibility: "Отменить запись",
                        action: onCancel
                    )

                    V4GlyphButton(
                        glyph: .send,
                        theme: theme,
                        kind: .accent,
                        diameter: 44,
                        iconSize: 16,
                        filled: true,
                        accessibility: "Отправить запрос",
                        action: onSend
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plinkGlass(.navigation, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
        // Пока палец удерживает кнопку, панель не должна перехватывать касание.
        .allowsHitTesting(capture.isLocked)
        .accessibilityIdentifier("voice.capture")
    }

    private var hint: String {
        if capture.cancelArmed { return "Отпустите — запрос отменится" }
        if capture.isLocked { return "Запись идёт. Отправьте или отмените." }
        return "Отпустите — отправлю. Вверх — отмена."
    }
}

/// Inline failure state for microphone/speech permissions. A voice feature is
/// optional; refusing access must leave the room/chat usable.
struct V4VoiceErrorBanner: View {
    @ObservedObject var capture: V4VoiceCapture
    var body: some View {
        if let message = capture.errorMessage {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Настройки") {
                    PlinkPermissions.openAppSettings()
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.plain)
                Button {
                    capture.dismissError()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .plinkHitTarget(32)
                .accessibilityLabel("Закрыть уведомление")
            }
            .foregroundStyle(V4.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(V4.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(V4.danger.opacity(0.35), lineWidth: 0.8)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Вкладка «ИИ» — лента трейлеров

struct V4AIViewLive: View {
    let theme: V4Theme
    @Bindable var store: V4AIStore
    /// Тот же стор, что кормит Главную: лента берёт из него полку «Новинки»,
    /// поэтому за онбордингом видны настоящие тайтлы, а не выдуманные.
    @Bindable var searchStore: V4SearchStore
    /// Вкладка сейчас на экране. Корень держит все вкладки живыми через ZStack,
    /// поэтому уход с вкладки виден только отсюда — и обрывает запись.
    var isActive: Bool = true

    @StateObject private var capture = V4VoiceCapture()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottom) {
            // Лента занимает весь экран и сама оставляет место под шапку и док.
            // Каталог ещё не подключён, поэтому лента в превью-режиме: кадры
            // и названия видны и листаются, а контролы, которым нечего делать
            // без живых данных, просто не рисуются. Прежний вариант — дизмер
            // на весь экран с плашкой «Будет доступно скоро» поверх живых
            // кнопок — выглядел как сломанный экран, а не как продукт.
            V4ReelsPanel(
                theme: theme,
                items: reelItems,
                isPreview: true,
                onWatchTogether: { reel in
                    Task { await store.send("Собери комнату на «\(reel.title)»") }
                    NotificationCenter.default.post(name: .plinkOpenAIChat, object: nil)
                },
                onEnqueue: { reel in
                    Task { await store.send("Добавь «\(reel.title)» в очередь") }
                },
                onShare: { reel in
                    Task { await store.send("Отправь друзьям трейлер «\(reel.title)»") }
                    NotificationCenter.default.post(name: .plinkOpenAIChat, object: nil)
                },
                onMore: { reel in
                    Task { await store.send("Расскажи про «\(reel.title)»") }
                    NotificationCenter.default.post(name: .plinkOpenAIChat, object: nil)
                }
            )
            .ignoresSafeArea()
            // Лента под онбордингом — декорация: видна силуэтами за фростом,
            // но не листается и не ловит касания.
            .allowsHitTesting(false)

            onboarding
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: capture.isCapturing)
        .foregroundStyle(V4.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("screen.ai")
        .task {
            await searchStore.loadShelf(HomeCinemaCatalog.freshChip)
        }
        .onChange(of: isActive) { _, active in
            if !active { capture.cancel() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { capture.cancel() }
        }
        .onDisappear { capture.cancel() }
    }

    /// Лента = полка «Новинки» каталога. Восьми карточек хватает: за фростом
    /// онбординга видны только первые, а грузить всю полку в ленту незачем.
    private var reelItems: [V4ReelItem] {
        searchStore.shelf(for: HomeCinemaCatalog.freshChip)
            .prefix(8)
            .map(V4ReelItem.init(from:))
    }

    /// Голос с ленты уходит в чат: там живут пузыри и кнопки подтверждения.
    private func handleVoiceResult(_ text: String) {
        NotificationCenter.default.post(name: .plinkOpenAIChat, object: nil)
        Task { await store.send(text) }
    }

    /// Онбординг раздела: фрост поверх ленты — карточки позади читаются
    /// силуэтами, — живая Metal-сфера ассистента и два уже работающих
    /// входа: чат с ИИ и голосовой ввод.
    ///
    /// 04.09.2026: слой и силуэты остались (решение 23.08), но 44-птшным
    /// заголовком было слово «Скоро» — вкладка крупнее всего рекламировала
    /// собственную пустоту, хотя чат и голос под ней работают. Теперь наверху
    /// то, что работает, а «Скоро» — бейдж в сноске под кнопками, у той
    /// единственной части раздела, которой правда ещё нет.
    private var onboarding: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            // Градиент прижимает низ — тексты и кнопки стоят на тёмном,
            // а верх оставляет ленте больше просвета. Верх намеренно почти
            // открыт (0.12): позади онбординга должно угадываться живое —
            // карточки трейлеров, — иначе фрост читается глухой заглушкой.
            LinearGradient(
                colors: [.black.opacity(0.12), .black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 16)

                AssistantOrbView(state: .idle)
                    .frame(width: 216, height: 216)
                    .accessibilityHidden(true)

                Text("ПОМОЩНИК PLINK")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2.4)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 16)

                Text("Опишите вечер")
                    .font(.system(size: 44, weight: .heavy))
                    .tracking(-1)
                    .foregroundStyle(V4.ink)
                    .padding(.top, 2)

                Text("Подберём кино под настроение и соберём очередь на вечер — текстом или голосом.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(V4.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3.5)
                    .frame(maxWidth: 300)
                    .padding(.top, 10)

                VStack(spacing: 10) {
                    Button {
                        HapticManager.impact(.medium)
                        NotificationCenter.default.post(name: .plinkOpenAIChat, object: nil)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .bold))
                            Text("Чат с ИИ")
                        }
                    }
                    .buttonStyle(PlinkProminentButtonStyle(
                        tint: .white, textColor: .black,
                        height: 48, cornerRadius: 16, fillsWidth: true
                    ))
                    .accessibilityIdentifier("ai.onboarding.chat")

                    Button {
                        HapticManager.impact(.light)
                        NotificationCenter.default.post(name: .plinkOpenAIVoice, object: nil)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("Голосовой ввод")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .buttonStyle(PlinkGlassButtonStyle(
                        tint: nil, height: 48, cornerRadius: 16, fillsWidth: true
                    ))
                    .accessibilityIdentifier("ai.onboarding.voice")
                }
                .frame(maxWidth: 300)
                .padding(.top, 26)

                // Единственное, чего в разделе правда ещё нет, — и сказано
                // это ровно один раз, шрифтом сноски, а не заголовком.
                HStack(spacing: 8) {
                    Text("СКОРО")
                        .font(.system(size: 9.5, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(.white.opacity(0.16))
                        )
                    Text("Лента трейлеров и рилсов")
                        .font(.system(size: 12))
                        .foregroundStyle(V4.muted)
                }
                .padding(.top, 18)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Лента трейлеров и рилсов — скоро")
                .accessibilityIdentifier("ai.onboarding.soon")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            // Контент — выше таб-бара; сам слой закрывает раздел целиком.
            .padding(.bottom, 96)
        }
        .accessibilityIdentifier("ai.onboarding")
    }

    /// Шапка только называет экран и не перехватывает касания ленты.
    /// Раньше здесь стоял крупный заголовок «ИИ» с надстрокой «ТРЕЙЛЕРЫ» на
    /// собственной чёрной подложке: 32-птшный титул наезжал на карточку, а
    /// полоса подложки обрывалась и читалась отдельным экраном. Вкладку и так
    /// называет таб-бар; сверху достаточно тихой метки, скрим — в фоне ленты.
    ///
    /// 23.08.2026: пока раздел закрыт онбордингом, шапка и док не в иерархии
    /// (онбординг сам называет раздел и даёт входы в чат и голос); вернутся
    /// вместе с живой лентой.
    private var header: some View {
        Text("ТРЕЙЛЕРЫ")
            .font(.system(size: 11, weight: .heavy))
            .tracking(2.4)
            .foregroundStyle(Color.white.opacity(0.65))
            .frame(maxWidth: .infinity)
            // Единый «вдох» шапок от статус-бара (см. topBar Главной).
            .padding(.top, 20)
            .allowsHitTesting(false)
    }

    /// Зона большого пальца: строка открывает чат, круглая кнопка пишет голос.
    private var dock: some View {
        VStack(spacing: 10) {
            if capture.isCapturing {
                V4VoiceDock(
                    capture: capture,
                    theme: theme,
                    onSend: { capture.pressEnded(complete: handleVoiceResult) },
                    onCancel: { capture.cancel() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            V4VoiceErrorBanner(capture: capture)

            HStack(spacing: 10) {
                Button {
                    HapticManager.selection()
                    capture.cancel()
                    NotificationCenter.default.post(name: .plinkOpenAIChat, object: nil)
                } label: {
                    HStack(spacing: 9) {
                        V4GlyphIcon(glyph: .sparkle, size: 15, weight: .regular)
                            .foregroundStyle(theme.accentColor)
                        Text("Спросите про фильмы и комнаты")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(V4.muted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                    .frame(maxWidth: .infinity)
                    .plinkGlass(.navigation, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Текстовый чат с ИИ")

                V4VoiceMicButton(
                    capture: capture,
                    theme: theme,
                    surface: "ai_tab",
                    chrome: .dock,
                    onResult: handleVoiceResult
                )
            }
        }
        .padding(.horizontal, 14)
        // Над таб-баром (64 pt) с воздухом.
        .padding(.bottom, 84)
    }
}

// MARK: - Состояние сферы

enum AIOrbState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case error
}

extension AIOrbState {
    /// То же состояние для шейдерной сферы `AssistantOrbView`: у Metal-модели
    /// свой публичный enum `OrbState`, случаи совпадают один в один. Перевод
    /// живёт здесь, а не в вызывающем экране: сфера нужна и вкладке, и чату.
    var orb: OrbState {
        switch self {
        case .idle: return .idle
        case .listening: return .listening
        case .thinking: return .thinking
        case .speaking: return .speaking
        case .error: return .error
        }
    }
}

// AICompanionModel определён в AI3DCompanionSphere.swift (настоящая SceneKit-сфера).
