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

// Голосовой чат отключён (транспорт не подключён), но paywall-триггер уже
// использует это уведомление — объявление было потеряно при вырезании
// голосового чата из продукта. Оставляем только имя нотификации, чтобы
// таргет собирался; сам flow остаётся выключенным через FeatureFlags.
extension Notification.Name {
    static let showPlinkPlusPaywall = Notification.Name("showPlinkPlusPaywall")
}

struct PresenceBar: View {
    let model: WatchRoomModel
    // Ревью 26.07.2026: см. WatchChatView — скрим живой темы читает
    // «Уменьшение прозрачности» и наличие подложки за поверхностью.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.verticalSizeClass) private var heightClass

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
                        // Free users — show paywall for voice chat
                        Button {
                            NotificationCenter.default.post(
                                name: .showPlinkPlusPaywall,
                                object: nil,
                                userInfo: ["trigger": PlinkPlusPaywall.Trigger.voiceChat]
                            )
                        } label: {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Cinema2026.secondary)
                                .frame(width: 36, height: 36)
                                .background(Cinema2026.raised.opacity(0.5), in: Capsule())
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Cinema2026.amber)
                                        .offset(x: 4, y: -4)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    if hasPremium {
                        CameraActionButton(state: model.cameraState) {
                            Task { await model.toggleCamera() }
                        }
                    } else {
                        // Free users — show paywall for camera
                        Button {
                            NotificationCenter.default.post(
                                name: .showPlinkPlusPaywall,
                                object: nil,
                                userInfo: ["trigger": PlinkPlusPaywall.Trigger.cameraFilter]
                            )
                        } label: {
                            Image(systemName: "video.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Cinema2026.secondary)
                                .frame(width: 36, height: 36)
                                .background(Cinema2026.raised.opacity(0.5), in: Capsule())
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Cinema2026.amber)
                                        .offset(x: 4, y: -4)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .plinkGlass(.overlay, in: Capsule(style: .continuous))
                .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        // P1 5.11: полоса присутствия — первая поверхность под плеером, именно
        // здесь живая тема комнаты читается лучше всего. Без темы фон прежний.
        .background(
            Cinema2026.background
                .opacity(RoomLiveTheme.scrimOpacity(
                    model.appearanceStore.appearance,
                    reduceTransparency: reduceTransparency,
                    backdropVisible: heightClass != .compact
                ))
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Cinema2026.divider.opacity(0.35))
                .frame(height: 0.5)
        }
    }
}