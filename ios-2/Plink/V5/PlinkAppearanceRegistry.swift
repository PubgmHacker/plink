//
//  PlinkAppearanceRegistry.swift
//  Plink
//
//  P1 — Appearance registry, store, and entitlement provider.
//  Implements Sections 2, 3, 4 of PLINK_CUSTOMIZATION_AUTH_ADMIN_SPEC_FOR_GLM_5_2.md
//

import SwiftUI
import Foundation

// MARK: - Color(hex: String) bridge
// V4 base only ships `Color(hex: UInt32)` in CinemaComponents.swift.
// V5 catalog stores colors as hex strings ("#0A0E27"). Add a String
// overload that parses the hex and delegates to the UInt32 initializer.
extension Color {
    init(hex string: String) {
        let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgbValue: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&rgbValue)
        // Clamp to 24-bit RGB — never trap on UInt32 conversion
        let clamped = UInt32(rgbValue & 0x00FF_FFFF)
        self.init(hex: clamped)
    }
}

// MARK: - AppearanceKind

internal enum AppearanceKind: String, Codable, Sendable {
    case appStatic
    case appLive
    case roomLive
    case bubbleStatic
    case bubbleAnimated
    case emojiPack
}

// MARK: - AppearanceDescriptor

internal struct AppearanceDescriptor: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let revision: Int
    let kind: AppearanceKind
    let title: String
    let subtitle: String
    let premium: Bool
    let previewAsset: String        // SF Symbol or bundled asset name (temporary)
    let previewColors: [String]    // hex strings for gradient swatch (temporary)
    let fallbackID: String?

    init(
        id: String,
        revision: Int = 1,
        kind: AppearanceKind,
        title: String,
        subtitle: String,
        premium: Bool,
        previewAsset: String,
        previewColors: [String],
        fallbackID: String? = nil
    ) {
        self.id = id
        self.revision = revision
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.premium = premium
        self.previewAsset = previewAsset
        self.previewColors = previewColors
        self.fallbackID = fallbackID
    }
}

// MARK: - AppearanceError

internal enum AppearanceError: LocalizedError, Sendable {
    case requiresPlinkPlus
    case hostRoomContextRequired
    case unknownDescriptor
    case persistenceFailed(reason: String)
    case backendRejected(reason: String)

    var errorDescription: String? {
        switch self {
        case .requiresPlinkPlus:            return "Доступно с Plink+"
        case .hostRoomContextRequired:      return "Тема комнаты выбирается только хостом."
        case .unknownDescriptor:            return "Неизвестный пресет."
        case .persistenceFailed(let r):     return "Не удалось сохранить: \(r)"
        case .backendRejected(let r):       return "Сервер отклонил: \(r)"
        }
    }
}

// MARK: - EntitlementProviding

/// Single source of truth for Plink+ status.
/// Do NOT reference `PremiumStatusManager.shared` from views directly.
internal protocol EntitlementProviding: AnyObject, Sendable {
    var isPlinkPlus: Bool { get }
    var plinkPlusExpiresAt: Date? { get }
    func refresh() async
}

@Observable
internal final class DefaultEntitlementProvider: EntitlementProviding {
    @MainActor private(set) var isPlinkPlus: Bool = false
    @MainActor private(set) var plinkPlusExpiresAt: Date?

    init() {}

    @MainActor
    func refresh() async {
        // Bridge to real PremiumStatusManager.
        let pm = PremiumStatusManager.shared
        self.isPlinkPlus = pm.isPremium
        self.plinkPlusExpiresAt = nil
    }
}

// MARK: - ProfileAPI

/// Backend facade for appearance persistence.
/// Real implementation calls `/api/profile/appearance` (PUT).
internal protocol ProfileAPI: Sendable {
    func updateAppearance(
        appThemeID: String,
        bubbleStyleID: String,
        emojiPackID: String
    ) async throws
    func fetchAppearance() async throws -> RemoteAppearance
}

internal struct RemoteAppearance: Codable, Sendable {
    let appThemeID: String
    let bubbleStyleID: String
    let emojiPackID: String
    init(appThemeID: String, bubbleStyleID: String, emojiPackID: String) {
        self.appThemeID = appThemeID
        self.bubbleStyleID = bubbleStyleID
        self.emojiPackID = emojiPackID
    }
}

/// Default impl bridges to real `AuthService` V5 extensions
/// (see `PlinkAuthBridge.swift`). Calls real `PUT /api/profile/appearance`
/// and `GET /api/profile/appearance`.
internal final class DefaultProfileAPI: ProfileAPI {
    init() {}

    func updateAppearance(
        appThemeID: String,
        bubbleStyleID: String,
        emojiPackID: String
    ) async throws {
        try await AuthService.shared.updateAppearance(
            appThemeID: appThemeID,
            bubbleStyleID: bubbleStyleID,
            emojiPackID: emojiPackID
        )
    }

    func fetchAppearance() async throws -> RemoteAppearance {
        let resp = try await AuthService.shared.fetchAppearance()
        return RemoteAppearance(
            appThemeID: resp.appThemeID,
            bubbleStyleID: resp.bubbleStyleID,
            emojiPackID: resp.emojiPackID
        )
    }
}

// MARK: - AppearanceStore

@MainActor
@Observable
internal final class AppearanceStore {
    private(set) var catalog: [AppearanceDescriptor] = []
    var appThemeID: String
    var bubbleStyleID: String
    var emojiPackID: String

    private(set) var isCommitting: Bool = false
    private(set) var lastError: AppearanceError?

    private let entitlement: EntitlementProviding
    private let profileAPI: ProfileAPI
    private let defaults: UserDefaults

    init(
        entitlement: EntitlementProviding,
        profileAPI: ProfileAPI = DefaultProfileAPI(),
        defaults: UserDefaults = .standard
    ) {
        self.entitlement = entitlement
        self.profileAPI = profileAPI
        self.defaults = defaults

        // Local-first restore for instant launch.
        self.appThemeID = defaults.string(forKey: "plink.appThemeID") ?? AppearanceCatalog.defaultAppThemeID
        self.bubbleStyleID = defaults.string(forKey: "plink.bubbleStyleID") ?? AppearanceCatalog.defaultBubbleStyleID
        self.emojiPackID = defaults.string(forKey: "plink.emojiPackID") ?? AppearanceCatalog.defaultEmojiPackID

        self.catalog = AppearanceCatalog.all
    }

    // MARK: - Catalog queries

    func items(of kind: AppearanceKind) -> [AppearanceDescriptor] {
        catalog.filter { $0.kind == kind }
    }

    func descriptor(id: String) -> AppearanceDescriptor? {
        catalog.first { $0.id == id }
    }

    func currentAppTheme() -> AppearanceDescriptor? {
        descriptor(id: appThemeID) ?? descriptor(id: AppearanceCatalog.defaultAppThemeID)
    }

    // MARK: - Select

    func select(_ item: AppearanceDescriptor) async {
        guard !item.premium || entitlement.isPlinkPlus else {
            lastError = .requiresPlinkPlus
            return
        }

        switch item.kind {
        case .appStatic, .appLive:
            appThemeID = item.id
        case .bubbleStatic, .bubbleAnimated:
            bubbleStyleID = item.id
        case .emojiPack:
            emojiPackID = item.id
        case .roomLive:
            lastError = .hostRoomContextRequired
            return
        }

        persistLocallyImmediately()

        isCommitting = true
        defer { isCommitting = false }
        do {
            try await profileAPI.updateAppearance(
                appThemeID: appThemeID,
                bubbleStyleID: bubbleStyleID,
                emojiPackID: emojiPackID
            )
            lastError = nil
        } catch {
            lastError = .backendRejected(reason: error.localizedDescription)
            // Local change is kept; backend sync retried on next heartbeat.
        }
    }

    // MARK: - Pull from backend (cross-device restore)

    func restoreFromBackend() async {
        guard let remote = try? await profileAPI.fetchAppearance() else { return }
        if catalog.contains(where: { $0.id == remote.appThemeID }) {
            appThemeID = remote.appThemeID
        } else {
            appThemeID = AppearanceCatalog.defaultAppThemeID
        }
        if catalog.contains(where: { $0.id == remote.bubbleStyleID }) {
            bubbleStyleID = remote.bubbleStyleID
        } else {
            bubbleStyleID = AppearanceCatalog.defaultBubbleStyleID
        }
        if catalog.contains(where: { $0.id == remote.emojiPackID }) {
            emojiPackID = remote.emojiPackID
        } else {
            emojiPackID = AppearanceCatalog.defaultEmojiPackID
        }
        persistLocallyImmediately()
    }

    // MARK: - Plink+ expiry rollback

    /// Called when entitlement expires. Locked selections are reverted to
    /// their fallback so the user never sees a "broken" profile.
    func handleEntitlementExpiry() {
        if let d = descriptor(id: appThemeID), d.premium {
            appThemeID = d.fallbackID ?? AppearanceCatalog.defaultAppThemeID
            persistLocallyImmediately()
        }
        if let d = descriptor(id: bubbleStyleID), d.premium {
            bubbleStyleID = d.fallbackID ?? AppearanceCatalog.defaultBubbleStyleID
            persistLocallyImmediately()
        }
        if let d = descriptor(id: emojiPackID), d.premium {
            emojiPackID = d.fallbackID ?? AppearanceCatalog.defaultEmojiPackID
            persistLocallyImmediately()
        }
    }

    // MARK: - Persistence

    private func persistLocallyImmediately() {
        defaults.set(appThemeID, forKey: "plink.appThemeID")
        defaults.set(bubbleStyleID, forKey: "plink.bubbleStyleID")
        defaults.set(emojiPackID, forKey: "plink.emojiPackID")
    }
}

// MARK: - AppearanceCatalog

/// Temporary catalog using built-in SF Symbols + hex colors as placeholders
/// until approved Rive/Lottie assets arrive. Replacing assets does NOT require
/// touching `AppearanceStore` or any view code — only this enum.
internal enum AppearanceCatalog {
    static let defaultAppThemeID = "electric-static"
    static let defaultBubbleStyleID = "bubble-quiet"
    static let defaultEmojiPackID = "system-unicode"

    static let all: [AppearanceDescriptor] = appStatic + appLive + roomLive + bubbleStatic + bubbleAnimated + emojiPack

    // 2 free app themes
    static let appStatic: [AppearanceDescriptor] = [
        .init(
            id: "electric-static", kind: .appStatic,
            title: "Electric", subtitle: "Тёмно-синий V4",
            premium: false,
            previewAsset: "circle.hexagonpath.fill",
            previewColors: ["#0A0E27", "#1E2A5E", "#00D4FF"]
        ),
        .init(
            id: "plink-static", kind: .appStatic,
            title: "Plink", subtitle: "Бирюзовый V4",
            premium: false,
            previewAsset: "drop.fill",
            previewColors: ["#06231F", "#0F4D45", "#3FE8C8"]
        ),
    ]

    // 5 Plink+ live app themes
    static let appLive: [AppearanceDescriptor] = [
        .init(
            id: "afterglow-live", kind: .appLive,
            title: "Afterglow", subtitle: "Северное свечение",
            premium: true, previewAsset: "sparkles",
            previewColors: ["#0A0E27", "#00D4FF", "#7DD3FC"],
            fallbackID: "electric-static"
        ),
        .init(
            id: "ember-live", kind: .appLive,
            title: "Ember", subtitle: "Свет проектора",
            premium: true, previewAsset: "flame.fill",
            previewColors: ["#1A1410", "#FF8A3D", "#F5C26B"],
            fallbackID: "electric-static"
        ),
        .init(
            id: "violet-live", kind: .appLive,
            title: "Violet", subtitle: "Текучие лепестки",
            premium: true, previewAsset: "moon.stars.fill",
            previewColors: ["#160B2A", "#A855F7", "#F0ABFC"],
            fallbackID: "electric-static"
        ),
        .init(
            id: "tide-live", kind: .appLive,
            title: "Tide", subtitle: "Волновой параллакс",
            premium: true, previewAsset: "water.waves",
            previewColors: ["#04212F", "#0891B2", "#22D3EE"],
            fallbackID: "plink-static"
        ),
        .init(
            id: "bloom-live", kind: .appLive,
            title: "Bloom", subtitle: "Дыхание облаков",
            premium: true, previewAsset: "circle.dashed.inset.filled",
            previewColors: ["#2A0B1F", "#F472B6", "#FBCFE8"],
            fallbackID: "plink-static"
        ),
    ]

    // 5 Plink+ room themes
    static let roomLive: [AppearanceDescriptor] = [
        .init(id: "room-cinema-dust", kind: .roomLive,
              title: "Cinema Dust", subtitle: "Холодный кинозал",
              premium: true, previewAsset: "film.stack.fill",
              previewColors: ["#0A0E1A", "#5B6B8C", "#A0AEC0"]),
        .init(id: "room-neon-rain", kind: .roomLive,
              title: "Neon Rain", subtitle: "Вертикальные следы",
              premium: true, previewAsset: "cloud.rain.fill",
              previewColors: ["#0A0E27", "#A855F7", "#22D3EE"]),
        .init(id: "room-aurora", kind: .roomLive,
              title: "Aurora", subtitle: "Медленные ленты",
              premium: true, previewAsset: "waveform.path.ecg",
              previewColors: ["#04141A", "#10B981", "#A7F3D0"]),
        .init(id: "room-deep-sea", kind: .roomLive,
              title: "Deep Sea", subtitle: "Caustics",
              premium: true, previewAsset: "tortoise.fill",
              previewColors: ["#021318", "#0E7490", "#67E8F9"]),
        .init(id: "room-afterparty", kind: .roomLive,
              title: "Afterparty", subtitle: "Defocused spots",
              premium: true, previewAsset: "light.beacon.max.fill",
              previewColors: ["#1A0B14", "#EC4899", "#FDE68A"]),
    ]

    // M16: Free tier — exactly two standard bubbles
    static let bubbleStatic: [AppearanceDescriptor] = [
        .init(id: "bubble-quiet", kind: .bubbleStatic,
              title: "Тихий", subtitle: "Стеклянная капсула",
              premium: false, previewAsset: "circle.fill",
              previewColors: ["#1A1F3A", "#2A2F4E"]),
        .init(id: "bubble-accent", kind: .bubbleStatic,
              title: "Неон", subtitle: "Акцент Plink",
              premium: false, previewAsset: "circle.fill",
              previewColors: ["#00D4FF", "#3FE8C8"]),
    ]

    // M16: Plink+ — 5 детальных кино-баблов (pixel-perfect PNG из арт-референса,
    // Resources/CinemaBubbles/). Заменяют старые «животные» рамки целиком.
    static let bubbleAnimated: [AppearanceDescriptor] = [
        .init(id: "bubble-cine-artdeco", kind: .bubbleAnimated,
              title: "Арт-деко", subtitle: "Золото на бархате",
              premium: true, previewAsset: "building.columns.fill",
              previewColors: ["#5A0E14", "#D4A24C"], fallbackID: "bubble-quiet"),
        .init(id: "bubble-cine-filmreel", kind: .bubbleAnimated,
              title: "Киноплёнка", subtitle: "Бобины и кадры",
              premium: true, previewAsset: "film.fill",
              previewColors: ["#6E7681", "#B8C0CC"], fallbackID: "bubble-quiet"),
        .init(id: "bubble-cine-marquee", kind: .bubbleAnimated,
              title: "Афиша", subtitle: "Лампы кинотеатра",
              premium: true, previewAsset: "lightbulb.fill",
              previewColors: ["#2A2450", "#FFC65C"], fallbackID: "bubble-quiet"),
        .init(id: "bubble-cine-vippass", kind: .bubbleAnimated,
              title: "VIP Pass", subtitle: "Золотой билет",
              premium: true, previewAsset: "ticket.fill",
              previewColors: ["#8A6014", "#F5D77A"], fallbackID: "bubble-accent"),
        .init(id: "bubble-cine-noir", kind: .bubbleAnimated,
              title: "Film Noir", subtitle: "Серебряный город",
              premium: true, previewAsset: "moon.fill",
              previewColors: ["#23262E", "#C9D1DC"], fallbackID: "bubble-quiet"),
    ]

    // Emoji packs
    static let emojiPack: [AppearanceDescriptor] = [
        .init(id: "system-unicode", kind: .emojiPack,
              title: "Системные", subtitle: "Apple Unicode",
              premium: false, previewAsset: "face.smiling",
              previewColors: ["#FBBF24", "#F59E0B"]),
        .init(id: "plink-orbit", kind: .emojiPack,
              title: "Plink Orbit", subtitle: "Эмоции вокруг Plink Orb",
              premium: true, previewAsset: "circle.grid.3x3.fill",
              previewColors: ["#3FE8C8", "#00D4FF"], fallbackID: "system-unicode"),
        .init(id: "plink-cinema", kind: .emojiPack,
              title: "Cinema", subtitle: "Popcorn, projector, clapboard",
              premium: true, previewAsset: "popcorn.fill",
              previewColors: ["#F59E0B", "#FDE68A"], fallbackID: "system-unicode"),
        .init(id: "plink-reactions", kind: .emojiPack,
              title: "Reactions", subtitle: "Wow, laugh, cry, rage, heart",
              premium: true, previewAsset: "heart.fill",
              previewColors: ["#EC4899", "#F472B6"], fallbackID: "system-unicode"),
        .init(id: "plink-night", kind: .emojiPack,
              title: "Night", subtitle: "Moon, neon eye, ghost",
              premium: true, previewAsset: "moon.stars.fill",
              previewColors: ["#A855F7", "#1E1B4B"], fallbackID: "system-unicode"),
        .init(id: "plink-signal", kind: .emojiPack,
              title: "Signal", subtitle: "Sync, buffering, host crown",
              premium: true, previewAsset: "crown.fill",
              previewColors: ["#22D3EE", "#0E7490"], fallbackID: "system-unicode"),
    ]
}
