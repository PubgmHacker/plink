// Plink/Features/Premium2026/PlinkPlusPaywall.swift — Contextual paywall
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §8

import SwiftUI
import StoreKit

struct PlinkPlusPaywall: View {
    enum Trigger: Identifiable { case emoji, theme, capacity, cameraFilter, settings, voiceChat

    var id: String {
        switch self {
        case .emoji: return "emoji"
        case .theme: return "theme"
        case .capacity: return "capacity"
        case .cameraFilter: return "cameraFilter"
        case .settings: return "settings"
        case .voiceChat: return "voiceChat"
        }
    }
}

    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?

    let trigger: Trigger

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Cinema2026.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    PaywallArtwork(trigger: trigger)
                        .frame(height: 250)

                    VStack(spacing: 8) {
                        Text(headline)
                            .font(.system(size: 28, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text(L.string(.plusTagline))
                            .font(.subheadline)
                            .foregroundStyle(Cinema2026.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    PaywallBenefits(trigger: trigger)
                    PlanPicker(selectedID: $selectedID)

                    Button(action: purchase) {
                        Text(ctaText)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CinematicPrimaryButtonStyle())
                    .disabled(selectedID == nil)
                    .padding(.horizontal, 24)

                    Button("Восстановить покупки") {
                        Task { await StoreManager.shared.restorePurchases() }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Cinema2026.secondary)

                    HStack(spacing: 14) {
                        Link("Условия", destination: URL(string: "https://plink.app/terms")!)
                        Link("Конфиденциальность", destination: URL(string: "https://plink.app/privacy")!)
                    }
                    .font(.caption)
                    .foregroundStyle(Cinema2026.secondary)
                }
                .padding(.bottom, 30)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
                    .background(Cinema2026.surface, in: Circle())
            }
            .padding(14)
            .accessibilityLabel("Закрыть")
        }
        .task {
            await StoreManager.shared.loadProducts()
            selectedID = StoreManager.shared.products.first { $0.id.contains("yearly") }?.id
                ?? StoreManager.shared.products.first?.id
        }
    }

    private var headline: String {
        switch trigger {
        case .emoji: return "Реагируйте по-своему."
        case .theme: return "Сделайте комнату своей."
        case .capacity: return "Соберите всех друзей."
        case .cameraFilter: return "Выглядите лучше в кадре."
        case .settings: return "Больше характера с Plink+."
        case .voiceChat: return "Голосовой чат в комнате."
        }
    }

    private var ctaText: String {
        if let product = StoreManager.shared.products.first(where: { $0.id == selectedID }) {
            return "Попробовать \(product.displayPrice)"
        }
        return "Попробовать Plink+"
    }

    private func purchase() {
        guard let product = StoreManager.shared.products.first(where: { $0.id == selectedID }) else { return }
        Task {
            await StoreManager.shared.purchase(product)
            if PremiumStatusManager.shared.isPremium { dismiss() }
        }
    }
}

struct PaywallArtwork: View {
    let trigger: PlinkPlusPaywall.Trigger

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Cinema2026.accent.opacity(0.2), Cinema2026.background],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: symbol)
                .font(.system(size: 60))
                .foregroundStyle(Cinema2026.accent)
        }
    }

    private var symbol: String {
        switch trigger {
        case .emoji: return "face.smiling.fill"
        case .theme: return "paintpalette.fill"
        case .capacity: return "person.3.fill"
        case .cameraFilter: return "camera.filters"
        case .settings: return "star.circle.fill"
        case .voiceChat: return "mic.fill"
        }
    }
}

struct PaywallBenefits: View {
    let trigger: PlinkPlusPaywall.Trigger

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(benefits, id: \.self) { benefit in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Cinema2026.accent)
                    Text(benefit)
                        .font(.subheadline)
                        .foregroundStyle(Cinema2026.text)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var benefits: [String] {
        switch trigger {
        // M18: только реальные фичи — никаких обещаний, которых нет в продукте.
        // Функциональные: 20 участников (бэк: cap free=10) + приоритет в очереди ИИ.
        case .emoji: return [L.string(.plusBenefitPremiumReactions), L.string(.plusBenefitCustomEmoji), L.string(.plusBenefitAiPriority)]
        case .theme: return [L.string(.plusBenefitLiveThemes), L.string(.plusBenefitAvatarFrames), L.string(.plusBenefitCapacity20)]
        case .capacity: return [L.string(.plusBenefitCapacity20), L.string(.plusBenefitAiPriority), L.string(.plusBenefitCineBubbles)]
        case .cameraFilter: return [L.string(.plusBenefitVideoFilters), L.string(.plusBenefitCapacity20), L.string(.plusBenefitAiPriority)]
        case .settings: return [L.string(.plusBenefitCapacity20), L.string(.plusBenefitAiPriority), L.string(.plusBenefitLiveThemes)]
        case .voiceChat: return [L.string(.plusBenefitVoiceChat), L.string(.plusBenefitCapacity20), L.string(.plusBenefitAiPriority)]
        }
    }
}

struct PlanPickerRow: View {
    let product: Product
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            planRowContent
        }
        .buttonStyle(.plain)
    }

    private var planRowContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(product.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                Text(product.description)
                    .font(.caption)
                    .foregroundStyle(Cinema2026.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(product.displayPrice)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Cinema2026.text)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Cinema2026.accent : Cinema2026.tertiary)
        }
        .padding(16)
        .background(rowBackground)
        .overlay(rowBorder)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: CinemaRadius.medium)
            .fill(isSelected ? Cinema2026.accent.opacity(0.08) : Cinema2026.surface)
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: CinemaRadius.medium)
            .stroke(isSelected ? Cinema2026.accent.opacity(0.4) : .clear, lineWidth: 1)
    }
}

struct PlanPicker: View {
    @Binding var selectedID: String?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(StoreManager.shared.products, id: \.id) { product in
                PlanPickerRow(product: product, isSelected: selectedID == product.id) {
                    selectedID = product.id
                }
            }
        }
        .padding(.horizontal, 24)
    }
}
