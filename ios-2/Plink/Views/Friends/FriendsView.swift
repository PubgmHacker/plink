import SwiftUI

// MARK: - Friends View (Блок 3 — система друзей)
/// Экран управления друзьями: список друзей, входящие/исходящие заявки,
/// поиск пользователей для добавления.
struct FriendsView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var friendManager = FriendManager(api: APIClient.shared)
    @State private var selectedTab: FriendsTab = .friends
    @State private var searchText = ""
    @State private var showShareSheet = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Cinema2026.background

                VStack(spacing: 0) {
                    // Табы: Друзья / Входящие / Поиск
                    tabSelector

                    // Контент по табу
                    switch selectedTab {
                    case .friends:
                        friendsListTab
                    case .requests:
                        requestsTab
                    case .search:
                        searchTab
                    }

                    Spacer(minLength: 0)
                }
            }
            .navigationTitle(loc.string(.friendsTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.ravePrimary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showShareSheet = true } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                    }
                    .foregroundColor(.raveAccent)
                }
            }
            .preferredColorScheme(.dark)
        }
        // ── Sheet: поделиться ссылкой-приглашением ────────────────
        .sheet(isPresented: $showShareSheet) {
            VStack { }
                .onAppear {
                    ShareManager.shareRoom(
                        roomID: "current_user",
                        code: nil,
                        roomName: "Добавить в друзья",
                        onCopied: { showShareSheet = false }
                    )
                }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 8) {
            ForEach(FriendsTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(tab.title)
                            .font(.caption.bold())
                        if let badge = tab.badge(for: friendManager), badge > 0 {
                            Text("\(badge)")
                                .font(.caption2.bold().monospacedDigit())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.raveAccent)
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundColor(selectedTab == tab ? .white : .raveTextSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(selectedTab == tab ? AnyShapeStyle(Color.ravePrimary) : AnyShapeStyle(Color.raveCard))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Friends List Tab

    private var friendsListTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if friendManager.friends.isEmpty {
                    emptyState(
                        icon: "person.2",
                        title: loc.string(.friendsNoFriends),
                        subtitle: loc.string(.friendsNoFriendsHint)
                    )
                } else {
                    ForEach(friendManager.friends) { friend in
                        FriendRow(friend: friend) {
                            Task { await friendManager.removeFriend(friend) }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    // MARK: - Requests Tab

    private var requestsTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Входящие
                if !friendManager.incomingRequests.isEmpty {
                    sectionHeader(loc.string(.friendsIncoming))
                    ForEach(friendManager.incomingRequests) { request in
                        IncomingRequestRow(request: request) {
                            Task { await friendManager.acceptRequest(request) }
                        } onDecline: {
                            Task { await friendManager.declineRequest(request) }
                        }
                    }
                }

                // Исходящие
                if !friendManager.outgoingRequests.isEmpty {
                    sectionHeader(loc.string(.friendsOutgoing))
                    ForEach(friendManager.outgoingRequests) { request in
                        OutgoingRequestRow(request: request)
                    }
                }

                if friendManager.incomingRequests.isEmpty && friendManager.outgoingRequests.isEmpty {
                    emptyState(
                        icon: "envelope.open",
                        title: loc.string(.friendsNoRequests),
                        subtitle: loc.string(.friendsNoRequestsHint)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    // MARK: - Search Tab

    private var searchTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.raveTextSecondary)
                TextField(loc.string(.friendsSearchPlaceholder), text: $searchText)
                    .foregroundColor(.raveTextPrimary)
                    .onChange(of: searchText) { _, newValue in
                        Task { await friendManager.searchUsers(query: newValue) }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.raveCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(friendManager.searchResults) { user in
                        UserSearchRow(
                            user: user,
                            isAlreadyFriend: friendManager.isFriend(user.id),
                            hasPendingRequest: friendManager.hasOutgoingRequest(to: user.id)
                        ) {
                            Task { await friendManager.sendRequest(to: user.id, username: user.username) }
                        }
                    }

                    if friendManager.searchResults.isEmpty && !searchText.isEmpty {
                        emptyState(
                            icon: "person.magnifyingglass",
                            title: loc.string(.friendsNoResults),
                            subtitle: loc.string(.friendsNoResultsHint)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundColor(.raveTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 40)
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.raveTextTertiary)
            Text(title)
                .font(.headline)
                .foregroundColor(.raveTextPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.raveTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }
}

// MARK: - Tabs Enum
enum FriendsTab: String, CaseIterable, Identifiable {
    case friends
    case requests
    case search

    var id: String { rawValue }

    @MainActor
    var title: String {
        let l = LocalizationManager.shared
        switch self {
        case .friends: return l.string(.friendsTab)
        case .requests: return l.string(.friendsRequests)
        case .search: return l.string(.friendsSearch)
        }
    }

    @MainActor
    func badge(for manager: FriendManager) -> Int? {
        switch self {
        case .requests: return manager.incomingRequests.count
        default: return nil
        }
    }
}

// MARK: - Friend Row
private struct FriendRow: View {
    @ObservedObject private var loc = LocalizationManager.shared
    let friend: Friend
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            avatar(friend)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayTitle)
                    .font(.subheadline.bold())
                    .foregroundColor(.raveTextPrimary)
                HStack(spacing: 4) {
                    if friend.deleted {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(.system(size: 10))
                            .foregroundColor(.raveTextTertiary)
                        Text("аккаунт удалён")
                            .font(.caption)
                            .foregroundColor(.raveTextSecondary)
                    } else {
                        Circle()
                            .fill(friend.isOnline ? Color.raveGreen : Color.raveTextTertiary)
                            .frame(width: 6, height: 6)
                            .scaleEffect(friend.isOnline ? 1.0 : 1.0)
                            .animation(
                                friend.isOnline
                                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                    : .default,
                                value: friend.isOnline
                            )
                        Text(friend.isOnline ? loc.string(.friendsOnline) : loc.string(.friendsOffline))
                            .font(.caption)
                            .foregroundColor(.raveTextSecondary)
                    }
                }
            }
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "person.fill.xmark")
                    .font(.subheadline)
                    .foregroundColor(.raveDanger)
                    .frame(width: 34, height: 34)
                    .background(Color.raveCard)
                    .clipShape(Circle())
            }
        }
        .padding(12)
        .background(Color.raveCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func avatar(_ friend: Friend) -> some View {
        Group {
            if friend.deleted {
                PlinkDeletedAvatar(size: 44)
            } else if let url = PlinkAvatarURL.resolve(userId: friend.id, stored: friend.avatarURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private var fallback: some View {
        Text(friend.initials)
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.ravePrimary)
    }
}

// MARK: - Incoming Request Row
private struct IncomingRequestRow: View {
    @ObservedObject private var loc = LocalizationManager.shared
    let request: FriendRequest
    var onAccept: () -> Void
    var onDecline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(request.fromUser.username.prefix(1).uppercased())
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.ravePrimary)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(request.fromUser.username)
                    .font(.subheadline.bold())
                    .foregroundColor(.raveTextPrimary)
                Text(loc.string(.friendsWantsToAdd))
                    .font(.caption)
                    .foregroundColor(.raveTextSecondary)
            }

            Spacer()

            Button(action: onAccept) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.raveGreen)
            }

            Button(action: onDecline) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.raveDanger)
            }
        }
        .padding(12)
        .background(Color.raveCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Outgoing Request Row
private struct OutgoingRequestRow: View {
    @ObservedObject private var loc = LocalizationManager.shared
    let request: FriendRequest

    var body: some View {
        HStack(spacing: 12) {
            Text(request.toUser.username.prefix(1).uppercased())
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.raveSurface)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(request.toUser.username)
                    .font(.subheadline.bold())
                    .foregroundColor(.raveTextPrimary)
                Text("\(loc.string(.friendsWaiting)) · \(request.formattedDate)")
                    .font(.caption)
                    .foregroundColor(.raveTextSecondary)
            }

            Spacer()

            PulsingDot(color: .raveWarning)
                .frame(width: 8, height: 8)
        }
        .padding(12)
        .background(Color.raveCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - User Search Row
private struct UserSearchRow: View {
    @ObservedObject private var loc = LocalizationManager.shared
    let user: UserPreview
    let isAlreadyFriend: Bool
    let hasPendingRequest: Bool
    var onSendRequest: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(user.username.prefix(1).uppercased())
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.ravePrimary)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.username)
                        .font(.subheadline.bold())
                        .foregroundColor(.raveTextPrimary)
                    // 🔧 NEW: Show short ID next to username in search results
                    Text("#\(String(user.id.suffix(8)))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.raveTextTertiary)
                }
                Text(user.isOnline ? loc.string(.friendsOnline) : loc.string(.friendsOffline))
                    .font(.caption)
                    .foregroundColor(.raveTextSecondary)
            }

            Spacer()

            if isAlreadyFriend {
                Text(loc.string(.friendsAlreadyFriends))
                    .font(.caption.bold())
                    .foregroundColor(.raveGreen)
            } else if hasPendingRequest {
                Text(loc.string(.friendsSent))
                    .font(.caption)
                    .foregroundColor(.raveTextSecondary)
            } else {
                Button(action: onSendRequest) {
                    Image(systemName: "person.badge.plus")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.ravePrimary)
                        .clipShape(Circle())
                }
            }
        }
        .padding(12)
        .background(Color.raveCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
