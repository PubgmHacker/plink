// Plink/V4/V4AIChatView.swift — текстовый чат с ИИ
//
// 03.08.2026. Вынесен из V4AIView.swift. Причина не в размере файла, а в том,
// что это две разные сущности: вкладка «ИИ» — лента трейлеров, а чат —
// поиск и действия. Они открываются с разных мест и живут по-разному.
//
// Ответы здесь не читаются вслух и читаться не могут: синтезатора речи в
// приложении больше нет. Микрофон в композере — только ввод.

import SwiftUI
import UIKit

struct V4AIChatView: View {
    let theme: V4Theme
    @Bindable var store: V4AIStore
    /// Открыть экран с сразу включённым микрофоном (вход «спросить голосом»).
    var autoStartVoice: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var input = ""
    @FocusState private var inputFocused: Bool
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
        // Длинная присказка объясняет, что умеет ассистент, и уместна пока
        // разговор не начался: под ней пусто. В переписке её место занимает
        // сфера-аватар, и строка обрезалась многоточием («…и соберёт ком…»),
        // хотя объяснять уже нечего — там короткое «в сети», как в личке.
        case .idle: return isFresh ? "Подберёт фильм и соберёт комнату" : "в сети"
        case .listening: return "Слушаю…"
        case .thinking: return "Думаю…"
        case .speaking: return "Отвечаю…"
        case .error: return store.state
        }
    }

    private var lastUserPrompt: String? {
        store.messages.last(where: { !$0.isBot })?.text
    }

    /// Разговор ещё не начался: в ленте только приветствие ассистента.
    /// Пользователь не мог ответить раньше, чем спросил, поэтому одна
    /// единственная реплика бота — всегда приветствие (то же после «очистить»).
    private var isFresh: Bool {
        store.messages.count == 1 && store.messages[0].isBot
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            // Пустой чат — это не «лента без сообщений»: до первого вопроса
            // экран занимает сфера. Раньше здесь стояла та же лента, и она
            // прижимала единственное приветствие к композеру, оставляя две
            // трети экрана чёрными.
            if isFresh {
                hero
            } else {
                thread
            }

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

            V4VoiceErrorBanner(capture: capture)
                .padding(.horizontal, 13)
                .padding(.bottom, 8)

            composer
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: capture.isCapturing)
        .foregroundStyle(V4.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Фон экрана — канвас приложения: V4.cardBG (цвет карточек, светлее
        // канваса) делал весь чат «выцветшим» рядом с остальными экранами.
        .background {
            ZStack {
                V4.canvas
                RadialGradient(
                    colors: [theme.accentColor.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.5, y: 0),
                    startRadius: 0,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
        }
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
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $presentedRoom) { room in
            WatchRoomContainer(room: room)
                .preferredColorScheme(.dark)
        }
    }

    private func sendVoiceResult(_ text: String) {
        input = ""
        Task { await store.send(text) }
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: 10) {
            V4GlyphButton(
                glyph: .close,
                theme: theme,
                kind: .glass,
                diameter: 44,
                iconSize: 15,
                accessibility: "Закрыть чат"
            ) {
                capture.cancel()
                dismiss()
            }

            // Пока разговор не начался, сфера стоит в полный рост посреди
            // экрана (см. `hero`), и второй её копии в шапке быть не должно:
            // это MTKView, каждый кадрирует свой Metal-проход. Как только
            // пошла переписка, сфера сжимается в аватар собеседника — чат
            // с ассистентом устроен как чат с человеком.
            if !isFresh {
                AssistantOrbView(state: orbState.orb)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("ИИ-ассистент").font(.system(size: 16, weight: .heavy))
                Text(stateCaption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
            }

            Spacer()

            if store.messages.count > 1 {
                V4GlyphButton(
                    glyph: .trash,
                    theme: theme,
                    kind: .glass,
                    diameter: 44,
                    iconSize: 15,
                    accessibility: "Очистить историю чата"
                ) {
                    withAnimation { store.clearHistory() }
                }
            }
        }
        .frame(height: 61)
        .padding(.horizontal, 15)
        .accessibilityIdentifier("screen.aichat")
    }

    // MARK: Сфера

    /// Лицо пустого чата: живая шейдерная сфера ассистента — та же модель и
    /// того же вида, что на онбординге вкладки «ИИ» (`AssistantOrbView`), а не
    /// 26-птшный значок у пузыря. Под ней — приветствие ассистента и три
    /// подсказки, с чего начать.
    ///
    /// Высота 168 против 216 на онбординге: здесь под сферой ещё композер и
    /// шапка, и на 5,4" (iPhone 13 mini, 375×812) 216 съедали подсказки.
    /// Всё, что не влезло, скроллится — центрирование держится `minHeight`
    /// по высоте окна, а не жёстким `Spacer`.
    private var hero: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    AssistantOrbView(state: orbState.orb)
                        .frame(width: 168, height: 168)
                        .accessibilityHidden(true)

                    Text(greeting)
                        .font(.system(size: 15))
                        .foregroundStyle(V4.ink.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 300)
                        .padding(.top, 10)

                    Text("С ЧЕГО НАЧАТЬ")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(2.4)
                        .foregroundStyle(V4.muted)
                        .padding(.top, 26)

                    // Ряд подсказок в пустом чате всегда состоит из трёх
                    // зашитых чипов: серверные подсказки приходят только
                    // вместе с ответом, то есть когда чат уже не пустой.
                    // Поэтому здесь их можно просто отцентровать, а
                    // `ViewThatFits` страхует длинные строки прокруткой.
                    ViewThatFits(in: .horizontal) {
                        chipRow
                        ScrollView(.horizontal, showsIndicators: false) {
                            chipRow.padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 10)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: geo.size.height, alignment: .center)
            }
        }
        .accessibilityIdentifier("aichat.hero")
    }

    /// Приветствие ассистента показывает сама сфера, отдельным пузырём его
    /// рисовать незачем: в ленте оно единственное и висело бы у композера.
    private var greeting: String {
        store.messages.first?.text ?? ""
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
                // Разговор растёт снизу вверх, как в любом мессенджере:
                // короткая переписка стоит над композером, а пустота
                // уходит вверх, а не разрывает экран посередине.
                .frame(maxWidth: .infinity, minHeight: 0, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
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
        // Значка-сферы у пузыря больше нет: сфера ассистента — одна, живая, и
        // стоит в шапке (в пустом чате — во весь экран). 26-птшная копия
        // SceneKit-модели у каждой реплики повторяла собеседника, которого и
        // так видно, и заводила по своему SCNView на строку ленты.
        HStack(alignment: .top, spacing: 8) {
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

                // Кнопки «Озвучить ответ» здесь нет намеренно.
                HStack(spacing: 2) {
                    bubbleAction(
                        glyph: copiedMessageID == id ? .check : .copy,
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
                        bubbleAction(glyph: .retry, label: "Повторить запрос") {
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
            // Тот же графит, что у входящего пузыря в личке
            // (`Cinema2026.incomingBubble`). Было `.ultraThinMaterial`:
            // стекло на слое контента — против правила шапки PlinkGlass.swift,
            // и два разговора в одном приложении выглядели по-разному.
            .fill(Cinema2026.incomingBubble)
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
        glyph: V4Glyph,
        label: String,
        _ perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            V4GlyphIcon(glyph: glyph, size: 14, weight: .regular)
                .foregroundStyle(V4.muted)
                .frame(width: 44, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .plinkHitTarget(34)
        .accessibilityLabel(label)
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            chipRow.padding(.vertical, 2)
        }
    }

    /// Сам ряд подсказок, без прокрутки: в ленте он живёт внутри
    /// горизонтального `ScrollView`, в пустом чате — по центру под сферой.
    @ViewBuilder
    private var chipRow: some View {
        HStack(spacing: 7) {
            if store.lastSuggestions.isEmpty {
                // Подпись чипа — сам вопрос, а не ярлык рядом с ним: раньше
                // «Через AI» отправляло «Создай комнату с Inception», и по
                // чипу нельзя было угадать, что уедет ассистенту. Ярлыки
                // прогоняются через тот же chipLabel, что и серверные
                // подсказки, — длинные строки режутся по слову, а ряд
                // страхует ViewThatFits прокруткой.
                ForEach(Self.seedPrompts, id: \.self) { prompt in
                    chip(chipLabel(prompt), prompt)
                }
            } else {
                ForEach(store.lastSuggestions.prefix(4), id: \.self) { s in
                    chip(chipLabel(s), s)
                }
            }
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
                    Task { await store.send("Собери очередь на просмотр") }
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
                V4GlyphIcon(glyph: .plus, size: 18, weight: .regular)
                    .foregroundStyle(V4.ink)
                    .frame(width: 40, height: 40)
                    .plinkGlass(.control, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Быстрые действия")

            TextField("Спросите про фильмы", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
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
                V4GlyphIcon(glyph: .send, size: 17, filled: true, weight: .regular)
                    .foregroundStyle(theme.buttonTextColor)
                    .frame(width: 42, height: 42)
                    .background(theme.accentColor, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
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

    /// Затравочные подсказки пустого чата. Серверные приходят только вместе
    /// с ответом, то есть когда чат уже не пустой, — этот список и есть
    /// единственное, что видит новый пользователь.
    private static let seedPrompts = [
        "Собери очередь на просмотр",
        "Что смотрят друзья?",
        "Создай комнату с Inception",
    ]

    /// Подсказки приходят с сервера произвольной длины. Раньше их резали ровно
    /// по 22 символа, и чип заканчивался на полуслове без многоточия («Добавь
    /// ещё фильм в оче»). Отдать обрезку самому `Text` нельзя: чтобы поставить
    /// потолок ширины, ему нужен гибкий `frame(maxWidth:)`, а с ним короткие
    /// чипы в пустом чате растягиваются на всю строку вместо того, чтобы
    /// облегать текст. Поэтому режем строку — но по границе слова и с «…».
    private func chipLabel(_ text: String) -> String {
        let limit = 26
        guard text.count > limit else { return text }
        let head = text.prefix(limit)
        let cut = head.lastIndex(of: " ").map { head[head.startIndex..<$0] } ?? head
        return cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:—-")) + "…"
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
                .lineLimit(1)
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

// MARK: - Кнопка подтверждения действия (P0.4)

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
                VStack(alignment: .leading, spacing: 6) {
                    if let title = preview.title {
                        Label {
                            Text(title).font(.system(size: 12, weight: .semibold))
                        } icon: {
                            V4GlyphIcon(glyph: .play, size: 11, weight: .regular)
                        }
                        .foregroundStyle(V4.ink)
                    }
                    if let privacy = preview.privacy {
                        Label {
                            Text(privacy).font(.system(size: 12))
                        } icon: {
                            V4GlyphIcon(glyph: .lock, size: 11, weight: .regular)
                        }
                        .foregroundStyle(V4.muted)
                    }
                    if let count = preview.queueCount {
                        Label {
                            Text("\(count) в очереди").font(.system(size: 12))
                        } icon: {
                            V4GlyphIcon(glyph: .queue, size: 11, weight: .regular)
                        }
                        .foregroundStyle(V4.muted)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .plinkGlass(.overlay, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 8) {
                let theme = V4Theme.saved
                Button {
                    Task { await confirm() }
                } label: {
                    HStack(spacing: 5) {
                        if loading {
                            ProgressView().tint(theme.buttonTextColor)
                        } else {
                            V4GlyphIcon(glyph: .check, size: 12, weight: .semibold)
                        }
                        Text(LocalizationManager.shared.string(.rcCreate))
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(theme.buttonTextColor)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(theme.accentColor)
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
