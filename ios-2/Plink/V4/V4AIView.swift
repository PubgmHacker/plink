// Plink/V4/V4AIView.swift — ИИ Plink
//
// 02.08.2026, решение владельца: вкладка «ИИ» — это развлечение (голос, дальше рилсы),
// а текстовый чат — это способ поиска фильма, поэтому он живёт отдельным экраном
// поверх вкладок и открывается с «Главной» (строка поиска)
// и кнопкой в шапке вкладки «ИИ».
//
// 03.08.2026: обещанные рилсы пришли. Лента живёт в V4ReelsView.swift.
//
// 03.08.2026, голос перестал быть режимом. Раньше вкладка делилась сегментом на
// «Рилсы» и «Голос», и голосовой экран умел только говорить — подтвердить
// предложение ассистента там было нечем, AIActionButton существует лишь в пузыре
// чата. Теперь голос — это способ ввода: нажимаешь микрофон, снизу поднимается
// сфера, отпускаешь — распознанный текст уходит запросом, ответ приходит текстом
// вместе с кнопками действий.
//
// 03.08.2026, вторая правка по эргономике. Микрофон и чат стояли в шапке справа —
// до верхнего угла экрана 6.9" большим пальцем не дотянуться. Обе кнопки съехали
// вниз, в плавающий док над таб-баром: широкая строка открывает чат, круглая
// кнопка 58 pt пишет голос. И запись больше не гасит экран целиком: вместо
// полноэкранного слоя снизу поднимается компактная панель с мини-сферой —
// как у Siri на iOS. В чате панель встаёт над композером, переписка видна.
//
// Следствие: приложение не произносит ответы вслух нигде. AISpeaker и
// AVSpeechSynthesizer удалены вместе с голосовым экраном — чат остаётся чатом,
// голос остаётся вводом.
//
// Цвет: акцент всегда берётся из активной темы (theme.accentColor), не зашивается в экран.

import SwiftUI
import PhotosUI
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
    }

    func pressBegan(surface: String) {
        guard !isCapturing else { return }
        pressStartedAt = Date()
        heard = ""
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
            Image(systemName: active ? "mic.fill" : "mic")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? theme.accentColor : V4.muted)
                .frame(width: 34, height: 34)
        case .dock:
            Image(systemName: active ? "mic.fill" : "mic")
                .font(.system(size: 20, weight: .bold))
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
/// переписка. Теперь запись — компактная панель, которая поднимается снизу над
/// кнопкой микрофона: слева живая сфера, справа расшифровка. Контент виден.
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
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(V4.muted)
                            .frame(width: 44, height: 44)
                            .plinkGlass(.overlay, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Отменить запись")

                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(theme.buttonTextColor)
                            .frame(width: 44, height: 44)
                            .background(theme.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Отправить запрос")
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

// MARK: - Вкладка «ИИ» — лента трейлеров

struct V4AIViewLive: View {
    let theme: V4Theme
    @Bindable var store: V4AIStore
    /// Вкладка сейчас на экране. Корень держит все вкладки живыми через ZStack,
    /// поэтому уход с вкладки виден только отсюда — и обрывает запись.
    var isActive: Bool = true

    @StateObject private var capture = V4VoiceCapture()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    V4ReelsPanel(theme: theme)
                        .padding(.top, 14)
                        // Место под плавающий док и таб-бар.
                        .padding(.bottom, 190)
                }
            }

            dock
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: capture.isCapturing)
        .foregroundStyle(V4.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("screen.ai")
        .onChange(of: isActive) { _, active in
            if !active { capture.cancel() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { capture.cancel() }
        }
        .onDisappear { capture.cancel() }
    }

    /// Голос с ленты уходит в чат: там живут пузыри и кнопки подтверждения.
    private func handleVoiceResult(_ text: String) {
        NotificationCenter.default.post(name: .plinkOpenAIChat, object: nil)
        Task { await store.send(text) }
    }

    /// Шапка теперь только называет экран. Всё, что нажимается, уехало вниз.
    private var header: some View {
        HStack(spacing: 10) {
            V4Heading(eyebrow: "ТРЕЙЛЕРЫ", title: "ИИ")
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
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

            HStack(spacing: 10) {
                Button {
                    HapticManager.selection()
                    capture.cancel()
                    NotificationCenter.default.post(name: .plinkOpenAIChat, object: nil)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.accentColor)
                        Text("Спроси про фильмы и комнаты")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(V4.muted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
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

// MARK: - Текстовый чат — отдельный экран поверх вкладок
//
// Ответы здесь не читаются вслух и читаться не могут: синтезатора речи в
// приложении больше нет. Микрофон в композере — только ввод.

struct V4AIChatView: View {
    let theme: V4Theme
    @Bindable var store: V4AIStore
    /// Открыть экран с сразу включённым микрофоном (вход «спросить голосом»).
    var autoStartVoice: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var input = ""
    @State private var showManualCreate = false
    @State private var confirmingAction: AIProposedAction?
    @State private var presentedRoom: Room?
    @State private var copiedMessageID: String?
    @StateObject private var capture = V4VoiceCapture()

    /// Состояние без .speaking: приложение не говорит вслух.
    private var orbState: AIOrbState {
        let s = store.state.lowercased()
        if s.contains("ошиб") || s.contains("error") || s.contains("не удалось") { return .error }
        if s.contains("дума") { return .thinking }
        if capture.isCapturing || s.contains("слуша") { return .listening }
        return .idle
    }

    private var stateCaption: String {
        switch orbState {
        case .idle: return "Подберёт фильм и соберёт комнату"
        case .listening: return "Слушаю…"
        case .thinking: return "Думаю…"
        case .speaking: return "Отвечаю…"
        case .error: return store.state
        }
    }

    private var lastUserPrompt: String? {
        store.messages.last(where: { !$0.isBot })?.text
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            thread

            // Панель записи встаёт между лентой и композером: переписка остаётся
            // на экране, кнопка микрофона — прямо под пальцем.
            if capture.isCapturing {
                V4VoiceDock(
                    capture: capture,
                    theme: theme,
                    onSend: { capture.pressEnded(complete: sendVoiceResult) },
                    onCancel: { capture.cancel() }
                )
                .padding(.horizontal, 13)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            composer
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: capture.isCapturing)
        .foregroundStyle(V4.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(V4.cardBG.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            if autoStartVoice { capture.startLocked(surface: "ai_chat_autostart") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { capture.cancel() }
        }
        // Закрытие экрана любым способом обязано выключить микрофон.
        .onDisappear { capture.cancel() }
        .sheet(isPresented: $showManualCreate) {
            RoomCreationView(onRoomCreated: { _ in showManualCreate = false })
                .environmentObject(APIClient.shared)
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $presentedRoom) { room in
            WatchRoomContainer(room: room)
        }
    }

    private func sendVoiceResult(_ text: String) {
        input = ""
        Task { await store.send(text) }
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                HapticManager.selection()
                capture.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(V4.ink)
                    .frame(width: 44, height: 44)
                    .background(V4.roundBG, in: Circle())
                    .overlay(Circle().stroke(V4.line))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Закрыть чат")

            VStack(alignment: .leading, spacing: 2) {
                Text("ИИ-ассистент").font(.system(size: 16, weight: .heavy))
                Text(stateCaption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
            }

            Spacer()

            if store.messages.count > 1 {
                Button {
                    HapticManager.impact(.light)
                    withAnimation { store.clearHistory() }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(V4.muted)
                        .frame(width: 44, height: 44)
                        .plinkGlass(.overlay, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить историю чата")
            }
        }
        .frame(height: 61)
        .padding(.horizontal, 15)
        .accessibilityIdentifier("screen.aichat")
    }

    // MARK: Лента

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.messages) { msg in
                        if msg.isBot {
                            botBubble(id: "\(msg.id)", text: msg.text, action: msg.proposedAction)
                                .id(msg.id)
                        } else {
                            userBubble(text: msg.text)
                                .id(msg.id)
                        }
                    }

                    if orbState == .thinking {
                        TypingIndicator(tint: stateColor)
                            .padding(.leading, 2)
                    }

                    suggestionChips
                        .padding(.top, 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .onChange(of: store.messages.count) { _, _ in
                if let lastID = store.messages.last?.id {
                    withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }
        }
    }

    private func userBubble(text: String) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(4)
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
                .background {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 18,
                        bottomLeadingRadius: 18,
                        bottomTrailingRadius: 6,
                        topTrailingRadius: 18,
                        style: .continuous
                    )
                    .fill(theme.accentColor.opacity(0.18))
                    .overlay {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 18,
                            bottomLeadingRadius: 18,
                            bottomTrailingRadius: 6,
                            topTrailingRadius: 18,
                            style: .continuous
                        )
                        .stroke(theme.accentColor.opacity(0.34), lineWidth: 0.6)
                    }
                }
        }
    }

    private func botBubble(id: String, text: String, action: AIProposedAction?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            AICompanionModel(theme: theme, size: 26, glow: 10, state: .idle)
                .frame(width: 28, height: 28)
                .clipped()
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.system(size: 14))
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let action {
                    AIActionButton(
                        action: action,
                        store: store,
                        presentedRoom: $presentedRoom,
                        confirmingAction: $confirmingAction
                    )
                }

                Divider().overlay(V4.line)

                // Кнопки «Озвучить ответ» здесь нет намеренно: приложение
                // не произносит текст вслух ни на одном экране.
                HStack(spacing: 2) {
                    bubbleAction(
                        icon: copiedMessageID == id ? "checkmark" : "doc.on.doc",
                        label: "Копировать ответ"
                    ) {
                        UIPasteboard.general.string = text
                        HapticManager.impact(.light)
                        withAnimation { copiedMessageID = id }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                            await MainActor.run {
                                withAnimation {
                                    if copiedMessageID == id { copiedMessageID = nil }
                                }
                            }
                        }
                    }

                    Spacer()

                    if let prompt = lastUserPrompt {
                        bubbleAction(icon: "arrow.clockwise", label: "Повторить запрос") {
                            HapticManager.impact(.light)
                            Task { await store.send(prompt) }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 6,
                bottomTrailingRadius: 18,
                topTrailingRadius: 18,
                style: .continuous
            )
            .fill(.ultraThinMaterial)
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18,
                    style: .continuous
                )
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.03),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func bubbleAction(
        icon: String,
        label: String,
        _ perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(V4.muted)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if store.lastSuggestions.isEmpty {
                    chip("Очередь", "Собери очередь на вечер")
                    chip("У друзей", "Что смотрят друзья?")
                    chip("Через AI", "Создай комнату с Inception")
                } else {
                    ForEach(store.lastSuggestions.prefix(4), id: \.self) { s in
                        chip(String(s.prefix(22)), s)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Композер

    private var composer: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    showManualCreate = true
                } label: {
                    Label("Создать комнату", systemImage: "plus.circle")
                }
                Button {
                    Task { await store.send("Что посмотреть сегодня вечером?") }
                } label: {
                    Label("Подобрать фильм", systemImage: "film")
                }
                Button {
                    Task { await store.send("Собери очередь на вечер") }
                } label: {
                    Label("Собрать очередь", systemImage: "list.bullet")
                }
                if store.messages.count > 1 {
                    Divider()
                    Button(role: .destructive) {
                        withAnimation { store.clearHistory() }
                    } label: {
                        Label("Очистить чат", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(V4.ink)
                    .frame(width: 40, height: 40)
                    .plinkGlass(.overlay, in: Circle())
            }
            .accessibilityLabel("Быстрые действия")

            TextField("Спроси про фильмы и комнаты", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .foregroundStyle(V4.ink)
                .font(.system(size: 14))
                .padding(.vertical, 4)

            // Удержание поднимает панель со сферой, отпускание отправляет
            // распознанный текст обычным сообщением.
            V4VoiceMicButton(
                capture: capture,
                theme: theme,
                surface: "ai_chat",
                chrome: .bare,
                onResult: sendVoiceResult
            )

            Button {
                let text = input
                guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                input = ""
                HapticManager.impact(.light)
                Task { await store.send(text) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.buttonTextColor)
                    .frame(width: 40, height: 40)
                    .background(theme.accentColor, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(input.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
            .accessibilityLabel("Отправить сообщение")
        }
        .padding(7)
        .frame(minHeight: 58)
        .plinkGlass(.navigation, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 13)
        .padding(.bottom, 10)
    }

    private var stateColor: Color {
        switch orbState {
        case .idle: return theme.accentColor
        case .listening: return Color(red: 0.45, green: 0.55, blue: 1.0)
        case .thinking: return Color(red: 0.85, green: 0.4, blue: 1.0)
        case .speaking: return Color(red: 0.25, green: 0.9, blue: 0.7)
        case .error: return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
    }

    private func chip(_ label: String, _ prompt: String) -> some View {
        Button {
            input = prompt
            HapticManager.impact(.light)
            Task { await store.send(prompt) }
        } label: {
            Text(label)
                .font(.system(size: 11.52, weight: .semibold))
                .foregroundStyle(V4.ink)
                .padding(.horizontal, 13)
                .frame(minHeight: 36)
                .plinkGlass(.overlay, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Индикатор набора

/// Три точки, пока ИИ думает. Без этого экран выглядел замершим.
struct TypingIndicator: View {
    let tint: Color
    @State private var phase = 0

    private let timer = Timer.publish(every: 0.28, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(tint.opacity(phase == index ? 0.95 : 0.3))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == index ? 1.15 : 0.9)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .plinkGlass(.overlay, in: Capsule())
        .animation(.easeInOut(duration: 0.24), value: phase)
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
        .accessibilityLabel("ИИ печатает ответ")
    }
}

// MARK: - AIActionButton (P0.4)

struct AIActionButton: View {
    let action: AIProposedAction
    let store: V4AIStore
    @Binding var presentedRoom: Room?
    @Binding var confirmingAction: AIProposedAction?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let preview = action.payloadPreview {
                VStack(alignment: .leading, spacing: 4) {
                    if let title = preview.title {
                        Text("📝 \(title)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(V4.ink)
                    }
                    if let privacy = preview.privacy {
                        Text("🔒 \(privacy)")
                            .font(.system(size: 12))
                            .foregroundStyle(V4.muted)
                    }
                    if let count = preview.queueCount {
                        Text("📋 \(count) в очереди")
                            .font(.system(size: 12))
                            .foregroundStyle(V4.muted)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .plinkGlass(.overlay, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 8) {
                Button {
                    Task { await confirm() }
                } label: {
                    HStack(spacing: 4) {
                        if loading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(LocalizationManager.shared.string(.rcCreate))
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(loading)

                Button {
                    confirmingAction = nil
                } label: {
                    Text(LocalizationManager.shared.string(.aiCancel))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(V4.muted)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .plinkGlass(.overlay, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if let err = error {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(V4.danger)
            }
        }
        .padding(.top, 6)
    }

    private func confirm() async {
        loading = true
        error = nil
        if let room = await store.confirmAction(action) {
            HapticManager.roomJoined()
            presentedRoom = room
        } else {
            HapticManager.errorOccurred()
            error = "Не удалось создать комнату"
        }
        loading = false
    }
}

enum AIOrbState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case error
}

// AICompanionModel is defined in AI3DCompanionSphere.swift (real SceneKit 3D orb)
