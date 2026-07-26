// Plink/AppShell/PlinkPhoneTabShell.swift — Cinema2026 unified phone shell
//
// 5 tabs: Home (Discovery) · Rooms · AI · Friends · Profile
// Home uses DiscoveryHomeView with HeroVideoCarousel (3 video banners).
// Profile uses ProfileView (Apple ID style with rotating gradient ring).
// Room creation uses RoomCreationView (service selection + trending).

import SwiftUI

struct PlinkPhoneTabShell: View {
    @Binding var selection: AppSection
    @Binding var createPresented: Bool
    let dependencies: AppDependencies

    @State private var navigateToRoom: Room?

    var body: some View {
        TabView(selection: $selection) {
            // ── Главная — Discovery home with HeroVideoCarousel ──
            NavigationStack {
                DiscoveryHomeView(dependencies: dependencies)
                    .fullScreenCover(item: $navigateToRoom) { room in
                        watchRoom(for: room)
                    }
            }
            .tag(AppSection.home)
            .tabItem { Label(AppSection.home.title, systemImage: AppSection.home.symbol) }

            // ── Комнаты — active rooms list ──
            NavigationStack {
                VStack { Text("Комнаты").font(.title) }
                    .fullScreenCover(item: $navigateToRoom) { room in
                        watchRoom(for: room)
                    }
            }
            .tag(AppSection.rooms)
            .tabItem { Label(AppSection.rooms.title, systemImage: AppSection.rooms.symbol) }

            // ── AI Companion ──
            NavigationStack {
                AIAssistantView()
            }
            .tag(AppSection.ai)
            .tabItem { Label(AppSection.ai.title, systemImage: AppSection.ai.symbol) }

            // ── Друзья ──
            NavigationStack {
                FriendsView()
            }
            .tag(AppSection.friends)
            .tabItem { Label(AppSection.friends.title, systemImage: AppSection.friends.symbol) }

            // ── Профиль — Apple ID style with rotating gradient ring ──
            NavigationStack {
                ProfileView(
                    viewModel: ProfileViewModel(
                        authService: dependencies.authService
                    ),
                    onSignOut: {
                        Task {
                            try? await dependencies.authService.signOut()
                            NotificationCenter.default.post(name: .plinkSignedOut, object: nil)
                        }
                    }
                )
            }
            .tag(AppSection.profile)
            .tabItem { Label("Профиль", systemImage: "person.circle.fill") }
        }
        .tint(Cinema2026.accent)
        .toolbarBackground(Cinema2026.background.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .environmentObject(dependencies.apiClient)
        .environmentObject(dependencies.friendManager ?? FriendManager(api: dependencies.apiClient))
        .environmentObject(dependencies.dmChatService ?? DMChatService(api: dependencies.apiClient))
    }

    // MARK: - Watch Room

    @ViewBuilder
    private func watchRoom(for room: Room) -> some View {
        // Hydrates plink_current_user_id / token — never empty plink_user_id keys
        WatchRoomContainer(room: room)
    }
}
