// Plink/Features/Auth2026/PlinkBrandMark.swift
//
// Знак бренда на экранах входа и сплэша — та же сцена, что в иконке
// приложения: светящийся экран, двое перед ним.
//
// ПОЧЕМУ ЗНАК БОЛЬШЕ НЕ СИНИЙ (редизайн 04.08.2026)
//
// Синий в Plink — это ОДНА ИЗ ТЕМ (electric/cosmos), а не цвет бренда. Рядом
// с ней живут verdant (зелёная), magma (красная), aurora и bloom (розовые),
// ember (янтарная), violet. Знак с синим корпусом и синими силуэтами означал,
// что человек, выбравший Magma, видит на входе и на сплэше чужой цвет — не
// свой и даже не нейтральный. Логотип не может принадлежать одной теме.
//
// Второй вариант — сделать знак «подхватывающим» акцент темы — отвергнут
// осознанно. Ни Telegram, ни Raycast, ни Arc, ни системная схема
// tinted-иконок Apple, ни themed icons Android так не делают: во всех этих
// системах цвет ГЛИФА не зависит от акцента пользователя, потому что знак,
// меняющий цвет, перестаёт быть узнаваемым знаком. Цвет темы допускается
// только ВОКРУГ знака (гало, подсветка), но не внутри него.
//
// Решение: знак нейтральный. Графитовый корпус, силуэты цвета темноты зала,
// и ровно одно цветное пятно — ТЁПЛЫЙ СВЕТ ЭКРАНА. Тёплый свет универсален:
// включённый экран тёплый в любой теме, поэтому он не спорит ни с зелёной,
// ни с красной, ни с синей. Это и есть постоянный цвет бренда — эквивалент
// «телеграмного синего», только у нас это тёплый свет, а не хюэ.
//
// Побочная выгода. На домашнем экране Plink стоит рядом с Rave, Teleparty,
// Kast и Discord — они ВСЕ тёмно-синие. Графит с тёплым светом отличает нас
// от них сильнее, чем ещё один синий квадрат, и читается как настоящий
// кинозал, а не как ещё один мессенджер.
//
// Формы совпадают с scripts/make_app_icons.py — пропорции взяты оттуда,
// чтобы знак и иконка читались как одна вещь.

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
            // Корпус: графит. Верх заметно светлее — знак не должен сливаться
            // с почти чёрным фоном экрана входа.
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [PlinkBrand.graphiteLift, PlinkBrand.graphiteDeep],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Свет от экрана — единственное цветное пятно знака и то, что
            // делает его «кино», а не схемой.
            RadialGradient(
                colors: [PlinkBrand.warm.opacity(0.42), .clear],
                center: UnitPoint(x: 0.5, y: 0.34),
                startRadius: size * 0.02,
                endRadius: size * 0.54
            )

            scene
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        // Гало — в background, а НЕ слоем ZStack: круг диаметром 1.9·size
        // задавал бы размер стека, корпус растягивался под него, и знак
        // выезжал на вордмарк. background рисуется, но в раскладке не
        // участвует.
        //
        // Само гало нужно: без него графитовый корпус на тёмной мозаике почти
        // пропадал — «нейтральный» превращалось в «невидимый». Это ровно то
        // место, где свету и положено быть: знак стоит в луче проектора.
        .background {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [PlinkBrand.warm.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.80
                    )
                )
                .frame(width: size * 2.0, height: size * 2.0)
                .blur(radius: size * 0.18)
        }
        .overlay {
            // Верхний блик отдельно от нижней кромки: свет падает сверху,
            // поэтому равномерная обводка по всему контуру читалась бы
            // наклейкой. Тёплый сверху, гаснет к низу.
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            PlinkBrand.warm.opacity(0.34),
                            PlinkBrand.warm.opacity(0.05),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: max(0.5, size * 0.009)
                )
        }
        // Тень тёплая, а не синяя: знак должен выглядеть источником света.
        .shadow(color: PlinkBrand.warm.opacity(0.18), radius: size * 0.22, y: size * 0.05)
        .shadow(color: .black.opacity(0.55), radius: size * 0.13, y: size * 0.07)
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
                                .foregroundStyle(PlinkBrand.ink)
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
                    .fill(PlinkBrand.ink)
                    .frame(width: s * 0.69, height: s * 0.135)
                    .offset(x: s * 0.155, y: s * 0.795)
            }
        }
    }

    private func silhouette(s: CGFloat) -> some View {
        VStack(spacing: -s * 0.045) {
            Circle()
                .fill(PlinkBrand.ink)
                .frame(width: s * 0.164, height: s * 0.164)
            RoundedRectangle(cornerRadius: s * 0.082, style: .continuous)
                .fill(PlinkBrand.ink)
                .frame(width: s * 0.25, height: s * 0.18)
        }
        .frame(width: s * 0.25, alignment: .center)
    }
}

// MARK: - Вордмарк

/// Надпись PLINK как ЗНАК, а не как набранный текст.
///
/// Прошлая версия была `Text("PLINK")` системным начертанием .black с
/// трекингом −1.2. Это уже лучше, чем .rounded вразрядку (шрифт по умолчанию
/// у любого шаблона), но всё равно читается как «текст, набранный шрифтом
/// системы»: ни одной собственной черты, отличающей его от подписи в любом
/// другом приложении.
///
/// Здесь одна намеренная авторская правка: «I» — не буква, а СВЕТЯЩАЯСЯ ЩЕЛЬ.
/// Тёплая полоса на месте литеры читается как прорезь проектора, тем же
/// тёплым, что свет экрана в знаке. Выбор пал на «I» потому, что это
/// единственная литера в слове, чью форму можно заменить простым
/// прямоугольником, не теряя читаемости слова: щель на месте «I» — это всё
/// ещё «I». Слово остаётся PLINK, но набрать его в текстовом поле нельзя.
///
/// Разряжаем вручную по парам: между «P» и «L» зазор оптически больше, чем
/// между «N» и «K», поэтому единый трекинг оставляет слово рыхлым слева.
struct PlinkWordmark: View {
    /// Кегль. Все размеры внутри считаются от него.
    var size: CGFloat = 42

    /// Ширина щели на месте «I» — от кегля, чтобы масштабировалась вместе.
    private var slitWidth: CGFloat { max(2.5, size * 0.085) }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            letter("P")
            // Отрицательные зазоры — оптическая, а не метрическая разрядка:
            // «P» и «L» стоят слишком широко по метрикам шрифта, «N» и «K»
            // почти вплотную.
            spacer(-0.055)
            letter("L")
            spacer(-0.028)
            slit
            spacer(-0.030)
            letter("N")
            spacer(-0.050)
            letter("K")
        }
        .accessibilityElement()
        .accessibilityLabel("Plink")
    }

    private func letter(_ character: String) -> some View {
        Text(character)
            .font(.system(size: size, weight: .black, design: .default))
            .foregroundStyle(PlinkTheatre.screen)
    }

    private func spacer(_ factor: CGFloat) -> some View {
        Spacer().frame(width: size * factor)
    }

    /// Щель: тёплая полоса с мягким свечением по бокам. Высота чуть меньше
    /// прописной, чтобы не выпирать над строкой.
    private var slit: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [PlinkBrand.warmHot, PlinkBrand.warm],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: slitWidth, height: size * 0.72)
        }
        // Свечение — то, что делает щель источником света, а не жёлтой
        // палочкой. Два радиуса: плотное ядро и широкое гало.
        .shadow(color: PlinkBrand.warm.opacity(0.85), radius: size * 0.055)
        .shadow(color: PlinkBrand.warm.opacity(0.38), radius: size * 0.20)
        // Компенсация: капсула уже прописной литеры, и без отступов соседние
        // буквы прилипают к свечению.
        .padding(.horizontal, size * 0.075)
    }
}


/// Палитра ЗНАКА — ровно те же значения, что в scripts/make_app_icons.py.
///
/// Живёт отдельно от PlinkTheatre (шелл приложения) и от V4 (палитра
/// продукта): это цвета знака, они не меняются вместе с темой комнаты — и в
/// этом весь смысл. Ни одного оттенка из тем здесь быть не должно.
enum PlinkBrand {
    /// Верх корпуса — графит. Заметно светлее фона входа (#0B0B0D): при
    /// первом подборе (36,39,44) знак почти растворялся в тёмной мозаике —
    /// «нейтральный» получилось «невидимый».
    static let graphiteLift = Color(red: 58 / 255, green: 60 / 255, blue: 66 / 255)
    /// Низ корпуса.
    static let graphiteDeep = Color(red: 22 / 255, green: 23 / 255, blue: 27 / 255)
    /// «Темнота зала»: силуэты и диван. Почти чёрный, нейтральный.
    static let ink = Color(red: 8 / 255, green: 9 / 255, blue: 11 / 255)
    /// Тёплый свет экрана — ПОСТОЯННЫЙ цвет бренда, единственное тёплое
    /// пятно. Универсален: включённый экран тёплый при любой теме.
    static let warm = Color(red: 255 / 255, green: 214 / 255, blue: 148 / 255)
    static let warmHot = Color(red: 255 / 255, green: 240 / 255, blue: 214 / 255)
}
