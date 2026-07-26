// Plink/Features/Discovery/DiscoveryHomeView.swift — Cinematic home
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §3: Discovery Home

import SwiftUI

struct DiscoveryHomeView: View {
    @State private var model: DiscoveryViewModel
    @Environment(\.horizontalSizeClass) private var widthClass

    init(dependencies: AppDependencies) {
        _model = State(initialValue: DiscoveryViewModel(service: dependencies.discoveryService))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                HomeHeader()
                    .padding(.horizontal, 18)

                switch model.state {
                case .loading:
                    DiscoverySkeleton()
                case .empty:
                    DiscoveryEmptyState()
                case .failed(let message):
                    DiscoveryErrorState(message: message) { Task { await model.load() } }
                case .loaded:
                    // Premium video hero carousel (3 banners from Grok Imagine)
                    HeroVideoCarousel()
                        .padding(.horizontal, 18)

                    // Quick Room card
                    quickRoomCard
                        .padding(.horizontal, 18)

                    // Promo banners
                    promoBanner(
                        title: "Смотрите вместе",
                        subtitle: "Создай комнату и пригласи друзей смотреть кино синхронно",
                        icon: "person.2.fill",
                        isPremium: false
                    )
                    .padding(.horizontal, 18)

                    promoBanner(
                        title: "Plink+ премиум",
                        subtitle: "Живые темы, анимированные эмодзи и эксклюзивные функции",
                        icon: "crown.fill",
                        isPremium: true
                    )
                    .padding(.horizontal, 18)

                    if !model.featured.isEmpty {
                        FeaturedCarousel(items: model.featured)
                    }
                    if !model.continueTogether.isEmpty {
                        ContinueTogetherRail(items: model.continueTogether)
                    }
                    if !model.liveRooms.isEmpty {
                        LiveRoomsRail(rooms: model.liveRooms)
                    }
                    if !model.collections.isEmpty {
                        EditorialCollections(collections: model.collections)
                    }
                }
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(Cinema2026.background)
        .task { await model.load() }
        .navigationTitle(widthClass == .regular ? "Смотреть" : "")
    }
}

// MARK: - Header

struct HomeHeader: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Plink")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                Text(LocalizationManager.shared.string(.dvWatchTogether))
                    .font(.system(size: 14))
                    .foregroundStyle(Cinema2026.secondary)
            }
            Spacer()
            Text(LocalizationManager.shared.string(.dvWithWhom))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Cinema2026.accent)
        }
    }
}

// MARK: - Quick Room Card

extension DiscoveryHomeView {
    private var quickRoomCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Cinema2026.accent, Color(red: 0.15, green: 0.85, blue: 0.64)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Cinema2026.background)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizationManager.shared.string(.dvQuickRoom))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                Text(LocalizationManager.shared.string(.dvCreateOrJoin))
                    .font(.system(size: 13))
                    .foregroundStyle(Cinema2026.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Cinema2026.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Быстрая комната — создать или войти по коду")
    }

    // MARK: - Promo Banner (from V4)

    private func promoBanner(title: String, subtitle: String, icon: String, isPremium: Bool = false) -> some View {
        let bannerAccent = isPremium ? Color(hex: 0xD7A750) : Cinema2026.accent
        let _ = isPremium

        return HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(bannerAccent.opacity(0.2))
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(bannerAccent)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Cinema2026.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Cinema2026.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [bannerAccent.opacity(0.08), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(bannerAccent.opacity(0.2), lineWidth: 1)
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

// MARK: - Featured carousel

struct FeaturedCarousel: View {
    let items: [DiscoveryItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(items) { item in
                    FeaturedHero(item: item, onWatch: {}, onAdd: {})
                        .frame(width: UIScreen.main.bounds.width - 36)
                }
            }
            .padding(.horizontal, 18)
        }

        // Swipe hint for hero carousel (first time users)
        Text("Swipe to see more →")
            .font(.caption)
            .foregroundStyle(Cinema2026.secondary)
            .padding(.leading, 18)
            .padding(.top, 4)
    }
}

struct FeaturedHero: View {
    let item: DiscoveryItem
    let onWatch: () -> Void
    let onAdd: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PosterImage(url: item.backdropURL)
                .aspectRatio(16 / 10, contentMode: .fill)
                .overlay {
                    LinearGradient(
                        colors: [.clear, Cinema2026.background.opacity(0.16), Cinema2026.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            VStack(alignment: .leading, spacing: 10) {
                Text(item.eyebrow.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(Cinema2026.accent)

                Text(item.title)
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-1.2)
                    .lineLimit(2)

                Text(item.metadata)
                    .font(.caption)
                    .foregroundStyle(Cinema2026.secondary)

                HStack(spacing: 10) {
                    Button(action: onWatch) {
                        Label("Смотреть вместе", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Cinema2026.text)
                    .foregroundStyle(Cinema2026.background)

                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(Cinema2026.text)
                }

                if !item.interestedFriends.isEmpty {
                    ParticipantAvatarStack(participants: item.interestedFriends)
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Continue together rail

struct ContinueTogetherRail: View {
    let items: [ContinueItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizationManager.shared.string(.dvContinueTogether))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Cinema2026.text)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            PosterImage(url: item.thumbnailURL)
                                .frame(width: 140, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: CinemaRadius.poster))
                            Text(item.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Cinema2026.text)
                                .lineLimit(1)
                                .frame(width: 140, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }
}

// MARK: - Live rooms rail

struct LiveRoomsRail: View {
    let rooms: [Room]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalizationManager.shared.string(.dvLiveNow))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                Circle()
                    .fill(Cinema2026.live)
                    .frame(width: 8, height: 8)
                Spacer()
            }
            .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(rooms) { room in
                        LiveRoomCard(room: room)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }
}

struct LiveRoomCard: View {
    let room: Room

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                PosterImage(url: room.mediaItem?.thumbnailURL)
                    .frame(width: 160, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: CinemaRadius.poster))

                Text("LIVE")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Cinema2026.danger, in: Capsule())
                    .padding(6)
            }

            Text(room.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Cinema2026.text)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)

            Text("\(room.participantCount) смотрят")
                .font(.system(size: 10))
                .foregroundStyle(Cinema2026.secondary)
        }
    }
}

// MARK: - Editorial collections

struct EditorialCollections: View {
    let collections: [EditorialCollection]

    var body: some View {
        ForEach(collections) { collection in
            VStack(alignment: .leading, spacing: 12) {
                Text(collection.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                    .padding(.horizontal, 18)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(collection.items) { item in
                            PosterCard(item: item)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
    }
}

struct PosterCard: View {
    let item: DiscoveryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: item.backdropURL)
                .frame(width: 140, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: CinemaRadius.poster))
                .hoverScale()

            Text(item.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Cinema2026.text)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
        }
    }
}

// MARK: - States

struct DiscoverySkeleton: View {
    var body: some View {
        VStack(spacing: 20) {
            ShimmerView()
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 18)
            ForEach(0..<2, id: \.self) { _ in
                ShimmerView()
                    .frame(height: 100)
                    .padding(.horizontal, 18)
            }
        }
    }
}

struct DiscoveryEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle.on.rectangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Cinema2026.tertiary)

            Text(LocalizationManager.shared.string(.dvNoRooms))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Cinema2026.text)

            Text(LocalizationManager.shared.string(.dvNoRoomsSub))
                .font(.system(size: 14))
                .foregroundStyle(Cinema2026.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

struct DiscoveryErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Cinema2026.warning)

            Text(LocalizationManager.shared.string(.dvLoadFailed))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Cinema2026.text)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Cinema2026.secondary)
                .multilineTextAlignment(.center)

            Button("Повторить", action: onRetry)
                .buttonStyle(.bordered)
                .tint(Cinema2026.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 24)
    }
}
