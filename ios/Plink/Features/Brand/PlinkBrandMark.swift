// Plink/Features/Brand/PlinkBrandMark.swift
//
// Знак, вордмарк и полный лого-блок PLINK для интерфейса. Геометрия —
// PlinkBrandGeometry.swift, снятая 1:1 с эталонного макета
// (brand/source/reference.png, пайплайн brand/tools/gen_swift.py). Цвета —
// PlinkBrandPalette: они постоянные, тема приложения знак не красит.
//
// Один знак на весь продукт: иконка на домашнем экране, сплэш, онбординг,
// вход. Раньше здесь жил teal-знак другой формы, и продукт встречал
// пользователя тремя разными логотипами.

import SwiftUI

// MARK: - Знак

/// Стрелка «play» из двух плоскостей: светлая A поверх тёмного хвоста B,
/// по кромке A — тонкий светлый рим, как на макете.
struct PlinkBrandMark: View {
    /// Высота знака в пунктах. Ширина следует пропорции макета.
    var size: CGFloat = 96
    /// Мягкое фиолетовое свечение под знаком. На иконке-плитке выключено.
    var glow = true

    static let aspect = PlinkBrandGeometry.markBox.width / PlinkBrandGeometry.markBox.height

    var body: some View {
        let width = size * Self.aspect
        ZStack {
            if glow {
                PlinkMarkSilhouette()
                    .fill(PlinkBrandPalette.violetLight.opacity(0.55))
                    .blur(radius: size * 0.16)
                    .offset(y: size * 0.05)
                    .frame(width: width, height: size)
            }
            PlinkMarkShapeB()
                .fill(PlinkBrandPalette.markB)
            PlinkMarkShapeA()
                .fill(PlinkBrandPalette.markA)
            PlinkMarkShapeA()
                .stroke(
                    PlinkBrandPalette.rim,
                    lineWidth: max(0.6, width * PlinkBrandPalette.rimWidthRatio)
                )
        }
        .frame(width: width, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Вордмарк

/// Надпись PLINK — контур с макета, заливка сверху-вниз #f4f4f5 → #c2bfdb.
/// Буквы с отверстиями рисуются even-odd, иначе P и R зальются целиком.
struct PlinkWordmark: View {
    /// Высота букв в пунктах.
    var size: CGFloat = 40

    static let aspect = PlinkBrandGeometry.wordmarkBox.width / PlinkBrandGeometry.wordmarkBox.height

    var body: some View {
        PlinkWordmarkShape()
            .fill(PlinkBrandPalette.wordmark, style: FillStyle(eoFill: true))
            .frame(width: size * Self.aspect, height: size)
            .accessibilityLabel("Plink")
    }
}

// MARK: - Теглайн

/// Разряженная строка под вордмарком в градиенте теглайна макета.
struct PlinkTagline: View {
    var text = "СМОТРИМ ВМЕСТЕ"
    var size: CGFloat = 11.5

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .tracking(size * 0.28)
            // Компенсация tracking после последнего символа — строка
            // иначе стоит чуть левее центра.
            .padding(.leading, size * 0.28)
            .foregroundStyle(PlinkBrandPalette.tagline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

// MARK: - Лого-блок

/// Знак, вордмарк и теглайн одной колонкой — шапка сплэша и входа.
struct PlinkLockup: View {
    var markSize: CGFloat = 96
    var wordmarkSize: CGFloat = 34
    var tagline: String? = "СМОТРИМ ВМЕСТЕ"
    var spacing: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            PlinkBrandMark(size: markSize)
            PlinkWordmark(size: wordmarkSize)
                .padding(.top, spacing)
            if let tagline {
                PlinkTagline(text: tagline)
                    .padding(.top, 12)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tagline.map { "Plink. \($0.capitalized)" } ?? "Plink")
    }
}

// MARK: - Плитка иконки

/// Знак на плитке цвета иконки — как приложение выглядит на домашнем экране.
/// Нужен там, где интерфейс показывает «Плинк» как приложение: баннер
/// уведомления в онбординге, строка «Открыть в Плинке».
struct PlinkAppIconTile: View {
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
            .fill(PlinkBrandPalette.background)
            .overlay {
                PlinkBrandMark(size: size * 0.46, glow: false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Превью

#if DEBUG
#Preview("Lockup") {
    ZStack {
        PlinkShellBackground()
        VStack(spacing: 40) {
            PlinkLockup()
            HStack(spacing: 24) {
                PlinkAppIconTile(size: 60)
                PlinkBrandMark(size: 60)
                PlinkWordmark(size: 24)
            }
        }
    }
    .preferredColorScheme(.dark)
}
#endif
