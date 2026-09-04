// Stories rail at the top of the Friends tab — Telegram's row of rings, but a
// story here is what a friend watched this week plus their status. The first
// tile is the viewer's own; friends with unseen stories come first.
import SwiftUI

/// What the full-screen viewer opens on: the ordered owners and where to start.
struct PlinkStoryPresentation: Identifiable {
    let id = UUID()
    let owners: [FriendStoryOwner]
    let start: Int
}

struct V4FriendStoriesRail: View {
    let theme: V4Theme
    let store: V4FriendsStore
    /// Tap on a friend: the viewer opens on that person.
    let onOpen: (PlinkStoryPresentation) -> Void
    /// Tap on the own tile: open own story, or the status editor when empty.
    let onMine: (FriendStoryOwner?) -> Void

    private let tile: CGFloat = 66

    /// Unseen first, then seen — both keep the server's newest-first order.
    private var ordered: [FriendStoryOwner] {
        let ledger = PlinkStorySeenLedger.shared
        let fresh = store.stories.filter { !ledger.isSeen($0) }
        let seen = store.stories.filter { ledger.isSeen($0) }
        return fresh + seen
    }

    var body: some View {
        let owners = ordered
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                mineTile
                ForEach(Array(owners.enumerated()), id: \.element.id) { index, owner in
                    Button {
                        HapticManager.impact(.light)
                        onOpen(PlinkStoryPresentation(owners: owners, start: index))
                    } label: {
                        storyTile(
                            owner: owner,
                            title: owner.displayTitle,
                            seen: PlinkStorySeenLedger.shared.isSeen(owner),
                            mine: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(owner.displayTitle)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .overlay(alignment: .bottomLeading) {
            if store.storiesLoaded && owners.isEmpty {
                Text(LocalizationManager.shared.string(.frStoryEmpty))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(V4.muted)
                    .padding(.leading, 18 + tile + 14)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
            }
        }
    }

    private var mineTile: some View {
        let mine = store.myStory
        let hasStory = mine?.hasStory ?? false
        return Button {
            HapticManager.impact(.light)
            onMine(hasStory ? mine : nil)
        } label: {
            storyTile(
                owner: mine,
                title: LocalizationManager.shared.string(.frMyStory),
                seen: true,
                mine: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LocalizationManager.shared.string(.frMyStory))
    }

    private func storyTile(owner: FriendStoryOwner?, title: String, seen: Bool, mine: Bool) -> some View {
        VStack(spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                PlinkStoryRing(
                    accent: theme.accentColor,
                    state: (owner?.hasStory ?? false) ? (seen && !mine ? .seen : .fresh) : .none,
                    size: tile
                ) {
                    if let owner {
                        PlinkStableAvatar(
                            url: PlinkAvatarURL.stable(userId: owner.id, stored: owner.avatarURL),
                            letter: owner.initials,
                            size: tile - 10,
                            userId: owner.id
                        )
                    } else {
                        V4Avatar(letter: "", seed: "me", size: tile - 10)
                    }
                }
                if mine {
                    // Telegram's "+" — add or change the status from the tile.
                    Image(systemName: (owner?.hasStory ?? false) ? "pencil" : "plus")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(theme.accentColor, in: Circle())
                        .overlay(Circle().stroke(V4.surface, lineWidth: 2.5))
                        .offset(x: 2, y: 2)
                } else if owner?.isOnline == true {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(V4.surface, lineWidth: 2.5))
                        .offset(x: -1, y: -1)
                }
            }
            Text(title)
                .font(.system(size: 11.5, weight: seen && !mine ? .medium : .semibold))
                .foregroundStyle(seen && !mine ? V4.muted : V4.ink)
                .lineLimit(1)
                .frame(width: tile + 10)
        }
        .frame(width: tile + 10)
    }
}

/// Avatar in a story ring: gradient for unseen, thin grey for seen, nothing
/// when there is no story (own empty tile).
struct PlinkStoryRing<Content: View>: View {
    enum RingState { case none, fresh, seen }

    let accent: Color
    let state: RingState
    let size: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            switch state {
            case .fresh:
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [accent, accent.opacity(0.55), Color.white.opacity(0.9), accent],
                            center: .center
                        ),
                        lineWidth: 2.6
                    )
            case .seen:
                Circle().strokeBorder(V4.muted.opacity(0.45), lineWidth: 1.6)
            case .none:
                Circle().strokeBorder(V4.line, style: StrokeStyle(lineWidth: 1.4, dash: [4, 4]))
            }
            content
                .clipShape(Circle())
        }
        .frame(width: size, height: size)
    }
}
