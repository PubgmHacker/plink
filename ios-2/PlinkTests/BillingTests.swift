// PlinkTests/BillingTests.swift — PATCH 21: billing system tests
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
}
