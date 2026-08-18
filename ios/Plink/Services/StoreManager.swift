// StoreKit 2 + backend verification
//
// StoreKit 2 subscription manager with server-authoritative entitlement.
// The backend verifies signed transactions (JWS) and receives App Store
// Server Notifications V2 to stay in sync even when the app is closed.
//
// Invariants:
//   - StoreKit 2 API: Product.products, purchase, Transaction.currentEntitlements,
//     Transaction.updates, AppStore.sync
//   - NEVER hardcode displayed prices — always use Product.displayPrice
//   - Backend verifies signed transaction/JWS (server-authoritative)
//   - App Store Server Notifications V2 handled by backend
//   - Entitlements are server-authoritative (iOS is optimistic UI only)
//   - Products: monthly, yearly, optional non-consumable lifetime
//   - Trial wording: "7-day free trial, eligibility determined by App Store"
//   - No "priority sync" tier — free sync is never degraded
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
import CryptoKit

// MARK: - Product IDs

enum PlinkProductID {
    // Exactly three subscription products: 1m, 3m, 12m
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
        case verifying  // Backend JWS verification in progress
    }

    // MARK: - appAccountToken

    /// Namespace для деривации appAccountToken из userId (RFC 4122 UUID v5).
    /// ВАЖНО: ровно та же константа и формула продублированы на сервере
    /// (billing.ts) — сервер сверяет токен из подписанной Apple транзакции
    /// с аутентифицированным пользователем. Менять только синхронно.
    // Namespace обязан побайтово совпадать с
    // PLINK_APP_ACCOUNT_NAMESPACE на сервере (billing.ts) — расхождение
    // означало 403 на КАЖДОЙ покупке после списания денег.
    static let plinkAccountNamespace = UUID(uuidString: "3F2C9A1E-8D5B-4E7A-B6C4-2A9D71F0E583")!

    /// RFC 4122 UUID v5: SHA-1(байты namespace + name), версия 5, вариант 10x.
    static func uuidV5(namespace: UUID, name: String) -> UUID {
        var data = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        data.append(contentsOf: Array(name.utf8))
        let digest = Insecure.SHA1.hash(data: data)
        var bytes = Array(Array(digest).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // версия 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // вариант RFC 4122
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Детерминированный appAccountToken для пользователя Plink.
    static func appAccountToken(for userId: String) -> UUID {
        uuidV5(namespace: plinkAccountNamespace, name: userId)
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
            // Привязываем покупку к аккаунту через
            // appAccountToken (UUID v5 из userId) — сервер сверяет его
            // с покупателем в billing.ts. Без userId — покупка без токена.
            var options: Set<Product.PurchaseOption> = []
            if let userId = AuthService.shared.currentUserValue?.id {
                options.insert(.appAccountToken(Self.appAccountToken(for: userId)))
            }

            let result = try await product.purchase(options: options)

            switch result {
            case .success(let verification):
                guard let transaction = Self.verifiedTransaction(verification) else {
                    purchaseState = .failed
                    errorMessage = "Transaction verification failed"
                    return
                }

                // Send JWS to backend for server-authoritative
                // entitlement. StoreKit's local state is optimistic UI only.
                // Передаём именно jwsRepresentation —
                // раньше уходил jsonRepresentation, и подпись на сервере
                // не могла пройти НИКОГДА.
                let outcome = await verifyWithBackend(
                    transaction: transaction,
                    jws: verification.jwsRepresentation
                )

                // finish() был безусловным — сервер,
                // не узнавший о покупке, терял второй шанс через
                // Transaction.updates. Теперь finish() только когда сервер
                // реально ответил (подтвердил или авторитетно отказал).
                switch outcome {
                case .confirmed:
                    await transaction.finish()
                    purchaseState = .success
                    resetToIdleSoon()
                case .rejected:
                    // Сервер авторитетно отказал (revoke / чужая транзакция):
                    // премиум не включаем, ретраи бессмысленны — закрываем.
                    await transaction.finish()
                    purchaseState = .failed
                    errorMessage = "Покупка отклонена сервером"
                case .unavailable:
                    // Бэкенд недоступен: офлайн-грейс уже применён,
                    // finish() НЕ зовём — StoreKit передоставит транзакцию,
                    // и сервер получит второй шанс на верификацию.
                    purchaseState = .success
                    resetToIdleSoon()
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
                guard let (transaction, jws) = Self.verifiedTransactionWithJWS(result) else { continue }
                let outcome = await verifyWithBackend(transaction: transaction, jws: jws)
                // Авторитетный отказ сервера
                // не считаем успешным восстановлением.
                if outcome != .rejected { restored = true }
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
            if let token = AuthTokenStore.shared.token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                await checkLocalEntitlement()
                return
            }

            if http.statusCode == 200 {
                let entitlement = try JSONDecoder().decode(BackendEntitlementResponse.self, from: data)
                applyEntitlement(entitlement)
                return
            }

            // 4xx (например 401 без токена) — авторитетный
            // ответ сервера, НЕ включаем премиум по локальному StoreKit;
            // статус не трогаем. Локальный фолбэк только при 5xx/сети.
            if (400..<500).contains(http.statusCode) { return }

            await checkLocalEntitlement()
        } catch {
            // Network error — fall back to local StoreKit check.
            await checkLocalEntitlement()
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() {
        transactionListener = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let (transaction, jws) = Self.verifiedTransactionWithJWS(result) else { continue }
                // finish() только когда сервер ответил
                // (200 или авторитетный 4xx). При недоступном бэкенде
                // транзакцию не закрываем — StoreKit передоставит её позже.
                let outcome = await self?.verifyWithBackend(transaction: transaction, jws: jws)
                if outcome == .confirmed || outcome == .rejected {
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Backend verification

    /// Итог серверной верификации JWS.
    enum VerifyOutcome: Equatable {
        case confirmed    // 200 — entitlement применён с сервера
        case rejected     // 4xx — авторитетный отказ (revoke / чужая транзакция)
        case unavailable  // сеть / 5xx / нет baseURL — офлайн-грейс по StoreKit
    }

    /// Sends the signed transaction JWS to backend for verification.
    /// Backend is authoritative — local StoreKit state is optimistic only.
    /// `jws` — verification.jwsRepresentation (RFC 7515), а не jsonRepresentation.
    /// Раньше ЛЮБОЙ не-200 (включая 403 «чужая
    /// транзакция» и 400 «revoked») включал премиум локально (fail-open).
    /// Теперь 4xx — авторитетный отказ без applyLocalTransaction.
    @discardableResult
    private func verifyWithBackend(transaction: Transaction, jws: String) async -> VerifyOutcome {
        guard let apiBaseURL else {
            // No backend configured — apply local StoreKit state.
            applyLocalTransaction(transaction)
            return .unavailable
        }

        purchaseState = .verifying

        do {
            var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/billing/verify"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = AuthTokenStore.shared.token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            // Подписанный JWS (Apple) — сервер валидирует подпись по Apple Root CA.
            let body: [String: Any] = [
                "jws": jws,
                "productId": transaction.productID,
                "transactionId": String(transaction.id)
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                applyLocalTransaction(transaction)
                return .unavailable
            }

            if http.statusCode == 200 {
                let entitlement = try JSONDecoder().decode(BackendEntitlementResponse.self, from: data)
                applyEntitlement(entitlement)
                return .confirmed
            }

            if (400..<500).contains(http.statusCode) {
                // Авторитетный отказ сервера — премиум НЕ включаем.
                return .rejected
            }

            // 5xx — сервер временно недоступен: офлайн-грейс.
            applyLocalTransaction(transaction)
            return .unavailable
        } catch {
            // Network error — офлайн-грейс по локальному StoreKit-состоянию
            // (честный источник до восстановления связи).
            applyLocalTransaction(transaction)
            return .unavailable
        }
    }

    /// Возврат purchaseState в .idle через 2 секунды после success.
    private func resetToIdleSoon() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.purchaseState = .idle
        }
    }

    // MARK: - Apply entitlement

    // JS Date.toISOString() всегда отдаёт миллисекунды
    // ('2026-08-25T10:00:00.000Z'), а ISO8601DateFormatter без
    // .withFractionalSeconds возвращал nil — оплаченный премиум молча терялся.
    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseISO8601(_ string: String) -> Date? {
        isoFormatterFractional.date(from: string) ?? isoFormatterPlain.date(from: string)
    }

    private func applyEntitlement(_ response: BackendEntitlementResponse) {
        let entitlement = response.entitlement

        // Сервер-авторитетно: active=false с платным tier — премиума нет.
        guard entitlement.active || entitlement.tier == .free else {
            PremiumStatusManager.shared.deactivatePremium()
            return
        }

        let expiryDate = entitlement.expiryDate.flatMap { Self.parseISO8601($0) }

        switch entitlement.tier {
        case .lifetime:
            PremiumStatusManager.shared.activateLifetime()
            onEntitlementActive?(.lifetime, nil)
        case .premium:
            // Сервер подтвердил премиум — не молчим при
            // неразобранной дате, активируем с дефолтным окном и логом.
            let expiry: Date
            if let parsed = expiryDate {
                expiry = parsed
            } else {
                expiry = Date().addingTimeInterval(30 * 24 * 3600)
                print("[StoreManager] entitlement.expiryDate не распарсился: '\(entitlement.expiryDate ?? "nil")' — применяю дефолт 30 дней")
            }
            PremiumStatusManager.shared.activatePremium(expiryDate: expiry)
            onEntitlementActive?(.premium, expiry)
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

    /// Транзакция + её jwsRepresentation (для серверной проверки подписи).
    private static func verifiedTransactionWithJWS(
        _ result: VerificationResult<Transaction>
    ) -> (Transaction, String)? {
        switch result {
        case .unverified:
            return nil
        case .verified(let tx):
            return (tx, result.jwsRepresentation)
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
