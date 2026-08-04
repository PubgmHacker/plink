// Plink/Features/Onboarding2026/OnboardingFlow.swift
//
// Первый запуск: три экрана, каждый продаёт одну мысль — смотрим синхронно,
// лента трейлеров, ИИ собирает комнату. Четвёртого («все экраны») больше нет:
// кросс-платформенность — не причина установить приложение, а сноска.
//
// Что изменено против прошлой версии и почему:
//
//   • Было четыре статичных экрана с иконкой SF Symbols и кнопкой «Далее» —
//     ровно тот устаревший паттерн, от которого отказываемся. Теперь историю
//     несёт движение: на каждом экране живёт своя сцена.
//
//   • «Пропустить» уехало из правого верхнего угла вниз, к основной кнопке.
//     Верхний правый угол недосягаем большим пальцем (решение из брифа #1), а
//     выход должен быть под рукой, а не в самом неудобном месте экрана.
//
//   • Разрешение на уведомления раньше запрашивалось молча в конце — системный
//     диалог без объяснения. Теперь последний экран сам объясняет, зачем оно:
//     «друг позвал смотреть» — и пользователь нажимает «Разрешить» осознанно.
//     Кто не хочет, нажимает «Не сейчас» и системного диалога не видит вовсе.
//
//   • Свайп между экранами остаётся (TabView), стрелок нет — как в ленте.

import SwiftUI
import UserNotifications

struct OnboardingFlow: View {
    let onFinish: () -> Void
    let onSkip: (() -> Void)?

    @State private var page = 0
    @State private var isAskingPermission = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pageCount = 3

    private var isLast: Bool { page >= Self.pageCount - 1 }

    var body: some View {
        ZStack {
            PlinkTheatre.velvetDeep.ignoresSafeArea()
            ProjectorBeamBackground()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    OnboardingSyncScene().tag(0)
                    OnboardingReelsScene().tag(1)
                    OnboardingAIScene().tag(2)
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
                    .fill(index == page ? PlinkTheatre.screen : PlinkTheatre.hairline)
                    .frame(width: index == page ? 22 : 7, height: 7)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: page)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Шаг \(page + 1) из \(Self.pageCount)")
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
                    Text(isLast ? "Разрешить и начать" : "Далее")
                        .opacity(isAskingPermission ? 0 : 1)
                    if isAskingPermission {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(PlinkTheatre.velvetDeep)
                    }
                }
            }
            .buttonStyle(AuthPrimaryButtonStyle())
            .disabled(isAskingPermission)
            .accessibilityLabel(isLast ? "Разрешить уведомления и начать" : "Далее")

            Button {
                HapticManager.impact(.light)
                // «Пропустить» и «Не сейчас» ведут в одно место: внутрь
                // приложения без запроса разрешения.
                (onSkip ?? onFinish)()
            } label: {
                Text(isLast ? "Не сейчас" : "Пропустить")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PlinkTheatre.muted)
                    .frame(maxWidth: .infinity)
                    // 44 pt — минимальный хит-таргет, даже у второстепенной кнопки.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isAskingPermission)
            .accessibilityLabel(isLast ? "Начать без уведомлений" : "Пропустить знакомство")
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

// MARK: - Отдельная сцена для рендера кадров
//
// Свайп между экранами в офскрин-рендере не воспроизвести, а судить о
// редизайне надо по всем трём. Точка входа отдаёт одну сцену по номеру.

struct OnboardingScenePreview: View {
    let page: Int

    var body: some View {
        ZStack {
            PlinkTheatre.velvetDeep.ignoresSafeArea()
            ProjectorBeamBackground().ignoresSafeArea()
            switch page {
            case 1:  OnboardingReelsScene()
            case 2:  OnboardingAIScene()
            default: OnboardingSyncScene()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Общая рамка экрана

/// Сцена сверху, текст снизу — одинаково на всех экранах, чтобы при свайпе
/// заголовки не прыгали по вертикали.
struct OnboardingScaffold<Scene: View>: View {
    let title: String
    let body_: String
    @ViewBuilder var scene: Scene

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            scene
                .frame(height: 240)
                .accessibilityHidden(true)

            Spacer(minLength: 24)

            Text(title)
                .font(.system(size: 27, weight: .heavy))
                .tracking(-0.6)
                .foregroundStyle(PlinkTheatre.screen)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            Text(body_)
                .font(.system(size: 15))
                .foregroundStyle(PlinkTheatre.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 16)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(body_)")
    }
}

// MARK: - Экран 1: синхронный просмотр

/// Два телефона с одним таймкодом. Смысл — не «две картинки», а то, что
/// полоса прогресса и время на них идут ОДИНАКОВО: это и есть продукт.
struct OnboardingSyncScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var animated: Bool {
        !reduceMotion && scenePhase == .active
    }

    var body: some View {
        OnboardingScaffold(
            title: "Смотрите вместе — кадр в кадр",
            body_: "YouTube, VK, Rutube. Один таймкод у всех: поставил на паузу — пауза у друга."
        ) {
            if animated {
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    phones(at: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                // Статичный кадр: Reduce Motion и фон приложения.
                phones(at: 8)
            }
        }
    }

    private func phones(at t: TimeInterval) -> some View {
        let loop = t.truncatingRemainder(dividingBy: 20) / 20
        let seconds = Int(loop * 143)
        // Подпись «синхронно» — под парой, а не между картами: в середине она
        // налезала на оба телефона и читалась обрезанной.
        return VStack(spacing: 14) {
            HStack(spacing: 18) {
                phone(progress: loop, seconds: seconds, tilt: -4)
                phone(progress: loop, seconds: seconds, tilt: 4)
            }
            HStack(spacing: 7) {
                V4GlyphIcon(glyph: .watchTogether, size: 14, weight: .regular)
                Text("один таймкод")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.7)
            }
            .foregroundStyle(PlinkTheatre.muted)
        }
    }

    private func phone(progress: Double, seconds: Int, tilt: Double) -> some View {
        VStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(PlinkTheatre.velvet)
                .frame(width: 96, height: 56)
                .overlay {
                    // Свет экрана — то, что делает картинку «кино», а не схемой.
                    RadialGradient(
                        colors: [PlinkTheatre.tealDeep.opacity(0.55), .clear],
                        center: .center, startRadius: 2, endRadius: 62
                    )
                }
                .overlay {
                    V4GlyphIcon(glyph: .play, size: 15, filled: true, weight: .regular)
                        .foregroundStyle(PlinkTheatre.screen)
                }

            ZStack(alignment: .leading) {
                Capsule().fill(PlinkTheatre.screen.opacity(0.14))
                Capsule().fill(PlinkTheatre.screen)
                    .frame(width: max(5, 96 * progress))
            }
            .frame(width: 96, height: 4)

            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(PlinkTheatre.muted)
                .monospacedDigit()
        }
        .padding(11)
        .plinkGlass(.control, cornerRadius: 20)
        .rotationEffect(.degrees(tilt))
    }
}

// MARK: - Экран 2: лента трейлеров

/// Колода карточек, верхняя чуть отъезжает — намёк на пролистывание лентой.
/// Стрелок нет: жест показывается движением, а не иконкой (решение брифа #1).
struct OnboardingReelsScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lift = false

    var body: some View {
        OnboardingScaffold(
            title: "Лента трейлеров",
            body_: "Свайп вверх — следующий трейлер. Понравился — комната собирается одним касанием."
        ) {
            ZStack {
                // Веером и с поворотом, а не строго друг за другом: при
                // одинаковом центре колода читалась как одна карточка.
                card(x: -30, y: 20, angle: -8, scale: 0.88, opacity: 0.40)
                card(x: 30, y: 20, angle: 8, scale: 0.88, opacity: 0.40)
                card(x: 0, y: lift ? -14 : 0, angle: 0, scale: 1, opacity: 1)
            }
            .onAppear {
                guard !reduceMotion, scenePhase == .active else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    lift = true
                }
            }
        }
    }

    private func card(
        x: CGFloat,
        y: CGFloat,
        angle: Double,
        scale: CGFloat,
        opacity: Double
    ) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(PlinkTheatre.velvet)
            .frame(width: 128, height: 190)
            .overlay {
                RadialGradient(
                    colors: [PlinkTheatre.tealDeep.opacity(0.42), .clear],
                    center: UnitPoint(x: 0.5, y: 0.32), startRadius: 4, endRadius: 150
                )
            }
            .overlay(alignment: .bottomLeading) {
                // Строки-заглушки вместо реального текста: это иллюстрация, а
                // не превью конкретного фильма.
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(PlinkTheatre.screen.opacity(0.85)).frame(width: 70, height: 7)
                    Capsule().fill(PlinkTheatre.muted.opacity(0.55)).frame(width: 46, height: 5)
                }
                .padding(14)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(PlinkTheatre.hairline, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .scaleEffect(scale)
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
            .opacity(opacity)
    }
}

// MARK: - Экран 3: ИИ собирает комнату + разрешение на уведомления

/// Здесь же объясняем, зачем нужны уведомления — экран, на котором стоит
/// главная кнопка «Разрешить и начать».
struct OnboardingAIScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var pulse = false

    var body: some View {
        OnboardingScaffold(
            title: "ИИ соберёт комнату",
            body_: "Скажите, что хочется посмотреть — Plink найдёт видео, создаст комнату и позовёт друзей. Уведомления нужны, чтобы вы не пропустили приглашение."
        ) {
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .strokeBorder(
                            PlinkTheatre.tealDeep.opacity(0.30 - Double(ring) * 0.08),
                            lineWidth: 1
                        )
                        .frame(width: 108 + CGFloat(ring) * 46)
                        .scaleEffect(pulse ? 1.06 : 0.98)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 2.2)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(ring) * 0.28),
                            value: pulse
                        )
                }

                Circle()
                    .fill(PlinkTheatre.velvet)
                    .frame(width: 96)
                    .overlay {
                        RadialGradient(
                            colors: [PlinkTheatre.tealDeep.opacity(0.6), .clear],
                            center: .center, startRadius: 2, endRadius: 70
                        )
                    }
                    .overlay {
                        V4GlyphIcon(glyph: .sparkle, size: 34, weight: .regular)
                            .foregroundStyle(PlinkTheatre.screen)
                    }
                    .overlay {
                        Circle().strokeBorder(PlinkTheatre.hairline, lineWidth: 1)
                    }
            }
            .onAppear {
                guard !reduceMotion, scenePhase == .active else { return }
                pulse = true
            }
        }
    }
}
