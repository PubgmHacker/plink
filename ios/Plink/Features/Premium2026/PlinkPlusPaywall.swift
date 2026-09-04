// PlinkPlusPaywall.swift — the Plink+ sheet.
//
// Plink+ is sold only on the website (YooKassa, webpay.ts). The sheet shows the
// web tariffs, explains what is included and hands the user over to /plus with
// the chosen tariff preselected. The entitlement comes back through
// GET /api/billing/entitlements: the sheet re-reads it when the app returns to
// the foreground and on the "already paid" button, then closes itself once
// Plink+ is active.
import SwiftUI

struct PlinkPlusPaywall: View {
    enum Trigger: Identifiable {
        case emoji, theme, capacity, settings

        var id: String {
            switch self {
            case .emoji: return "emoji"
            case .theme: return "theme"
            case .capacity: return "capacity"
            case .settings: return "settings"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var plansLoader = PlinkWebPlansLoader()
    @ObservedObject private var premium = PremiumStatusManager.shared
    @State private var selectedID = "12m"
    @State private var awaitingReturn = false
    @State private var refreshing = false
    @State private var notice: String?

    let trigger: Trigger

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Cinema2026.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    hero
                    sectionLabel(LocalizationManager.shared.string(.plusIncluded))
                    featureGrid
                    sectionLabel(LocalizationManager.shared.string(.plusChoosePlan))
                        .padding(.top, 26)
                    planRow
                    footnotes
                        .padding(.top, 16)
                }
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .bottom) { ctaBar }
            closeButton
        }
        .task { await plansLoader.load() }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from Safari after paying: pull the entitlement quietly.
            guard phase == .active, awaitingReturn else { return }
            awaitingReturn = false
            Task { await refreshEntitlement(announce: false) }
        }
        .onChange(of: premium.isPremium) { _, isPremium in
            if isPremium {
                Haptics.success()
                dismiss()
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            PaywallNebula(animated: !reduceMotion)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Cinema2026.background.opacity(0.55), location: 0.55),
                    .init(color: Cinema2026.background, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 12) {
                wordmark
                Text(headline)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .tracking(-0.7)
                    .foregroundStyle(Cinema2026.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(LocalizationManager.shared.string(.plusTagline))
                    .font(.system(size: 14.5))
                    .foregroundStyle(Cinema2026.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 350)
        .clipped()
    }

    private var wordmark: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("Plink")
                .foregroundStyle(Cinema2026.text)
            Text("+")
                .foregroundStyle(PlinkPlusBrand.gradient)
        }
        .font(.system(size: 42, weight: .heavy, design: .rounded))
        .tracking(-1.4)
        .accessibilityLabel("Plink+")
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11.5, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(Cinema2026.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.bottom, 10)
    }

    // MARK: - Features

    private var featureGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(PaywallFeature.all) { feature in
                PaywallFeatureTile(feature: feature, highlighted: feature.id == highlightedFeatureID)
            }
        }
        .padding(.horizontal, 18)
    }

    /// The tile that explains why the paywall opened gets the accent ring.
    private var highlightedFeatureID: String? {
        switch trigger {
        case .emoji: return "reactions"
        case .theme: return "themes"
        case .capacity: return "capacity"
        case .settings: return nil
        }
    }

    // MARK: - Plans

    private var plans: [PlinkWebPlan] { plansLoader.plans }

    private var selectedPlan: PlinkWebPlan? {
        plans.first { $0.id == selectedID } ?? plans.last
    }

    /// Savings against paying month by month, in whole percent.
    private func savings(for plan: PlinkWebPlan) -> Int? {
        guard let monthly = plans.min(by: { $0.days < $1.days }), monthly.id != plan.id,
              monthly.monthlyRub > 0, plan.monthlyRub < monthly.monthlyRub else { return nil }
        let ratio = (monthly.monthlyRub - plan.monthlyRub) / monthly.monthlyRub * 100
        let percent = Int(NSDecimalNumber(decimal: ratio).doubleValue.rounded())
        return percent > 0 ? percent : nil
    }

    private var planRow: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(plans) { plan in
                PaywallPlanCard(
                    plan: plan,
                    savings: savings(for: plan),
                    popular: plan.id == "12m" && plans.count > 1,
                    selected: selectedPlan?.id == plan.id
                ) {
                    guard selectedID != plan.id else { return }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selectedID = plan.id
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14) // room for the "popular" badge above the cards
    }

    // MARK: - Footnotes, CTA, close

    private var footnotes: some View {
        VStack(spacing: 12) {
            if plansLoader.state == .failed {
                Label(LocalizationManager.shared.string(.plusPricesStale), systemImage: "wifi.exclamationmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Cinema2026.amber)
                    .multilineTextAlignment(.center)
            }
            if let notice {
                Text(notice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Cinema2026.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            Button {
                Task { await refreshEntitlement(announce: true) }
            } label: {
                HStack(spacing: 6) {
                    if refreshing {
                        ProgressView().controlSize(.small).tint(Cinema2026.secondary)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(LocalizationManager.shared.string(.plusAlreadyPaid))
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Cinema2026.secondary)
            }
            .disabled(refreshing)
            HStack(spacing: 14) {
                if let terms = PlinkLegal.terms {
                    Link(LocalizationManager.shared.string(.plusTerms), destination: terms)
                }
                if let privacy = PlinkLegal.privacy {
                    Link(LocalizationManager.shared.string(.plusPrivacy), destination: privacy)
                }
            }
            .font(.caption)
            .foregroundStyle(Cinema2026.secondary)
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.2), value: notice)
    }

    private var ctaBar: some View {
        VStack(spacing: 8) {
            Button(action: openSite) {
                HStack(spacing: 8) {
                    Text(ctaText)
                        .font(.system(size: 16, weight: .bold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(PlinkPlusBrand.gradient, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.18), lineWidth: 0.6))
                .shadow(color: PlinkPlusBrand.violet.opacity(0.42), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(selectedPlan == nil)
            Text(LocalizationManager.shared.string(.plusSiteNote))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Cinema2026.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .plinkGlass(.navigation, cornerRadius: 28)
        .padding(.horizontal, 14)
        // Грунт под панель. safeAreaInset(.bottom) ставит бар НАД safe area, а полосу
        // домашнего индикатора под ним заполняет то, что лежит сзади, — живой текст
        // скролла. На замере 03-paywall.png этот текст читался с контрастом 6.44:1
        // и резался посередине слова («обложки-переливы в профиле»). Растяжка фона
        // вниз сквозь safe area гасит полосу до ~1:1, стекло панели остаётся живым.
        .background(alignment: .bottom) {
            LinearGradient(
                // Сплошной цвет уже к 0.62 высоты: градиент начинается на 772 pt,
                // 0.62 · 96 = 59.5 pt → полная непрозрачность ровно с 831.5 pt,
                // то есть к началу полосы индикатора (832 pt). Линейная растяжка
                // до самого низа оставляла там 62 % и текст всё ещё читался
                // остатком (замер: размах 1.57:1 вместо 1.00:1).
                stops: [
                    .init(color: Cinema2026.background.opacity(0), location: 0),
                    .init(color: Cinema2026.background, location: 0.62)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 96)
            // Не ignoresSafeArea: содержимое safeAreaInset живёт в своей области,
            // и «игнорировать» ему уже нечего — замер v3 показал ту же полосу
            // 7.34:1. Отрицательный отступ выводит грунт на 40 pt ниже панели
            // физически: её низ на 828 pt, значит хвост доходит до 868 pt и
            // накрывает всю полосу индикатора (832–852 pt).
            .padding(.bottom, -40)
            .allowsHitTesting(false)
        }
        .padding(.bottom, 4)
    }

    private var ctaText: String {
        guard let plan = selectedPlan else { return LocalizationManager.shared.string(.plusSiteCta) }
        return "\(LocalizationManager.shared.string(.plusSiteCta)) · \(PlinkRub.format(plan.priceRub))"
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .plinkGlass(.control, in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
        .padding(.trailing, 16)
        .accessibilityLabel(LocalizationManager.shared.string(.close))
    }

    private var headline: String {
        switch trigger {
        case .emoji: return LocalizationManager.shared.string(.plusHeadlineEmoji)
        case .theme: return LocalizationManager.shared.string(.plusHeadlineTheme)
        case .capacity: return LocalizationManager.shared.string(.plusHeadlineCapacity)
        case .settings: return LocalizationManager.shared.string(.plusHeadlineSettings)
        }
    }

    // MARK: - Actions

    private func openSite() {
        guard let plan = selectedPlan, let url = PlinkURLs.plusSite(plan: plan.id) else { return }
        Haptics.medium()
        awaitingReturn = true
        openURL(url)
    }

    private func refreshEntitlement(announce: Bool) async {
        guard !refreshing else { return }
        refreshing = true
        notice = nil
        await StoreManager.shared.refreshEntitlement()
        refreshing = false
        // `onChange(of: premium.isPremium)` closes the sheet on success.
        if announce, !PremiumStatusManager.shared.isPremium {
            notice = LocalizationManager.shared.string(.plusNotActiveYet)
            try? await Task.sleep(for: .seconds(4))
            notice = nil
        }
    }
}

enum PlinkLegal {
    static var terms: URL? { PlinkURLs.terms }
    static var privacy: URL? { PlinkURLs.privacy }
}

enum PlinkPlusBrand {
    static let violet = Color(hex: "#A855F7")
    static let gradient = LinearGradient(
        colors: [Color(hex: "#C084FC"), Color(hex: "#A855F7"), Color(hex: "#7C3AED")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - Hero backdrop

/// Three blurred orbs drifting slowly — the same nebula as the brand site.
/// Offsets animate on the render server; nothing re-evaluates per frame.
private struct PaywallNebula: View {
    let animated: Bool
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Color(hex: "#110A22")
                Circle()
                    .fill(Color(hex: "#7C3AED").opacity(0.78))
                    .frame(width: w * 0.95)
                    .blur(radius: 70)
                    .offset(x: w * (drift ? 0.34 : 0.26), y: -h * (drift ? 0.20 : 0.30))
                Circle()
                    .fill(Color(hex: "#EC4899").opacity(0.42))
                    .frame(width: w * 0.66)
                    .blur(radius: 64)
                    .offset(x: -w * (drift ? 0.28 : 0.36), y: h * (drift ? 0.06 : -0.04))
                Circle()
                    .fill(Color(hex: "#38BDF8").opacity(0.26))
                    .frame(width: w * 0.5)
                    .blur(radius: 60)
                    .offset(x: w * (drift ? 0.02 : 0.10), y: -h * 0.48)
            }
            .frame(width: w, height: h)
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

// MARK: - Feature tiles

private struct PaywallFeature: Identifiable {
    let id: String
    let glyph: V4Glyph
    let title: String
    let subtitle: String

    @MainActor static var all: [PaywallFeature] {
        [
            PaywallFeature(id: "themes", glyph: .appearance,
                           title: LocalizationManager.shared.string(.plusFeatThemes), subtitle: LocalizationManager.shared.string(.plusFeatThemesSub)),
            PaywallFeature(id: "capacity", glyph: .people3,
                           title: LocalizationManager.shared.string(.plusFeatCapacity), subtitle: LocalizationManager.shared.string(.plusFeatCapacitySub)),
            PaywallFeature(id: "reactions", glyph: .heart,
                           title: LocalizationManager.shared.string(.plusFeatReactions), subtitle: LocalizationManager.shared.string(.plusFeatReactionsSub)),
            PaywallFeature(id: "ai", glyph: .sparkle,
                           title: LocalizationManager.shared.string(.plusFeatAI), subtitle: LocalizationManager.shared.string(.plusFeatAISub)),
            PaywallFeature(id: "looks", glyph: .person,
                           title: LocalizationManager.shared.string(.plusFeatLooks), subtitle: LocalizationManager.shared.string(.plusFeatLooksSub)),
            PaywallFeature(id: "bubbles", glyph: .chat,
                           title: LocalizationManager.shared.string(.plusFeatBubbles), subtitle: LocalizationManager.shared.string(.plusFeatBubblesSub)),
        ]
    }
}

private struct PaywallFeatureTile: View {
    let feature: PaywallFeature
    let highlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle().fill(PlinkPlusBrand.violet.opacity(highlighted ? 0.30 : 0.14))
                V4GlyphIcon(glyph: feature.glyph, size: 17, filled: highlighted, weight: .semibold)
                    .foregroundStyle(highlighted ? Color(hex: "#D8B4FE") : Cinema2026.text)
            }
            .frame(width: 36, height: 36)
            Text(feature.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Cinema2026.text)
            Text(feature.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Cinema2026.secondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        // Плитка «что входит» — слой КОНТЕНТА, и стекла на ней быть не должно:
        // правило шапки PlinkGlass.swift («стекло живёт только на слое навигации
        // и управления»). Раньше здесь стояло .plinkGlass(.control), и на чёрном
        // фоне рефракции нечего было преломлять, кроме единственного яркого
        // пятна рядом — надписи «ЧТО ВХОДИТ» в 10 pt над сеткой. Линза затягивала
        // её внутрь плитки, и заголовок раздела читался ВТОРОЙ раз поверх иконки
        // с контрастом 2,79:1. Проба доказала связь: подменённый текст «ЖЖЖ ЩЩЩ»
        // тут же проступил призраком вместо прежнего. Разведение на 20 pt не
        // помогло — линза тянет и с большего расстояния, лечится только снятием
        // стекла с плитки.
        .background(Cinema2026.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    highlighted ? PlinkPlusBrand.violet.opacity(0.6) : V4.line,
                    lineWidth: highlighted ? 1.2 : 1
                )
        )
    }
}

// MARK: - Plan cards

private struct PaywallPlanCard: View {
    let plan: PlinkWebPlan
    let savings: Int?
    let popular: Bool
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Cinema2026.secondary)
                Text(PlinkRub.format(plan.priceRub))
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .tracking(-0.4)
                    .foregroundStyle(Cinema2026.text)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                if plan.months > 1 {
                    Text(String(format: LocalizationManager.shared.string(.plusPerMonthFormat), PlinkRub.format(plan.monthlyRub)))
                        .font(.system(size: 11))
                        .foregroundStyle(Cinema2026.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if let savings {
                    Text(String(format: LocalizationManager.shared.string(.plusSaveFormat), savings))
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Color(hex: "#D8B4FE"))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(PlinkPlusBrand.violet.opacity(0.22), in: Capsule())
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .plinkGlass(.control, cornerRadius: 20, interactive: true)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selected ? PlinkPlusBrand.violet : Color.white.opacity(0.08),
                            lineWidth: selected ? 1.6 : 0.8)
            )
            .shadow(color: PlinkPlusBrand.violet.opacity(selected ? 0.32 : 0), radius: 14, y: 6)
            .overlay(alignment: .top) {
                if popular {
                    Text(LocalizationManager.shared.string(.plusPopular).uppercased())
                        .font(.system(size: 9.5, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(PlinkPlusBrand.gradient, in: Capsule())
                        .offset(y: -11)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(selectionTraits)
    }

    private var accessibilityText: String {
        "\(title), \(PlinkRub.format(plan.priceRub))"
    }

    private var selectionTraits: AccessibilityTraits {
        selected ? .isSelected : []
    }

    private var title: String {
        switch plan.days {
        case ..<45: return LocalizationManager.shared.string(.plusPlanMonth)
        case ..<180: return LocalizationManager.shared.string(.plusPlanQuarter)
        case ..<400: return LocalizationManager.shared.string(.plusPlanYear)
        default: return plan.title
        }
    }
}
