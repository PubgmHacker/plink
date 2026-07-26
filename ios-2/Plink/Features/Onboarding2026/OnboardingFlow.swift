// Plink/Features/Onboarding2026/OnboardingFlow.swift — 4-step MVP onboarding
// Fixed: TabView no longer steals taps from Далее/Начать; callbacks always fire.

import SwiftUI

struct OnboardingPageModel: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let body: String
}

struct OnboardingFlow: View {
    let onFinish: () -> Void
    let onSkip: (() -> Void)?

    @State private var selection = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages: [OnboardingPageModel] = [
        .init(id: "sync", symbol: "play.circle.fill",
              title: "Смотрите вместе",
              body: "YouTube, VK, Rutube — один таймкод у всех. Пауза у друга — пауза у вас."),
        .init(id: "ai", symbol: "sparkles",
              title: "AI Companion",
              body: "Подскажет, что включить, и поможет создать комнату."),
        .init(id: "themes", symbol: "moon.stars.fill",
              title: "Живые темы",
              body: "Aurora, Cosmos, Verdant, Magma — атмосфера комнаты в Plink+."),
        .init(id: "cross", symbol: "iphone.gen3",
              title: "Все экраны",
              body: "iOS, Android, Mac, Windows — один код комнаты на всех."),
    ]

    private var isLast: Bool { selection >= pages.count - 1 }

    var body: some View {
        ZStack {
            Cinema2026.background.ignoresSafeArea()
            CompactLivingBackdrop(primary: Cinema2026.accent, secondary: Cinema2026.amber)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Skip
                HStack {
                    Spacer()
                    if let onSkip, !isLast {
                        Button {
                            HapticManager.impact(.light)
                            onSkip()
                        } label: {
                            Text("Пропустить")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Cinema2026.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Пропустить онбординг")
                    }
                }
                .frame(height: 48)
                .padding(.horizontal, 12)

                // Pages — constrained so they cannot cover the bottom CTA
                TabView(selection: $selection) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        OnboardingPage(page: page)
                            .tag(index)
                            .contentShape(Rectangle())
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Dots
                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selection ? Cinema2026.accent : Cinema2026.divider)
                            .frame(width: index == selection ? 22 : 7, height: 7)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selection)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
                .accessibilityLabel("Шаг \(selection + 1) из \(pages.count)")

                // CTA — outside TabView so hits always work
                Button {
                    HapticManager.impact(.medium)
                    advance()
                } label: {
                    Text(isLast ? "Начать" : "Далее")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Cinema2026.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .accessibilityLabel(isLast ? "Начать" : "Далее")
                .accessibilityAddTraits(.isButton)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func advance() {
        if isLast {
            onFinish()
            return
        }
        let next = min(selection + 1, pages.count - 1)
        if reduceMotion {
            selection = next
        } else {
            withAnimation(.easeOut(duration: 0.28)) {
                selection = next
            }
        }
    }
}

struct OnboardingPage: View {
    let page: OnboardingPageModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)
            if page.id == "sync" {
                // M14: wow-момент — два телефона с одним таймкодом
                SyncedPhonesArt()
                    .accessibilityHidden(true)
            } else {
                Image(systemName: page.symbol)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Cinema2026.accent)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
            }
            Text(page.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Cinema2026.text)
                .multilineTextAlignment(.center)
            Text(page.body)
                .font(.system(size: 15))
                .foregroundStyle(Cinema2026.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - M14: wow-арт синхронного просмотра (два телефона, один таймкод)

private struct SyncedPhonesArt: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let progress = (t.truncatingRemainder(dividingBy: 24)) / 24
            let seconds = Int(t.truncatingRemainder(dividingBy: 24 * 60))
            HStack(spacing: 16) {
                phone(progress: progress, seconds: seconds)
                VStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Cinema2026.accent)
                    Text("синхронно")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Cinema2026.secondary)
                }
                phone(progress: progress, seconds: seconds)
            }
        }
        .frame(height: 190)
    }

    private func phone(progress: Double, seconds: Int) -> some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Cinema2026.accent.opacity(0.22))
                .frame(width: 96, height: 54)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Cinema2026.accent)
                )
            // Общий прогресс — идентичен на обоих «телефонах»
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule().fill(Cinema2026.accent)
                    .frame(width: max(6, 96 * progress))
            }
            .frame(width: 96, height: 4)
            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Cinema2026.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }
}
