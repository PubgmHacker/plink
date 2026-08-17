// Plink/Services/VoiceNoteRecorder.swift
// Real hold-to-record voice notes for friend DMs (AVAudioRecorder).

import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class VoiceNoteRecorder: NSObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case recording
        case encoding
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var durationSec: TimeInterval = 0
    private(set) var peakLevel: Float = 0

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var startedAt: Date?
    private var fileURL: URL?

    /// Max length for a friend voice note.
    static let maxDuration: TimeInterval = 60

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    // MARK: - Public API

    /// Request mic permission if needed, then start recording. Returns false if denied.
    @discardableResult
    func start() async -> Bool {
        stopInternal(deleteFile: true)
        state = .requestingPermission

        let granted = await requestMicPermission()
        guard granted else {
            state = .failed("Нет доступа к микрофону")
            return false
        }

        do {
            try configureSession()
            let url = try makeFileURL()
            fileURL = url

            // AAC in .m4a — widely playable on iOS AVAudioPlayer + server stream
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                AVEncoderBitRateKey: 64_000,
            ]

            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.isMeteringEnabled = true
            rec.delegate = self
            guard rec.prepareToRecord(), rec.record() else {
                state = .failed("Не удалось начать запись")
                return false
            }

            recorder = rec
            startedAt = Date()
            durationSec = 0
            peakLevel = 0
            state = .recording
            startMetering()
            return true
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }

    /// Stop recording and return AAC/m4a data + duration. Nil if too short / failed.
    func stopAndExport() -> (data: Data, duration: TimeInterval, dataURL: String)? {
        guard let rec = recorder, let url = fileURL else {
            stopInternal(deleteFile: true)
            return nil
        }

        state = .encoding
        stopMetering()
        rec.stop()

        let dur = max(durationSec, rec.currentTime)
        durationSec = dur

        // Tiny taps produce empty / unusable clips
        guard dur >= 0.4 else {
            stopInternal(deleteFile: true)
            state = .failed("Слишком коротко — удерживайте кнопку")
            return nil
        }

        defer {
            recorder = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        guard let data = try? Data(contentsOf: url), data.count > 200 else {
            stopInternal(deleteFile: true)
            state = .failed("Пустая запись")
            return nil
        }

        // Cap ~1.4MB client-side
        guard data.count < 1_400_000 else {
            stopInternal(deleteFile: true)
            state = .failed("Слишком длинная запись")
            return nil
        }

        let b64 = data.base64EncodedString()
        let dataURL = "data:audio/mp4;base64,\(b64)"
        // Keep file for possible retry; clear on next start
        state = .idle
        return (data, dur, dataURL)
    }

    func cancel() {
        stopInternal(deleteFile: true)
        state = .idle
    }

    // MARK: - Internals

    private func requestMicPermission() async -> Bool {
        // Central helper — system dialog once (NSMicrophoneUsageDescription in Info.plist)
        return await PlinkPermissions.requestMicrophoneIfNeeded()
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers, .mixWithOthers]
        )
        try session.setActive(true)
        try? session.overrideOutputAudioPort(.speaker)
    }

    private func makeFileURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("plink-voice", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("note-\(UUID().uuidString).m4a")
    }

    private func startMetering() {
        stopMetering()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        if let meterTimer {
            RunLoop.main.add(meterTimer, forMode: .common)
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func tick() {
        guard let rec = recorder, rec.isRecording else { return }
        rec.updateMeters()
        let power = rec.averagePower(forChannel: 0) // dB, typically -60...0
        let normalized = max(0, min(1, (power + 50) / 50))
        peakLevel = normalized
        if let startedAt {
            durationSec = Date().timeIntervalSince(startedAt)
        } else {
            durationSec = rec.currentTime
        }
        if durationSec >= Self.maxDuration {
            // Auto-stop at max — UI should call stopAndExport
            rec.stop()
            stopMetering()
            state = .encoding
        }
    }

    private func stopInternal(deleteFile: Bool) {
        stopMetering()
        recorder?.stop()
        recorder = nil
        if deleteFile, let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        fileURL = nil
        startedAt = nil
        durationSec = 0
        peakLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension VoiceNoteRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag, case .recording = self.state {
                self.state = .failed("Запись прервана")
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.state = .failed(error?.localizedDescription ?? "Ошибка кодирования")
        }
    }
}

// MARK: - Wire format helpers

enum PlinkVoiceWire {
    /// Content marker: `[[vn:12.5]]optional preview text`
    private static let pattern = try! NSRegularExpression(
        pattern: #"^\[\[vn:([0-9]+(?:\.[0-9]+)?)\]\]"#
    )

    static func encode(durationSec: TimeInterval, preview: String? = nil) -> String {
        let d = max(0.5, min(60, durationSec))
        let mins = Int(d) / 60
        let secs = Int(d) % 60
        let label = preview ?? "🎤 \(mins):\(String(format: "%02d", secs))"
        return "[[vn:\(String(format: "%.1f", d))]]\(label)"
    }

    static func decode(_ raw: String) -> (isVoice: Bool, durationSec: TimeInterval?, displayText: String) {
        let ns = raw as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = pattern.firstMatch(in: raw, options: [], range: range),
              match.numberOfRanges >= 2,
              let dr = Range(match.range(at: 1), in: raw) else {
            // Fallback: legacy placeholder "🎤 Голосовое · 0:xx"
            if raw.contains("🎤") && (raw.contains("Голосовое") || raw.contains("0:")) {
                return (true, nil, raw)
            }
            return (false, nil, raw)
        }
        let dur = TimeInterval(raw[dr])
        let after = match.range(at: 0)
        let rest = after.location != NSNotFound
            ? ns.substring(from: after.location + after.length).trimmingCharacters(in: .whitespaces)
            : ""
        let display = rest.isEmpty ? "🎤 Голосовое" : rest
        return (true, dur, display)
    }

    static func formatDuration(_ sec: TimeInterval) -> String {
        let s = max(0, Int(sec.rounded()))
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}
