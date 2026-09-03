// Plink/Features/Onboarding2026/OnboardingDeviceFrame.swift
//
// Реальный скриншот раздела в рамке устройства для 2-го и 3-го экрана
// онбординга. Кадр стоит от верха сцены и уходит в фейд у текста (виден верх
// раздела — там смысл: кнопки «Создать комнату» / «Войти по коду», список
// чатов), слегка плавает и чуть повёрнут — телефон в руке, а не плоская
// картинка. На третьем экране сверху прилетает пуш-карточка: наглядно, о чём
// спрашивает кнопка «Разрешить и начать».
//
// Снимки — Assets.xcassets/Onboarding/*, наш собственный интерфейс
// (ios/ART_ASSET_LICENSES.md).

import SwiftUI

struct OnboardingDeviceFrame: View {
    let imageName: String
    var tilt: Double = 0
    var showsInviteToast = false

    @State private var floating = false
    @State private var toastShown = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.plinkFreezeAnimations) private var frozen
    @Environment(\.plinkAccessibilityOverride) private var override

    private var reduceMotion: Bool { systemReduceMotion || override.reduceMotion || frozen }

    /// Соотношение сторон снимков: 782×1700 (iPhone 17 Pro, без рамки).
    private let aspect: CGFloat = 782.0 / 1700.0

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width * 0.72, 300)
            let height = width / aspect
            let bezel: CGFloat = 8
            let outer = RoundedRectangle(cornerRadius: 40, style: .continuous)
            let inner = RoundedRectangle(cornerRadius: 40 - bezel, style: .continuous)

            ZStack(alignment: .top) {
                ZStack {
                    outer.fill(PlinkShell.surface)
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width - bezel * 2, height: height - bezel * 2)
                        .clipShape(inner)
                    outer.strokeBorder(PlinkShell.specular, lineWidth: 1)
                }
                .frame(width: width, height: height)
                .shadow(color: PlinkShell.deep.opacity(0.45), radius: 36, y: 18)
                .rotation3DEffect(.degrees(tilt), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .offset(y: floating ? -5 : 5)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .center)

                if showsInviteToast {
                    OnboardingInviteToast()
                        .padding(.horizontal, 18)
                        .padding(.top, 34)
                        .opacity(toastShown ? 1 : 0)
                        .offset(y: toastShown ? 0 : -18)
                        .scaleEffect(toastShown ? 1 : 0.96)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()
            .mask(
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.78),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
        }
        .onAppear {
            if reduceMotion {
                floating = false
                toastShown = true
                return
            }
            withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
                floating = true
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.6)) {
                toastShown = true
            }
        }
    }
}

/// Пуш-карточка «друг позвал» — иллюстрация к запросу уведомлений. Имя и
/// текст условные, без выдуманных названий фильмов.
private struct OnboardingInviteToast: View {
    var body: some View {
        HStack(spacing: 12) {
            PlinkAppIconTile(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Plink")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PlinkShell.text)
                    Spacer(minLength: 8)
                    Text(L10n.text(.onbNow))
                        .font(.system(size: 12))
                        .foregroundStyle(PlinkShell.muted)
                }
                Text(L10n.text(.onbInvitePreview))
                    .font(.system(size: 14))
                    .foregroundStyle(PlinkShell.text.opacity(0.92))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PlinkShell.surfaceLift.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(PlinkShell.specular, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
    }
}
