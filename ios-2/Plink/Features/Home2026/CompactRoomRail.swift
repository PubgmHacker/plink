// Plink/Features/Home2026/CompactRoomRail.swift — §5 Final Unified
//
// Compact horizontal room rail for Home. Two styles: landscape (186x105)
// and poster (108x154). Uses Cinema2026 palette.

import SwiftUI

struct CompactRoomRail: View {
    enum Style { case landscape, poster }

    let title: String
    let rooms: [Room]
    let style: Style
    let open: (Room) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                    .tracking(-0.25)
                Spacer()
                if !rooms.isEmpty {
                    Text("\(rooms.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Cinema2026.secondary)
                }
            }
            .padding(.horizontal, CompactPhoneMetrics.horizontalInset)

            ScrollView(.horizontal) {
                LazyHStack(spacing: CompactPhoneMetrics.railSpacing) {
                    ForEach(rooms) { room in
                        Button { open(room) } label: {
                            if style == .landscape {
                                CompactLiveRoomCard(room: room)
                            } else {
                                CompactRoomPoster(room: room)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, CompactPhoneMetrics.horizontalInset)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct CompactLiveRoomCard: View {
    let room: Room

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PosterImage(url: room.mediaItem?.thumbnailURL)
                .frame(
                    width: CompactPhoneMetrics.landscapeCardWidth,
                    height: CompactPhoneMetrics.landscapeCardHeight
                )
                .clipped()

            LinearGradient(
                colors: [.clear, Cinema2026.background.opacity(0.92)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                if room.isActive {
                    Text("LIVE")
                        .font(.system(size: 8, weight: .black))
                        .tracking(0.8)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Cinema2026.danger, in: Capsule())
                }
                Text(room.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("\(room.participantCount) смотрят")
                    .font(.system(size: 10))
                    .foregroundStyle(Cinema2026.secondary)
            }
            .padding(9)
        }
        .frame(
            width: CompactPhoneMetrics.landscapeCardWidth,
            height: CompactPhoneMetrics.landscapeCardHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: CompactPhoneMetrics.landscapeRadius))
    }
}

struct CompactRoomPoster: View {
    let room: Room

    var body: some View {
        PosterImage(url: room.mediaItem?.thumbnailURL)
            .aspectRatio(CompactPhoneMetrics.posterAspect, contentMode: .fill)
            .frame(width: CompactPhoneMetrics.posterWidth)
            .clipShape(RoundedRectangle(cornerRadius: CompactPhoneMetrics.posterRadius))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(room.name), \(room.participantCount) участников")
    }
}

// MARK: - Compact home components

struct CompactHomeHeader: View {
    let openProfile: () -> Void
    let openJoin: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Plink")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                Text("Смотрите вместе")
                    .font(.system(size: 13))
                    .foregroundStyle(Cinema2026.secondary)
            }
            Spacer()
            Button(action: openProfile) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(Cinema2026.secondary)
            }
        }
        .padding(.horizontal, CompactPhoneMetrics.horizontalInset)
    }
}

struct CompactAIEntryCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Cinema2026.accent)
                Text("Что посмотреть?")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Cinema2026.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Cinema2026.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, CompactPhoneMetrics.horizontalInset)
    }
}

struct CompactNoLiveRoomsState: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 32))
                .foregroundStyle(Cinema2026.secondary)
            Text("Нет активных комнат")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Cinema2026.text)
            Button("Создать комнату", action: onCreate)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Cinema2026.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

struct CompactRoomActions: View {
    let create: () -> Void
    let join: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: create) {
                Label("Создать", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: CompactPhoneMetrics.primaryButtonHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(Cinema2026.accent)

            Button(action: join) {
                Label("Войти", systemImage: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: CompactPhoneMetrics.primaryButtonHeight)
            }
            .buttonStyle(.bordered)
            .tint(Cinema2026.text)
        }
        .padding(.horizontal, CompactPhoneMetrics.horizontalInset)
        .padding(.vertical, 10)
        .background(Cinema2026.background.opacity(0.96))
    }
}

// MARK: - Featured Room Banner (hero)

struct FeaturedRoomBanner: View {
    let room: Room
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Backdrop
                AsyncImage(url: URL(string: room.mediaItem?.thumbnailURL ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Cinema2026.surface)
                }
                .frame(height: 200)
                .clipped()

                // Gradient overlay
                LinearGradient(
                    colors: [.clear, Cinema2026.background.opacity(0.5), Cinema2026.background],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    if room.isActive {
                        Text("● В ЭФИРЕ")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(Cinema2026.danger)
                    }
                    Text(room.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Cinema2026.text)
                        .lineLimit(2)
                    Text("\(room.participantCount) смотрят")
                        .font(.system(size: 12))
                        .foregroundStyle(Cinema2026.secondary)
                }
                .padding(16)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, CompactPhoneMetrics.horizontalInset)
    }
}

// MARK: - Trending Rail (YouTube videos)

struct TrendingRail: View {
    let title: String
    let videos: [YouTubeVideoSummary]
    let onSelect: (YouTubeVideoSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                Spacer()
                Text("\(videos.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Cinema2026.secondary)
            }
            .padding(.horizontal, CompactPhoneMetrics.horizontalInset)

            ScrollView(.horizontal) {
                LazyHStack(spacing: CompactPhoneMetrics.railSpacing) {
                    ForEach(videos) { video in
                        Button {
                            onSelect(video)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                AsyncImage(url: URL(string: video.thumbnailURLString ?? "")) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle().fill(Cinema2026.surface)
                                }
                                .frame(width: CompactPhoneMetrics.posterWidth,
                                       height: CGFloat(CompactPhoneMetrics.posterWidth) / 0.70)
                                .clipShape(RoundedRectangle(cornerRadius: CompactPhoneMetrics.posterRadius))

                                Text(video.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Cinema2026.text)
                                    .lineLimit(2)
                                    .frame(width: CompactPhoneMetrics.posterWidth, alignment: .leading)

                                Text(video.channelTitle)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Cinema2026.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, CompactPhoneMetrics.horizontalInset)
            }
            .scrollIndicators(.hidden)
        }
    }
}
