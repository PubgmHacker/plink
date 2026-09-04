// PlinkWebPlans.swift — Plink+ tariffs sold on the website.
//
// Mirrors GET /api/webpay/status (webpay.ts). The app never charges anyone
// itself: it shows these prices, hands the user to /plus and later reads the
// entitlement back from /api/billing/entitlements. When the request fails the
// built-in defaults stay on screen (they equal the server defaults) and the
// paywall shows a "prices may be stale" note instead of an empty state.
import Foundation

struct PlinkWebPlan: Identifiable, Equatable {
    let id: String        // "1m" | "3m" | "12m"
    let title: String     // Server title, used only when the id is unknown
    let priceRub: Decimal
    let days: Int

    var months: Int { max(1, Int((Double(days) / 30.0).rounded())) }
    var monthlyRub: Decimal { priceRub / Decimal(months) }

    static let fallback: [PlinkWebPlan] = [
        PlinkWebPlan(id: "1m", title: "Plink+", priceRub: 199, days: 30),
        PlinkWebPlan(id: "3m", title: "Plink+", priceRub: 499, days: 90),
        PlinkWebPlan(id: "12m", title: "Plink+", priceRub: 1490, days: 365),
    ]
}

struct PlinkWebPlansResponse: Decodable {
    struct Plan: Decodable {
        let title: String
        let price: String
        let days: Int
    }
    let enabled: Bool
    let plans: [String: Plan]
}

@MainActor
final class PlinkWebPlansLoader: ObservableObject {
    enum State: Equatable { case idle, loading, loaded, failed }

    @Published private(set) var plans: [PlinkWebPlan] = PlinkWebPlan.fallback
    @Published private(set) var state: State = .idle
    @Published private(set) var siteEnabled = false

    func load() async {
        state = .loading
        do {
            let response: PlinkWebPlansResponse = try await APIClient.shared.request("webpay/status")
            let parsed = response.plans.compactMap { key, plan -> PlinkWebPlan? in
                guard let price = Decimal(string: plan.price, locale: Locale(identifier: "en_US_POSIX")),
                      price > 0, plan.days > 0 else { return nil }
                return PlinkWebPlan(id: key, title: plan.title, priceRub: price, days: plan.days)
            }
            .sorted { $0.days < $1.days }
            if !parsed.isEmpty { plans = parsed }
            siteEnabled = response.enabled
            state = .loaded
        } catch {
            state = .failed
        }
    }
}

enum PlinkRub {
    /// "1 490 ₽" — whole rubles, narrow no-break space as the group separator.
    static func format(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = "\u{202F}"
        let number = formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
        return "\(number)\u{00A0}₽"
    }
}
