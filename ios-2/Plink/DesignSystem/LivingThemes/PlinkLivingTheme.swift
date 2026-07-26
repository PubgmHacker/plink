// Plink/DesignSystem/LivingThemes/PlinkLivingTheme.swift — GPT-5.6 §4
import SwiftUI

struct PlinkLivingTheme: Identifiable, Codable, Hashable, Sendable {
    enum Access: String, Codable, Sendable { case free, premium }
    enum Master: String, Codable, Sendable {
        case electricBlue, cinemaEmber, violetHorizon, plinkTeal, magentaBloom
    }
    let id: String
    let name: String
    let access: Access
    let master: Master
    let colors: [RGBAColor]
    let chatScrim: RGBAColor
}

struct RGBAColor: Codable, Hashable, Sendable {
    let red: Double; let green: Double; let blue: Double; let alpha: Double
    var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }
}
