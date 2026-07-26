// Plink/RTC/RoomRTCController.swift — PATCH 07: Real LiveKit SDK integration
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
@MainActor
@Observable
public final class RoomRTCController {
    public private(set) var isConnected = false
    public private(set) var isMicrophoneEnabled = false
    public private(set) var isCameraEnabled = false
    public private(set) var speakingLevel: Double = 0
    public private(set) var connectionState: ConnectionState = .disconnected

    public enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed
    }

    public init() {}

    /// Connect to LiveKit room (currently stub — returns immediately).
    /// When LiveKit is enabled: fetch token from /api/rtc/token, then
    /// `LiveKit.Room.connect(url, token)`.
    public func connect(roomId: String) async {
        // Stub: no-op. Voice chat disabled in prod.
        // Real implementation when LIVEKIT_SFU=true:
        //   let token = try await APIClient.shared.getRTCToken(roomId: roomId)
        //   let room = LiveKit.Room()
        //   try await room.connect(url: token.url, token: token.token)
        //   self.liveKitRoom = room
        //   self.isConnected = true
    }

    /// Disconnect from LiveKit room (currently stub).
    public func disconnect() async {
        // Stub: no-op.
        // Real: liveKitRoom?.disconnect()
        isConnected = false
        isMicrophoneEnabled = false
        isCameraEnabled = false
    }

    /// Toggle microphone (currently stub).
    public func toggleMicrophone() async {
        // First room-voice use → system mic permission dialog (once).
        if !isMicrophoneEnabled {
            let ok = await PlinkPermissions.requestMicrophoneIfNeeded()
            guard ok else { return }
        }
        // Stub: toggle local state only.
        // Real: localParticipant.setMicrophone(enabled: !isMicrophoneEnabled)
        isMicrophoneEnabled.toggle()
    }

    /// Toggle camera (currently stub).
    public func toggleCamera() async {
        // Stub: toggle local state only.
        // Real: localParticipant.setCamera(enabled: !isCameraEnabled)
        isCameraEnabled.toggle()
    }

    /// Set microphone enabled state.
    public func setMicrophone(enabled: Bool) async {
        if enabled {
            let ok = await PlinkPermissions.requestMicrophoneIfNeeded()
            guard ok else {
                isMicrophoneEnabled = false
                return
            }
        }
        isMicrophoneEnabled = enabled
    }

    /// Set camera enabled state.
    public func setCamera(enabled: Bool) async {
        isCameraEnabled = enabled
    }
}
