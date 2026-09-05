// Plink/Design/Identity/PlinkAvatarPalette.swift
//
// Цвет личности и цвет лица профиля — два источника правды, и ни один из
// них не тема приложения.
//
// До 25.08.2026 буква-аватар красилась градиентом текущей темы (V4Avatar) или
// парой «акцент + purple» (PlinkStableAvatar). Следствий два: один и тот же
// человек выглядел по-разному в чате и в списке друзей, а все люди сразу —
// одинаково, потому что цвет принадлежал оформлению, а не им. Здесь цвет
// выводится из идентификатора человека: он один во всех компонентах, стабилен
// между запусками и не зависит от того, какую тему выбрал смотрящий.
//
// Тем же принципом живёт акцент лица профиля: его задаёт обложка владельца
// (пресет или своя фотография), а не глобальная тема.

import SwiftUI
import UIKit
import CoreImage

// MARK: - Палитра личности

enum PlinkAvatarPalette {

    /// Восемь пар для тёмного интерфейса: белая буква читается на любой.
    /// Ряд подобран по тону — соседние индексы не сливаются в списке.
    private static let ramp: [(String, String)] = [
        ("#5B6CFF", "#8E4BE0"),   // индиго
        ("#FF5C7A", "#C0326B"),   // роза
        ("#FFA23A", "#E0632B"),   // янтарь
        ("#22C1A4", "#0E7C8A"),   // бирюза
        ("#A05CFF", "#5C2FD6"),   // фиалка
        ("#35A8FF", "#2C63E0"),   // небо
        ("#7BD44A", "#2E9E5B"),   // лайм
        ("#E24BC8", "#7A1F9E"),   // слива
    ]

    /// FNV-1a 32: короткая, детерминированная, без зависимостей. Hasher из
    /// стандартной библиотеки не подходит — он засолен и даёт новый результат
    /// после каждого запуска приложения.
    static func hash(_ seed: String) -> UInt32 {
        var h: UInt32 = 0x811C_9DC5
        for byte in seed.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).utf8 {
            h ^= UInt32(byte)
            h = h &* 0x0100_0193
        }
        return h
    }

    /// Пара цветов личности. Ключ — идентификатор или @ник; если их нет,
    /// подойдёт и буква: цвет всё равно перестанет зависеть от темы.
    static func pair(for seed: String) -> (Color, Color) {
        let key = seed.isEmpty ? "?" : seed
        let hex = ramp[Int(hash(key) % UInt32(ramp.count))]
        return (Color(hex: hex.0), Color(hex: hex.1))
    }

    /// Готовый градиент под круг аватара.
    static func gradient(for seed: String) -> LinearGradient {
        let (c1, c2) = pair(for: seed)
        return LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Акцент обложки-фотографии

/// Средний цвет своей обложки, приведённый к рабочему акценту. У градиентных
/// пресетов акцент прописан в самом пресете (`V4CoverStyle.accent`) — сюда
/// попадают только фотографии из галереи.
@MainActor
enum PlinkCoverAccent {

    /// Серо-стальной для фотографий без выраженного тона (ч/б, туман, снег):
    /// вытягивать насыщенность из шума — получать грязь.
    static let neutral = Color(hex: "#93A7C8")

    private static var cache: [ObjectIdentifier: Color] = [:]
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// Кэш по объекту картинки: обложка живёт в сторе одним экземпляром,
    /// пересчёт нужен только когда пользователь выбрал новое фото.
    static func of(_ image: UIImage) -> Color {
        let key = ObjectIdentifier(image)
        if let hit = cache[key] { return hit }
        let color = compute(image)
        cache[key] = color
        // Обложек за сессию меняют единицы; страховка от неограниченного роста.
        if cache.count > 24 { cache.removeAll(); cache[key] = color }
        return color
    }

    private static func compute(_ image: UIImage) -> Color {
        guard let cg = image.cgImage else { return neutral }
        let input = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ]), let output = filter.outputImage else { return neutral }

        var px = [UInt8](repeating: 0, count: 4)
        context.render(output,
                       toBitmap: &px,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let avg = UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255,
                          blue: CGFloat(px[2]) / 255, alpha: 1)
        guard avg.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return neutral }
        guard s > 0.08 else { return neutral }

        // Среднее по фотографии почти всегда тусклое: тон берём от кадра,
        // насыщенность и яркость поднимаем до уровня, читаемого на стекле.
        return Color(UIColor(hue: h,
                             saturation: min(0.86, max(0.52, s * 1.6)),
                             brightness: min(0.94, max(0.66, b * 1.35)),
                             alpha: 1))
    }

    // MARK: - Читаемость

    /// Потолок яркости: этим цветом заливается стеклянная кнопка с БЕЛОЙ
    /// подписью. Светлее — подпись пропадает. Планка снята замером по живым
    /// снимкам шапки: стекло отдаёт яркость тона почти без потерь, и белая
    /// подпись читается от 2.9:1 (0.313 — розовый «Огни») и плывёт на 2.75:1
    /// (0.332 — янтарный «Проектор»). Граница проходит между ними.
    private static let luminanceCeiling: Double = 0.31
    /// Пол яркости: этим же цветом пишутся подписи поверх тёмного холста.
    /// Темнее — пропадают уже они.
    private static let luminanceFloor: Double = 0.14

    /// Заводит акцент в полосу, читаемую с обеих сторон. Границы считаются в
    /// относительной яркости (WCAG), а не в HSB: розовый и голубой с одной
    /// «яркостью» по HSB светят на глаз совершенно по-разному.
    ///
    /// Тон и насыщенность неприкосновенны — обложка узнаётся по ним; двигается
    /// только яркость. Цвета внутри полосы возвращаются как есть, поэтому на
    /// уже отгруженных пресетах приведение не срабатывает.
    static func legible(_ color: Color) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
            return color
        }
        let lum = luminance(h, s, b)
        guard lum > luminanceCeiling || lum < luminanceFloor else { return color }
        let target = min(luminanceCeiling, max(luminanceFloor, lum))
        // Обратной формулы у относительной яркости нет, но по яркости она
        // монотонна — двенадцати делений хватает до неразличимости.
        var lo: CGFloat = 0, hi: CGFloat = 1
        for _ in 0..<12 {
            let mid = (lo + hi) / 2
            if luminance(h, s, mid) < target { lo = mid } else { hi = mid }
        }
        return Color(UIColor(hue: h, saturation: s, brightness: (lo + hi) / 2, alpha: a))
    }

    private static func luminance(_ h: CGFloat, _ s: CGFloat, _ b: CGFloat) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, a: CGFloat = 0
        UIColor(hue: h, saturation: s, brightness: b, alpha: 1)
            .getRed(&r, green: &g, blue: &bl, alpha: &a)
        func lin(_ c: CGFloat) -> Double {
            let v = max(0, min(1, Double(c)))
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(bl)
    }
}

// MARK: - Обложка без обложки
//
// 04.09.2026. Каталог держится на постерах, а постер приходит по сети. Когда
// картинки нет — её вырезал источник, оборвалась загрузка, лёг CDN — плитка
// оставалась пустым серым прямоугольником, и рельса из трёх таких плиток
// выглядела фотокопией самой себя. Хуже: `AsyncImage(url:content:placeholder:)`
// в двухзамыкательной форме показывает `placeholder` и при загрузке, и при
// ошибке, так что «пусто» становилось конечным состоянием, а не промежуточным.
//
// Тот же принцип, что у буквы-аватара: если нечего показать, показываем то,
// что у нас точно есть, — название. Хеш заголовка задаёт оттенок, монограмма
// даёт вещи лицо, и соседние плитки в рельсе перестают быть одинаковыми.
// Тон намеренно приглушён: заглушка не должна перекрикивать настоящие постеры,
// стоящие рядом в той же полке.

extension PlinkAvatarPalette {

    /// Пара под обложку: оттенок берётся из заголовка, насыщенность и яркость
    /// фиксированы. Отсюда семейное сходство всех заглушек при том, что две
    /// соседние различимы.
    /// Дуга оттенков вместо полного круга. Раньше `hue` брался со всего
    /// колеса, и «RuTube» выпадал болотным, а «YouTube» — бирюзовым: две
    /// самые крупные плиты на лице профиля светились цветами, которых в
    /// приложении нет нигде. Теперь оттенок ходит вокруг фиолетового
    /// Plink (0.72) на ±0.075 — от индиго до сливового. Соседние плитки
    /// по-прежнему различимы, но полка перестала спорить с интерфейсом.
    /// Дуга фиксированная, не от темы: заглушка обязана выглядеть
    /// одинаково при любом оформлении — как и лицо профиля (5dbed1d).
    private static let posterHueCenter = 0.72
    private static let posterHueSpread = 0.075

    static func posterPair(for seed: String) -> (Color, Color) {
        let key = seed.isEmpty ? "?" : seed
        let offset = Double(hash(key) % 2001) / 1000.0 - 1.0   // −1…+1
        let hue = (posterHueCenter + offset * posterHueSpread)
            .truncatingRemainder(dividingBy: 1)
        // 04.09.2026: на 0.30/0.27 оттенок съедался — в шапке шита плитка
        // читалась графитовым прямоугольником, а не тоном вещи. Подняли до
        // 0.38/0.33, оставаясь ниже настоящего постера: рядом на полке
        // заглушка по-прежнему тише соседей, но две соседние различимы.
        return (
            Color(hue: hue, saturation: 0.38, brightness: 0.33),
            // Дрейф верх→низ ужат с 0.055 до 0.030 вместе с дугой: на
            // круге в 0.15 прежний сдвиг перекрывал треть диапазона и
            // сам градиент уводил плитку за пределы семьи.
            Color(hue: (hue + 0.030).truncatingRemainder(dividingBy: 1),
                  saturation: 0.48, brightness: 0.15)
        )
    }

    /// Монограмма вещи: первая буква первого значащего слова. Служебные
    /// префиксы вроде «The» пропускаем — иначе половина полки будет «T».
    ///
    /// Слова из цифр пропускаем тоже: у «10 Новых фильмов 2026» монограммой
    /// вставала «1» — на постере это читается номером, а не именем. Буква
    /// первого словесного слова («Н») вещь называет, цифра — нет. Если букв
    /// в заголовке нет вовсе («2026»), берём что есть.
    static func monogram(for title: String) -> String {
        let skip: Set<String> = ["the", "a", "an", "и", "в", "на"]
        let words = title
            .replacingOccurrences(of: "[^\\p{L}\\p{N} ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
        func isWord(_ w: String) -> Bool {
            guard let f = w.unicodeScalars.first else { return false }
            return CharacterSet.letters.contains(f)
        }
        let pick = words.first { isWord($0) && !skip.contains($0.lowercased()) }
            ?? words.first { isWord($0) }
            ?? words.first
            ?? "?"
        return String(pick.prefix(1)).uppercased()
    }
}

/// Заглушка обложки: тонированный градиент, косой блик и монограмма.
/// Ставится и на время загрузки, и вместо не пришедшей картинки — состояние
/// одно и то же с точки зрения смотрящего: обложки нет.
struct PlinkArtlessPoster: View {
    /// Источник цвета и монограммы — заголовок вещи (или id, если его нет).
    let seed: String
    /// Символ вида носителя в углу (film, music.note…). nil — без угла.
    var glyph: String? = nil
    /// Монограмма мешает на плитке меньше 60 pt: там остаётся только тон.
    var showsMonogram: Bool = true

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let (top, bottom) = PlinkAvatarPalette.posterPair(for: seed)
            ZStack {
                LinearGradient(colors: [top, bottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)

                // Косой блик по верхнему углу — так плитка читается объёмной
                // карточкой, а не залитым прямоугольником.
                LinearGradient(colors: [.white.opacity(0.10), .clear],
                               startPoint: .topLeading, endPoint: .center)

                if showsMonogram && side >= 44 {
                    Text(PlinkAvatarPalette.monogram(for: seed))
                        .font(.system(size: side * 0.46, weight: .black, design: .serif))
                        .foregroundStyle(.white.opacity(0.16))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }

                if let glyph, side >= 44 {
                    VStack {
                        HStack {
                            Spacer(minLength: 0)
                            Image(systemName: glyph)
                                .font(.system(size: max(8, side * 0.11), weight: .semibold))
                                .foregroundStyle(.white.opacity(0.42))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(max(5, side * 0.07))
                }
            }
        }
    }
}
