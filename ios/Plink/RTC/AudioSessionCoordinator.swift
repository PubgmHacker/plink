// Plink/RTC/AudioSessionCoordinator.swift — Stage 9: centralized audio session
//
// AVAudioSession is configured CENTRALLY. Voice and media must not
// independently change category/mode/active.
//
// Categories:
//   - .playback: media playback (video, music)
//   - .playAndRecord: voice chat active (echo cancellation, noise suppression)
//   - .ambient: media without interrupting other audio
//
// Ducking: when voice chat is active, media volume is reduced by 30%.
// Interruption: handled centrally, not per-service.
// Route change: headphones connect/disconnect handled here.

import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
public final class AudioSessionCoordinator {
    public static let shared = AudioSessionCoordinator()

    public private(set) var isVoiceChatActive = false
    public private(set) var isMediaPlaybackActive = false
    public private(set) var currentRoute: String = "speaker"

    private init() {
        setupNotificationObservers()
    }

    // MARK: - Configuration

    /// Configure for media playback (video, music)
    public func configureForMediaPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true, options: [])
            isMediaPlaybackActive = true
        } catch {
            Logger.app.error("[AudioSession] media playback config failed: \(error)")
        }
    }

    /// Configure for voice chat (adds recording capability)
    public func configureForVoiceChat() {
        do {
            let session = AVAudioSession.sharedInstance()
            // `.allowBluetooth` переименован в `.allowBluetoothHFP` в SDK iOS 26.
            // Тулчейн CI (Xcode 16.4 / iOS 18 SDK) знает только прежнее имя — выбираем
            // символ по версии компилятора. Чистое переименование, поведение то же.
            #if compiler(>=6.2)
            let bluetoothOption: AVAudioSession.CategoryOptions = .allowBluetoothHFP
            #else
            let bluetoothOption: AVAudioSession.CategoryOptions = .allowBluetooth
            #endif
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [
                    bluetoothOption,
                    .defaultToSpeaker,
                    .duckOthers,  // Duck media by 30% during voice
                ]
            )
            try session.setActive(true, options: [])
            isVoiceChatActive = true
        } catch {
            Logger.app.error("[AudioSession] voice chat config failed: \(error)")
        }
    }

    /// Deactivate voice chat, return to media playback
    public func deactivateVoiceChat() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true, options: [])
            isVoiceChatActive = false
        } catch {
            Logger.app.warn("[AudioSession] voice deactivation failed: \(error)")
        }
    }

    /// Fully deactivate audio session
    public func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            isVoiceChatActive = false
            isMediaPlaybackActive = false
        } catch {
            Logger.app.warn("[AudioSession] deactivation failed: \(error)")
        }
    }

    // MARK: - Route changes

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleRouteChange(notification) }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleInterruption(notification) }
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        let session = AVAudioSession.sharedInstance()
        currentRoute = session.currentRoute.outputs.first?.portType.rawValue ?? "speaker"

        switch reason {
        case .newDeviceAvailable:
            // Headphones connected — continue playback
            break
        case .oldDeviceUnavailable:
            // Headphones disconnected — pause to avoid sudden speaker blast
            // Notify media controller to pause
            NotificationCenter.default.post(name: .plinkHeadphonesDisconnected, object: nil)
        default:
            break
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // Pause all playback
            NotificationCenter.default.post(name: .plinkAudioInterruptionBegan, object: nil)
        case .ended:
            // Resume if appropriate
            NotificationCenter.default.post(name: .plinkAudioInterruptionEnded, object: nil)
        @unknown default:
            break
        }
    }
}

// MARK: - Custom notification names

extension Notification.Name {
    static let plinkHeadphonesDisconnected = Notification.Name("plinkHeadphonesDisconnected")
    static let plinkAudioInterruptionBegan = Notification.Name("plinkAudioInterruptionBegan")
    static let plinkAudioInterruptionEnded = Notification.Name("plinkAudioInterruptionEnded")
}
