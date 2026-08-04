// Plink/Features/Auth2026/AnimatedPosterMosaic.swift — Auth 2026 redesign
//
// Фон и палитра шелла (сплэш, вход, онбординг).
//
// ЧТО БЫЛО НЕ ТАК (аудит 04.08.2026)
//
// Фон был одним вертикальным градиентом плюс три размытых пятна. На экране это
// читалось как ровная серая заливка: ни глубины, ни фактуры, ни повода
// смотреть. Именно отсюда ощущение «дешёво по сравнению с остальным
// приложением» — не от цвета кнопок, а от того, что за формой ПУСТО. У Netflix
// за формой входа сетка кадров: она даёт глубину и говорит «здесь кино»
// до того, как человек прочтёт хоть слово.
//
// ЧТО ЗДЕСЬ ТЕПЕРЬ
//
// Шесть слоёв вместо одного (порядок важен):
//
//   1. База — ТЁПЛЫЙ почти чёрный, не #000. Чистый чёрный на OLED даёт
//      провал, в котором не работает ни одна тень, и любой градиент поверх
//      выглядит грязным. Тёплый уголь оставляет запас на четыре ступени
//      подъёма для полей и кнопок.
//   2. Зал — ряды кресел, уходящие в перспективе к экрану. Тот же мотив,
//      что в знаке: двое перед светящимся экраном, только шире.
//   3. Луч проектора — из-за верхней кромки, к знаку. Мотивирует свет:
//      знак светится, потому что на него падает луч.
//   4. Виньетка — круговая, гасит углы, собирает взгляд в центр.
//   5. Скрим под формой — гарантия контраста независимо от того, что
//      происходит в слоях выше.
//   6. Зерно плёнки — то, что отличает «кино» от «градиента». Без него
//      любой тёмный фон выглядит пластиковым баннером.
//
// ПОЧЕМУ ЗАЛ, А НЕ СЕТКА ПОСТЕРОВ (правка 04.08.2026)
//
// Слой 2 сначала был наклонённой сеткой «постеров» — одинаковые
// прямоугольники 2:3 со сдвигом ряда на половину ширины. На живом экране это
// прочли как КИРПИЧНУЮ КЛАДКУ, и правильно: ряды одинаковых блоков со сдвигом
// на полблока — дословное определение кирпичной перевязки. Ни приглушённые
// тона, ни размытие не помогали, потому что дело было не в цвете, а в схеме
// раскладки: постеры узнаются по РАЗНОМУ содержимому, а содержимого у нас
// быть не может (прав на постеры нет). Без содержимого остаётся сетка, то
// есть кладка.
//
// Теперь мотив взят из собственного знака: двое перед светящимся экраном.
// Фон — тот же зал, снятый шире. Знак и фон стали одной сценой.
//
// ПОЧЕМУ ВСЁ РИСУЕТСЯ, А НЕ БЕРЁТСЯ ГОТОВЫМ
//
// Хотелось «как у Netflix — настоящие фильмы». Юридически это закрытая дверь:
// постеры и кадры — объекты авторского права студий, декоративное
// использование в чужом интерфейсе не fair use, а App Review 5.2 требует,
// чтобы приложение подавала сторона, которой права принадлежат или
// лицензированы. Netflix показывает эти постеры, потому что лицензировал
// сам контент; у нас лицензии нет. Прошлая версия тянула их с image.tmdb.org
// и оправдывалась тем, что «не бандлит» — это отвечает на вопрос о
// распространении, а не о правах на показ. Слой удалён, ART_ASSET_LICENSES.md
// исправлен.
//
// Поэтому зал рисуется кодом: тона намеренно приглушены до графита с тёплым,
// фон даёт ФАКТУРУ И ГЛУБИНУ, а не цвет, поэтому не спорит ни с одной темой
// продукта.
//
// Доступность / энергия:
//   - Reduce Motion → статичный кадр (без TimelineView)
//   - Reduce Transparency → база + виньетка, без мозаики и свечений
//   - Low Power / термотроттлинг → статичный кадр
//   - Фон приложения (scenePhase) → статичный кадр

import SwiftUI

// MARK: - Палитра шелла

enum PlinkTheatre {
    // Монохромный бренд-шелл (решение 26.07.2026, подтверждено 04.08.2026):
    // обёртка приложения — уголь с белым. ЦВЕТ живёт ВНУТРИ продукта (темы
    // комнат: electric, ember, violet, plink, bloom, aurora, cosmos, verdant,
    // magma), поэтому вход и сплэш не привязаны ни к одной теме.
    //
    // Аудит 04.08.2026: экран входа это правило нарушал — все стеклянные
    // поверхности тинтились синим `PlinkBrand.glassTint`, то есть шелл
    // объявлял цветом бренда одну из тем. Тинт снят.

    /// База — тёплый почти чёрный. Не #000: на OLED чистый чёрный съедает
    /// тени, и подъёмы поверхностей перестают читаться.
    static let velvetDeep = Color(hex: 0x0B0B0D)
    /// Подсвеченная лучом часть зала.
    static let velvet = Color(hex: 0x16161A)

    /// Ступени подъёма поверхностей. Иерархия строится ими, а не тенями:
    /// тень на почти чёрном не видна, поэтому «выше» = светлее.
    static let surface = Color(hex: 0x17171C)
    static let surfaceLift = Color(hex: 0x1F1F25)

    /// Свет экрана — основной текст.
    static let screen = Color(hex: 0xF4F3F1)
    /// Вторичный текст. Тёплый серый, а не холодный: холодный на тёплой базе
    /// выглядит выцветшим.
    static let muted = Color(hex: 0x9A9691)

    /// ЕДИНСТВЕННЫЙ акцент шелла — тёплый свет экрана, тот же, что в знаке.
    ///
    /// Аудит 04.08.2026: раньше здесь жил `tealDeep = #2E7BFF` — синий,
    /// то есть акцент темы electric/cosmos, назначенный акцентом всего шелла.
    /// Человек с темой Magma видел на входе синий фокус полей и синие ссылки.
    /// Тёплый свет нейтрален к темам: включённый экран тёплый всегда.
    static let warm = Color(hex: 0xFFD694)
    static let warmSoft = Color(hex: 0xF6E3C4)

    /// Янтарь ламп — ТОЛЬКО ошибки и предупреждения, точечно.
    /// Отличается от `warm` насыщенностью: рядом их не ставим.
    static let amber = Color(hex: 0xF0A55E)

    /// Тонкая рамка поверхностей — общая.
    static let hairline = Color.white.opacity(0.07)
    /// Верхняя кромка поверхности: блик «поймал свет». Ставится ТОЛЬКО
    /// сверху — равномерная обводка по контуру читается наклейкой.
    static let specular = Color.white.opacity(0.16)
}

// MARK: - Фон: уголь + зал + луч + виньетка + скрим + зерно

/// Принудительное включение доступностных режимов для рендера кадров аудита.
///
/// `\.accessibilityReduceTransparency` и `\.accessibilityReduceMotion` в
/// SwiftUI доступны только на чтение: выставить их из теста нельзя, а
/// UIKit-трейтами эти два флага не переопределяются (пробовал
/// `accessibilityContrast = .high` — кадр выходил побайтово равен обычному,
/// то есть тест «проверял» ровно ничего).
///
/// Фон собран из шести слоёв, и каждый обязан гаситься по этим настройкам.
/// Ломается такой код молча: обычные кадры выглядят нормально, а человек с
/// включённой настройкой получает либо кашу, либо пустой чёрный экран.
/// Поэтому нужен шов, через который оба состояния реально снимаются.
struct PlinkAccessibilityOverride: Equatable {
    var reduceTransparency = false
    var reduceMotion = false
}

private struct PlinkAccessibilityOverrideKey: EnvironmentKey {
    static let defaultValue = PlinkAccessibilityOverride()
}

extension EnvironmentValues {
    var plinkAccessibilityOverride: PlinkAccessibilityOverride {
        get { self[PlinkAccessibilityOverrideKey.self] }
        set { self[PlinkAccessibilityOverrideKey.self] = newValue }
    }
}

struct ProjectorBeamBackground: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.plinkAccessibilityOverride) private var override
    @Environment(\.scenePhase) private var scenePhase

    private var reduceMotion: Bool { systemReduceMotion || override.reduceMotion }
    private var reduceTransparency: Bool {
        systemReduceTransparency || override.reduceTransparency
    }

    private var animationEnabled: Bool {
        !reduceMotion
            && scenePhase == .active
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
            && ProcessInfo.processInfo.thermalState == .nominal
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                // 1. База.
                LinearGradient(
                    stops: [
                        .init(color: PlinkTheatre.velvet, location: 0),
                        .init(color: PlinkTheatre.velvetDeep, location: 0.55),
                        .init(color: Color(hex: 0x08080A), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if !reduceTransparency {
                    // 2. Зал: ряды кресел, уходящие к экрану.
                    if animationEnabled {
                        // 1/12 с, а не 1/20: кресла стоят на месте, меняется
                        // только яркость экрана — чаще перерисовывать нечего.
                        TimelineView(.animation(minimumInterval: 1 / 12)) { timeline in
                            CinemaAudience(
                                size: size,
                                t: timeline.date.timeIntervalSinceReferenceDate
                            )
                        }
                    } else {
                        CinemaAudience(size: size, t: 37)
                    }

                    // 3. Луч проектора.
                    ProjectorBeam(size: size)
                }

                // 4. Виньетка — всегда, в том числе при Reduce Transparency:
                // это не украшение, а то, что удерживает взгляд на форме.
                RadialGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.42),
                        .init(color: .black.opacity(0.30), location: 0.78),
                        .init(color: .black.opacity(0.62), location: 1),
                    ],
                    center: .center,
                    startRadius: 0,
                    // По большей стороне — иначе на узком телефоне виньетка
                    // выходит эллипсом и «сдавливает» кадр по бокам.
                    endRadius: max(size.width, size.height) * 0.78
                )

                // 5. Скрим под формой.
                //
                // Мозаика ДВИЖЕТСЯ, а значит яркость под любым текстом — вещь
                // непредсказуемая: сейчас под кнопкой тёмный кадр, через минуту
                // светлый со засветом. Контраст, который «выглядит нормально»
                // на одном кадре, ломается на другом.
                //
                // Скрим убирает саму зависимость: нижние две трети экрана, где
                // живут поля, кнопка и юридический футер, гарантированно
                // затемнены, поэтому 4.5:1 держится при любом положении сетки.
                // Верх остаётся открытым — там знак, и ему фон нужен.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.30), location: 0.42),
                        .init(color: .black.opacity(0.72), location: 0.72),
                        .init(color: .black.opacity(0.86), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // 6. Зерно плёнки.
                if !reduceTransparency {
                    FilmGrain()
                        .blendMode(.overlay)
                        .opacity(0.20)
                }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

// MARK: - Зал: ряды кресел, уходящие к экрану

/// Зрительный зал, снятый сзади: силуэты спинок кресел рядами уходят к
/// светящемуся экрану.
///
/// ПОЧЕМУ НЕ СЕТКА ПОСТЕРОВ (правка 04.08.2026)
///
/// Здесь была наклонённая сетка «постеров»: одинаковые прямоугольники 2:3 со
/// сдвигом ряда на половину ширины. На экране это прочли как КИРПИЧНУЮ КЛАДКУ,
/// и совершенно справедливо: ряды одинаковых блоков со сдвигом на полблока —
/// это дословное определение кирпичной перевязки. Приглушённые тона и размытие
/// делу не помогали, потому что проблема была не в цвете, а в самой схеме
/// раскладки. Постеры узнаются по РАЗНОМУ содержимому; когда содержимого нет
/// (а его и не могло быть — прав на постеры у нас нет), остаётся только сетка,
/// то есть кладка.
///
/// Что вместо. Мотив взят из собственного знака: двое перед светящимся
/// экраном. Фон — тот же зал, снятый шире: несколько рядов кресел, уходящих в
/// перспективе к экрану, который светит из-за верхней кромки. Знак и фон
/// становятся одной сценой — фон объясняет знак, знак объясняет фон.
///
/// Почему это работает там, где сетка провалилась:
///   • ряды РАЗНЫЕ по размеру и яркости (перспектива), а не одинаковые;
///   • горизонтальные ряды с вертикальными разрывами не образуют перевязки;
///   • силуэт спинки кресла с подголовником — узнаваемая форма, а не блок;
///   • сцена мотивирует свет: экран сверху, поэтому дальние ряды светлее
///     ближних. Ровно то, что происходит в настоящем зале.
private struct CinemaAudience: View {
    let size: CGSize
    let t: TimeInterval

    /// Семь рядов. При пяти кресла выходили размером с ладонь и читались
    /// надгробиями, а не залом: зал узнаётся по КОЛИЧЕСТВУ рядов, а не по
    /// размеру кресла.
    private let rowCount = 7

    var body: some View {
        Canvas { ctx, canvasSize in
            // Горизонт — там, где стоит экран. 0.42, а не 0.30: при 0.30
            // верхний ряд налезал на подпись под вордмарком. Блок бренда
            // должен стоять в ЧИСТОМ воздухе, зал начинается под ним.
            let horizon = canvasSize.height * 0.42
            // Дальняя кромка зала. 0.86: зал уходит под форму, а не
            // заканчивается над ней аккуратной полосой.
            let nearY = canvasSize.height * 0.86

            // Очень медленное «дыхание» зала: не движение кресел (они стоят),
            // а колебание яркости, будто на экране меняется кадр. 0.055 —
            // полный цикл примерно за две минуты.
            let pulse = 0.5 + 0.5 * sin(t * 0.055)

            for row in 0..<rowCount {
                // Нелинейный шаг: в перспективе дальние ряды сжаты, ближние
                // разрежены. Квадрат даёт ровно такое сгущение к горизонту.
                let f0 = pow(Double(row) / Double(rowCount), 2.0)
                let f1 = pow(Double(row + 1) / Double(rowCount), 2.0)
                let y0 = horizon + (nearY - horizon) * f0
                let y1 = horizon + (nearY - horizon) * f1

                drawRow(
                    ctx: &ctx,
                    canvas: canvasSize,
                    top: y0,
                    bottom: y1,
                    depth: Double(row) / Double(rowCount - 1),
                    pulse: pulse
                )
            }
        }
        .allowsHitTesting(false)
    }

    /// Один ряд кресел.
    ///
    /// - Parameters:
    ///   - depth: 0 — самый дальний ряд (у экрана), 1 — самый близкий.
    ///   - pulse: 0…1, колебание яркости экрана.
    private func drawRow(
        ctx: inout GraphicsContext,
        canvas: CGSize,
        top: CGFloat,
        bottom: CGFloat,
        depth: Double,
        pulse: Double
    ) {
        let height = bottom - top
        guard height > 1 else { return }

        // Ближние ряды шире кадра: зал не должен заканчиваться внутри экрана.
        let rowWidth = canvas.width * (1.05 + 0.75 * depth)
        // Кресел в дальнем ряду больше — они мельче. 14→9, а не 11→6: чем
        // больше кресел в ряду, тем меньше каждое, и тем очевиднее, что это
        // зал, а не несколько крупных фигур.
        let seatCount = max(6, Int(14 - depth * 5))
        let pitch = rowWidth / CGFloat(seatCount)
        let originX = (canvas.width - rowWidth) / 2

        // Дальние ряды СВЕТЛЕЕ: на них падает свет экрана. Ближние почти
        // чёрные — они в темноте зала. Это и создаёт глубину.
        let lit = (1.0 - depth)
        let brightness = 0.040 + lit * lit * (0.125 + 0.04 * pulse)

        for seat in 0..<seatCount {
            let cx = originX + (CGFloat(seat) + 0.5) * pitch
            // Спинка: ширина чуть меньше шага, между креслами остаётся щель —
            // именно она не даёт ряду слиться в полосу.
            let w = pitch * 0.78
            // Кресло выше своего ряда: спинки перекрывают следующий, как в
            // настоящем зале, если смотреть сзади. 1.35, а не 1.9: при 1.9
            // спинка вытягивалась в надгробие. Настоящее кресло почти
            // квадратное по силуэту.
            let h = min(height * 1.35, w * 1.15)

            var seatPath = Path()
            let rect = CGRect(x: cx - w / 2, y: bottom - h, width: w, height: h)
            // Подголовник — скругление только сверху: снизу кресло уходит в
            // следующий ряд, и там скругление не видно.
            seatPath.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: w * 0.30, height: w * 0.30)
            )

            ctx.fill(
                seatPath,
                with: .linearGradient(
                    Gradient(colors: [
                        // Верх спинки ловит свет экрана, низ тонет в темноте.
                        Color(hue: 0.09, saturation: 0.10, brightness: brightness),
                        Color(hue: 0.09, saturation: 0.06, brightness: brightness * 0.35),
                    ]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.minX, y: rect.maxY)
                )
            )

            // Тёплый контур по верхней кромке подголовника: контражур от
            // экрана. Без него ряды сливаются в одно пятно.
            guard lit > 0.15 else { continue }
            var rim = Path()
            rim.addArc(
                center: CGPoint(x: cx, y: rect.minY + w * 0.30),
                radius: w * 0.30,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
            ctx.stroke(
                rim,
                with: .color(PlinkTheatre.warm.opacity(0.16 * lit)),
                lineWidth: max(0.5, w * 0.022)
            )
        }
    }
}


// MARK: - Луч проектора

/// Луч из-за верхней кромки экрана. Мотивирует свет: знак и главная кнопка
/// светлые не «просто так», а потому что на них падает луч.
private struct ProjectorBeam: View {
    let size: CGSize

    var body: some View {
        let apexX = size.width * 0.5
        let topY: CGFloat = -80
        let bottomY = size.height * 0.62

        var cone = Path()
        cone.move(to: CGPoint(x: apexX - 14, y: topY))
        cone.addLine(to: CGPoint(x: apexX + 14, y: topY))
        cone.addLine(to: CGPoint(x: apexX + size.width * 0.42, y: bottomY))
        cone.addLine(to: CGPoint(x: apexX - size.width * 0.42, y: bottomY))
        cone.closeSubpath()

        return ZStack {
            cone.fill(
                LinearGradient(
                    stops: [
                        // Тёплый, а не белый: луч и свет знака — один источник.
                        .init(color: PlinkTheatre.warm.opacity(0.10), location: 0),
                        .init(color: PlinkTheatre.warm.opacity(0.035), location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .blur(radius: 30)
            .blendMode(.screen)

            // Свечение «объектива» у источника.
            Circle()
                .fill(PlinkTheatre.warm.opacity(0.14))
                .frame(width: 76, height: 76)
                .blur(radius: 36)
                .position(x: apexX, y: topY + 34)
                .blendMode(.screen)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Зерно плёнки

/// Зерно — самый дешёвый по цене и самый заметный по эффекту слой: он убирает
/// «пластиковость» ровных градиентов и полосы бандинга на тёмном.
///
/// Рисуется ОДИН раз в статичную картинку и не анимируется: живое зерно на
/// каждом кадре — это перерисовка всего экрана 60 раз в секунду ради эффекта,
/// который человек на экране входа не заметит, зато заметит по нагреву.
private struct FilmGrain: View {
    var body: some View {
        Image(uiImage: Self.tile)
            .resizable(resizingMode: .tile)
            .allowsHitTesting(false)
    }

    /// Тайл 128×128. Сид фиксированный — снапшот-тесты не должны мигать.
    private static let tile: UIImage = {
        let side = 128
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        var state: UInt64 = 0x9E3779B97F4A7C15

        for i in 0..<(side * side) {
            // xorshift: детерминированно и без Foundation-рандома.
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            let v = UInt8(truncatingIfNeeded: state >> 24)
            // Серое вокруг средней точки: в .overlay это и осветляет, и
            // затемняет, то есть работает как зерно, а не как «шум сверху».
            let g = 108 + UInt8(Double(v) * 0.16)
            let o = i * 4
            pixels[o] = g
            pixels[o + 1] = g
            pixels[o + 2] = g
            pixels[o + 3] = 255
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(
                width: side, height: side,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: side * 4,
                space: cs,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent
              )
        else { return UIImage() }
        return UIImage(cgImage: cg)
    }()
}
