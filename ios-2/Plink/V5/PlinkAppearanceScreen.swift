//
//  PlinkAppearanceScreen.swift
//  Plink
//
//  P1 — Appearance screen with 5 sections + horizontal rails + live preview.
//  Implements Section 4 of PLINK_CUSTOMIZATION_AUTH_ADMIN_SPEC_FOR_GLM_5_2.md
//

import SwiftUI

internal struct AppearanceRootView: View {
    @Bindable var store: AppearanceStore
    @State private var paywallItem: AppearanceDescriptor?

    init(store: AppearanceStore) {
        self.store = store
    }

    /// Lazy shared store for app-wide access (used by SettingsView, etc.).
    /// Bridges entitlement to `PremiumStatusManager.shared`.
    @MainActor
    static let sharedStore: AppearanceStore = {
        let entitlement = DefaultEntitlementProvider()
        let store = AppearanceStore(entitlement: entitlement)
        Task { await entitlement.refresh() }
        return store
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                AppearanceSection(
                    title: "Оформление приложения",
                    explanation: "Общий визуальный язык Plink. Бесплатные темы статичны, живые темы — Plink+.",
                    items: store.items(of: .appStatic) + store.items(of: .appLive),
                    selectedID: store.appThemeID,
                    onSelect: { item in handleSelect(item) }
                )

                AppearanceSection(
                    title: "Оформление комнаты",
                    explanation: "Анимированный фон комнаты и общего чата. Выбирает хост, видно всем гостям.",
                    items: store.items(of: .roomLive),
                    selectedID: nil,
                    onSelect: { item in
                        paywallItem = item
                    },
                    ctaLabel: "Использовать при создании комнаты",
                    ctaAction: {
                        NotificationCenter.default.post(name: .plinkOpenAICreateWithRoomTheme, object: nil)
                    }
                )

                AppearanceSection(
                    title: "Стиль сообщений",
                    explanation: "BubbleStyle принадлежит отправителю. Сервер проверяет Plink+ при отправке.",
                    items: store.items(of: .bubbleStatic) + store.items(of: .bubbleAnimated),
                    selectedID: store.bubbleStyleID,
                    onSelect: { item in handleSelect(item) }
                )

                AppearanceSection(
                    title: "Стиль эмоджи",
                    explanation: "Базовый слой — системные Unicode. Авторские анимированные паки — Plink+.",
                    items: store.items(of: .emojiPack),
                    selectedID: store.emojiPackID,
                    onSelect: { item in handleSelect(item) }
                )

                MotionAccessibilitySection()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .background(Color.black.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $paywallItem) { item in
            PlinkPlusPaywallSheet(item: item) {
                paywallItem = nil
                Task { await store.select(item) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizationManager.shared.string(.apTitle))
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.white)
            Text(LocalizationManager.shared.string(.apSub))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 8)
    }

    private func handleSelect(_ item: AppearanceDescriptor) {
        Task { await store.select(item) }
    }
}

// MARK: - AppearanceSection

struct AppearanceSection: View {
    let title: String
    let explanation: String
    let items: [AppearanceDescriptor]
    let selectedID: String?
    let onSelect: (AppearanceDescriptor) -> Void
    var ctaLabel: String? = nil
    var ctaAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        AppearancePreviewTile(
                            item: item,
                            isSelected: selectedID == item.id,
                            onTap: { onSelect(item) }
                        )
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 4)
            }

            if let label = ctaLabel, let action = ctaAction {
                Button(action: action) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(label)
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.cyan)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

// MARK: - AppearancePreviewTile

struct AppearancePreviewTile: View {
    let item: AppearanceDescriptor
    let isSelected: Bool
    let onTap: () -> Void

    @State private var previewing = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    previewSwatch
                        .frame(width: 132, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.cyan : Color.white.opacity(0.08),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                        .scaleEffect(previewing ? 1.04 : 1.0)
                        .animation(.easeOut(duration: 0.35), value: previewing)

                    if item.premium {
                        PlinkPlusLockBadge()
                            .padding(6)
                    }
                }
                .contentShape(Rectangle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                    Text(item.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .frame(width: 132)
            // Phase 9.4: Accessibility
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.title), \(item.subtitle)\(item.premium ? ", Plink+" : "")")
            .accessibilityHint(isSelected ? "Уже выбрано" : "Выбрать оформление")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)  // Phase 9.4: 44pt target
        .onChange(of: isSelected) { _, new in
            if new {
                previewing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    previewing = false
                }
            }
        }
    }

    private var previewSwatch: some View {
        LinearGradient(
            colors: item.previewColors.map { Color(hex: $0) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: item.previewAsset)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .blendMode(.overlay)
        )
    }
}

// MARK: - PlinkPlusLockBadge

struct PlinkPlusLockBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill")
                .font(.system(size: 8, weight: .bold))
            Text("Plink+")
                .font(.system(size: 9, weight: .heavy))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .foregroundStyle(.yellow)
    }
}

// MARK: - MotionAccessibilitySection

struct MotionAccessibilitySection: View {
    @State private var livingMotion = true
    @State private var highContrast = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizationManager.shared.string(.apMotion))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            Text("Reduce Motion и Reduce Transparency всегда имеют приоритет над выбором пользователя.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))

            VStack(spacing: 1) {
                Toggle(isOn: $livingMotion) {
                    Label("Живое движение", systemImage: "waveform")
                }
                .tint(.cyan)

                Toggle(isOn: $highContrast) {
                    Label("Больше контраста", systemImage: "circle.lefthalf.filled")
                }
                .tint(.cyan)
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - PlinkPlusPaywallSheet

struct PlinkPlusPaywallSheet: View {
    let item: AppearanceDescriptor
    let onSubscribe: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: item.previewAsset)
                .font(.system(size: 48))
                .foregroundStyle(.cyan)

            Text("\(item.title) — Plink+")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text(LocalizationManager.shared.string(.apPlusPitch))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Button(action: { onSubscribe(); dismiss() }) {
                    Text(LocalizationManager.shared.string(.apGetPlus))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cyan)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button("Не сейчас") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - Notifications

internal extension Notification.Name {
    static let plinkOpenAICreateWithRoomTheme = Notification.Name("plink.openAICreateWithRoomTheme")
}
