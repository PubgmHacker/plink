// Реальное распознавание речи (ru-RU)
// SFSpeechRecognizer + AVAudioEngine, partial results прямо в поле ввода.
//
// 03.08.2026: распознавание работает в режиме удержания кнопки, поэтому сессия
// живёт доли секунды. Отсюда два правила ниже — wantsRecording и finish().

import Foundation
import Speech
import AVFoundation

@MainActor
final class V4SpeechRecognizer: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    /// Non-fatal, user-facing failure. TCC and audio-session errors must never
    /// terminate the app or leave the mic button stuck in the recording state.
    @Published private(set) var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false

    /// Пользователь всё ещё держит кнопку. Разрешение на микрофон приходит
    /// асинхронно, и при коротком нажатии stop() успевал сработать раньше
    /// колбэка — сессия стартовала уже после отпускания, и остановить её было
    /// некому. Микрофон оставался включённым.
    private var wantsRecording = false

    func start() {
        transcript = ""
        errorMessage = nil
        wantsRecording = true
        // Двухступенчатый запрос: распознавание речи, затем микрофон. Оба ключа
        // обязаны быть в Info.plist — без NSSpeechRecognitionUsageDescription
        // requestAuthorization не показывал диалог, а мгновенно ронял процесс
        // (TCC kill), что выглядело как «вылет вместо запроса разрешения».
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self, self.wantsRecording else { return }
                switch status {
                case .authorized:
                    break
                case .denied:
                    self.fail("Разрешите распознавание речи в настройках Plink")
                    return
                case .restricted:
                    self.fail("Распознавание речи ограничено на этом устройстве")
                    return
                case .notDetermined:
                    self.fail("Не удалось получить доступ к распознаванию речи")
                    return
                @unknown default:
                    self.fail("Распознавание речи недоступно")
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        guard self.wantsRecording else { return }
                        guard granted else {
                            self.fail("Разрешите доступ к микрофону в настройках Plink")
                            return
                        }
                        self.beginSession()
                    }
                }
            }
        }
    }

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else {
            fail("Распознавание речи сейчас недоступно")
            return
        }
        guard !audioEngine.isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let node = audioEngine.inputNode
            let format = node.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                fail("Микрофон недоступен на этом устройстве")
                return
            }
            if tapInstalled {
                node.removeTap(onBus: 0)
                tapInstalled = false
            }
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        self.stopEngineOnly()
                    }
                }
            }
        } catch {
            fail(Self.userMessage(for: error))
        }
    }

    /// Мягкое завершение: движок останавливается, но задача распознавания
    /// продолжает жить. Финальная расшифровка приходит уже после отпускания
    /// кнопки, и именно в ней оказывается последнее слово короткой фразы —
    /// если рубить задачу сразу, «поставь Дюну» превращается в «поставь».
    func finish() {
        wantsRecording = false
        stopEngineOnly()
    }

    func stop() {
        wantsRecording = false
        stopEngineOnly()
        task?.cancel()
        task = nil
    }

    private func stopEngineOnly() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fail(_ message: String) {
        wantsRecording = false
        stopEngineOnly()
        task?.cancel()
        task = nil
        errorMessage = message
    }

    private static func userMessage(for error: Error) -> String {
        let ns = error as NSError
        // AVAudioEngine's low-level messages vary by OS and are not suitable
        // for a toast. Keep diagnostics in the console, copy only the action.
        #if DEBUG
        print("[Voice] audio session failed: \(ns.domain) / \(ns.code) / \(ns.localizedDescription)")
        #endif
        return "Не удалось включить микрофон. Проверьте разрешение и попробуйте ещё раз."
    }
}
