// Plink/Features/Premium2026/PlinkPlusPaywall.swift — Contextual paywall
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH
//
// M26 (доводка). Было пять дефектов — каждый стоил либо конверсии, либо
// доверия:
//
// 1. Предвыбор годового тарифа не работал никогда: условие
//    `$0.id.contains("yearly")`, а реальный id — "plink.plus.12m"
//    (PlinkProductID.yearly). Отрабатывал fallback `products.first`, а
//    loadProducts сортирует по цене возрастанию — то есть по умолчанию всегда
//    был выбран самый невыгодный месячный тариф.
// 2. CTA обещал «Попробовать <цена>» независимо от наличия вводного
//    предложения. Если триала нет или юзер его уже потратил — это обещание,
//    которого App Store не даёт.
// 3. PlanPicker рисовал все тарифы одинаковым рядом: ни доминанты, ни
//    экономии, ни цены за месяц. Годовой выглядел просто «дороже».
// 4. StoreManager — ObservableObject, но вьюха читала `.shared.products` без
//    подписки; список обновлялся побочно, через смену @State selectedID.
// 5. Хардкод русских строк и два force-unwrap URL посреди файла, где всё
//    остальное уже шло через LocalizationManager.
//
// Процент экономии и цена за месяц считаются из РЕАЛЬНЫХ StoreKit-периодов,
// а не из подстроки в id и не из хардкода — расхождение с чеком невозможно.

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
    // StoreManager — ObservableObject, но вьюха читала `.shared.products` без
    // подписки: список перерисовывался лишь потому, что в том же .task менялся
    // @State selectedID. Если стор отвечал позже или пусто — не перерисовывался.
    @ObservedObject private var store = StoreManager.shared
    @State private var selectedID: String?
    @State private var trialEligibleIDs: Set<String> = []

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
                            .foregroundStyle(Cinema2026.text)
                            .multilineTextAlignment(.center)
                        Text(L.string(.plusTagline))
                            .font(.subheadline)
                            .foregroundStyle(Cinema2026.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    PaywallBenefits(trigger: trigger)
                    planSection
                    legalSection
                }
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) { purchaseBar }

            closeButton
        }
        .task { await load() }
    }

    /// Тарифы, загрузка и внятный отказ. Раньше при пустом ответе стора здесь
    /// был пустой VStack и выключенная кнопка — без единого слова почему.
    @ViewBuilder
    private var planSection: some View {
        if !plans.isEmpty {
            PlanPicker(plans: plans, trialEligibleIDs: trialEligibleIDs, selectedID: $selectedID)
        } else if store.purchaseState == .loading {
            HStack(spacing: 10) {
                ProgressView()
                Text(L.string(.plusPlansLoading))
                    .font(.subheadline)
                    .foregroundStyle(Cinema2026.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        } else {
            VStack(spacing: 12) {
                Text(L.string(.plusPlansUnavailable))
                    .font(.subheadline)
                    .foregroundStyle(Cinema2026.secondary)
                    .multilineTextAlignment(.center)
                Button(L.string(.commonRetry)) {
                    Task { await load() }
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(Cinema2026.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
    }

    /// Кнопка покупки закреплена снизу: в скролле она уезжала за экран ровно
    /// тогда, когда юзер дочитывал список выгод.
    private var purchaseBar: some View {
        VStack(spacing: 8) {
            Button(action: purchase) {
                ZStack {
                    Text(ctaText).opacity(isBusy ? 0 : 1)
                    if isBusy {
                        ProgressView().tint(Cinema2026.background)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CinematicPrimaryButtonStyle())
            .disabled(selectedID == nil || isBusy)

            if let footnote = ctaFootnote {
                Text(footnote)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Cinema2026.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(14)
        .plinkGlass(.navigation, cornerRadius: 26)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .animation(.easeInOut(duration: 0.2), value: ctaFootnote)
    }

    private var legalSection: some View {
        VStack(spacing: 12) {
            Button(L.string(.plusRestore)) {
                Task { await store.restorePurchases() }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Cinema2026.secondary)
            .disabled(store.purchaseState == .restoring)

            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Cinema2026.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 14) {
                if let terms = PlinkLegal.terms {
                    Link(L.string(.plusTerms), destination: terms)
                }
                if let privacy = PlinkLegal.privacy {
                    Link(L.string(.plusPrivacy), destination: privacy)
                }
            }
            .font(.caption)
            .foregroundStyle(Cinema2026.secondary)
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Cinema2026.text)
                .frame(width: 44, height: 44)
                .background(Cinema2026.surface, in: Circle())
        }
        .padding(14)
        .accessibilityLabel(L.string(.close))
    }

    private var headline: String {
        switch trigger {
        case .emoji: return L.string(.plusHeadlineEmoji)
        case .theme: return L.string(.plusHeadlineTheme)
        case .capacity: return L.string(.plusHeadlineCapacity)
        case .cameraFilter: return L.string(.plusHeadlineCameraFilter)
        case .settings: return L.string(.plusHeadlineSettings)
        case .voiceChat: return L.string(.plusHeadlineCapacity)
        }
    }

    private var plans: [PlinkPlanOption] { PlinkPlanBuilder.build(from: store.products) }

    private var selectedPlan: PlinkPlanOption? { plans.first { $0.id == selectedID } }

    private var isBusy: Bool {
        store.purchaseState == .purchasing || store.purchaseState == .verifying
    }

    /// CTA больше не обещает триал по умолчанию: «Начать бесплатно» показывается
    /// только если у выбранного продукта есть вводное предложение И юзер имеет
    /// на него право. Иначе — прямая цена.
    private var ctaText: String {
        guard let plan = selectedPlan else { return L.string(.plusCtaFallback) }
        if trialEligibleIDs.contains(plan.id) { return L.string(.plusCtaTrial) }
        return String(format: L.string(.plusCtaSubscribeFormat), plan.product.displayPrice)
    }

    /// Приписка под кнопкой обязана называть цену после триала: «Начать
    /// бесплатно» без неё — ровно то, за что App Store Review отклоняет пейволл.
    private var ctaFootnote: String? {
        guard let plan = selectedPlan,
              trialEligibleIDs.contains(plan.id),
              let trial = plan.trialPeriod else { return nil }
        let free = String(format: L.string(.plusTrialFormat),
                          PlinkPlanBuilder.localizedDuration(trial))
        let then = String(format: L.string(.plusThenPriceFormat), plan.product.displayPrice)
        return "\(free), \(then)"
    }

    private func load() async {
        await store.loadProducts()
        // Предвыбор — самый выгодный тариф (он же первый в build()).
        // Старое условие `id.contains("yearly")` не совпадало НИКОГДА: реальный
        // id это "plink.plus.12m", поэтому отрабатывал fallback products.first,
        // а loadProducts сортирует по цене возрастанию — по умолчанию всегда
        // оказывался выбран самый невыгодный месячный тариф.
        if selectedID == nil || !store.products.contains(where: { $0.id == selectedID }) {
            selectedID = plans.first?.id
        }
        await refreshTrialEligibility()
    }

    /// Право на вводное предложение спрашивается у StoreKit, а не угадывается.
    private func refreshTrialEligibility() async {
        var eligible: Set<String> = []
        for product in store.products {
            guard let subscription = product.subscription,
                  subscription.introductoryOffer != nil else { continue }
            if await subscription.isEligibleForIntroOffer {
                eligible.insert(product.id)
            }
        }
        trialEligibleIDs = eligible
    }

    private func purchase() {
        guard let plan = selectedPlan else { return }
        Haptics.medium()
        Task {
            await store.purchase(plan.product)
            if PremiumStatusManager.shared.isPremium {
                Haptics.success()
                dismiss()
            }
        }
    }
}

// MARK: - Legal links
//
// They live in PlinkURLs (ios/Plink/Networking/PlinkURLs.swift): one origin for
// every public page, and it is the API host — the only host that actually serves
// those pages. What is left here is an alias, so the four call sites on the
// paywall and the sign-in screen stay as they are.
enum PlinkLegal {
    static var terms: URL? { PlinkURLs.terms }
    static var privacy: URL? { PlinkURLs.privacy }
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
        // Только реальные фичи — никаких обещаний, которых нет в продукте.
        // Функциональные: 20 участников (бэк: cap free=10) + приоритет в очереди ИИ.
        case .emoji: return [L.string(.plusBenefitPremiumReactions), L.string(.plusBenefitCustomEmoji), L.string(.plusBenefitAiPriority)]
        case .theme: return [L.string(.plusBenefitLiveThemes), L.string(.plusBenefitAvatarFrames), L.string(.plusBenefitCapacity20)]
        case .capacity: return [L.string(.plusBenefitCapacity20), L.string(.plusBenefitAiPriority), L.string(.plusBenefitCineBubbles)]
        case .cameraFilter: return [L.string(.plusBenefitVideoFilters), L.string(.plusBenefitCapacity20), L.string(.plusBenefitAiPriority)]
        case .settings: return [L.string(.plusBenefitCapacity20), L.string(.plusBenefitAiPriority), L.string(.plusBenefitLiveThemes)]
        // Голос в сборке не продаём (LiveKit выключен). Триггер .voiceChat
        // показывает те же реальные плюсы, что capacity/themes.
        case .voiceChat: return [L.string(.plusBenefitCapacity20), L.string(.plusBenefitLiveThemes), L.string(.plusBenefitAiPriority)]
        }
    }
}

// MARK: - Нормализованный тариф
//
// Цена за месяц считается из РЕАЛЬНОГО StoreKit-периода, а не из подстроки
// в id и не из хардкода — поэтому «экономия N%» физически не может разойтись
// с тем, что спишет App Store. Если владелец поменяет цены в App Store
// Connect, проценты пересчитаются сами.
struct PlinkPlanOption: Identifiable {
    let product: Product
    /// Цена, приведённая к одному месяцу. nil для не-подписочных продуктов.
    let monthlyPrice: Decimal?
    /// Экономия против самого дорогого месяца в наборе (обычно месячный тариф).
    let savingsPercent: Int?
    let isBestValue: Bool
    /// Период бесплатного триала, если у продукта есть вводное предложение
    /// именно типа .freeTrial. Право на него проверяется отдельно и асинхронно.
    let trialPeriod: Product.SubscriptionPeriod?

    var id: String { product.id }
}

// Весь билдер — MainActor: localizedDuration читает текущий язык из
// LocalizationManager, который изолирован на главном акторе, а все вызовы
// приходят из тел вьюх.
@MainActor
enum PlinkPlanBuilder {
    /// Длина периода в месяцах. Без switch — у Product.SubscriptionPeriod.Unit
    /// нет гарантии frozen, а @unknown default здесь только мешает.
    static func months(in period: Product.SubscriptionPeriod) -> Decimal {
        let value = Decimal(period.value)
        if period.unit == .year { return value * 12 }
        if period.unit == .month { return value }
        if period.unit == .week { return value * 7 / 30 }
        return value / 30 // .day и любые будущие единицы
    }

    static func freeTrialPeriod(of product: Product) -> Product.SubscriptionPeriod? {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return offer.period
    }

    /// Длительность периода словами, с правильными склонениями во всех трёх
    /// языках — это умеет DateComponentsFormatter, поэтому «7 дней / 7 days /
    /// 7天» не требует ни одного дополнительного ключа перевода.
    static func localizedDuration(_ period: Product.SubscriptionPeriod) -> String {
        var comps = DateComponents()
        if period.unit == .year {
            comps.year = period.value
        } else if period.unit == .month {
            comps.month = period.value
        } else if period.unit == .week {
            comps.day = period.value * 7
        } else {
            comps.day = period.value
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: LocalizationManager.shared.currentLanguage.rawValue)

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.year, .month, .day]
        formatter.maximumUnitCount = 1
        formatter.calendar = calendar
        return formatter.string(from: comps) ?? ""
    }

    static func build(from products: [Product]) -> [PlinkPlanOption] {
        // Подписки: считаем цену за месяц.
        let subs: [(product: Product, monthly: Decimal)] = products.compactMap { product in
            guard let period = product.subscription?.subscriptionPeriod else { return nil }
            let months = months(in: period)
            guard months > 0 else { return nil }
            return (product, product.price / months)
        }

        let baseline = subs.map(\.monthly).max()
        let bestValueID = subs.count > 1 ? subs.min(by: { $0.monthly < $1.monthly })?.product.id : nil

        var options: [PlinkPlanOption] = subs.map { entry in
            var savings: Int?
            if let baseline, baseline > 0, entry.monthly < baseline {
                let ratio = (baseline - entry.monthly) / baseline * 100
                let rounded = Int(NSDecimalNumber(decimal: ratio).doubleValue.rounded())
                if rounded >= 1 { savings = min(rounded, 99) }
            }
            return PlinkPlanOption(
                product: entry.product,
                monthlyPrice: entry.monthly,
                savingsPercent: savings,
                isBestValue: entry.product.id == bestValueID,
                trialPeriod: freeTrialPeriod(of: entry.product)
            )
        }

        // Самый выгодный тариф идёт первым — доминанта сверху, сразу под выгодами.
        options.sort { lhs, rhs in
            (lhs.monthlyPrice ?? .greatestFiniteMagnitude) < (rhs.monthlyPrice ?? .greatestFiniteMagnitude)
        }

        // Не-подписочные продукты (если когда-нибудь появится lifetime) —
        // показываем без расчёта экономии, в конце списка.
        options.append(contentsOf: products.filter { $0.subscription == nil }.map { product in
            PlinkPlanOption(
                product: product,
                monthlyPrice: nil,
                savingsPercent: nil,
                isBestValue: false,
                trialPeriod: nil
            )
        })

        return options
    }
}

struct PlanPickerRow: View {
    let plan: PlinkPlanOption
    let isSelected: Bool
    let trialEligible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            planRowContent
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var planRowContent: some View {
        VStack(alignment: .leading, spacing: plan.isBestValue ? 10 : 0) {
            if plan.isBestValue || plan.savingsPercent != nil {
                badgeRow
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.product.displayName)
                        .font(.system(size: plan.isBestValue ? 18 : 15, weight: .semibold))
                        .foregroundStyle(Cinema2026.text)
                    if let perMonth = perMonthText {
                        Text(perMonth)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Cinema2026.accent)
                            .monospacedDigit()
                    } else {
                        Text(plan.product.description)
                            .font(.caption)
                            .foregroundStyle(Cinema2026.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(plan.product.displayPrice)
                        .font(.system(size: plan.isBestValue ? 18 : 15, weight: .bold))
                        .foregroundStyle(Cinema2026.text)
                        .monospacedDigit()
                    if trialEligible, let trial = plan.trialPeriod {
                        Text(String(format: L.string(.plusTrialFormat),
                                    PlinkPlanBuilder.localizedDuration(trial)))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Cinema2026.accent)
                    }
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: plan.isBestValue ? 22 : 18))
                    .foregroundStyle(isSelected ? Cinema2026.accent : Cinema2026.tertiary)
            }
        }
        .padding(plan.isBestValue ? 18 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay(rowBorder)
        .contentShape(RoundedRectangle(cornerRadius: rowRadius, style: .continuous))
    }

    private var badgeRow: some View {
        HStack(spacing: 6) {
            if plan.isBestValue {
                Text(L.string(.plusBadgeBestValue))
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .kerning(0.4)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Cinema2026.accent, in: Capsule(style: .continuous))
                    .foregroundStyle(Cinema2026.background)
            }
            if let savings = plan.savingsPercent {
                Text(String(format: L.string(.plusSaveFormat), savings))
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Cinema2026.accent.opacity(0.16), in: Capsule(style: .continuous))
                    .foregroundStyle(Cinema2026.accent)
            }
            Spacer(minLength: 0)
        }
    }

    /// Цена за месяц показывается только там, где она несёт информацию:
    /// на месячном тарифе это была бы та же цифра дважды.
    private var perMonthText: String? {
        guard let monthly = plan.monthlyPrice,
              let period = plan.product.subscription?.subscriptionPeriod,
              PlinkPlanBuilder.months(in: period) > 1 else { return nil }
        return String(format: L.string(.plusPerMonthFormat),
                      monthly.formatted(plan.product.priceFormatStyle))
    }

    private var rowRadius: CGFloat {
        plan.isBestValue ? CinemaRadius.large : CinemaRadius.medium
    }

    // Лучший тариф — стекло (тот же материал, что таббар и карточки),
    // остальные — плоская поверхность. Разница материалом, а не только
    // рамкой: именно для этого liquid glass и нужен.
    @ViewBuilder
    private var rowBackground: some View {
        if plan.isBestValue {
            Color.clear
                .plinkGlass(.control,
                            cornerRadius: rowRadius,
                            tint: Cinema2026.accent.opacity(isSelected ? 0.22 : 0.10),
                            interactive: true)
        } else {
            RoundedRectangle(cornerRadius: rowRadius, style: .continuous)
                .fill(isSelected ? Cinema2026.accent.opacity(0.08) : Cinema2026.surface)
        }
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: rowRadius, style: .continuous)
            .stroke(
                isSelected ? Cinema2026.accent.opacity(plan.isBestValue ? 0.75 : 0.4) : .clear,
                lineWidth: plan.isBestValue ? 1.5 : 1
            )
    }

    private var accessibilityText: String {
        var parts = [plan.product.displayName, plan.product.displayPrice]
        if let perMonth = perMonthText { parts.append(perMonth) }
        if plan.isBestValue { parts.append(L.string(.plusBadgeBestValue)) }
        if let savings = plan.savingsPercent {
            parts.append(String(format: L.string(.plusSaveFormat), savings))
        }
        if trialEligible, let trial = plan.trialPeriod {
            parts.append(String(format: L.string(.plusTrialFormat),
                                PlinkPlanBuilder.localizedDuration(trial)))
        }
        return parts.joined(separator: ", ")
    }
}

struct PlanPicker: View {
    let plans: [PlinkPlanOption]
    let trialEligibleIDs: Set<String>
    @Binding var selectedID: String?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(plans) { plan in
                PlanPickerRow(
                    plan: plan,
                    isSelected: selectedID == plan.id,
                    trialEligible: trialEligibleIDs.contains(plan.id)
                ) {
                    Haptics.selection()
                    selectedID = plan.id
                }
            }
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.18), value: selectedID)
    }
}
