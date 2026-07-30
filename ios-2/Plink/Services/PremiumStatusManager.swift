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

    /// Аудит 26.07.2026 (P2, ревью): по C9 `isPremium` на старте ВСЕГДА false,
    /// поэтому «этот девайс был премиумным» знает только кэш UserDefaults.
    /// Подсказка нужна для двух вещей: не отбирать у платящего выбор
    /// премиум-оформления на каждом холодном старте и всё-таки откатить его,
    /// когда сервер/StoreKit подтвердит потерю прав.
    private var cachedPremiumHint = false

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
        // Аудит 26.07.2026 (P2, ревью): потерю прав надо отработать и когда
        // премиум был только в локальном кэше (isPremium уже false из-за C9) —
        // иначе у пользователя с истёкшей подпиской платное оформление
        // оставалось бы навсегда.
        let hadPremium = isPremium || cachedPremiumHint
        cachedPremiumHint = false
        isPremium = false
        subscriptionExpiry = nil
        selectedNickStyle = .default
        selectedAvatarBorder = .none
        selectedRoomTheme = .default
        persist()
        // Аудит 26.07.2026 (P2): откат оформления не вызывал никто — после
        // истечения Plink+ оставались премиум-тема приложения, кино-бабл,
        // эмоджи-пак и живой оверлей.
        if hadPremium {
            rollbackPremiumAppearance()
        }
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
        if serverIsPremium {
            // Аудит 26.07.2026 (P2): expiry == nil здесь означает «сервер не
            // сообщил дату» — /auth/signin, /auth/signup и /users/me не отдают
            // premiumUntil. Раньше такой вызов записывал nil и подписка молча
            // становилась пожизненной. Настоящую дату приносит
            // StoreManager.refreshEntitlement() → /api/billing/entitlements
            // (activatePremium/activateLifetime), поэтому неизвестную дату
            // просто не трогаем. Ревью: заведомо просроченную локальную дату
            // при этом не сохраняем — сервер только что сказал «права есть»,
            // значит она устарела (иначе UI показал бы «Действует до <прошлое>»).
            let resolvedExpiry = expiry ?? subscriptionExpiry.flatMap { $0 > Date() ? $0 : nil }
            cachedPremiumHint = false
            if isPremium != true || subscriptionExpiry != resolvedExpiry {
                isPremium = true
                subscriptionExpiry = resolvedExpiry
                persist()
                onPremiumStatusChanged?(true)
            }
        } else {
            // Ревью: `cachedPremiumHint` — случай «на старте премиум был только
            // в кэше, сервер говорит нет»: isPremium уже false, но платное
            // оформление ещё выбрано и его надо откатить.
            if isPremium == true || cachedPremiumHint {
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

    // Аудит 26.07.2026 (P2): флаг serverConfirmed был мёртвым — он только
    // писался (syncFromServer / loadPersistedState) и не читался нигде.
    // Роль «сервер — источник истины» выполняют syncFromServer и
    // StoreManager.applyEntitlement, отдельный флаг ничего не гейтил.

    private func loadPersistedState() {
        // C9: local UserDefaults is NOT authority. Always start free until
        // server (syncFromServer) or StoreKit confirms purchase. Prevents
        // sticky "Plink+ active" after testing / stale flags on other devices.
        let cachedPremium = defaults.bool(forKey: premiumKey)
        isPremium = false
        cachedPremiumHint = cachedPremium
        subscriptionExpiry = defaults.object(forKey: expiryKey) as? Date
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
            // Аудит 26.07.2026 (P2): страховочный clamp чистил только бабл и
            // live-тему — премиум-тема приложения и эмоджи-пак оставались
            // выбранными. Откатываем их на fallback из каталога, но ТОЛЬКО если
            // локальный кэш тоже не помнит премиум: здесь isPremium всегда false
            // (C9), поэтому безусловный clamp отбирал бы выбор у платящего
            // подписчика на каждом холодном старте. Реальную потерю прав
            // отрабатывает deactivatePremium() → rollbackPremiumAppearance().
            if !cachedPremium {
                clampPremiumAppearanceKey("plink.appThemeID", fallback: AppearanceCatalog.defaultAppThemeID)
                clampPremiumAppearanceKey("plink.emojiPackID", fallback: AppearanceCatalog.defaultEmojiPackID)
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

    /// Сбрасывает премиум-пресет оформления в его бесплатный fallback.
    /// Работает на уровне UserDefaults — AppearanceStore читает эти же ключи
    /// при создании, поэтому clamp обязан отработать до его инициализации.
    private func clampPremiumAppearanceKey(_ key: String, fallback: String) {
        let current = UserDefaults.standard.string(forKey: key) ?? fallback
        guard let descriptor = AppearanceCatalog.all.first(where: { $0.id == current }),
              descriptor.premium else { return }
        UserDefaults.standard.set(descriptor.fallbackID ?? fallback, forKey: key)
    }

    /// Полный откат платного оформления при потере прав: ключи UserDefaults,
    /// живой оверлей Plink+ и уже созданный AppearanceStore (чтобы UI обновился
    /// без перезапуска). Стор намеренно НЕ создаём — сервисный слой не должен
    /// инстанцировать SwiftUI-стор как побочный эффект (это ломало юнит-тесты
    /// и порядок инициализации).
    private func rollbackPremiumAppearance() {
        clampPremiumAppearanceKey("plink.appThemeID", fallback: AppearanceCatalog.defaultAppThemeID)
        clampPremiumAppearanceKey("plink.emojiPackID", fallback: AppearanceCatalog.defaultEmojiPackID)
        let bubble = UserDefaults.standard.string(forKey: "plink.bubbleStyleID") ?? "bubble-quiet"
        if !Self.isFreeBubbleStyle(bubble) {
            UserDefaults.standard.set("bubble-quiet", forKey: "plink.bubbleStyleID")
        }
        // Ревью: live-оверлей Plink+ раньше сбрасывался только на следующем
        // холодном старте — платная тема продолжала работать всю сессию.
        if UserDefaults.standard.integer(forKey: "plink.liveTheme") > 0 {
            UserDefaults.standard.set(0, forKey: "plink.liveTheme")
            NotificationCenter.default.post(name: .plinkLiveThemeChanged, object: 0)
        }
        AppearanceStore.live?.handleEntitlementExpiry()
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
