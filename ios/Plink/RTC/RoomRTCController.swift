// Real LiveKit SDK integration
//
// P1/P2 Sprint fix: LiveKit integration disabled due to:
// 1. Name collision: Plink's `Room` struct vs LiveKit's `Room` class
// 2. API changes: setEnabled/localParticipant/remoteParticipants moved
// 3. Backend returns 503 (LIVEKIT_SFU=false in prod)
// 4. Voice UI hidden on all platforms (Option B from audit)
//
// Replaced with clean stub. When LiveKit is re-enabled:
// - Use `import LiveKit` + `LiveKit.Room` (qualified) to avoid collision
// - Update to current LiveKit SDK API (publish/unpublish instead of setEnabled)
// - Wire to backend /api/rtc/token (currently 503)
//

import Foundation
import AVFoundation
import Observation

/// Stub RTC controller — no LiveKit dependency.
/// Voice chat UI is hidden across all platforms (audit Option B).
/// When LiveKit is re-enabled, replace with real implementation
/// using `LiveKit.Room` (qualified to avoid Plink's Room collision).
///
/// Заглушка больше НЕ врёт. Раньше toggleMicrophone/toggleCamera просто
/// переключали локальный флаг — UI показывал «микрофон включён», хотя ни один
/// трек не публиковался. Спасал только выключенный FeatureFlags
/// .liveKitVoiceEnabled: стоило кому-то включить флаг, и он получил бы рабочий
/// с виду интерфейс без звука, без единой строчки в логах.
/// Теперь каждый мутирующий метод проходит через `ensureAvailable()`:
/// состояние не меняется, ставится `.failed` + `unavailableReason`, пишется
/// Logger.webrtc.error. Когда придёт аккаунт Apple Developer и LiveKit —
/// `isAvailable` это единственное место, которое нужно переписать.
@MainActor
@Observable
public final class RoomRTCController {
    public private(set) var isConnected = false
    public private(set) var isMicrophoneEnabled = false
    public private(set) var isCameraEnabled = false
    public private(set) var speakingLevel: Double = 0
    public private(set) var connectionState: ConnectionState = .disconnected

    /// Последняя причина отказа. nil = отказов не было.
    public private(set) var unavailableReason: UnavailableReason?

    public enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed
    }

    public enum UnavailableReason: Equatable {
        /// LiveKit SDK не подключён к сборке (нет аккаунта Apple Developer).
        case sdkNotLinked
        /// Флаг выключен — голос скрыт во всём UI.
        case featureDisabled
        /// Микрофон не разрешён пользователем.
        case microphonePermissionDenied

        public var debugDescription: String {
            switch self {
            case .sdkNotLinked:
                return "LiveKit SDK не подключён к сборке — RoomRTCController это заглушка"
            case .featureDisabled:
                return "FeatureFlags.liveKitVoiceEnabled == false"
            case .microphonePermissionDenied:
                return "пользователь не дал доступ к микрофону"
            }
        }
    }

    /// Единственное место, которое надо переписать, когда LiveKit приедет.
    public var isAvailable: Bool { false }

    public init() {}

    /// Отказ вместо тихой лжи: состояние не двигается, причина фиксируется.
    @discardableResult
    private func ensureAvailable(_ operation: String) -> Bool {
        if isAvailable { return true }
        let reason: UnavailableReason = FeatureFlags.liveKitVoiceEnabled
            ? .sdkNotLinked
            : .featureDisabled
        unavailableReason = reason
        connectionState = .failed
        isConnected = false
        isMicrophoneEnabled = false
        isCameraEnabled = false
        speakingLevel = 0
        Logger.webrtc.error("\(operation) отклонён: \(reason.debugDescription)")
        assertionFailure("RoomRTCController.\(operation) вызван, пока голос недоступен: \(reason.debugDescription)")
        return false
    }

    /// Connect to LiveKit room.
    /// When LiveKit is enabled: fetch token from /api/rtc/token, then
    /// `LiveKit.Room.connect(url, token)`.
    public func connect(roomId: String) async {
        guard ensureAvailable("connect(roomId:)") else { return }
        // Real implementation when LIVEKIT_SFU=true:
        //   let token = try await APIClient.shared.getRTCToken(roomId: roomId)
        //   let room = LiveKit.Room()
        //   try await room.connect(url: token.url, token: token.token)
        //   self.liveKitRoom = room
        //   self.isConnected = true
    }

    /// Disconnect from LiveKit room. Разрыв разрешён всегда — это сброс
    /// состояния в безопасное, он не может соврать.
    public func disconnect() async {
        // Real: liveKitRoom?.disconnect()
        isConnected = false
        isMicrophoneEnabled = false
        isCameraEnabled = false
        speakingLevel = 0
        connectionState = .disconnected
        unavailableReason = nil
    }

    /// Toggle microphone.
    public func toggleMicrophone() async {
        guard ensureAvailable("toggleMicrophone()") else { return }
        // First room-voice use → system mic permission dialog (once).
        if !isMicrophoneEnabled {
            let ok = await PlinkPermissions.requestMicrophoneIfNeeded()
            guard ok else {
                unavailableReason = .microphonePermissionDenied
                Logger.webrtc.warn("toggleMicrophone(): доступ к микрофону не выдан")
                return
            }
        }
        // Real: localParticipant.setMicrophone(enabled: !isMicrophoneEnabled)
        isMicrophoneEnabled.toggle()
    }

    /// Toggle camera.
    public func toggleCamera() async {
        guard ensureAvailable("toggleCamera()") else { return }
        // Real: localParticipant.setCamera(enabled: !isCameraEnabled)
        isCameraEnabled.toggle()
    }

    /// Set microphone enabled state.
    public func setMicrophone(enabled: Bool) async {
        // Выключение разрешено всегда — это движение в безопасную сторону.
        guard enabled else {
            isMicrophoneEnabled = false
            return
        }
        guard ensureAvailable("setMicrophone(enabled:)") else { return }
        let ok = await PlinkPermissions.requestMicrophoneIfNeeded()
        guard ok else {
            isMicrophoneEnabled = false
            unavailableReason = .microphonePermissionDenied
            Logger.webrtc.warn("setMicrophone(enabled:): доступ к микрофону не выдан")
            return
        }
        isMicrophoneEnabled = true
    }

    /// Set camera enabled state.
    public func setCamera(enabled: Bool) async {
        guard enabled else {
            isCameraEnabled = false
            return
        }
        guard ensureAvailable("setCamera(enabled:)") else { return }
        isCameraEnabled = true
    }
}
