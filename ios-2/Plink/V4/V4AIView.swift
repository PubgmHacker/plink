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
            // Лента занимает весь экран и сама оставляет место под шапку и док.
            V4ReelsPanel(
                theme: theme,
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

            dock
        }
        .overlay(alignment: .top) { header }
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

    /// Шапка только называет экран и не перехватывает касания ленты.
    private var header: some View {
        HStack(spacing: 10) {
            V4Heading(eyebrow: "ТРЕЙЛЕРЫ", title: "ИИ")
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.75), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
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

            HStack(spacing: 10) {
                Button {
                    HapticManager.selection()
                    capture.cancel()
                    NotificationCenter.default.post(name: .plinkOpenAIChat, object: nil)
                } label: {
                    HStack(spacing: 9) {
                        V4GlyphIcon(glyph: .sparkle, size: 15, weight: .regular)
                            .foregroundStyle(theme.accentColor)
                        Text("Спроси про фильмы и комнаты")
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

// AICompanionModel определён в AI3DCompanionSphere.swift (настоящая SceneKit-сфера).
