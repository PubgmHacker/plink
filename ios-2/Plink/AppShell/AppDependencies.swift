// Plink/AppShell/AppDependencies.swift — Dependency injection container
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §2: AppDependencies wraps existing services.
// Does NOT create new singletons — just bundles existing ones for the shell.

import Foundation

@MainActor
final class AppDependencies {
    let apiClient: APIClient
    let authService: AuthService
    let roomService: RoomService
    let mediaService: MediaService
    let discoveryService: DiscoveryService
    let premiumStatusManager: PremiumStatusManager
    let friendManager: FriendManager?
    let dmChatService: DMChatService?

    init(
        apiClient: APIClient,
        authService: AuthService,
        roomService: RoomService,
        mediaService: MediaService? = nil,
        discoveryService: DiscoveryService? = nil,
        premiumStatusManager: PremiumStatusManager? = nil,
        friendManager: FriendManager? = nil,
        dmChatService: DMChatService? = nil
    ) {
        self.apiClient = apiClient
        self.authService = authService
        self.roomService = roomService
        self.mediaService = mediaService ?? MediaService()
        self.discoveryService = discoveryService ?? DiscoveryService(apiClient: apiClient, roomService: roomService)
        self.premiumStatusManager = premiumStatusManager ?? PremiumStatusManager.shared
        self.friendManager = friendManager
        self.dmChatService = dmChatService
    }

    /// Live dependencies wired from existing app state.
    @MainActor
    static var live: AppDependencies {
        let apiClient = APIClient.shared
        let authService = AuthService.shared
        let roomService = RoomService(api: apiClient)
        return AppDependencies(
            apiClient: apiClient,
            authService: authService,
            roomService: roomService
        )
    }
}
