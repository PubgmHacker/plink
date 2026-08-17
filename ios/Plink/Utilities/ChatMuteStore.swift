// ChatMuteStore.swift
// M22: Telegram-style per-chat mute state (persisted in UserDefaults)

import Foundation
import Combine

final class ChatMuteStore: ObservableObject {
    static let shared = ChatMuteStore()

    private let key = "plink_muted_chats_v1"
    @Published private var mutedIds: Set<String>

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        mutedIds = Set(saved)
    }

    func isMuted(_ id: String) -> Bool {
        mutedIds.contains(id)
    }

    func setMuted(_ id: String, muted: Bool) {
        if muted {
            mutedIds.insert(id)
        } else {
            mutedIds.remove(id)
        }
        UserDefaults.standard.set(Array(mutedIds), forKey: key)
    }

    func toggle(_ id: String) {
        setMuted(id, muted: !isMuted(id))
    }
}
