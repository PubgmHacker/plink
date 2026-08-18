// Billing system tests
//
// Tests StoreKit 2 + PremiumTier + PlinkProductID (no real App Store).

import XCTest
@testable import Plink

@MainActor
final class BillingTests: XCTestCase {

    // MARK: - PlinkProductID

    func testPlinkProductID_allThreeProducts() {
        XCTAssertEqual(PlinkProductID.all.count, 3)
        XCTAssertTrue(PlinkProductID.all.contains(PlinkProductID.monthly))
        XCTAssertTrue(PlinkProductID.all.contains(PlinkProductID.quarterly))
        XCTAssertTrue(PlinkProductID.all.contains(PlinkProductID.yearly))
    }

    func testPlinkProductID_productIdStrings() {
        XCTAssertEqual(PlinkProductID.monthly, "plink.plus.1m")
        XCTAssertEqual(PlinkProductID.quarterly, "plink.plus.3m")
        XCTAssertEqual(PlinkProductID.yearly, "plink.plus.12m")
    }

    // MARK: - PremiumTier

    func testPremiumTier_allCases() {
        XCTAssertEqual(PremiumTier.allCases.count, 3)
    }

    func testPremiumTier_rawValues() {
        XCTAssertEqual(PremiumTier.free.rawValue, "free")
        XCTAssertEqual(PremiumTier.premium.rawValue, "premium")
        XCTAssertEqual(PremiumTier.lifetime.rawValue, "lifetime")
    }

    // MARK: - PlinkProductID.tier(for:)

    func testPlinkProductID_tierForMonthly() {
        XCTAssertEqual(PlinkProductID.tier(for: PlinkProductID.monthly), .premium)
    }

    func testPlinkProductID_tierForQuarterly() {
        XCTAssertEqual(PlinkProductID.tier(for: PlinkProductID.quarterly), .premium)
    }

    func testPlinkProductID_tierForYearly() {
        XCTAssertEqual(PlinkProductID.tier(for: PlinkProductID.yearly), .premium)
    }

    func testPlinkProductID_tierForUnknown_returnsNil() {
        XCTAssertNil(PlinkProductID.tier(for: "unknown.product"))
    }

    // MARK: - BackendEntitlementResponse

    func testBackendEntitlementResponse_decoding() throws {
        let json = """
        {
            "entitlement": {
                "active": true,
                "tier": "premium",
                "expiryDate": "2026-12-31T23:59:59Z"
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(BackendEntitlementResponse.self, from: json)
        XCTAssertTrue(response.entitlement.active)
        XCTAssertEqual(response.entitlement.tier, .premium)
        XCTAssertNotNil(response.entitlement.expiryDate)
    }

    func testBackendEntitlementResponse_lifetimeHasNullExpiry() throws {
        let json = """
        {
            "entitlement": {
                "active": true,
                "tier": "lifetime",
                "expiryDate": null
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(BackendEntitlementResponse.self, from: json)
        XCTAssertTrue(response.entitlement.active)
        XCTAssertEqual(response.entitlement.tier, .lifetime)
        XCTAssertNil(response.entitlement.expiryDate)
    }

    // MARK: - PremiumStatusManager integration

    func testPremiumStatusManager_activateLifetime_setsNilExpiry() {
        let manager = PremiumStatusManager()
        manager.activateLifetime()
        XCTAssertTrue(manager.isPremium)
        XCTAssertNil(manager.subscriptionExpiry, "Lifetime = nil expiry")
    }

    func testPremiumStatusManager_activatePremium_setsExpiry() {
        let manager = PremiumStatusManager()
        let expiry = Date().addingTimeInterval(30 * 24 * 3600)
        manager.activatePremium(expiryDate: expiry)
        XCTAssertEqual(manager.subscriptionExpiry, expiry)
    }

    // MARK: - StoreManager state

    func testStoreManager_initialState_idle() {
        let manager = StoreManager()
        XCTAssertEqual(manager.purchaseState, .idle)
        XCTAssertNil(manager.errorMessage)
    }

    // MARK: - User.premiumUntil (серверная дата окончания Plink+)
    //
    // Бэкенд отдаёт `premiumUntil` в GET /users/me и
    // PATCH /users/me, но модель User это поле теряла — PremiumStatusManager
    // никогда не узнавал авторитетную дату истечения подписки.

    /// Копия стратегии дат из APIClient.init — сервер шлёт JS `toISOString()`
    /// с миллисекундами, стандартный `.iso8601` их не разбирает.
    private func apiLikeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = formatter.date(from: raw) { return date }
            if let date = ISO8601DateFormatter().date(from: raw) { return date }
            return Date()
        }
        return decoder
    }

    /// "2026-08-25T10:00:00.000Z"
    private let premiumUntilEpoch: TimeInterval = 1_787_652_000

    func testUser_decodesPremiumUntilWithMilliseconds() throws {
        let json = """
        {
            "id": "u1", "username": "alex_films", "email": "alex@example.com",
            "avatarURL": null, "avatarData": null, "displayName": "Alex",
            "coverURL": null, "isOnline": true, "isPremium": true,
            "premiumUntil": "2026-08-25T10:00:00.000Z",
            "role": "USER", "createdAt": "2026-07-03T16:53:52.778Z"
        }
        """.data(using: .utf8)!

        let user = try apiLikeDecoder().decode(User.self, from: json)
        XCTAssertTrue(user.isPremium)
        // Жёсткая проверка значения: стратегия APIClient на неразобранной строке
        // возвращает Date() («сейчас»), поэтому XCTAssertNotNil ничего не доказал бы.
        XCTAssertEqual(user.premiumUntil?.timeIntervalSince1970 ?? 0,
                       premiumUntilEpoch, accuracy: 0.5)
    }

    func testUser_decodesWithoutPremiumUntil_authResponseShape() throws {
        // /auth/signin и /auth/signup поле не отдают — модель обязана выжить.
        let json = """
        {
            "id": "u1", "username": "alex_films", "email": "alex@example.com",
            "isPremium": true, "role": "USER"
        }
        """.data(using: .utf8)!

        let user = try apiLikeDecoder().decode(User.self, from: json)
        XCTAssertNil(user.premiumUntil, "Отсутствующее поле = «сервер дату не сообщил»")
        XCTAssertTrue(user.isPremium)
        XCTAssertEqual(user.username, "alex_films")
    }

    func testUser_decodesNullPremiumUntil_lifetime() throws {
        // isPremium=true + premiumUntil=null в БД = пожизненный Plink+.
        let json = """
        {
            "id": "u1", "username": "alex_films", "email": "alex@example.com",
            "isPremium": true, "premiumUntil": null,
            "role": "USER", "createdAt": "2026-07-03T16:53:52.778Z"
        }
        """.data(using: .utf8)!

        let user = try apiLikeDecoder().decode(User.self, from: json)
        XCTAssertNil(user.premiumUntil)
        XCTAssertTrue(user.isPremium)
    }

    /// User декодируют и обычным `JSONDecoder()` (кэш профиля, сторонние
    /// вызовы) — там стратегия `.deferredToDate` ждёт число и на ISO-строке
    /// бросает typeMismatch. Новое поле не должно ронять всю модель.
    func testUser_premiumUntilSurvivesDefaultDateStrategy() throws {
        let json = """
        {
            "id": "u1", "username": "alex_films", "email": "alex@example.com",
            "isPremium": true, "premiumUntil": "2026-08-25T10:00:00.000Z"
        }
        """.data(using: .utf8)!

        let user = try JSONDecoder().decode(User.self, from: json)
        XCTAssertEqual(user.premiumUntil?.timeIntervalSince1970 ?? 0,
                       premiumUntilEpoch, accuracy: 0.5)
    }

    /// AuthService.cacheUser кодирует `.iso8601`, decodeCachedUser читает
    /// кастомной стратегией — дата обязана пережить перезапуск приложения.
    func testUser_premiumUntilSurvivesCacheRoundTrip() throws {
        let original = User(
            id: "u1", username: "alex_films", email: "alex@example.com",
            avatarURL: nil, isOnline: true, isPremium: true,
            premiumUntil: Date(timeIntervalSince1970: premiumUntilEpoch),
            role: "USER", createdAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let restored = try apiLikeDecoder().decode(User.self, from: data)
        XCTAssertEqual(restored.premiumUntil?.timeIntervalSince1970 ?? 0,
                       premiumUntilEpoch, accuracy: 1.0)
    }
}
