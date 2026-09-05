// Plink/Features/WatchRoom/RoomIdentityBar.swift
//
// Extracted from WatchRoomSupportTypes.swift.
//
// Shows room title, host badge, and (in tablet) the deep-link share button.
// Professional design:
//   - 14pt semibold title (was 13pt)
//   - HOST badge as pill with gold accent (was thin text)
//   - Subtle divider below (was nothing)
//   - 16pt horizontal padding (was 14pt)

import SwiftUI

struct RoomIdentityBar: View {
    let model: WatchRoomModel

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Комната")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("Код \(model.displayRoomCode)")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Cinema2026.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Cinema2026.accent.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(Cinema2026.accent.opacity(0.26), lineWidth: 0.5))

                    if let host = model.participants.first(where: { $0.userId == model.hostId }) {
                        Text("Хост: \(host.username)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Cinema2026.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if model.isHost {
                    // Тот же знак, что в углу аватара участника: человек
                    // должен узнать в списке себя по той же метке.
                    HStack(spacing: 4) {
                        PlinkHostMark(size: 10, ring: false)
                        Text("ХОСТ")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Cinema2026.amber)
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 8)
                    .padding(.vertical, 3)
                    .background(Cinema2026.amber.opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke(Cinema2026.amber.opacity(0.3), lineWidth: 0.5))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Вы хост комнаты")
                }

                ShareLink(item: model.roomShareText) {
                    Label("Позвать", systemImage: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PlinkRoomAccent.ink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(PlinkRoomAccent.current, in: Capsule())
                }
                .accessibilityLabel("Пригласить в комнату")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Cinema2026.divider.opacity(0.35))
                .frame(height: 0.5)
        }
    }
}
