//  StoreKitManager.swift
//  Plink — M39
//
//  До M39 в проекте был пейволл-экран, но кнопка не совершала транзакцию.
//
//  Два правила, которые чаще всего нарушают и которые здесь соблюдены:
//   1. Transaction.updates слушается СРАЗУ при старте, а не при открытии пейволла.
//   2. finish() вызывается ТОЛЬКО после подтверждения покупки сервером.

import Foundation
import StoreKit

@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    enum ProductID: String, CaseIterable {
        case monthly = "com.plink.app.plus.monthly"
        case yearly = "com.plink.app.plus.yearly"
        case lifetime = "com.plink.app.plus.lifetime"
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPlus = false
    @Published private(set) var activeProductID: String?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(verification: update)
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: ProductID.allCases.map(\.rawValue))
            let order = [ProductID.monthly.rawValue, ProductID.yearly.rawValue, ProductID.lifetime.rawValue]
            products = loaded.sorted {
                (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99)
            }
        } catch {
            lastError = "Не удалось загрузить тарифы. Проверьте соединение."
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                return await handle(verification: verification)
            case .userCancelled:
                return false
            case .pending:
                lastError = "Покупка ждёт подтверждения. Мы включим Plink+ автоматически."
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = "Покупка не завершена: \(error.localizedDescription)"
            return false
        }
    }

    func restore() async {
        isLoading = true
        defer { isLoading = false }
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var found = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  ProductID(rawValue: transaction.productID) != nil else { continue }
            if let revoked = transaction.revocationDate, revoked <= Date() { continue }
            if let expires = transaction.expirationDate, expires <= Date() { continue }
            found = true
            activeProductID = transaction.productID
            expiresAt = transaction.expirationDate
        }
        isPlus = found
        if !found {
            activeProductID = nil
            expiresAt = nil
        }
        await syncStatusFromServer()
    }

    @discardableResult
    private func handle(verification: VerificationResult<Transaction>) async -> Bool {
        switch verification {
        case .unverified(_, let error):
            lastError = "Покупку не удалось проверить: \(error.localizedDescription)"
            return false
        case .verified(let transaction):
            let confirmed = await verifyOnServer(transaction)
            if confirmed { await transaction.finish() }
            applyLocally(transaction)
            return confirmed
        }
    }

    private func applyLocally(_ transaction: Transaction) {
        if transaction.revocationDate == nil,
           transaction.expirationDate.map({ $0 > Date() }) ?? true {
            isPlus = true
            activeProductID = transaction.productID
            expiresAt = transaction.expirationDate
        }
    }

    private func verifyOnServer(_ transaction: Transaction) async -> Bool {
        guard let url = URL(string: APIConfig.baseURL + "/api/subscription/verify") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = AuthTokenStore.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "signedTransaction": transaction.jsonRepresentation.base64EncodedString(),
            "transactionId": String(transaction.id),
            "productId": transaction.productID,
        ])
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(code)
        } catch {
            // Без finish() StoreKit повторит транзакцию позже — деньги не потеряются.
            lastError = "Покупка прошла, но нет связи с сервером. Plink+ включится автоматически."
            return false
        }
    }

    private func syncStatusFromServer() async {
        guard let url = URL(string: APIConfig.baseURL + "/api/subscription/status") else { return }
        var request = URLRequest(url: url)
        if let token = AuthTokenStore.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 10

        struct StatusResponse: Decodable {
            let isPlus: Bool
            let productId: String?
            let expiresAt: Date?
        }

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let status = try? decoder.decode(StatusResponse.self, from: data) else { return }

        // Сервер может только ДОБАВИТЬ права, но не отобрать их у валидной локальной покупки.
        if status.isPlus && !isPlus {
            isPlus = true
            activeProductID = status.productId
            expiresAt = status.expiresAt
        }
    }

    func monthlyEquivalent(for product: Product) -> String? {
        guard product.id == ProductID.yearly.rawValue else { return nil }
        return product.priceFormatStyle.format(product.price / 12)
    }

    var yearlySavingsPercent: Int? {
        guard let monthly = products.first(where: { $0.id == ProductID.monthly.rawValue }),
              let yearly = products.first(where: { $0.id == ProductID.yearly.rawValue }) else { return nil }
        let full = monthly.price * 12
        guard full > 0 else { return nil }
        return Int(truncating: ((full - yearly.price) / full * 100) as NSDecimalNumber)
    }

    func trialDescription(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let value = offer.period.value
        switch offer.period.unit {
        case .day: return "\(value) дня бесплатно"
        case .week: return "\(value) нед. бесплатно"
        case .month: return "\(value) мес. бесплатно"
        case .year: return "\(value) г. бесплатно"
        @unknown default: return nil
        }
    }
}
