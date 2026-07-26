// Plink/Features/Discovery/DiscoveryViewModel.swift — Home view model
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §3

import Foundation
import Observation

@MainActor
@Observable
final class DiscoveryViewModel {
    enum LoadState { case loading, loaded, empty, failed(String) }

    private(set) var state: LoadState = .loading
    private(set) var featured: [DiscoveryItem] = []
    private(set) var continueTogether: [ContinueItem] = []
    private(set) var liveRooms: [Room] = []
    private(set) var collections: [EditorialCollection] = []

    private let service: DiscoveryService

    init(service: DiscoveryService) {
        self.service = service
    }

    func load() async {
        state = .loading
        do {
            async let hero = service.featured()
            async let progress = service.continueTogether()
            async let rooms = service.liveRooms()
            async let curated = service.collections()
            (featured, continueTogether, liveRooms, collections) = try await (hero, progress, rooms, curated)
            state = featured.isEmpty && liveRooms.isEmpty ? .empty : .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
