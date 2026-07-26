//  OnboardingView.swift
//  Plink — M39
//
//  Три слайда, не четыре. Каждый лишний экран онбординга — минус к активации.
//  Кнопка «Пропустить» видна всегда.

import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private struct Slide: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let text: String
    }

    private let slides: [Slide] = [
        Slide(icon: "play.rectangle.on.rectangle.fill",
              title: "Смотрите вместе — кадр в кадр",
              text: "Rutube, VK Видео, Одноклассники, Дзен, YouTube и ваши файлы. Рассинхрон ниже 50 мс."),
        Slide(icon: "bubble.left.and.text.bubble.right.fill",
              title: "Реакции и голос прямо в комнате",
              text: "Эмодзи поверх видео, чат и голосовой режим — без переключения приложений."),
        Slide(icon: "wand.and.stars",
              title: "ИИ подберёт, что смотреть",
              text: "Скажите настроение — получите подборку за пару секунд."),
    ]

    var body: some View {
        ZStack {
            Cinema2026.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Пропустить") {
                        Haptics.light()
                        onFinish()
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(V4.muted)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                TabView(selection: $page) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        VStack(spacing: 18) {
                            Spacer()
                            Image(systemName: slide.icon)
                                .font(.system(size: 64, weight: .light))
                                .foregroundStyle(V4.accent)
                            Text(slide.title)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(V4.ink)
                                .multilineTextAlignment(.center)
                            Text(slide.text)
                                .font(.system(size: 15))
                                .foregroundStyle(V4.muted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 34)
                            Spacer()
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 6) {
                    ForEach(0..<slides.count, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? V4.accent : V4.line)
                            .frame(width: index == page ? 22 : 7, height: 7)
                            .animation(.spring(response: 0.3), value: page)
                    }
                }
                .padding(.bottom, 22)

                Button {
                    Haptics.medium()
                    if page < slides.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page < slides.count - 1 ? "Дальше" : "Начать")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(V4.accent))
                        .foregroundStyle(V4.accentInk)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
        .onAppear { Haptics.prepare() }
    }
}
