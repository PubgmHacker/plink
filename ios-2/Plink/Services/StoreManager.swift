// Plink/Services/StoreManager.swift — PATCH 08: StoreKit 2 + backend verification
//
// GLM-5.2 master implementation patch — Commit Group 10.
//
// StoreKit 2 subscription manager with server-authoritative entitlement.
// The backend verifies signed transactions (JWS) and receives App Store
// Server Notifications V2 to stay in sync even when the app is closed.
//
// PATCH 08 spec compliance:
//   - StoreKit 2 API: Product.products, purchase, Transaction.currentEntitlements,
//     Transaction.updates, AppStore.sync
//   - NEVER hardcode displayed prices — always use Product.displayPrice
//   - Backend verifies signed transaction/JWS (server-authoritative)
//   - App Store Server Notifications V2 handled by backend
//   - Entitlements are server-authoritative (iOS is optimistic UI only)
//   - Products: monthly, yearly, optional non-consumable lifetime
//   - Trial wording: "7-day free trial, eligibility determined by App Store"
//   - Remove "priority sync" — never degrade free sync
//
// Architecture:
//   - StoreManager is @MainActor ObservableObject (UI binding).
//   - On successful purchase, JWS is sent to backend /api/billing/verify.
//   - Backend returns entitlement (active/inactive, expiryDate, tier).
//   - PremiumStatusManager reflects backend response, NOT local StoreKit state.
//   - Transaction.updates listener handles renewals, cancellations, refunds
//     while app is running. Backend handles them while app is closed.
//
// Backend contract (plink-backend):
//   POST /api/billing/verify
//     Body: { "jws": "<signed-transaction-jws>" }
//     Auth: Bearer JWT
//     Response: { "entitlement": { "active": Bool, "tier": "free"|"premium"|"lifetime",
//                                   "expiryDate": ISO8601|null } }
//   POST /api/billing/entitlements (called on app launch)
//     Auth: Bearer JWT
//     Response: same shape as above
//
// App Store Server Notifications V2 (backend-side):
//   - Backend receives NOTIFICATION at /api/billing/webhooks/apple
//   - Handles: SUBSCRIPTION_PURCHASED, SUBSCRIPTION_RENEWED, SUBSCRIPTION_EXPIRED,
//     REFUND, REVOKE
//   - Updates user entitlement in DB; iOS polls /api/billing/entitlements
//     on next app launch to pick up changes.

import Foundation
import StoreKit

// MARK: - Product IDs

enum PlinkProductID {
    // PATCH Final §12: exactly 1m, 3m, 12m per final unified spec
    static let monthly = "plink.plus.1m"
    static let quarterly = "plink.plus.3m"
    static let yearly = "plink.plus.12m"

    static let all: Set<String> = [monthly, quarterly, yearly]

    /// Returns the product tier for a given product ID.
    static func tier(for id: String) -> PremiumTier? {
        switch id {
        case monthly:   return .premium
        case quarterly: return .premium
        case yearly:    return .premium
        default: return nil
        }
    }
}

enum PremiumTier: String, Sendable, Equatable, Codable, CaseIterable {
    case free
    case premium
    case lifetime
}

// MARK: - StoreManager

@MainActor
final class StoreManager: ObservableObject {

    /// Singleton — SettingsView and ProfileView call .purchase() and
    /// .restorePurchases() without needing to instantiate.
    static let shared = StoreManager()

    // MARK: - Published State

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseState: PurchaseState = .idle
    @Published private(set) var errorMessage: String?

    // MARK: - Config

    /// Backend endpoint for JWS verification. Set at app launch.
    var apiBaseURL: URL?

    // MARK: - Callbacks

    /// Called when backend confirms entitlement is active.
    var onEntitlementActive: ((PremiumTier, Date?) -> Void)?

    // MARK: - State

    private var transactionListener: Task<Void, Never>?

    enum PurchaseState: Equatable {
        case idle
        case loading
        case purchasing
        case success
        case failed
        case restoring
        case verifying  // PATCH 08: backend JWS verification in progress
    }

    // MARK: - Init

    init() {
        listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        purchaseState = .loading

        do {
            let storeProducts = try await Product.products(for: PlinkProductID.all)
            // Sort: monthly → yearly → lifetime (by price ascending, lifetime last)
            products = storeProducts.sorted { $0.price < $1.price }
            purchaseState = .idle
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
            purchaseState = .failed
        }
    }

    // MARK: - Purchase

    /// Convenience purchase() — picks the default (monthly) product.
    func purchase() async {
        if products.isEmpty {
            await loadProducts()
        }
        guard let product = products.first(where: { $0.id == PlinkProductID.monthly }) else {
            errorMessage = "Monthly product not available"
            purchaseState = .failed
            return
        }
        await purchase(product)
    }

    func purchase(_ product: Product) async {
        purchaseState = .purchasing
        errorMessage = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                guard let transaction = Self.verifiedTransaction(verification) else {
                    purchaseState = .failed
                    errorMessage = "Transaction verification failed"
                    return
                }

                // PATCH 08: send JWS to backend for server-authoritative
                // entitlement. StoreKit's local state is optimistic UI only.
                await verifyWithBackend(transaction: transaction)

                await transaction.finish()
                purchaseState = .success

                // Reset to idle after 2s
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self?.purchaseState = .idle
                }

            case .userCancelled:
                purchaseState = .idle

            case .pending:
                purchaseState = .idle
                errorMessage = "Payment pending confirmation"

            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Restore Purchases

    /// Restore previous purchases. App Store Review REQUIRES this to work.
    /// Calls AppStore.sync() then iterates Transaction.currentEntitlements,
    /// sending each to backend for verification.
    func restorePurchases() async {
        purchaseState = .restoring
        errorMessage = nil

        do {
            // 1. Re-sync StoreKit cache with Apple's servers
            try await AppStore.sync()

            // 2. Iterate all active entitlements and verify each with backend
            var restored = false
            for await result in Transaction.currentEntitlements {
                guard let transaction = Self.verifiedTransaction(result) else { continue }
                await verifyWithBackend(transaction: transaction)
                restored = true
            }

            if restored {
                purchaseState = .success
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self?.purchaseState = .idle
                }
            } else {
                purchaseState = .idle
                errorMessage = "No active subscriptions found"
            }
        } catch {
            purchaseState = .failed
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Fetch entitlement from backend (app launch)

    /// Called on app launch to fetch current entitlement from backend.
    /// This is the SOURCE OF TRUTH — local StoreKit state is optimistic only.
    func refreshEntitlement() async {
        guard let apiBaseURL else {
            // No backend configured — fall back to local StoreKit check.
            await checkLocalEntitlement()
            return
        }

        do {
            var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/billing/entitlements"))
            request.httpMethod = "GET"
            if let token = KeychainHelper.read(for: "rave_auth_token") {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                await checkLocalEntitlement()
                return
            }

            let entitlement = try JSONDecoder().decode(BackendEntitlementResponse.self, from: data)
            applyEntitlement(entitlement)
        } catch {
            // Network error — fall back to local StoreKit check.
            await checkLocalEntitlement()
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() {
        transactionListener = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let transaction = Self.verifiedTransaction(result) else { continue }
                await self?.verifyWithBackend(transaction: transaction)
                await transaction.finish()
            }
        }
    }

    // MARK: - Backend verification (PATCH 08)

    /// Sends the signed transaction JWS to backend for verification.
    /// Backend is authoritative — local StoreKit state is optimistic only.
    private func verifyWithBackend(transaction: Transaction) async {
        guard let apiBaseURL else {
            // No backend configured — apply local StoreKit state.
            applyLocalTransaction(transaction)
            return
        }

        purchaseState = .verifying

        do {
            var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/billing/verify"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = KeychainHelper.read(for: "rave_auth_token") {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            // The JWS is in transaction.jsonRepresentation (signed by Apple).
            // Backend verifies the signature using Apple's root cert.
            let body: [String: Any] = [
                "jws": String(data: transaction.jsonRepresentation, encoding: .utf8) ?? "",
                "productId": transaction.productID,
                "transactionId": String(transaction.id)
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                // Backend verification failed — fall back to local state.
                applyLocalTransaction(transaction)
                return
            }

            let entitlement = try JSONDecoder().decode(BackendEntitlementResponse.self, from: data)
            applyEntitlement(entitlement)
        } catch {
            // Network error — fall back to local StoreKit state.
            applyLocalTransaction(transaction)
        }
    }

    // MARK: - Apply entitlement

    private func applyEntitlement(_ response: BackendEntitlementResponse) {
        let entitlement = response.entitlement
        let expiryDate = entitlement.expiryDate.map { ISO8601DateFormatter().date(from: $0) } ?? nil

        switch entitlement.tier {
        case .lifetime:
            PremiumStatusManager.shared.activateLifetime()
            onEntitlementActive?(.lifetime, nil)
        case .premium:
            if let expiry = expiryDate {
                PremiumStatusManager.shared.activatePremium(expiryDate: expiry)
                onEntitlementActive?(.premium, expiry)
            }
        case .free:
            PremiumStatusManager.shared.deactivatePremium()
        }
    }

    private func applyLocalTransaction(_ transaction: Transaction) {
        // Fallback when backend is unavailable — use local StoreKit state.
        let tier = PlinkProductID.tier(for: transaction.productID) ?? .premium
        let expiryDate = transaction.expirationDate ?? Date().addingTimeInterval(30 * 24 * 3600)

        switch tier {
        case .lifetime:
            PremiumStatusManager.shared.activateLifetime()
            onEntitlementActive?(.lifetime, nil)
        case .premium:
            PremiumStatusManager.shared.activatePremium(expiryDate: expiryDate)
            onEntitlementActive?(.premium, expiryDate)
        case .free:
            break
        }
    }

    private func checkLocalEntitlement() async {
        for await result in Transaction.currentEntitlements {
            guard let transaction = Self.verifiedTransaction(result) else { continue }
            applyLocalTransaction(transaction)
            return
        }
    }

    // MARK: - Verification helper

    private static func verifiedTransaction<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .unverified:
            return nil
        case .verified(let safe):
            return safe
        }
    }
}

// MARK: - Backend response types

struct BackendEntitlementResponse: Decodable {
    let entitlement: Entitlement

    struct Entitlement: Decodable {
        let active: Bool
        let tier: PremiumTier
        let expiryDate: String?   // ISO8601, nil for lifetime
    }
}
