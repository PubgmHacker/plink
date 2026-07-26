import Foundation
import SwiftUI

// MARK: - Premium Status Manager (Блок 3)
/// Управляет премиум-статусом пользователя: подписка, кастомизация,
/// проверка доступа к премиум-фичам (4K, темы, стили ника, рамки аватара).

@MainActor
final class PremiumStatusManager: ObservableObject {

    static let shared = PremiumStatusManager()

    // MARK: - Published State

    @Published private(set) var isPremium: Bool = false
    @Published private(set) var subscriptionExpiry: Date?
    @Published var selectedNickStyle: NickStyle = .default
    @Published var selectedAvatarBorder: AvatarBorder = .none
    @Published var selectedRoomTheme: RoomTheme = .default

    // MARK: - Persistence

    private let defaults = UserDefaults.standard
    private let premiumKey = "rave_user_is_premium"
    private let expiryKey = "rave_premium_expiry"
    private let nickStyleKey = "rave_nick_style"
    private let avatarBorderKey = "rave_avatar_border"
    private let roomThemeKey = "rave_room_theme"

    // MARK: - Callbacks

    /// Вызывается при изменении премиум-статуса (для обновления WS-состояния).
    var onPremiumStatusChanged: ((Bool) -> Void)?

    // MARK: - Init

    init() {
        loadPersistedState()
    }

    // MARK: - Premium Activation (от StoreKit 2)

    /// 🔧 FIX C9: This is the ONLY public entry point for activating premium.
    /// Called from StoreManager.handleSuccessfulPurchase after server-side IAP verification.
    func activatePremium(expiryDate: Date) {
        isPremium = true
        subscriptionExpiry = expiryDate
        persist()
        onPremiumStatusChanged?(true)
    }

    /// PATCH 08: Activate lifetime premium (non-consumable purchase).
    /// No expiry date — entitlement persists forever.
    func activateLifetime() {
        isPremium = true
        subscriptionExpiry = nil  // nil expiry = lifetime
        persist()
        onPremiumStatusChanged?(true)
    }

    func deactivatePremium() {
        isPremium = false
        subscriptionExpiry = nil
        selectedNickStyle = .default
        selectedAvatarBorder = .none
        selectedRoomTheme = .default
        persist()
        onPremiumStatusChanged?(false)
    }

    // 🔧 FIX C9: REMOVED setPremium(_:) — it allowed trivial IAP bypass.
    // Premium can only be activated via activatePremium(expiryDate:) which
    // is called from StoreManager.handleSuccessfulPurchase after server-side
    // IAP verification. Local UserDefaults flag is now a hint, not authority.

    /// 🔧 FIX C9+M6: Update premium status from server response (User.isPremium).
    /// Called after AuthService.signIn/signUp/getFreshToken resolves the user.
    /// This is the authoritative source — server decision overrides any local cache.
    func syncFromServer(isPremium serverIsPremium: Bool, expiry: Date?) {
        serverConfirmed = true
        if serverIsPremium {
            if isPremium != true || subscriptionExpiry != expiry {
                isPremium = true
                subscriptionExpiry = expiry
                persist()
                onPremiumStatusChanged?(true)
            }
        } else {
            if isPremium == true {
                deactivatePremium()
            }
        }
    }

    // MARK: - Feature Access Checks

    var canSelect4K: Bool { isPremium }
    var hasAdShield: Bool { isPremium }
    var canCustomizeRoomTheme: Bool { isPremium }
    var canCustomizeNick: Bool { isPremium }
    var canCustomizeAvatar: Bool { isPremium }

    // MARK: - Customization Setters

    func setNickStyle(_ style: NickStyle) {
        guard isPremium else { return }
        selectedNickStyle = style
        defaults.set(style.rawValue, forKey: nickStyleKey)
    }

    func setAvatarBorder(_ border: AvatarBorder) {
        guard isPremium else { return }
        selectedAvatarBorder = border
        defaults.set(border.rawValue, forKey: avatarBorderKey)
    }

    func setRoomTheme(_ theme: RoomTheme) {
        // Free: only default room theme. Plink+ unlocks the rest.
        if theme != .default && !isPremium {
            return
        }
        selectedRoomTheme = theme
        defaults.set(theme.rawValue, forKey: roomThemeKey)
    }

    /// True if this bubble style id is free for everyone.
    static func isFreeBubbleStyle(_ id: String) -> Bool {
        switch id {
        // M16: бесплатны только два базовых стиля; кино-баблы — Plink+
        case "bubble-quiet", "bubble-accent", "default":
            return true
        default:
            return false
        }
    }

    /// True if this room theme is free.
    static func isFreeRoomTheme(_ theme: RoomTheme) -> Bool {
        theme == .default
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(isPremium, forKey: premiumKey)
        defaults.set(subscriptionExpiry, forKey: expiryKey)
        defaults.set(selectedNickStyle.rawValue, forKey: nickStyleKey)
        defaults.set(selectedAvatarBorder.rawValue, forKey: avatarBorderKey)
        defaults.set(selectedRoomTheme.rawValue, forKey: roomThemeKey)
    }

    /// 🔧 FIX 3.4: Track whether server has confirmed premium status
    private var serverConfirmed = false

    private func loadPersistedState() {
        // C9: local UserDefaults is NOT authority. Always start free until
        // server (syncFromServer) or StoreKit confirms purchase. Prevents
        // sticky "Plink+ active" after testing / stale flags on other devices.
        let cachedPremium = defaults.bool(forKey: premiumKey)
        isPremium = false
        subscriptionExpiry = defaults.object(forKey: expiryKey) as? Date
        serverConfirmed = false
        if cachedPremium {
            Logger.store.info("[Premium] ignored stale local premium flag until server/StoreKit confirms")
        }

        if let nickRaw = defaults.string(forKey: nickStyleKey),
           let style = NickStyle(rawValue: nickRaw) {
            selectedNickStyle = style
        }
        if let borderRaw = defaults.string(forKey: avatarBorderKey),
           let border = AvatarBorder(rawValue: borderRaw) {
            selectedAvatarBorder = border
        }
        if let themeRaw = defaults.string(forKey: roomThemeKey),
           let theme = RoomTheme(rawValue: themeRaw) {
            selectedRoomTheme = theme
        }

        // Clamp premium-only cosmetics while free
        if !isPremium {
            if selectedRoomTheme != .default {
                selectedRoomTheme = .default
                defaults.set(RoomTheme.default.rawValue, forKey: roomThemeKey)
            }
            let bubble = UserDefaults.standard.string(forKey: "plink.bubbleStyleID") ?? "bubble-quiet"
            if !Self.isFreeBubbleStyle(bubble) {
                UserDefaults.standard.set("bubble-quiet", forKey: "plink.bubbleStyleID")
            }
            // Clear Plink+ live theme overlay
            if UserDefaults.standard.integer(forKey: "plink.liveTheme") > 0 {
                UserDefaults.standard.set(0, forKey: "plink.liveTheme")
                NotificationCenter.default.post(name: .plinkLiveThemeChanged, object: 0)
            }
        }

        // Проверка истечения подписки
        if let expiry = subscriptionExpiry, expiry < Date() {
            deactivatePremium()
        }
    }
}

// MARK: - Nick Style (Блок 3 — Оформление ника)
/// Градиентные цвета для ника в чате и бегущей строке.
enum NickStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case `default` = "default"
    case neonPurple = "neon_purple"
    case neonPink = "neon_pink"
    case neonCyan = "neon_cyan"
    case neonGreen = "neon_green"
    case gold = "gold"
    case fire = "fire"
    case ice = "ice"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "Стандартный"
        case .neonPurple: return "Неоновый фиолет"
        case .neonPink: return "Неоновый розовый"
        case .neonCyan: return "Неоновый голубой"
        case .neonGreen: return "Неоновый зелёный"
        case .gold: return "Золотой"
        case .fire: return "Огненный"
        case .ice: return "Ледяной"
        }
    }

    /// Градиент для текста ника.
    var gradient: LinearGradient {
        switch self {
        case .default:
            return LinearGradient(colors: [.white], startPoint: .leading, endPoint: .trailing)
        case .neonPurple:
            return LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)
        case .neonPink:
            return LinearGradient(colors: [.pink, Cinema2026.accent], startPoint: .leading, endPoint: .trailing)
        case .neonCyan:
            return LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)
        case .neonGreen:
            return LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
        case .gold:
            return LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
        case .fire:
            return LinearGradient(colors: [.red, .orange, .yellow], startPoint: .leading, endPoint: .trailing)
        case .ice:
            return LinearGradient(colors: [.blue, .cyan, .white], startPoint: .leading, endPoint: .trailing)
        }
    }

    /// Цвет ника (fallback для мест где нет градиента).
    var fallbackColor: Color {
        switch self {
        case .default: return .white
        case .neonPurple: return .purple
        case .neonPink: return .pink
        case .neonCyan: return .cyan
        case .neonGreen: return .green
        case .gold: return .orange
        case .fire: return .red
        case .ice: return .blue
        }
    }
}

// MARK: - Avatar Border (Блок 3 — Рамки аватара)
enum AvatarBorder: String, CaseIterable, Identifiable, Codable, Sendable {
    case none = "none"
    case neonGlow = "neon_glow"
    case goldRing = "gold_ring"
    case rainbowRing = "rainbow_ring"
    case fireRing = "fire_ring"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "Без рамки"
        case .neonGlow: return "Неоновое свечение"
        case .goldRing: return "Золотое кольцо"
        case .rainbowRing: return "Радужная рамка"
        case .fireRing: return "Огненное кольцо"
        }
    }
}

// MARK: - Room Theme (Блок 3 — Темы комнаты)
enum RoomTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case `default` = "default"
    case neonNight = "neon_night"
    case sunset = "sunset"
    case ocean = "ocean"
    case galaxy = "galaxy"
    case forest = "forest"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "Стандартная"
        case .neonNight: return "Неоновая ночь"
        case .sunset: return "Закат"
        case .ocean: return "Океан"
        case .galaxy: return "Галактика"
        case .forest: return "Лес"
        }
    }

    /// Градиент фона чата для комнаты.
    var chatBackground: LinearGradient {
        switch self {
        case .default:
            return LinearGradient(colors: [Color(hex: 0x1E222B), Color(hex: 0x0B0E14)], startPoint: .top, endPoint: .bottom)
        case .neonNight:
            return LinearGradient(colors: [Color(hex: 0x1a0533), Color(hex: 0x0B0E14)], startPoint: .top, endPoint: .bottom)
        case .sunset:
            return LinearGradient(colors: [Color(hex: 0x2d1810), Color(hex: 0x1a0a05)], startPoint: .top, endPoint: .bottom)
        case .ocean:
            return LinearGradient(colors: [Color(hex: 0x0a1929), Color(hex: 0x050d15)], startPoint: .top, endPoint: .bottom)
        case .galaxy:
            return LinearGradient(colors: [Color(hex: 0x1a0a2e), Color(hex: 0x050210)], startPoint: .top, endPoint: .bottom)
        case .forest:
            return LinearGradient(colors: [Color(hex: 0x0d1f0d), Color(hex: 0x050f05)], startPoint: .top, endPoint: .bottom)
        }
    }

    /// Цвет неоновой рамки плеера.
    var playerBorderColor: Color {
        switch self {
        case .default: return .clear
        case .neonNight: return Cinema2026.accent
        case .sunset: return Color(hex: 0xF59E0B)
        case .ocean: return Color(hex: 0x06B6D4)
        case .galaxy: return Cinema2026.accent
        case .forest: return Color(hex: 0x22C55E)
        }
    }

    /// Есть ли рамка у плеера.
    var hasPlayerBorder: Bool {
        self != .default
    }
}
