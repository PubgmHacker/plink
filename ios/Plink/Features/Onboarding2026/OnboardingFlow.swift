// Plink/Features/Onboarding2026/OnboardingFlow.swift
//
// Первый запуск: три живых экрана на палитре шелла (PlinkShell) — те же цвета,
// что у иконки, сплэша и экрана входа, поэтому онбординг читается как
// продолжение входа, а не как отдельный «туториал».
//
//   1. «Смотрим вместе» — стена реальных постеров: полка Иви, которую
//      показывает Главная, три дрейфующие колонки. Без сети — тайлы фирменного
//      градиента. Границы использования — ios/ART_ASSET_LICENSES.md.
//   2. «Комнаты» — реальный скриншот раздела в рамке устройства.
//   3. «Общение» — реальный скриншот «Чатов» и честное объяснение, зачем
//      уведомления. Системный диалог — только по кнопке «Разрешить и начать»;
//      «Не сейчас» заходит в приложение без диалога.
//
// Сохранено из прошлой версии: свайп (TabView), обе кнопки внизу в зоне
// большого пальца, запрос уведомлений осознанно на последнем экране.
// Всё движение гейтится Reduce Motion / plinkFreezeAnimations.

import SwiftUI
import UserNotifications

struct OnboardingFlow: View {
    let onFinish: () -> Void
    let onSkip: (() -> Void)?

    @State private var page = 0
    @State private var isAskingPermission = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.plinkFreezeAnimations) private var frozen
    @Environment(\.plinkAccessibilityOverride) private var override

    private static let pageCount = OnboardingPage.allCases.count

    private var isLast: Bool { page >= Self.pageCount - 1 }
    private var reduceMotion: Bool { systemReduceMotion || override.reduceMotion || frozen }

    var body: some View {
        ZStack {
            PlinkShell.background.ignoresSafeArea()

            // Сияние чуть уезжает за активной страницей: слева — комнаты,
            // справа — общение. Фон увеличен, чтобы сдвиг не открывал край.
            PlinkShellBackground(glowCenter: UnitPoint(x: 0.5, y: 0.3))
                .scaleEffect(1.12)
                .offset(x: reduceMotion ? 0 : CGFloat(page - 1) * -26)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: page)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(OnboardingPage.allCases) { item in
                        OnboardingScene(page: item)
                            .tag(item.rawValue)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                dots
                    .padding(.bottom, 18)

                actions
                    .padding(.horizontal, 22)
                    .padding(.bottom, 26)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Индикатор

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<Self.pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == page ? PlinkShell.text : PlinkShell.hairline)
                    .frame(width: index == page ? 22 : 7, height: 7)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: page)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(L10n.text(.onbStepA11y, page + 1, Self.pageCount))
    }

    // MARK: Кнопки

    /// На последнем экране главная кнопка запрашивает уведомления и заходит в
    /// приложение, вторичная — заходит без них. До последнего экрана — «Далее»
    /// и «Пропустить» рядом, обе в зоне большого пальца.
    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                HapticManager.impact(.medium)
                if isLast {
                    Task { await finishAllowingNotifications() }
                } else {
                    advance()
                }
            } label: {
                ZStack {
                    Text(isLast ? L10n.text(.onbAllowStart) : L10n.text(.onbNext))
                        .opacity(isAskingPermission ? 0 : 1)
                    if isAskingPermission {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(PlinkShell.text)
                    }
                }
            }
            .buttonStyle(AuthPrimaryButtonStyle())
            .disabled(isAskingPermission)
            .accessibilityLabel(isLast ? L10n.text(.onbAllowStartA11y) : L10n.text(.onbNext))

            Button {
                HapticManager.impact(.light)
                // «Пропустить» и «Не сейчас» ведут в одно место: внутрь
                // приложения без запроса разрешения.
                (onSkip ?? onFinish)()
            } label: {
                Text(isLast ? L10n.text(.onbNotNow) : L10n.text(.onbSkip))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PlinkShell.muted)
                    .frame(maxWidth: .infinity)
                    // 44 pt — минимальный хит-таргет, даже у второстепенной кнопки.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isAskingPermission)
            .accessibilityLabel(isLast ? L10n.text(.onbStartWithout) : L10n.text(.onbSkipTourA11y))
        }
    }

    private func advance() {
        let next = min(page + 1, Self.pageCount - 1)
        if reduceMotion {
            page = next
        } else {
            withAnimation(.easeOut(duration: 0.3)) { page = next }
        }
    }

    /// Спрашиваем разрешение здесь, а не молча в гейте: пользователь только что
    /// прочитал, зачем оно нужно. Отказ — не ошибка, идём дальше молча.
    private func finishAllowingNotifications() async {
        isAskingPermission = true
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        #if canImport(UIKit)
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
        #endif
        isAskingPermission = false
        onFinish()
    }
}

// MARK: - Страницы

/// Три страницы онбординга. Сцена и текст одной страницы живут вместе, чтобы
/// DesignAuditShots мог снять любую из них без свайпа: `OnboardingScene(page:)`.
enum OnboardingPage: Int, CaseIterable, Identifiable {
    case catalog
    case rooms
    case chats

    var id: Int { rawValue }

    var eyebrow: String {
        switch self {
        case .catalog: return L10n.text(.onbEyebrowCatalog)
        case .rooms: return L10n.text(.onbEyebrowRooms)
        case .chats: return L10n.text(.onbEyebrowChats)
        }
    }

    var glyph: V4Glyph {
        switch self {
        case .catalog: return .watchTogether
        case .rooms: return .play
        case .chats: return .chat
        }
    }

    var title: String {
        switch self {
        case .catalog: return L10n.text(.onbTitleCatalog)
        case .rooms: return L10n.text(.onbTitleRooms)
        case .chats: return L10n.text(.onbTitleChats)
        }
    }

    var body: String {
        switch self {
        case .catalog:
            return L10n.text(.onbBodyCatalog)
        case .rooms:
            return L10n.text(.onbBodyRooms)
        case .chats:
            return L10n.text(.onbBodyChats)
        }
    }
}

/// Одна страница: сцена сверху, текст снизу. Текстовый блок одной высоты на
/// всех страницах, чтобы при свайпе заголовки не прыгали по вертикали.
struct OnboardingScene: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 0) {
            scene
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    V4GlyphIcon(glyph: page.glyph, size: 13, weight: .regular)
                    Text(page.eyebrow.uppercased())
                        .font(.system(size: 11.5, weight: .semibold))
                        .tracking(1.6)
                }
                .foregroundStyle(PlinkShell.accentSoft)

                Text(page.title)
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(PlinkShell.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.body)
                    .font(.system(size: 16))
                    .lineSpacing(3)
                    .foregroundStyle(PlinkShell.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(page.title). \(page.body)")
        }
    }

    @ViewBuilder
    private var scene: some View {
        switch page {
        case .catalog:
            OnboardingCatalogWall()
                .padding(.horizontal, 22)
                .padding(.top, 8)
        case .rooms:
            OnboardingDeviceFrame(imageName: "OnboardingShotRooms", tilt: -2)
                .padding(.top, 14)
        case .chats:
            OnboardingDeviceFrame(imageName: "OnboardingShotChats", tilt: 2, showsInviteToast: true)
                .padding(.top, 14)
        }
    }
}
