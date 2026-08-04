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
//   2. Мозаика кадров — наклонённая сетка «постеров», сильно размытая и
//      затемнённая. Даёт ровно ту глубину, которой не хватало.
//   3. Луч проектора — из-за верхней кромки, к знаку. Мотивирует свет:
//      знак светится, потому что на него падает луч.
//   4. Виньетка — круговая, гасит углы, собирает взгляд в центр.
//   5. Скрим под формой — гарантия контраста: мозаика движется, и без него
//      читаемость текста зависела бы от того, какой кадр проплывает снизу.
//   6. Зерно плёнки — то, что отличает «кино» от «градиента». Без него
//      любой тёмный фон выглядит пластиковым баннером.
//
// ПОЧЕМУ КАДРЫ АБСТРАКТНЫЕ, А НЕ НАСТОЯЩИЕ ПОСТЕРЫ
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
// Здесь кадры генеративные: градиент + световая утечка + зерно, сид от
// индекса. При том размытии и затемнении, которое фону и нужно, глаз читает
// их именно как размытые постеры — а прав ни у кого не спрашиваем. Тона
// намеренно приглушены до графита с тёплым: мозаика даёт ФАКТУРУ, а не цвет,
// поэтому не спорит ни с одной темой продукта.
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

// MARK: - Фон: уголь + мозаика кадров + луч + виньетка + зерно

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
                    // 2. Мозаика кадров.
                    if animationEnabled {
                        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
                            CinemaFrameMosaic(
                                size: size,
                                t: timeline.date.timeIntervalSinceReferenceDate
                            )
                        }
                    } else {
                        // Не t=0: в нуле сетка стоит ровно по сетке и выглядит
                        // таблицей. Смещённый кадр выразительнее.
                        CinemaFrameMosaic(size: size, t: 37)
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

// MARK: - Мозаика «кадров»

/// Наклонённая сетка абстрактных кадров: градиент + световая утечка на каждом.
///
/// Наклон 12° — не украшение: ровная сетка прямоугольников на экране входа
/// читается как таблица или как сетка-заглушка, а наклонённая — как разложенные
/// кадры. Тот же приём в шапках Spotify и Apple Music.
private struct CinemaFrameMosaic: View {
    let size: CGSize
    let t: TimeInterval

    /// Ширина кадра. 0.19 экрана — примерно пять столбцов в кадре.
    ///
    /// Было 0.32 (три столбца): кадры выходили размером с ладонь и читались не
    /// «сеткой постеров», а серыми плитами во весь фон — глаз видел крупные
    /// пятна, а не мозаику. Постер узнаётся не фактурой, а ПРОПОРЦИЕЙ и
    /// количеством: нужен ряд из нескольких вертикальных кадров.
    private var tile: CGFloat { max(64, size.width * 0.19) }

    /// Размытие ЗАМЕТНО МЕНЬШЕ зазора между кадрами.
    ///
    /// Первая версия размывала на 0.30 тайла при зазоре 12 pt — размытие
    /// съедало швы целиком, и вся сетка сливалась в ровное мутное пятно: на
    /// экране фон было не отличить от простого градиента. Кадры должны
    /// остаться «расфокусированными», но СЧИТЫВАЕМЫМИ как отдельные кадры, а
    /// для этого шов между ними обязан выжить.
    private var blurRadius: CGFloat { tile * 0.10 }

    var body: some View {
        Canvas { ctx, canvasSize in
            // Полотно шире экрана: сетка наклонена и дрейфует, а её край не
            // должен попадать в кадр.
            let overscan = tile * 2.2
            let strideX = tile
            // 1.5 — пропорция киноплаката (2:3) с учётом зазора.
            let strideY = tile * 1.5
            let cols = Int(((canvasSize.width + overscan * 2) / strideX).rounded(.up))
            let rows = Int(((canvasSize.height + overscan * 2) / strideY).rounded(.up))

            // Дрейф: очень медленный, по диагонали. Примерно один тайл за две
            // минуты. Быстрее — и фон начинает отвлекать от формы.
            let drift = CGFloat(t * 0.0016).truncatingRemainder(dividingBy: 1) * tile

            ctx.addFilter(.blur(radius: blurRadius))
            ctx.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)
            ctx.rotate(by: .degrees(-12))
            ctx.translateBy(x: -canvasSize.width / 2, y: -canvasSize.height / 2)

            for row in 0..<max(1, rows) {
                for col in 0..<max(1, cols) {
                    // Кирпичная разбежка: ряды сдвинуты на половину тайла,
                    // иначе видны сплошные вертикальные швы.
                    let stagger = row.isMultiple(of: 2) ? 0 : strideX * 0.5
                    let x = -overscan + CGFloat(col) * strideX + stagger + drift
                    let y = -overscan + CGFloat(row) * strideY + drift * 0.5

                    // Зазор ~0.14 тайла против размытия 0.10: шов выживает и
                    // сетка читается кадрами, а не сплошной заливкой.
                    let frame = CGRect(
                        x: x, y: y,
                        width: strideX * 0.86,
                        height: strideY * 0.88
                    )
                    guard frame.maxX > -overscan, frame.minX < canvasSize.width + overscan,
                          frame.maxY > -overscan, frame.minY < canvasSize.height + overscan
                    else { continue }

                    draw(frame: frame, seed: row * 31 + col * 7, in: &ctx)
                }
            }
        }
        // Мозаика — подложка, а не картинка: всё, что ярче, начинает
        // конкурировать со знаком и формой.
        .opacity(0.42)
        .allowsHitTesting(false)
    }

    private func draw(frame: CGRect, seed: Int, in ctx: inout GraphicsContext) {
        // Детерминированный «шум» от сида: одинаковый кадр в снапшот-тестах,
        // разный вид у соседних тайлов.
        func noise(_ salt: Int) -> Double {
            let x = sin(Double(seed * 127 + salt * 311) * 12.9898) * 43758.5453
            return x - x.rounded(.down)
        }

        // Тона приглушённые: графит с тёплым и холодным подтоном. Ни одного
        // насыщенного цвета — фон не должен присваивать себе тему.
        //
        // Разброс яркости широкий (0.06…0.42): при узком диапазоне все кадры
        // выходили одинаково-серыми, и сетка читалась плиткой, а не кадрами.
        // Кино — это когда рядом стоят тёмный и светлый кадр.
        let warmth = noise(1)
        let lift = 0.06 + noise(2) * 0.36

        let top = Color(
            hue: warmth < 0.62 ? 0.09 : 0.58,     // тёплый янтарь / холодная сталь
            saturation: 0.06 + noise(3) * 0.14,
            brightness: lift
        )
        let bottom = Color(
            hue: warmth < 0.62 ? 0.07 : 0.60,
            saturation: 0.05 + noise(4) * 0.10,
            brightness: lift * 0.30
        )

        let shape = Path(
            roundedRect: frame,
            cornerRadius: frame.width * 0.06,
            style: .continuous
        )

        ctx.fill(
            shape,
            with: .linearGradient(
                Gradient(colors: [top, bottom]),
                startPoint: CGPoint(x: frame.minX, y: frame.minY),
                endPoint: CGPoint(x: frame.maxX, y: frame.maxY)
            )
        )

        // Световая утечка — то, что превращает прямоугольник в «кадр»:
        // яркое пятно у одного края, как засвет на плёнке. Есть не у всех
        // тайлов: одинаковый блик на каждом снова читался бы сеткой.
        guard noise(5) > 0.42 else { return }
        let leakR = frame.width * (0.5 + noise(6) * 0.45)
        let leak = CGRect(
            x: frame.minX + frame.width * CGFloat(noise(7)) - leakR / 2,
            y: frame.minY + frame.height * CGFloat(noise(8)) - leakR / 2,
            width: leakR,
            height: leakR
        )
        ctx.fill(
            Ellipse().path(in: leak),
            with: .radialGradient(
                Gradient(colors: [
                    PlinkTheatre.warm.opacity(0.16 + noise(9) * 0.16),
                    .clear,
                ]),
                center: CGPoint(x: leak.midX, y: leak.midY),
                startRadius: 0,
                endRadius: leakR / 2
            )
        )
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
