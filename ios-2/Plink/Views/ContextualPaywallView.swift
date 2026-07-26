import SwiftUI
import StoreKit

/// Единый контекстный пейволл Plink+ (M39).
/// Заголовок и подзаголовок зависят от того, что именно упёрлось в лимит.
struct ContextualPaywallView: View {
    enum Trigger: String {
        case participants
        case voice
        case rooms
        case quality
        case themes
        case generic

        var titleKey: String { "paywall.title.\(rawValue)" }
        var subtitleKey: String { "paywall.subtitle.\(rawValue)" }

        var icon: String {
            switch self {
            case .participants: return "person.3.fill"
            case .voice: return "mic.fill"
            case .rooms: return "rectangle.stack.badge.plus"
            case .quality: return "sparkles.tv.fill"
            case .themes: return "paintpalette.fill"
            case .generic: return "star.fill"
            }
        }
    }

    let trigger: Trigger
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = StoreKitManager.shared

    @State private var selected: StoreKitManager.ProductID = .yearly
    @State private var isWorking = false

    var body: some View {
        ZStack {
            Cinema2026.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    benefits
                    plans
                    ctaBlock
                    legal
                }
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 40)
            }

            closeButton
        }
        .task {
            await store.loadProducts()
            await store.refreshEntitlements()
        }
        .onChange(of: store.isPlus) { _, isPlus in
            if isPlus {
                Haptics.success()
                dismiss()
            }
        }
        .alert(
            "paywall.error.title",
            isPresented: .constant(store.lastError != nil),
            actions: {
                Button("common.ok") { store.lastError = nil }
            },
            message: {
                Text(store.lastError ?? "")
            }
        )
    }

    // MARK: - Секции

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(V4.accent.opacity(0.16))
                    .frame(width: 78, height: 78)
                Image(systemName: trigger.icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(V4.accent)
            }

            Text(LocalizedStringKey(trigger.titleKey))
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(V4.ink)

            Text(LocalizedStringKey(trigger.subtitleKey))
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(V4.muted)
                .padding(.horizontal, 8)
        }
        .padding(.top, 18)
    }

    private var benefits: some View {
        VStack(spacing: 12) {
            benefitRow("person.3.fill", "paywall.benefit.participants")
            benefitRow("mic.fill", "paywall.benefit.voice")
            benefitRow("rectangle.stack.badge.plus", "paywall.benefit.rooms")
            benefitRow("sparkles.tv.fill", "paywall.benefit.quality")
            benefitRow("bolt.fill", "paywall.benefit.ai")
        }
        .padding(16)
        .background(V4.cardBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func benefitRow(_ icon: String, _ key: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(V4.accent)
                .frame(width: 26)
            Text(LocalizedStringKey(key))
                .font(.system(size: 15))
                .foregroundStyle(V4.ink)
            Spacer(minLength: 0)
        }
    }

    private var plans: some View {
        VStack(spacing: 10) {
            planCard(.yearly)
            planCard(.monthly)
            planCard(.lifetime)
        }
    }

    private func planCard(_ id: StoreKitManager.ProductID) -> some View {
        let product = store.products.first { $0.id == id.rawValue }
        let isSelected = selected == id

        return Button {
            Haptics.selection()
            selected = id
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? V4.accent : V4.line, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(V4.accent).frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey("paywall.plan.\(id.shortName)"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(V4.ink)

                    if let product {
                        Text(subtitle(for: id, product: product))
                            .font(.system(size: 13))
                            .foregroundStyle(V4.muted)
                    } else {
                        Text(LocalizedStringKey("paywall.loading"))
                            .font(.system(size: 13))
                            .foregroundStyle(V4.muted)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(product?.displayPrice ?? "—")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(V4.ink)

                    if id == .yearly, let badge = savingsBadge {
                        Text(badge)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(V4.accent, in: Capsule())
                            .foregroundStyle(V4.accentInk)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(V4.raised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? V4.accent : V4.line, lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func subtitle(for id: StoreKitManager.ProductID, product: Product) -> String {
        switch id {
        case .yearly:
            let monthly = store.monthlyEquivalent(yearly: NSDecimalNumber(decimal: product.price).intValue)
            let trial = store.trialDescription(for: product)
            let perMonth = String(
                format: NSLocalizedString("paywall.plan.perMonth", comment: ""),
                monthly
            )
            return trial.isEmpty ? perMonth : "\(trial) · \(perMonth)"
        case .monthly:
            return NSLocalizedString("paywall.plan.monthly.note", comment: "")
        case .lifetime:
            return NSLocalizedString("paywall.plan.lifetime.note", comment: "")
        }
    }

    private var savingsBadge: String? {
        guard
            let monthly = store.products.first(where: { $0.id == StoreKitManager.ProductID.monthly.rawValue }),
            let yearly = store.products.first(where: { $0.id == StoreKitManager.ProductID.yearly.rawValue })
        else { return nil }

        let percent = store.yearlySavingsPercent(
            monthly: NSDecimalNumber(decimal: monthly.price).intValue,
            yearly: NSDecimalNumber(decimal: yearly.price).intValue
        )
        guard percent > 0 else { return nil }
        return String(format: NSLocalizedString("paywall.plan.savings", comment: ""), percent)
    }

    private var ctaBlock: some View {
        VStack(spacing: 12) {
            Button {
                Task { await purchase() }
            } label: {
                ZStack {
                    if isWorking {
                        ProgressView().tint(V4.accentInk)
                    } else {
                        Text(LocalizedStringKey("paywall.cta"))
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(V4.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(V4.accentInk)
            }
            .disabled(isWorking || store.products.isEmpty)
            .opacity(store.products.isEmpty ? 0.5 : 1)

            Button {
                Task { await restore() }
            } label: {
                Text(LocalizedStringKey("paywall.restore"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(V4.muted)
            }
            .disabled(isWorking)
        }
    }

    private var legal: some View {
        VStack(spacing: 10) {
            Text(LocalizedStringKey(
                selected == .lifetime ? "paywall.legal.lifetime" : "paywall.legal.subscription"
            ))
            .font(.system(size: 11))
            .multilineTextAlignment(.center)
            .foregroundStyle(V4.muted.opacity(0.85))

            HStack(spacing: 16) {
                Link(LocalizedStringKey("legal.terms"), destination: URL(string: "https://plink.app/terms")!)
                Link(LocalizedStringKey("legal.privacy"), destination: URL(string: "https://plink.app/privacy")!)
            }
            .font(.system(size: 12, weight: .medium))
            .tint(V4.accent)
        }
        .padding(.top, 4)
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    Haptics.light()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(V4.muted)
                        .frame(width: 32, height: 32)
                        .background(V4.raised, in: Circle())
                }
                .padding(.trailing, 16)
                .padding(.top, 10)
            }
            Spacer()
        }
    }

    // MARK: - Действия

    private func purchase() async {
        isWorking = true
        defer { isWorking = false }
        Haptics.light()
        await store.purchase(selected)
    }

    private func restore() async {
        isWorking = true
        defer { isWorking = false }
        await store.restore()
        if store.isPlus { Haptics.success() }
    }
}

private extension StoreKitManager.ProductID {
    var shortName: String {
        switch self {
        case .monthly: return "monthly"
        case .yearly: return "yearly"
        case .lifetime: return "lifetime"
        }
    }
}
