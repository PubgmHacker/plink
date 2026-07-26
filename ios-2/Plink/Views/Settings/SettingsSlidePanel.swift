import SwiftUI

// MARK: - Settings Bottom Sheet (чистая шторка снизу)
//
// Премиальная шторка настроек, выезжающая снизу.
// • Переход: .move(edge: .bottom) — без просветов, плотно к краям
// • Анимация: spring(response: 0.35, dampingFraction: 0.8)
// • Затемнённый оверлей закрывается по тапу
// • Матское стекло (ultraThin) + неоновая обводка сверху
struct SettingsSlidePanel: View {
    @Binding var isPresented: Bool

    @State private var profileVM: ProfileViewModel?
    @State private var showFullProfile = false
    @State private var showPrivacy = false
    @State private var showNotifications = false
    @State private var showPremium = false
    @State private var showAdminPanel = false
    @State private var isPremium = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Затемнённый оверлей (закрывается по тапу) ──
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { closePanel() }

            // ── Шторка снизу ──
            VStack(spacing: 0) {
                // Grabber (ручка)
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                panelContent
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 520)
            .background(
                ZStack {
                    Cinema2026.background.opacity(0.95)
                    Rectangle().fill(.ultraThinMaterial)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                // Неоновая обводка только сверху
                RoundedRectangle(cornerRadius: 28)
                    .stroke(
                        LinearGradient(
                            colors: [Cinema2026.accent.opacity(0.4), .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.15)
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Cinema2026.accent.opacity(0.15), radius: 20, y: -2)
            .shadow(color: .black.opacity(0.6), radius: 30, y: -4)
        }
        .ignoresSafeArea(.keyboard)
        .task {
            if profileVM == nil {
                let api = APIClient.shared // 🔧 Pack v3: shared, не новый без токена
                let vm = ProfileViewModel(authService: AuthService(api: api))
                await vm.loadUser()
                profileVM = vm
                isPremium = PremiumStatusManager.shared.isPremium
            }
        }
        .sheet(isPresented: $showFullProfile) {
            if let profileVM {
                NavigationStack {
                    ProfileView(viewModel: profileVM, onSignOut: {
                        AuthService.shared.signOutLocally()
                        closePanel()
                    })
                }
            }
        }
        .sheet(isPresented: $showPrivacy) {
            PrivacySettingsView().preferredColorScheme(.dark).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsView().preferredColorScheme(.dark).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPremium) {
            PremiumManagementView(isPremium: $isPremium)
        }
        .sheet(isPresented: $showAdminPanel) {
            AdminRootView()
        }
    }

    // MARK: - Panel Content (компактный список)

    private var panelContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ── Шапка: аватар + имя (компактно) ──
                accountHeader
                    .padding(.top, 16)
                    .padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.06))

            // ── Меню ──
            VStack(spacing: 0) {
                compactRow(icon: "person.crop.circle.fill", title: "Аккаунт", color: Cinema2026.accent) {
                    showFullProfile = true
                }
                compactRow(icon: "lock.shield.fill", title: "Конфиденциальность", color: Cinema2026.accent) {
                    showPrivacy = true
                }
                compactRow(icon: "bell.badge.fill", title: "Уведомления", color: Cinema2026.accent) {
                    showNotifications = true
                }
                compactRow(icon: "sparkles", title: "Premium Подписка", color: Cinema2026.accent) {
                    showPremium = true
                }

                // Админ-панель (только для ADMIN)
                if profileVM?.user?.isAdmin == true {
                    compactRow(icon: "shield.lefthalf.filled", title: "Админ-панель", color: Cinema2026.accent) {
                        showAdminPanel = true
                    }
                }
            }
            .padding(.vertical, 4)

            Divider().background(Color.white.opacity(0.06))

            // ── Разработчик (компактно) ──
            developerRow
                .padding(.vertical, 8)

            Divider().background(Color.white.opacity(0.06))

            // ── Выйти ──
            Button {
                // Synchronous, guaranteed to work — no async, no network,
                // no try? that can swallow errors. Clears Keychain immediately.
                AuthService.shared.signOutLocally()
                closePanel()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.square.fill")
                        .font(.system(size: 16))
                    Text(LocalizationManager.shared.string(.prSignOut))
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(Cinema2026.danger)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Account Header (компактный)

    @ViewBuilder
    private var accountHeader: some View {
        Button {
            showFullProfile = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Cinema2026.accentAction)
                        .frame(width: 44, height: 44)
                    Text((profileVM?.displayName ?? "?").prefix(2).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                .ifTransform(isPremium) { view in
                    view.premiumStroke(lineWidth: 2)
                }
                .ifTransform(!isPremium) { view in
                    view.overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    PremiumUsernameText(
                        text: profileVM?.displayName ?? "Гость",
                        isPremium: isPremium,
                        isAdmin: profileVM?.user?.isAdmin ?? false,
                        font: .system(size: 15, weight: .bold)
                    )
                    Text("@\((profileVM?.username ?? "guest").lowercased())")
                        .font(.system(size: 12))
                        .foregroundColor(Cinema2026.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(Cinema2026.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Compact Row

    private func compactRow(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Cinema2026.text)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(Cinema2026.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Developer Row (компактный)

    private var developerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizationManager.shared.string(.stDeveloper))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Cinema2026.secondary)
                .padding(.horizontal, 18)

            HStack(spacing: 0) {
                devLink(icon: "paperplane.fill", color: Cinema2026.accent, url: "https://t.me/raveclone")
                devLink(icon: "play.rectangle.fill", color: Cinema2026.danger, url: "https://youtube.com/@raveclone")
                devLink(icon: "music.note.tv", color: Cinema2026.text, url: "https://tiktok.com/@raveclone")
                devLink(icon: "globe", color: Cinema2026.accent, url: "https://raveclone.com")
            }
            .padding(.horizontal, 10)
        }
    }

    private func devLink(icon: String, color: Color, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
    }

    // MARK: - Close

    private func closePanel() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            isPresented = false
        }
    }
}

// MARK: - Premium Animated Stroke (пульсирующая пурпурно-чёрная обводка)
/// Вращающийся AngularGradient — обводка пульсирует.
struct PremiumAnimatedStroke: ShapeStyle {
    @State private var rotation: Double = 0

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        AngularGradient(
            colors: [
                Cinema2026.accent,
                Cinema2026.background,
                Cinema2026.accent,
                Cinema2026.background,
                Cinema2026.accent,
            ],
            center: .center
        )
    }
}

// MARK: - Premium Username Text (переливающийся градиент)
/// 🔧 REDESIGNED: Removed [Premium] suffix — just the shimmering nickname.
/// Premium = shimmering animated gradient text.
/// Free = plain white-gray static text.
///
/// 🔧 RESTORED: admin username uses `adminShimmerText` (was removed in previous
/// commit — user wants it back, just smoother). The shimmer modifier itself
/// has been fixed to be smoother (easeInOut instead of linear, duplicated color
/// stops for seamless wrap-around). No visual conflict with avatar ring — they
/// use different reds and the avatar ring rotates slowly.
struct PremiumUsernameText: View {
    let text: String
    let isPremium: Bool
    var isAdmin: Bool = false
    var font: Font = .system(size: 18, weight: .bold)

    var body: some View {
        if isAdmin {
            // 🔧 RESTORED: Админ — переливающийся красный (теперь плавный)
            Text(text)
                .font(font)
                .adminShimmerText()
        } else if isPremium {
            Text(text)
                .font(font)
                .shimmerGradientText(colors: premiumColors)
        } else {
            Text(text)
                .font(font)
                .foregroundColor(Cinema2026.text)
        }
    }

    private let premiumColors: [Color] = [
        Cinema2026.accent,
        Cinema2026.accent,
        Cinema2026.accent,
        Cinema2026.accent,
    ]
}

// MARK: - Premium Management View (экран управления подпиской)
struct PremiumManagementView: View {
    @Binding var isPremium: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                Cinema2026.background

                ScrollView {
                    VStack(spacing: 24) {
                        // Статус подписки
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 48))
                                .foregroundStyle(
                                    LinearGradient(colors: [Cinema2026.accent, Cinema2026.accent, Cinema2026.accent],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                )

                            if isPremium {
                                Text(LocalizationManager.shared.string(.stPlusActive))
                                    .font(.title2.bold())
                                    .foregroundColor(Cinema2026.text)
                                if let expiry = PremiumStatusManager.shared.subscriptionExpiry {
                                    Text("Действует до \(expiry, format: .dateTime.month().day().year())")
                                        .font(.subheadline)
                                        .foregroundColor(Cinema2026.secondary)
                                } else {
                                    Text(LocalizationManager.shared.string(.stActive))
                                        .font(.subheadline)
                                        .foregroundColor(Cinema2026.secondary)
                                }
                            } else {
                                Text(LocalizationManager.shared.string(.stPlusInactive))
                                    .font(.title2.bold())
                                    .foregroundColor(Cinema2026.text)
                                Text(LocalizationManager.shared.string(.stSubscribeHint))
                                    .font(.subheadline)
                                    .foregroundColor(Cinema2026.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                        .glassCard(cornerRadius: 20, opacity: 0.04)

                        if isPremium {
                            // Управление подпиской
                            Button {
                                // 🔧 Pack v3: Открыть управление подпиской �� App Store
                                if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "creditcard.fill")
                                    Text(LocalizationManager.shared.string(.stManageSub))
                                    Spacer()
                                }
                                .font(.subheadline.bold())
                                .foregroundColor(Cinema2026.accent)
                                .padding(16)
                                .glassCard(cornerRadius: 16, opacity: 0.06)
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                // 🔧 FIX C9: Use deactivatePremium() instead of setPremium(false)
                                PremiumStatusManager.shared.deactivatePremium()
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                    isPremium = false
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                    Text(LocalizationManager.shared.string(.stCancelSub))
                                    Spacer()
                                }
                                .font(.subheadline)
                                .foregroundColor(Cinema2026.danger)
                                .padding(16)
                                .glassCard(cornerRadius: 16, opacity: 0.04)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                showPaywall = true
                            } label: {
                                HStack {
                                    Spacer()
                                    Text(LocalizationManager.shared.string(.stSubscribe))
                                        .font(.headline.bold())
                                    Spacer()
                                }
                                .foregroundColor(.white)
                                .padding(.vertical, 16)
                                .background(Cinema2026.accentAction)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Cinema2026.accent)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPaywall) {
            // M17: единый paywall Plink+ во всём приложении
            PlinkPlusPaywall(trigger: .settings)
                .onDisappear { isPremium = PremiumStatusManager.shared.isPremium }
        }
    }
}
