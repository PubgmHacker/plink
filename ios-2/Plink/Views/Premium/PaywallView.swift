import SwiftUI

// MARK: - Paywall v3 — "Pure Black × Ice Glow"
/// Полноэкранный пейволл. Цены в рублях. Порядок: 1 → 3 → 12 месяцев.
/// Фон — чёрный с переливающимся сине-голубым градиентом.
struct PaywallView: View {
    let onPurchase: () -> Void
    let onRestore: () -> Void
    let onDismiss: () -> Void

    @State private var selectedPlan = 2  // По умолчанию — 12 месяцев (выгодный)
    @State private var glowPulse = false
    @State private var crownFloat = false
    @Environment(\.dismiss) private var dismiss

    private let plans: [(title: String, price: String, perMonth: String, badge: String?)] = [
        ("1 месяц", "150 ₽", "150 ₽/мес", nil),
        ("3 месяца", "390 ₽", "130 ₽/мес", "−13%"),
        ("12 месяцев", "990 ₽", "82 ₽/мес", "−45%"),
    ]

    var body: some View {
        ZStack {
            // Чёрный фон + сине-голубые blur-пятна
            Cinema2026.background
            CompactLivingBackdrop()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    // ── Закрыть ──────────────────────────────────────
                    HStack {
                        Spacer()
                        Button { onDismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.raveTextSecondary)
                                .frame(width: 36, height: 36)
                                .glassCard(cornerRadius: 18, opacity: 0.06)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    heroSection
                    planCards
                    ctaButton
                    comparisonSection
                    footerLinks
                }
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Hero (корона + glow)

    private var heroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                // Внешний пульсирующий glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.ravePrimary.opacity(glowPulse ? 0.35 : 0.1), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 90
                        )
                    )
                    .frame(width: 180, height: 180)
                    .scaleEffect(glowPulse ? 1.1 : 0.9)

                // Ледяной круг
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Cinema2026.accent,
                                Color(hex: 0x3D8DE0),
                                Color(hex: 0x22D3EE),
                                Cinema2026.accent,
                            ],
                            center: .center
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: Color.ravePrimary.opacity(0.5), radius: 24)

                Image(systemName: "crown.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                    .offset(y: crownFloat ? -3 : 3)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    glowPulse = true
                    crownFloat = true
                }
            }

            VStack(spacing: 8) {
                Text(LocalizationManager.shared.string(.pwPremium))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.raveTextPrimary)

                Text(LocalizationManager.shared.string(.pwSub))
                    .font(.system(size: 16))
                    .foregroundColor(.raveTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Plan Cards (1 → 3 → 12 месяцев)

    private var planCards: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    let plan = plans[index]
                    planCard(
                        title: plan.title,
                        price: plan.price,
                        perMonth: plan.perMonth,
                        badge: plan.badge,
                        isSelected: selectedPlan == index
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedPlan = index
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func planCard(title: String, price: String, perMonth: String, badge: String?, isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.raveAccent)
                        .clipShape(Capsule())
                } else {
                    Text(" ")
                        .font(.system(size: 10))
                        .padding(.vertical, 3)
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.raveTextPrimary)

                Text(price)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(isSelected ? .ravePrimary : .raveTextPrimary)

                Text(perMonth)
                    .font(.system(size: 10))
                    .foregroundColor(.raveTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassCard(cornerRadius: 16, opacity: isSelected ? 0.12 : 0.04)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.ravePrimary.opacity(0.6) : Color.white.opacity(0.06), lineWidth: isSelected ? 1.5 : 0.5)
            )
            .shadow(color: isSelected ? Color.ravePrimary.opacity(0.25) : .clear, radius: 14, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA

    private var ctaButton: some View {
        VStack(spacing: 10) {
            Button {
                HapticManager.impact(.medium)
                onPurchase()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18))
                    Text(LocalizationManager.shared.string(.pwTrial))
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.raveGradient)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.ravePrimary.opacity(0.4), radius: 16, y: 8)
            }
            .buttonStyle(PremiumButtonStyle())
            .padding(.horizontal, 24)

            Text("Затем \(plans[selectedPlan].price) — \(plans[selectedPlan].title.lowercased())")
                .font(.system(size: 13))
                .foregroundColor(.raveTextSecondary)
        }
    }

    // MARK: - Comparison (Free vs Premium)

    private var comparisonSection: some View {
        VStack(spacing: 0) {
            comparisonRow(icon: "person.3.fill", title: "Участники в комнате", free: "До 4", premium: "До 50")
            divider
            comparisonRow(icon: "rectangle.stack.fill.badge.play", title: "Реклама", free: "Есть", premium: "Нет")
            divider
            comparisonRow(icon: "4k.tv", title: "Качество видео", free: "720p", premium: "4K HDR")
            divider
            comparisonRow(icon: "paintpalette.fill", title: "Темы оформления", free: "1", premium: "Безлимит")
            divider
            comparisonRow(icon: "bubble.left.and.bubble.right.fill", title: "Цветной ник", free: "—", premium: "✓")
        }
        .padding(.vertical, 8)
        .glassCard(cornerRadius: 18, opacity: 0.04)
        .padding(.horizontal, 20)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 48)
    }

    private func comparisonRow(icon: String, title: String, free: String, premium: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.ravePrimary)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 15))
                .foregroundColor(.raveTextPrimary)

            Spacer()

            Text(free)
                .font(.system(size: 13))
                .foregroundColor(.raveTextTertiary)
                .frame(width: 50, alignment: .center)

            HStack(spacing: 4) {
                if premium == "✓" {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                }
                Text(premium)
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(.ravePrimary)
            .frame(width: 60, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footerLinks: some View {
        VStack(spacing: 8) {
            Button { onRestore() } label: {
                Text(LocalizationManager.shared.string(.pwRestore))
                    .font(.system(size: 14))
                    .foregroundColor(.raveTextSecondary)
            }

            Text(LocalizationManager.shared.string(.pwCancelAnytime))
                .font(.system(size: 12))
                .foregroundColor(.raveTextTertiary)
        }
    }
}

// MARK: - Premium Glow Badge (анимированный, для профилей и комнат)
/// Анимированная корона с пульсирующим свечением для premium-юзеров.
struct PremiumGlowBadge: View {
    var size: CGFloat = 20
    @State private var glow = false

    var body: some View {
        Image(systemName: "crown.fill")
            .font(.system(size: size))
            .foregroundColor(.ravePrimary)
            .shadow(color: .ravePrimary.opacity(glow ? 0.8 : 0.3), radius: glow ? 8 : 4)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    glow = true
                }
            }
    }
}

#Preview {
    PaywallView(onPurchase: {}, onRestore: {}, onDismiss: {})
}
