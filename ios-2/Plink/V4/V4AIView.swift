// Plink/V4/V4AIView.swift — ИИ Plink
//
// 02.08.2026, решение владельца: вкладка «ИИ» — это развлечение (голос, дальше рилсы),
// а текстовый чат — это способ поиска фильма, поэтому он живёт отдельным экраном
// поверх вкладок и открывается с «Главной» (строка поиска)
// и кнопкой в шапке вкладки «ИИ».
//
// 03.08.2026: обещанные рилсы пришли. Сегмент «Рилсы / Голос» стоит под общей
// шапкой, сама лента живёт в V4ReelsView.swift. Голосовой экран целиком переехал
// в voiceBody — содержимое не изменилось, у него только забрали собственную шапку,
// чтобы она не рисовалась дважды.
//
// 03.08.2026, граница режимов: чат — это чат, голос — это голос. AISpeaker
// используется только в голосовом режиме вкладки. В переписке ответы не читаются
// вслух никогда — ни автоматически, ни по кнопке.
//
// 03.08.2026, правило тишины: ассистент обязан замолчать при уходе со вкладки «ИИ»,
// переключении на рилсы и уходе приложения в фон. Вкладки живут в ZStack и не
// уничтожаются при переключении, поэтому onDisappear здесь не срабатывает —
// нужен явный флаг isActive из корня.
//
// Цвет: акцент всегда берётся из активной темы (theme.accentColor), не зашивается в экран.

import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import Foundation

extension Notification.Name {
    /// Открыть текстовый чат с ИИ поверх любого экрана.
    static let plinkOpenAIChat = Notification.Name("plinkOpenAIChat")
    /// Перейти на вкладку «ИИ» в голосовом режиме.
    static let plinkOpenAIVoice = Notification.Name("plinkOpenAIVoice")
}

// MARK: - Режимы вкладки

/// Два режима: лента трейлеров и голосовой помощник.
enum V4AIMode: String, CaseIterable, Identifiable {
    case reels
    case voice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reels: return "Рилсы"
        case .voice: return "Голос"
        }
    }

    var icon: String {
        switch self {
        case .reels: return "play.rectangle.on.rectangle"
        case .voice: return "waveform"
        }
    }
}

// MARK: - Озвучка ответов

/// Минимальная обёртка над AVSpeechSynthesizer. Один экземпляр на приложение,
/// чтобы два ответа не читались хором.
///
/// Единственный легальный потребитель — голосовой режим V4AIViewLive.
/// Текстовый чат озвучкой не пользуется вообще.
final class AISpeaker {
    static let shared = AISpeaker()
    private let synth = AVSpeechSynthesizer()

    private init() {}

    func toggle(_ text: String) {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ru-RU")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
    }
}

// MARK: - Вкладка «ИИ» — рилсы и голос

struct V4AIViewLive: View {
    let theme: V4Theme
    @Bindable var store: V4AIStore
    /// Вкладка сейчас на экране. Корень держит все вкладки живыми через ZStack,
    /// поэтому без этого флага голос продолжал бы работать с чужого экрана.
    var isActive: Bool = true

    @State private var mode: V4AIMode = .reels
    @State private var heard = ""
    @State private var speakingPulseUntil: Date = .distantPast
    @StateObject private var speech = V4SpeechRecognizer()

    @Environment(\.scenePhase) private var scenePhase

    private var orbState: AIOrbState {
        let s = store.state.lowercased()
        if s.contains("ошиб") || s.contains("error") || s.contains("не удалось") { return .error }
        if s.contains("дума") { return .thinking }
        if speech.isRecording || s.contains("слуша") { return .listening }
        if Date() < speakingPulseUntil { return .speaking }
        return .idle
    }

    private var stateCaption: String {
        switch orbState {
        case .idle: return store.state.isEmpty ? "Готов помочь" : store.state
        case .listening: return "Слушаю…"
        case .thinking: return "Думаю…"
        case .speaking: return "Отвечаю…"
        case .error: return store.state
        }
    }

    /// В голосовом режиме ленты нет, поэтому последний ответ показываем крупно.
    private var voicePrompt: String {
        if speech.isRecording && !heard.isEmpty { return heard }
        if let last = store.messages.last, last.isBot { return last.text }
        return LocalizationManager.shared.string(.aiWhatToday)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            V4SegmentedBar(
                options: [
                    (value: V4AIMode.reels, title: V4AIMode.reels.title),
                    (value: V4AIMode.voice, title: V4AIMode.voice.title),
                ],
                selection: $mode,
                theme: theme
            )
            .padding(.horizontal, 18)
            .padding(.top, 8)

            if mode == .reels {
                ScrollView(showsIndicators: false) {
                    V4ReelsPanel(theme: theme)
                        .padding(.top, 14)
                        .padding(.bottom, 120)
                }
            } else {
                voiceBody
            }
        }
        .foregroundStyle(V4.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("screen.ai")
        .onChange(of: mode) { _, newMode in
            // Ушли с голоса внутри вкладки — микрофон и озвучка не должны
            // работать поверх трейлера.
            if newMode != .voice { silenceAssistant() }
        }
        .onChange(of: isActive) { _, active in
            // Ушли на другую вкладку. Вкладка остаётся в памяти, onDisappear
            // не вызывается, поэтому глушим вручную.
            if !active { silenceAssistant() }
        }
        .onChange(of: scenePhase) { _, phase in
            // У приложения включён фоновый режим audio, иначе ответ продолжал
            // бы читаться после сворачивания.
            if phase != .active { silenceAssistant() }
        }
        .onDisappear { silenceAssistant() }
    }

    /// Единственная точка остановки голоса: и запись, и синтез речи.
    private func silenceAssistant() {
        if speech.isRecording { speech.stop() }
        AISpeaker.shared.stop()
    }

    // MARK: Голосовой режим

    private var voiceBody: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [stateColor.opacity(0.22), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 190
                        )
                    )
                    .frame(width: 360, height: 360)
                    .allowsHitTesting(false)

                AICompanionModel(theme: theme, size: 240, glow: 90, state: orbState)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 8)

            Text(voicePrompt)
                .font(.system(size: 19, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .frame(minHeight: 56)

            Text(stateCaption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(stateColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(stateColor.opacity(0.12), in: Capsule())

            Spacer(minLength: 16)

            micButton

            Text(speech.isRecording ? "Нажмите, когда закончите" : "Нажмите и говорите")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(V4.muted)
                .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 104) // над таб-баром
        .onChange(of: speech.transcript) { _, t in
            if speech.isRecording && !t.isEmpty { heard = t }
        }
        .onChange(of: store.messages.count) { _, _ in
            // Говорим только здесь и только когда экран на виду. Стор общий
            // с текстовым чатом, и без этой проверки ответ из переписки
            // заговорил бы сам собой.
            guard isActive, mode == .voice else { return }
            if let last = store.messages.last, last.isBot {
                speakingPulseUntil = Date().addingTimeInterval(2.5)
                AISpeaker.shared.toggle(last.text)
            }
        }
        .onDisappear { silenceAssistant() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            V4Heading(eyebrow: "ТРЕЙЛЕРЫ И ГОЛОС", title: "ИИ")
            Spacer()
            Button {
                HapticManager.selection()
                silenceAssistant()
                NotificationCenter.default.post(name: .plinkOpenAIChat, object: nil)
            } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(V4.ink)
                    .frame(width: 44, height: 44)
                    .background(V4.roundBG, in: Circle())
                    .overlay(Circle().stroke(V4.line))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Текстовый чат с ИИ")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var micButton: some View {
        Button {
            HapticManager.impact(.medium)
            if speech.isRecording {
                speech.stop()
                let text = heard.trimmingCharacters(in: .whitespaces)
                heard = ""
                if text.isEmpty {
                    store.setStatus("Готов помочь")
                } else {
                    Task { await store.send(text) }
                }
            } else {
                AISpeaker.shared.stop()
                speech.start()
                store.setStatus("Слушаю…")
                AnalyticsService.shared.track("voice_chat_started", parameters: ["surface": "ai_tab"])
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(stateColor.opacity(0.35), lineWidth: 1)
                    .frame(width: 96, height: 96)

                Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(speech.isRecording ? theme.buttonTextColor : V4.ink)
                    .frame(width: 76, height: 76)
                    .background {
                        if speech.isRecording {
                            Circle().fill(theme.accentColor)
                        } else {
                            Circle().fill(.ultraThinMaterial)
                        }
                    }
                    .environment(\.colorScheme, .dark)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speech.isRecording ? "Остановить запись" : "Говорить")
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
}

// MARK: - Текстовый чат — отдельный экран поверх вкладок
//
// Здесь нет ни одного обращения к AISpeaker для чтения ответов. Микрофон в
// композере — это диктовка в поле ввода, он только слушает и ничего не произносит.

struct V4AIChatView: View {
    let theme: V4Theme
    @Bindable var store: V4AIStore
    /// Закрыть чат и перейти в голосовой режим вкладки «ИИ».
    var onVoice: () -> Void = {
        NotificationCenter.default.post(name: .plinkOpenAIVoice, object: nil)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var input = ""
    @State private var showManualCreate = false
    @State private var confirmingAction: AIProposedAction?
    @State private var presentedRoom: Room?
    @State private var copiedMessageID: String?
    @StateObject private var speech = V4SpeechRecognizer()

    /// Состояние без .speaking: чат никогда не говорит вслух.
    private var orbState: AIOrbState {
        let s = store.state.lowercased()
        if s.contains("ошиб") || s.contains("error") || s.contains("не удалось") { return .error }
        if s.contains("дума") { return .thinking }
        if speech.isRecording || s.contains("слуша") { return .listening }
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
            composer
        }
        .foregroundStyle(V4.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(V4.cardBG.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: speech.transcript) { _, t in
            if speech.isRecording && !t.isEmpty { input = t }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { stopDictation() }
        }
        // Закрытие экрана любым способом обязано выключить микрофон.
        .onDisappear { stopDictation() }
        .sheet(isPresented: $showManualCreate) {
            RoomCreationView(onRoomCreated: { _ in showManualCreate = false })
                .environmentObject(APIClient.shared)
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $presentedRoom) { room in
            WatchRoomContainer(room: room)
        }
    }

    /// В чате глушить нечего, кроме диктовки — озвучки здесь нет по замыслу.
    private func stopDictation() {
        if speech.isRecording { speech.stop() }
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                HapticManager.selection()
                stopDictation()
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

            Button {
                HapticManager.selection()
                stopDictation()
                dismiss()
                onVoice()
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.buttonTextColor)
                    .frame(width: 44, height: 44)
                    .background(theme.accentColor, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Перейти в голосовой режим")
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

                // Кнопки «Озвучить ответ» здесь нет намеренно: чтение вслух живёт
                // только в голосовом режиме вкладки «ИИ».
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

            // Диктовка в поле ввода: микрофон только слушает, ответ приходит текстом.
            Button {
                HapticManager.impact(.light)
                if speech.isRecording {
                    speech.stop()
                    store.setStatus("Готов помочь")
                    let text = input.trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        input = ""
                        Task { await store.send(text) }
                    }
                } else {
                    speech.start()
                    store.setStatus("Слушаю…")
                }
            } label: {
                Image(systemName: speech.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(speech.isRecording ? theme.accentColor : V4.muted)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Голосовой ввод")

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
