// Plink/AppShell/AppSection.swift — GPT-5.6 Approved Patch §3
//
// Canonical tab architecture: Home, Rooms, AI, Friends, Profile.
// AI stays because it is a domain-specific watch-party companion.
// Create is a persistent action on Home/Rooms, not a sixth tab.

import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case home, rooms, ai, friends, profile

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Главная"
        case .rooms: "Комнаты"
        case .ai: "ИИ"
        case .friends: "Друзья"
        case .profile: "Профиль"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .rooms: "play.rectangle.on.rectangle.fill"
        case .ai: "sparkles"
        case .friends: "person.2.fill"
        case .profile: "person.crop.circle.fill"
        }
    }

    // Back-compat aliases
    var symbol: String { icon }
}
