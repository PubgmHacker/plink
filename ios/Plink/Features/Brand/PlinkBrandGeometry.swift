// Plink/Features/Brand/PlinkBrandGeometry.swift
//
// СГЕНЕРИРОВАНО из эталонного макета PLINK (1056×1008): контуры знака сняты с
// растра и восстановлены как кривые, вордмарк — как скруглённые многоугольники
// (дуги переведены в кубики). Координаты — в системе макета, поэтому знак,
// слово, градиенты и блики сходятся с эталоном 1:1. Правки — только через
// генератор (brand/tools/gen_swift.py), руками числа не трогать.

import SwiftUI

enum PlinkBrandGeometry {
    /// Рамка знака (фигуры A и B вместе) в координатах макета.
    static let markBox = CGRect(x: 388.33, y: 81.20, width: 349.90, height: 460.07)
    /// Рамка вордмарка PLINK в координатах макета.
    static let wordmarkBox = CGRect(x: 215.39, y: 594.38, width: 664.89, height: 127.00)
    /// Рамка всего лок-апа (знак + слово + слоган + подвал), макет целиком.
    static let lockupBox = CGRect(x: 0, y: 0, width: 1056, height: 1008)

    /// Фигура A — стрелка «play», верхняя, светло-фиолетовая.
    static let markA: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 422.78, y: 225.20))
        p.addCurve(to: CGPoint(x: 388.33, y: 160.96), control1: CGPoint(x: 401.28, y: 211.21), control2: CGPoint(x: 388.33, y: 183.26))
        p.addLine(to: CGPoint(x: 388.33, y: 160.96))
        p.addCurve(to: CGPoint(x: 507.65, y: 97.93), control1: CGPoint(x: 388.33, y: 93.65), control2: CGPoint(x: 446.29, y: 58.02))
        p.addLine(to: CGPoint(x: 696.11, y: 220.48))
        p.addCurve(to: CGPoint(x: 695.32, y: 389.73), control1: CGPoint(x: 752.92, y: 257.42), control2: CGPoint(x: 751.88, y: 356.95))
        p.addLine(to: CGPoint(x: 592.01, y: 449.62))
        p.addCurve(to: CGPoint(x: 562.50, y: 433.80), control1: CGPoint(x: 576.75, y: 458.46), control2: CGPoint(x: 562.50, y: 448.72))
        p.addLine(to: CGPoint(x: 562.50, y: 340.85))
        p.addCurve(to: CGPoint(x: 540.82, y: 301.96), control1: CGPoint(x: 562.50, y: 328.31), control2: CGPoint(x: 554.84, y: 311.07))
        p.closeSubpath()
        return p
    }()

    /// Фигура B — нижняя капля-хвост, тёмно-фиолетовая.
    static let markB: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 492.99, y: 338.08))
        p.addCurve(to: CGPoint(x: 527.31, y: 360.74), control1: CGPoint(x: 511.17, y: 327.86), control2: CGPoint(x: 527.31, y: 335.70))
        p.addLine(to: CGPoint(x: 527.31, y: 471.91))
        p.addCurve(to: CGPoint(x: 460.66, y: 541.27), control1: CGPoint(x: 527.31, y: 505.45), control2: CGPoint(x: 504.68, y: 541.27))
        p.addLine(to: CGPoint(x: 460.66, y: 541.27))
        p.addCurve(to: CGPoint(x: 396.11, y: 474.22), control1: CGPoint(x: 416.88, y: 541.27), control2: CGPoint(x: 396.11, y: 508.00))
        p.addLine(to: CGPoint(x: 396.11, y: 422.80))
        p.addCurve(to: CGPoint(x: 424.12, y: 376.81), control1: CGPoint(x: 396.11, y: 410.94), control2: CGPoint(x: 407.91, y: 385.93))
        p.closeSubpath()
        return p
    }()

    /// Слово PLINK: пять литер, каждая — замкнутый контур (P с противоположно ориентированным контуром-окошком).
    static let wordmark: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 219.31, y: 721.30))
        p.addCurve(to: CGPoint(x: 215.74, y: 717.73), control1: CGPoint(x: 217.34, y: 721.30), control2: CGPoint(x: 215.74, y: 719.70))
        p.addLine(to: CGPoint(x: 215.74, y: 637.34))
        p.addCurve(to: CGPoint(x: 220.23, y: 632.85), control1: CGPoint(x: 215.74, y: 634.86), control2: CGPoint(x: 217.75, y: 632.85))
        p.addLine(to: CGPoint(x: 236.50, y: 632.85))
        p.addCurve(to: CGPoint(x: 239.82, y: 636.17), control1: CGPoint(x: 238.33, y: 632.86), control2: CGPoint(x: 239.81, y: 634.34))
        p.addLine(to: CGPoint(x: 239.82, y: 656.10))
        p.addCurve(to: CGPoint(x: 240.76, y: 658.36), control1: CGPoint(x: 239.82, y: 656.95), control2: CGPoint(x: 240.16, y: 657.76))
        p.addCurve(to: CGPoint(x: 243.02, y: 659.29), control1: CGPoint(x: 241.36, y: 658.96), control2: CGPoint(x: 242.17, y: 659.29))
        p.addLine(to: CGPoint(x: 279.67, y: 659.29))
        p.addCurve(to: CGPoint(x: 300.41, y: 638.55), control1: CGPoint(x: 291.12, y: 659.29), control2: CGPoint(x: 300.41, y: 650.00))
        p.addLine(to: CGPoint(x: 300.41, y: 637.74))
        p.addCurve(to: CGPoint(x: 280.06, y: 617.39), control1: CGPoint(x: 300.41, y: 626.50), control2: CGPoint(x: 291.30, y: 617.39))
        p.addLine(to: CGPoint(x: 219.07, y: 617.39))
        p.addCurve(to: CGPoint(x: 216.47, y: 616.32), control1: CGPoint(x: 218.09, y: 617.39), control2: CGPoint(x: 217.16, y: 617.01))
        p.addCurve(to: CGPoint(x: 215.39, y: 613.72), control1: CGPoint(x: 215.78, y: 615.63), control2: CGPoint(x: 215.39, y: 614.70))
        p.addLine(to: CGPoint(x: 215.39, y: 599.31))
        p.addCurve(to: CGPoint(x: 220.09, y: 594.61), control1: CGPoint(x: 215.39, y: 596.71), control2: CGPoint(x: 217.49, y: 594.61))
        p.addLine(to: CGPoint(x: 283.39, y: 594.61))
        p.addCurve(to: CGPoint(x: 325.59, y: 636.81), control1: CGPoint(x: 306.70, y: 594.61), control2: CGPoint(x: 325.59, y: 613.50))
        p.addLine(to: CGPoint(x: 325.59, y: 640.04))
        p.addCurve(to: CGPoint(x: 284.89, y: 680.73), control1: CGPoint(x: 325.58, y: 662.51), control2: CGPoint(x: 307.36, y: 680.73))
        p.addLine(to: CGPoint(x: 244.06, y: 680.73))
        p.addCurve(to: CGPoint(x: 239.66, y: 685.13), control1: CGPoint(x: 241.63, y: 680.73), control2: CGPoint(x: 239.66, y: 682.70))
        p.addLine(to: CGPoint(x: 239.66, y: 717.74))
        p.addCurve(to: CGPoint(x: 238.62, y: 720.26), control1: CGPoint(x: 239.66, y: 718.68), control2: CGPoint(x: 239.29, y: 719.59))
        p.addCurve(to: CGPoint(x: 236.11, y: 721.30), control1: CGPoint(x: 237.96, y: 720.92), control2: CGPoint(x: 237.05, y: 721.30))
        p.closeSubpath()
        p.move(to: CGPoint(x: 367.63, y: 598.55))
        p.addCurve(to: CGPoint(x: 371.80, y: 594.38), control1: CGPoint(x: 367.64, y: 596.25), control2: CGPoint(x: 369.50, y: 594.39))
        p.addLine(to: CGPoint(x: 388.53, y: 594.38))
        p.addCurve(to: CGPoint(x: 391.67, y: 595.67), control1: CGPoint(x: 389.71, y: 594.38), control2: CGPoint(x: 390.84, y: 594.84))
        p.addCurve(to: CGPoint(x: 392.97, y: 598.81), control1: CGPoint(x: 392.50, y: 596.51), control2: CGPoint(x: 392.97, y: 597.63))
        p.addLine(to: CGPoint(x: 392.97, y: 694.84))
        p.addCurve(to: CGPoint(x: 393.93, y: 697.17), control1: CGPoint(x: 392.97, y: 695.71), control2: CGPoint(x: 393.31, y: 696.55))
        p.addCurve(to: CGPoint(x: 396.26, y: 698.14), control1: CGPoint(x: 394.55, y: 697.79), control2: CGPoint(x: 395.39, y: 698.14))
        p.addLine(to: CGPoint(x: 461.84, y: 698.14))
        p.addCurve(to: CGPoint(x: 465.54, y: 701.83), control1: CGPoint(x: 463.88, y: 698.14), control2: CGPoint(x: 465.53, y: 699.79))
        p.addLine(to: CGPoint(x: 465.54, y: 717.15))
        p.addCurve(to: CGPoint(x: 461.36, y: 721.33), control1: CGPoint(x: 465.54, y: 719.46), control2: CGPoint(x: 463.67, y: 721.33))
        p.addLine(to: CGPoint(x: 371.91, y: 721.33))
        p.addCurve(to: CGPoint(x: 367.63, y: 717.05), control1: CGPoint(x: 369.55, y: 721.32), control2: CGPoint(x: 367.64, y: 719.41))
        p.closeSubpath()
        p.move(to: CGPoint(x: 529.74, y: 594.57))
        p.addCurve(to: CGPoint(x: 533.63, y: 598.46), control1: CGPoint(x: 531.89, y: 594.57), control2: CGPoint(x: 533.63, y: 596.31))
        p.addLine(to: CGPoint(x: 533.63, y: 717.01))
        p.addCurve(to: CGPoint(x: 529.25, y: 721.38), control1: CGPoint(x: 533.62, y: 719.43), control2: CGPoint(x: 531.67, y: 721.38))
        p.addLine(to: CGPoint(x: 512.36, y: 721.38))
        p.addCurve(to: CGPoint(x: 510.01, y: 720.41), control1: CGPoint(x: 511.48, y: 721.38), control2: CGPoint(x: 510.64, y: 721.04))
        p.addCurve(to: CGPoint(x: 509.04, y: 718.07), control1: CGPoint(x: 509.39, y: 719.79), control2: CGPoint(x: 509.04, y: 718.95))
        p.addLine(to: CGPoint(x: 509.04, y: 599.06))
        p.addCurve(to: CGPoint(x: 513.53, y: 594.57), control1: CGPoint(x: 509.04, y: 596.58), control2: CGPoint(x: 511.05, y: 594.57))
        p.closeSubpath()
        p.move(to: CGPoint(x: 587.12, y: 721.32))
        p.addCurve(to: CGPoint(x: 583.33, y: 717.53), control1: CGPoint(x: 585.03, y: 721.32), control2: CGPoint(x: 583.33, y: 719.62))
        p.addLine(to: CGPoint(x: 583.33, y: 599.26))
        p.addCurve(to: CGPoint(x: 588.13, y: 594.46), control1: CGPoint(x: 583.33, y: 596.61), control2: CGPoint(x: 585.48, y: 594.46))
        p.addLine(to: CGPoint(x: 608.85, y: 594.46))
        p.addCurve(to: CGPoint(x: 614.84, y: 597.40), control1: CGPoint(x: 611.19, y: 594.46), control2: CGPoint(x: 613.41, y: 595.54))
        p.addLine(to: CGPoint(x: 681.07, y: 683.14))
        p.addCurve(to: CGPoint(x: 683.25, y: 683.79), control1: CGPoint(x: 681.58, y: 683.80), control2: CGPoint(x: 682.46, y: 684.07))
        p.addCurve(to: CGPoint(x: 684.58, y: 681.94), control1: CGPoint(x: 684.05, y: 683.52), control2: CGPoint(x: 684.58, y: 682.78))
        p.addLine(to: CGPoint(x: 684.58, y: 598.90))
        p.addCurve(to: CGPoint(x: 689.05, y: 594.43), control1: CGPoint(x: 684.58, y: 596.43), control2: CGPoint(x: 686.58, y: 594.43))
        p.addLine(to: CGPoint(x: 705.91, y: 594.43))
        p.addCurve(to: CGPoint(x: 708.56, y: 595.52), control1: CGPoint(x: 706.90, y: 594.43), control2: CGPoint(x: 707.86, y: 594.82))
        p.addCurve(to: CGPoint(x: 709.65, y: 598.17), control1: CGPoint(x: 709.26, y: 596.22), control2: CGPoint(x: 709.65, y: 597.18))
        p.addLine(to: CGPoint(x: 709.65, y: 717.17))
        p.addCurve(to: CGPoint(x: 705.51, y: 721.31), control1: CGPoint(x: 709.65, y: 719.46), control2: CGPoint(x: 707.80, y: 721.31))
        p.addLine(to: CGPoint(x: 683.57, y: 721.31))
        p.addCurve(to: CGPoint(x: 679.54, y: 719.33), control1: CGPoint(x: 681.99, y: 721.31), control2: CGPoint(x: 680.50, y: 720.58))
        p.addLine(to: CGPoint(x: 611.88, y: 631.75))
        p.addCurve(to: CGPoint(x: 609.24, y: 630.96), control1: CGPoint(x: 611.26, y: 630.95), control2: CGPoint(x: 610.20, y: 630.63))
        p.addCurve(to: CGPoint(x: 607.65, y: 633.20), control1: CGPoint(x: 608.29, y: 631.29), control2: CGPoint(x: 607.65, y: 632.19))
        p.addLine(to: CGPoint(x: 607.65, y: 717.11))
        p.addCurve(to: CGPoint(x: 603.44, y: 721.32), control1: CGPoint(x: 607.65, y: 719.44), control2: CGPoint(x: 605.77, y: 721.32))
        p.closeSubpath()
        p.move(to: CGPoint(x: 879.89, y: 718.37))
        p.addCurve(to: CGPoint(x: 880.10, y: 720.30), control1: CGPoint(x: 880.32, y: 718.92), control2: CGPoint(x: 880.40, y: 719.67))
        p.addCurve(to: CGPoint(x: 878.45, y: 721.33), control1: CGPoint(x: 879.79, y: 720.93), control2: CGPoint(x: 879.15, y: 721.33))
        p.addLine(to: CGPoint(x: 854.88, y: 721.33))
        p.addCurve(to: CGPoint(x: 851.14, y: 719.50), control1: CGPoint(x: 853.42, y: 721.33), control2: CGPoint(x: 852.04, y: 720.66))
        p.addLine(to: CGPoint(x: 809.02, y: 665.29))
        p.addCurve(to: CGPoint(x: 807.03, y: 664.22), control1: CGPoint(x: 808.54, y: 664.67), control2: CGPoint(x: 807.82, y: 664.28))
        p.addCurve(to: CGPoint(x: 804.91, y: 664.99), control1: CGPoint(x: 806.25, y: 664.17), control2: CGPoint(x: 805.48, y: 664.45))
        p.addLine(to: CGPoint(x: 785.05, y: 684.17))
        p.addLine(to: CGPoint(x: 785.05, y: 717.50))
        p.addCurve(to: CGPoint(x: 781.25, y: 721.30), control1: CGPoint(x: 785.05, y: 719.60), control2: CGPoint(x: 783.35, y: 721.30))
        p.addLine(to: CGPoint(x: 764.45, y: 721.30))
        p.addCurve(to: CGPoint(x: 760.66, y: 717.51), control1: CGPoint(x: 762.36, y: 721.30), control2: CGPoint(x: 760.66, y: 719.60))
        p.addLine(to: CGPoint(x: 760.66, y: 599.27))
        p.addCurve(to: CGPoint(x: 765.53, y: 594.40), control1: CGPoint(x: 760.66, y: 596.58), control2: CGPoint(x: 762.84, y: 594.40))
        p.addLine(to: CGPoint(x: 781.58, y: 594.40))
        p.addCurve(to: CGPoint(x: 785.14, y: 597.96), control1: CGPoint(x: 783.55, y: 594.40), control2: CGPoint(x: 785.14, y: 595.99))
        p.addLine(to: CGPoint(x: 785.14, y: 649.21))
        p.addCurve(to: CGPoint(x: 786.22, y: 650.83), control1: CGPoint(x: 785.14, y: 649.92), control2: CGPoint(x: 785.56, y: 650.56))
        p.addCurve(to: CGPoint(x: 788.13, y: 650.47), control1: CGPoint(x: 786.87, y: 651.11), control2: CGPoint(x: 787.62, y: 650.97))
        p.addLine(to: CGPoint(x: 844.06, y: 596.49))
        p.addCurve(to: CGPoint(x: 848.80, y: 594.58), control1: CGPoint(x: 845.33, y: 595.26), control2: CGPoint(x: 847.03, y: 594.58))
        p.addLine(to: CGPoint(x: 872.27, y: 594.58))
        p.addCurve(to: CGPoint(x: 874.57, y: 596.12), control1: CGPoint(x: 873.28, y: 594.58), control2: CGPoint(x: 874.19, y: 595.19))
        p.addCurve(to: CGPoint(x: 873.99, y: 598.83), control1: CGPoint(x: 874.95, y: 597.06), control2: CGPoint(x: 874.72, y: 598.13))
        p.addLine(to: CGPoint(x: 826.48, y: 644.69))
        p.addCurve(to: CGPoint(x: 826.15, y: 649.20), control1: CGPoint(x: 825.24, y: 645.89), control2: CGPoint(x: 825.09, y: 647.83))
        p.closeSubpath()
        return p
    }()

    /// Вписывает путь, снятый в координатах макета, в прямоугольник с
    /// сохранением пропорций (aspect-fit, по центру).
    static func fit(_ path: Path, box: CGRect, in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0, box.width > 0, box.height > 0 else { return Path() }
        let s = min(rect.width / box.width, rect.height / box.height)
        let tx = rect.midX - (box.midX * s)
        let ty = rect.midY - (box.midY * s)
        let t = CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: tx, ty: ty)
        return path.applying(t)
    }
}

// MARK: - Формы

/// Фигура A знака (стрелка). Заполнять `PlinkBrandPalette.markA`.
struct PlinkMarkShapeA: Shape {
    func path(in rect: CGRect) -> Path {
        PlinkBrandGeometry.fit(PlinkBrandGeometry.markA, box: PlinkBrandGeometry.markBox, in: rect)
    }
}

/// Фигура B знака (хвост). Заполнять `PlinkBrandPalette.markB`.
struct PlinkMarkShapeB: Shape {
    func path(in rect: CGRect) -> Path {
        PlinkBrandGeometry.fit(PlinkBrandGeometry.markB, box: PlinkBrandGeometry.markBox, in: rect)
    }
}

/// Силуэт знака целиком (A ∪ B) — для монохромных и tinted-вариантов, масок и теней.
struct PlinkMarkSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var p = PlinkBrandGeometry.fit(PlinkBrandGeometry.markA, box: PlinkBrandGeometry.markBox, in: rect)
        p.addPath(PlinkBrandGeometry.fit(PlinkBrandGeometry.markB, box: PlinkBrandGeometry.markBox, in: rect))
        return p
    }
}

/// Слово PLINK как контур. Заливать с `FillStyle(eoFill: true)` — окошко «P»
/// вырезано вторым контуром.
struct PlinkWordmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        PlinkBrandGeometry.fit(PlinkBrandGeometry.wordmark, box: PlinkBrandGeometry.wordmarkBox, in: rect)
    }
}

// MARK: - Палитра

/// Цвета бренда, снятые с эталона. НЕ зависят от темы приложения: знак меняет
/// цвет только вокруг себя (гало, фон), никогда внутри.
enum PlinkBrandPalette {
    /// Фон макета — почти чёрный с каплей фиолетового.
    static let background = Color(red: 1/255, green: 0/255, blue: 8/255)
    /// Основной акцент бренда (цвет иконок подвала макета).
    static let accent = Color(red: 141/255, green: 85/255, blue: 200/255)
    /// Верх стрелки — самый светлый фиолетовый.
    static let violetLight = Color(red: 143/255, green: 68/255, blue: 240/255)
    /// Низ стрелки — насыщенный индиго.
    static let violetDeep = Color(red: 64/255, green: 22/255, blue: 234/255)
    /// Хвост — тёмный фиолет.
    static let plum = Color(red: 44/255, green: 6/255, blue: 136/255)
    /// Точки-разделители подвала.
    static let dot = Color(red: 44/255, green: 31/255, blue: 90/255)
    /// Серый подвала (PLAYER · MESSENGER · REELS).
    static let footerText = Color(red: 189/255, green: 189/255, blue: 190/255)

    /// Градиент фигуры A (8 опор, подгонка под растр эталона).
    static let markAStops: [Gradient.Stop] = [
        Gradient.Stop(color: Color(red: 143/255, green: 68/255, blue: 240/255), location: 0.0625),
        Gradient.Stop(color: Color(red: 122/255, green: 57/255, blue: 240/255), location: 0.1875),
        Gradient.Stop(color: Color(red: 105/255, green: 49/255, blue: 239/255), location: 0.3125),
        Gradient.Stop(color: Color(red: 91/255, green: 41/255, blue: 238/255), location: 0.4375),
        Gradient.Stop(color: Color(red: 76/255, green: 33/255, blue: 237/255), location: 0.5625),
        Gradient.Stop(color: Color(red: 72/255, green: 35/255, blue: 238/255), location: 0.6875),
        Gradient.Stop(color: Color(red: 66/255, green: 28/255, blue: 235/255), location: 0.8125),
        Gradient.Stop(color: Color(red: 64/255, green: 22/255, blue: 234/255), location: 0.9375)
    ]
    static let markAStart = UnitPoint(x: 0.6420, y: 0.1249)
    static let markAEnd = UnitPoint(x: 0.3471, y: 0.7411)
    static var markA: LinearGradient {
        LinearGradient(stops: markAStops, startPoint: markAStart, endPoint: markAEnd)
    }

    /// Градиент фигуры B.
    static let markBStops: [Gradient.Stop] = [
        Gradient.Stop(color: Color(red: 44/255, green: 6/255, blue: 136/255), location: 0.0625),
        Gradient.Stop(color: Color(red: 41/255, green: 6/255, blue: 132/255), location: 0.1875),
        Gradient.Stop(color: Color(red: 46/255, green: 6/255, blue: 135/255), location: 0.3125),
        Gradient.Stop(color: Color(red: 50/255, green: 7/255, blue: 136/255), location: 0.4375),
        Gradient.Stop(color: Color(red: 56/255, green: 8/255, blue: 142/255), location: 0.5625),
        Gradient.Stop(color: Color(red: 60/255, green: 9/255, blue: 144/255), location: 0.6875),
        Gradient.Stop(color: Color(red: 68/255, green: 11/255, blue: 151/255), location: 0.8125),
        Gradient.Stop(color: Color(red: 80/255, green: 14/255, blue: 157/255), location: 0.9375)
    ]
    static let markBStart = UnitPoint(x: 0.4551, y: 0.6653)
    static let markBEnd = UnitPoint(x: 0.0223, y: 0.8874)
    static var markB: LinearGradient {
        LinearGradient(stops: markBStops, startPoint: markBStart, endPoint: markBEnd)
    }

    /// Светлая внутренняя кромка стрелки: гаснет сверху вниз. Рисуется как
    /// обводка, обрезанная самой фигурой (внутренний штрих).
    static let rimStart = UnitPoint(x: 0.6421, y: 0.1235)
    static let rimEnd = UnitPoint(x: 0.3477, y: 0.7408)
    static var rim: LinearGradient {
        LinearGradient(
            colors: [Color(red: 234/255, green: 223/255, blue: 255/255).opacity(0.6), Color(red: 234/255, green: 223/255, blue: 255/255).opacity(0.2)],
            startPoint: rimStart, endPoint: rimEnd
        )
    }
    /// Толщина кромки в долях ширины знака (3 px на 350 px макета; видна половина).
    static let rimWidthRatio: CGFloat = 3.0 / 349.90

    /// Вордмарк: сверху почти белый, книзу — холодный сиреневый.
    static var wordmark: LinearGradient {
        LinearGradient(colors: [Color(red: 244/255, green: 244/255, blue: 245/255), Color(red: 194/255, green: 191/255, blue: 219/255)], startPoint: .top, endPoint: .bottom)
    }

    /// Слоган WATCH TOGETHER. ANYWHERE.: фиолет → индиго → голубой, слева направо.
    static var tagline: LinearGradient {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(red: 134/255, green: 66/255, blue: 214/255), location: 0),
                Gradient.Stop(color: Color(red: 106/255, green: 73/255, blue: 209/255), location: 0.5),
                Gradient.Stop(color: Color(red: 65/255, green: 137/255, blue: 210/255), location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }
}
