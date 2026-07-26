import Foundation
import Observation

// MARK: - Friend pin order (Telegram-style)
/// Keeps pinned friend IDs in stable order. Local cache syncs with server when online.
@MainActor
@Observable
final class FriendPinStore {
    static let shared = FriendPinStore()

    /// Ordered pin list — index 0 is top of the pinned section.
    private(set) var orderedPinnedIds: [String] = []

    private let defaultsKey = "plink.friend_pins.v1"
    private let maxPins = 10

    private init() {
        load()
    }

    func isPinned(_ friendId: String) -> Bool {
        orderedPinnedIds.contains(friendId)
    }

    /// Pin order rank (0 = top). nil if not pinned.
    func pinRank(_ friendId: String) -> Int? {
        orderedPinnedIds.firstIndex(of: friendId)
    }

    @discardableResult
    func pin(_ friendId: String) -> Bool {
        guard !friendId.isEmpty else { return false }
        if let idx = orderedPinnedIds.firstIndex(of: friendId) {
            // Already pinned — move to top
            orderedPinnedIds.remove(at: idx)
            orderedPinnedIds.insert(friendId, at: 0)
            persist()
            return true
        }
        guard orderedPinnedIds.count < maxPins else { return false }
        orderedPinnedIds.insert(friendId, at: 0)
        persist()
        return true
    }

    func unpin(_ friendId: String) {
        orderedPinnedIds.removeAll { $0 == friendId }
        persist()
    }

    func toggle(_ friendId: String) -> Bool {
        if isPinned(friendId) {
            unpin(friendId)
            return false
        }
        return pin(friendId)
    }

    /// Merge server pin flags (isPinned + pinOrder) without dropping local-only pins.
    func mergeFromServer(_ friends: [Friend]) {
        let serverPinned = friends
            .filter { $0.isPinned == true }
            .sorted { ($0.pinOrder ?? 0) < ($1.pinOrder ?? 0) }
            .map(\.id)
        guard !serverPinned.isEmpty || friends.contains(where: { $0.isPinned != nil }) else {
            return
        }
        // Prefer server order when any pin metadata is present
        if friends.contains(where: { $0.isPinned == true }) {
            orderedPinnedIds = serverPinned
            persist()
        }
    }

    /// Apply pins from a list of IDs (e.g. after full server sync).
    func replaceAll(_ ids: [String]) {
        var seen = Set<String>()
        orderedPinnedIds = ids.filter { id in
            guard !id.isEmpty, !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }.prefix(maxPins).map { $0 }
        persist()
    }

    // MARK: - Sort (Telegram)

    /// Pinned first (stable pin order), then unpinned by last activity desc.
    func sortedChats(
        friends: [Friend],
        lastActivity: (String) -> Date?,
        unread: (String) -> Int
    ) -> [Friend] {
        let pinnedSet = Set(orderedPinnedIds)
        let pinned = orderedPinnedIds.compactMap { id in friends.first { $0.id == id } }
        let unpinned = friends
            .filter { !pinnedSet.contains($0.id) }
            .sorted { a, b in
                let ta = lastActivity(a.id) ?? .distantPast
                let tb = lastActivity(b.id) ?? .distantPast
                if ta != tb { return ta > tb }
                // Tie-break: unread first, then name
                let ua = unread(a.id)
                let ub = unread(b.id)
                if ua != ub { return ua > ub }
                return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedAscending
            }
        return pinned + unpinned
    }

    // MARK: - Persistence

    private func load() {
        orderedPinnedIds = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }

    private func persist() {
        UserDefaults.standard.set(orderedPinnedIds, forKey: defaultsKey)
    }
}
