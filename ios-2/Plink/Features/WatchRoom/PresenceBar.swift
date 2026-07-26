// Plink/Features/WatchRoom/PresenceBar.swift — PATCH 02 polish
//
// Professional design:
//   - Avatars: 36pt (was 34pt), -8pt overlap (was -6)
//   - Host avatar gold ring (was 0.5 opacity)
//   - Active speaker green ring
//   - Voice/camera buttons grouped in a capsule with .ultraThinMaterial bg
//   - "Invite to voice" button (new — chevron.right)
//   - 56pt total height (was 52pt)
//   - 16pt horizontal padding (was 12pt)

import SwiftUI

struct PresenceBar: View {
    let model: WatchRoomModel

    var body: some View {
        HStack(spacing: 12) {
            // Avatar stack
            HStack(spacing: -8) {
                ForEach(model.participants.prefix(5)) { participant in
                    ParticipantAvatar(
                        participant: participant,
                        hostId: model.hostId,
                        isSpeaking: model.activeSpeakerName == participant.username
                    )
                }
                if model.participants.count > 5 {
                    Text("+\(model.participants.count - 5)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Cinema2026.text)
                        .frame(width: 36, height: 36)
                        .background(Cinema2026.raised, in: Circle())
                        .overlay(Circle().stroke(Cinema2026.divider, lineWidth: 2))
                }
            }

            // Identity + status
            VStack(alignment: .leading, spacing: 2) {
                Text("\(max(1, model.participants.count)) в комнате")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                Text(model.activeSpeakerName.map { "\($0) говорит" } ?? "Смотрим вместе")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Cinema2026.secondary)
            }

            Spacer()

            // Voice/camera — only when LiveKit is enabled (prod SFU). MVP hides dead controls.
            if FeatureFlags.liveKitVoiceEnabled {
                let hasPremium = PremiumStatusManager.shared.isPremium
                HStack(spacing: 4) {
                    if hasPremium {
                        VoiceActionButton(state: model.microphoneState) {
                            Task { await model.toggleMicrophone() }
                        }
                    } else {
                        // Free users can only listen
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Cinema2026.secondary)
                            .frame(width: 36, height: 36)
                            .background(Cinema2026.raised.opacity(0.5), in: Capsule())
                    }
                    CameraActionButton(state: model.cameraState) {
                        Task { await model.toggleCamera() }
                    }
                }
                .padding(4)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Cinema2026.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Cinema2026.divider.opacity(0.35))
                .frame(height: 0.5)
        }
    }
}
