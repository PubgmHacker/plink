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

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Пользователь всё ещё держит кнопку. Разрешение на микрофон приходит
    /// асинхронно, и при коротком нажатии stop() успевал сработать раньше
    /// колбэка — сессия стартовала уже после отпускания, и остановить её было
    /// некому. Микрофон оставался включённым.
    private var wantsRecording = false

    func start() {
        transcript = ""
        wantsRecording = true
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard status == .authorized else { return }
                guard self?.wantsRecording == true else { return }
                self?.beginSession()
            }
        }
    }

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable, !audioEngine.isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let node = audioEngine.inputNode
            let format = node.outputFormat(forBus: 0)
            node.removeTap(onBus: 0)
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
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
            stop()
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
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
