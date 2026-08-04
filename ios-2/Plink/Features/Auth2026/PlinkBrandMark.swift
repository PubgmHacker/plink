// Plink/Features/Auth2026/PlinkBrandMark.swift
//
// Знак бренда на экранах входа и сплэша — та же сцена, что в иконке
// приложения: светящийся экран, двое перед ним, тёплый свет против холодного
// синего.
//
// Зачем заменил PlinkFrameMark. Тот знак был серым стеклянным квадратом с
// синим play-треугольником внутри и не совпадал НИ С ЧЕМ: ни с иконкой на
// домашнем экране, ни с акцентом приложения, ни с фоном экрана входа. Человек
// ставит приложение, видит на иконке двоих перед экраном — и на первом же
// экране получает другой логотип. Плюс серое стекло на почти чёрном фоне
// давало ровно тот «мутный» вид, за который экран и забраковали.
//
// Здесь ни одного серого пикселя: холодный синий корпус, тёплый свет экрана,
// силуэты цветом фона. Формы совпадают с scripts/make_app_icons.py —
// пропорции взяты оттуда, чтобы знак и иконка читались как одна вещь.

import SwiftUI

struct PlinkBrandMark: View {
    /// Сторона знака. Внутренние размеры считаются от неё, поэтому знак
    /// одинаково собирается и в 56, и в 200 pt.
    var size: CGFloat = 72
    /// Надпись PLINK на экране — как в иконке. Ниже ~64 pt буквы неразборчивы,
    /// поэтому по умолчанию выключена: на экране входа рядом и так стоит
    /// крупный вордмарк.
    var showsScreenLabel: Bool = false

    var body: some View {
        ZStack {
            // Корпус: холодный синий, тот же градиент, что у иконки.
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [PlinkBrand.blueLift, PlinkBrand.blueDeep],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Свет от экрана — то, что делает знак «кино», а не схемой.
            RadialGradient(
                colors: [PlinkBrand.warm.opacity(0.55), .clear],
                center: UnitPoint(x: 0.5, y: 0.34),
                startRadius: size * 0.02,
                endRadius: size * 0.52
            )

            scene
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay {
            // Тонкий тёплый контур: отделяет знак от почти чёрного фона, не
            // добавляя серого.
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(PlinkBrand.warm.opacity(0.16), lineWidth: max(0.5, size * 0.008))
        }
        .shadow(color: PlinkBrand.blueDeep.opacity(0.55), radius: size * 0.16, y: size * 0.07)
        .accessibilityHidden(true)
    }

    /// Экран, два силуэта и диван — пропорции те же, что в иконке.
    private var scene: some View {
        GeometryReader { proxy in
            let s = proxy.size.width
            ZStack(alignment: .topLeading) {
                // Экран.
                RoundedRectangle(cornerRadius: s * 0.035, style: .continuous)
                    .fill(PlinkBrand.warmHot)
                    .frame(width: s * 0.54, height: s * 0.31)
                    .overlay {
                        if showsScreenLabel {
                            Text("PLINK")
                                .font(.system(size: s * 0.115, weight: .heavy))
                                .tracking(s * 0.004)
                                .foregroundStyle(PlinkBrand.blueInk)
                                .minimumScaleFactor(0.5)
                                .padding(.horizontal, s * 0.04)
                        }
                    }
                    .offset(x: s * 0.23, y: s * 0.185)

                // Два силуэта: голова + плечи, цветом «темноты зала».
                ForEach([0.355, 0.645], id: \.self) { fx in
                    silhouette(s: s)
                        .offset(x: s * (fx - 0.125), y: s * 0.533)
                }

                // Диван — одна плотная полоса, не доходит до краёв.
                RoundedRectangle(cornerRadius: s * 0.05, style: .continuous)
                    .fill(PlinkBrand.blueInk)
                    .frame(width: s * 0.69, height: s * 0.135)
                    .offset(x: s * 0.155, y: s * 0.795)
            }
        }
    }

    private func silhouette(s: CGFloat) -> some View {
        VStack(spacing: -s * 0.045) {
            Circle()
                .fill(PlinkBrand.blueInk)
                .frame(width: s * 0.164, height: s * 0.164)
            RoundedRectangle(cornerRadius: s * 0.082, style: .continuous)
                .fill(PlinkBrand.blueInk)
                .frame(width: s * 0.25, height: s * 0.18)
        }
        .frame(width: s * 0.25, alignment: .center)
    }
}

// MARK: - Цвета знака

/// Палитра бренда — ровно те же значения, что в scripts/make_app_icons.py.
/// Живёт отдельно от PlinkTheatre (монохромный шелл) и от V4 (палитра
/// продукта): это цвета ЗНАКА, они не должны меняться вместе с темой комнаты.
enum PlinkBrand {
    /// Верх корпуса — светлее, чтобы знак не выглядел тёмным пятном.
    static let blueLift = Color(red: 46 / 255, green: 96 / 255, blue: 208 / 255)
    /// Низ корпуса.
    static let blueDeep = Color(red: 14 / 255, green: 38 / 255, blue: 104 / 255)
    /// «Темнота зала»: силуэты и диван.
    static let blueInk = Color(red: 9 / 255, green: 22 / 255, blue: 60 / 255)
    /// Тёплый свет экрана — единственное тёплое пятно бренда.
    static let warm = Color(red: 255 / 255, green: 214 / 255, blue: 148 / 255)
    static let warmHot = Color(red: 255 / 255, green: 236 / 255, blue: 205 / 255)

    /// Тинт для стеклянных поверхностей на экране входа.
    ///
    /// Не `blueLift`: тот — цвет корпуса знака, насыщенный, и на стекле
    /// заливал поля синим целиком, так что они перестали читаться как поля
    /// ввода и начали спорить с главной кнопкой. Здесь глубокий приглушённый
    /// синий: он лишь снимает серость, не превращая поле в плашку.
    static let glassTint = Color(red: 22 / 255, green: 44 / 255, blue: 96 / 255)
}
