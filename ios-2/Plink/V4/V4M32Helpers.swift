// Plink/V4/V4M32Helpers.swift — M32: история просмотров на профиле.
// M34: подсказка при пустой истории.

import SwiftUI

struct WatchHistorySection: View {
    @ObservedObject private var manager = WatchHistoryManager.shared

    var body: some View {
        if manager.history.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(V4.muted)
                Text("Здесь появится история — посмотри что-нибудь вместе с друзьями")
                    .font(.system(size: 12))
                    .foregroundStyle(V4.muted)
                Spacer()
            }
            .padding(14)
            .background(V4.cardBG.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(V4.line))
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 11) {
                    ForEach(manager.history.prefix(10)) { item in
                        historyCard(item)
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 8)
        }
    }

    private func historyCard(_ item: WatchHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let thumb = item.thumbnailURL, let url = URL(string: thumb) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12).fill(V4.cardBG)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(V4.cardBG)
                    }
                }
                .frame(width: 168, height: 94)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let progress = item.progress {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25))
                            Capsule()
                                .fill(V4.accent)
                                .frame(width: max(6, g.size.width * progress))
                        }
                    }
                    .frame(width: 152, height: 3)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 7)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(V4.line))

            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(V4.ink)
                .lineLimit(1)
                .frame(width: 168, alignment: .leading)

            Text(item.formattedDate)
                .font(.system(size: 10.5))
                .foregroundStyle(V4.muted)
                .frame(width: 168, alignment: .leading)
        }
    }
}
