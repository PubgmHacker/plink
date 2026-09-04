// Plink/Features/WatchRoom/PresenceBar.swift
// Полоса присутствия под плеером: кто в комнате и что происходит.

import SwiftUI

/// Открыть экран покупки Плинк+. Слушает WatchRoomContainer — шит должен
/// пережить автоскрытие хрома плеера, поэтому его держит экран, а не кнопка.
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
                        isSpeaking: false
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
                Text(model.presenceCountLine)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                Text(model.presenceStatusLine)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Cinema2026.secondary)
                    .lineLimit(1)
            }

            Spacer()
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