// Plink/RTC/ParticipantVideoView.swift — PATCH 09: LiveKit video rendering
//
// P1/P2 Sprint fix: LiveKit integration disabled (see RoomRTCController.swift).
// Voice/video chat UI hidden on all platforms (audit Option B).
//
// Replaced with stub that shows letter avatar fallback.
// When LiveKit is re-enabled, restore real VideoView implementation
// using `import LiveKit` + `LiveKit.VideoView`.

import SwiftUI

/// Stub — shows letter avatar fallback (no LiveKit video).
struct ParticipantVideoView: View {
    var track: Any? = nil  // ignored, kept for API compatibility
    var isMirrored: Bool = false

    var body: some View {
        Color.clear  // No-op when LiveKit disabled
    }
}

/// Composite view — video when available, letter avatar fallback.
/// Currently always shows letter avatar (LiveKit disabled).
struct ParticipantAvatarWithVideo: View {
    let participantId: String
    let participantName: String
    let hostId: String?
    let isSpeaking: Bool
    let avatarURL: String?
    var videoTrack: Any? = nil  // ignored

    private var isHost: Bool { participantId == hostId }
    private var hasVideo: Bool { false }  // LiveKit disabled

    var body: some View {
        ZStack {
            // Letter avatar fallback
            if let urlStr = avatarURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        letterAvatar
                    }
                }
            } else {
                letterAvatar
            }

            // Speaking indicator ring
            if isSpeaking {
                Circle()
                    .strokeBorder(Color(hex: 0x26D9A4), lineWidth: 2)
                    .frame(width: 40, height: 40)
            }

            // Host badge
            if isHost {
                Circle()
                    .fill(Color(hex: 0xD7A750))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Text("★")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .offset(x: 14, y: -14)
            }
        }
        .frame(width: 36, height: 36)
    }

    private var letterAvatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(hex: 0x2DE2E6), Color(hex: 0x26D9A4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(participantName.first?.uppercased() ?? "?")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0E1113))
            )
    }
}
