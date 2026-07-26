// Plink/DesignSystem/LivingThemes/PlinkThemeCatalog.swift — GPT-5.6 §4
import SwiftUI

enum PlinkThemeCatalog {
    static let defaultID = "electric-blue"

    static let electricBlue = PlinkLivingTheme(
        id: "electric-blue", name: "Electric Blue", access: .free, master: .electricBlue,
        colors: [
            RGBAColor(red: 0.04, green: 0.08, blue: 0.16, alpha: 1),
            RGBAColor(red: 0.10, green: 0.30, blue: 0.70, alpha: 1),
            RGBAColor(red: 0.20, green: 0.60, blue: 0.90, alpha: 1),
        ],
        chatScrim: RGBAColor(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.88)
    )

    static let cinemaEmber = PlinkLivingTheme(
        id: "cinema-ember", name: "Cinema Ember", access: .premium, master: .cinemaEmber,
        colors: [
            RGBAColor(red: 0.06, green: 0.03, blue: 0.02, alpha: 1),
            RGBAColor(red: 0.50, green: 0.18, blue: 0.05, alpha: 1),
            RGBAColor(red: 0.90, green: 0.50, blue: 0.15, alpha: 1),
        ],
        chatScrim: RGBAColor(red: 0.04, green: 0.02, blue: 0.01, alpha: 0.88)
    )

    static let violetHorizon = PlinkLivingTheme(
        id: "violet-horizon", name: "Violet Horizon", access: .premium, master: .violetHorizon,
        colors: [
            RGBAColor(red: 0.05, green: 0.02, blue: 0.08, alpha: 1),
            RGBAColor(red: 0.30, green: 0.10, blue: 0.50, alpha: 1),
            RGBAColor(red: 0.60, green: 0.30, blue: 0.80, alpha: 1),
        ],
        chatScrim: RGBAColor(red: 0.03, green: 0.01, blue: 0.04, alpha: 0.88)
    )

    static let plinkTeal = PlinkLivingTheme(
        id: "plink-teal", name: "Plink Teal", access: .free, master: .plinkTeal,
        colors: [
            RGBAColor(red: 0.02, green: 0.05, blue: 0.06, alpha: 1),
            RGBAColor(red: 0.05, green: 0.40, blue: 0.45, alpha: 1),
            RGBAColor(red: 0.15, green: 0.69, blue: 0.61, alpha: 1),
        ],
        chatScrim: RGBAColor(red: 0.01, green: 0.03, blue: 0.03, alpha: 0.88)
    )

    static let magentaBloom = PlinkLivingTheme(
        id: "magenta-bloom", name: "Magenta Bloom", access: .premium, master: .magentaBloom,
        colors: [
            RGBAColor(red: 0.06, green: 0.02, blue: 0.05, alpha: 1),
            RGBAColor(red: 0.60, green: 0.10, blue: 0.40, alpha: 1),
            RGBAColor(red: 0.90, green: 0.30, blue: 0.60, alpha: 1),
        ],
        chatScrim: RGBAColor(red: 0.03, green: 0.01, blue: 0.03, alpha: 0.88)
    )

    static let all: [PlinkLivingTheme] = [electricBlue, cinemaEmber, violetHorizon, plinkTeal, magentaBloom]

    static func resolve(_ id: String?) -> PlinkLivingTheme {
        guard let id else { return electricBlue }
        return all.first(where: { $0.id == id }) ?? electricBlue
    }
}
