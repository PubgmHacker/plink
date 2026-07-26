// Plink/V4/V4Theme.swift — split from PlinkV4PixelPerfect (move-only, no logic change)
// Source of truth: V4 design module. Do not change visuals.

import SwiftUI
import PhotosUI
import UIKit
import Foundation

// MARK: - KeyboardObserver
@Observable
final class KeyboardObserver {
    @MainActor private(set) var isVisible: Bool = false
    private var showToken: NSObjectProtocol?
    private var hideToken: NSObjectProtocol?

    init() {
        let nc = NotificationCenter.default
        showToken = nc.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isVisible = true }
        }
        hideToken = nc.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isVisible = false }
        }
    }

    deinit {
        if let s = showToken { NotificationCenter.default.removeObserver(s) }
        if let h = hideToken { NotificationCenter.default.removeObserver(h) }
    }
}

extension Color {
    /// Exact CSS OKLCH -> linear sRGB -> display sRGB conversion.
    static func oklch(_ l: Double, _ c: Double, _ h: Double, alpha: Double = 1) -> Color {
        let hr = h * .pi / 180
        let a = c * cos(hr)
        let b = c * sin(hr)
        let l1 = l + 0.3963377774 * a + 0.2158037573 * b
        let m1 = l - 0.1055613458 * a - 0.0638541728 * b
        let s1 = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l1 * l1 * l1
        let M = m1 * m1 * m1
        let S = s1 * s1 * s1
        let rLin =  4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
        let gLin = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
        let bLin = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        func gamma(_ x: Double) -> Double {
            let v = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
            return min(1, max(0, v))
        }
        return Color(.sRGB, red: gamma(rLin), green: gamma(gLin), blue: gamma(bLin), opacity: alpha)
    }
}

enum V4 {
    static let canvas = Color.oklch(0.06, 0.01, 190)
    static let ink = Color.oklch(0.96, 0.008, 190)
    static let muted = Color.oklch(0.72, 0.018, 190)
    static let line = Color.oklch(0.88, 0.01, 190, alpha: 0.13)
    static let surface = Color.oklch(0.17, 0.018, 190)
    static let raised = Color.oklch(0.22, 0.02, 190)
    static let accent = Color.oklch(0.78, 0.12, 174)
    static let accentInk = Color.oklch(0.17, 0.04, 174)
    static let amber = Color.oklch(0.79, 0.14, 78)
    static let danger = Color.oklch(0.65, 0.18, 25)
    static let roundBG = Color.oklch(0.15, 0.016, 190, alpha: 0.86)
    static let searchBG = Color.oklch(0.14, 0.016, 190, alpha: 0.82)
    static let cardBG = Color.oklch(0.17, 0.02, 190, alpha: 0.82)
    static let navBG = Color.oklch(0.13, 0.015, 190, alpha: 0.94)
    static let botBG = Color.oklch(0.17, 0.018, 190, alpha: 0.94)
    static let composerBG = Color.oklch(0.13, 0.015, 190, alpha: 0.96)
}


// MARK: - Section

enum V4Theme: String, CaseIterable, Identifiable {
    case electric, ember, violet, plink, bloom
    var id: Self { self }
    var name: String { rawValue.capitalized }
    var colors: (Color, Color, Color, Color) {
        switch self {
        case .electric: return (.oklch(0.09,0.02,255), .oklch(0.60,0.22,258), .oklch(0.72,0.18,210), .oklch(0.62,0.20,270))
        case .ember: return (.oklch(0.10,0.025,45), .oklch(0.63,0.24,35), .oklch(0.75,0.20,78), .oklch(0.65,0.22,28))
        case .violet: return (.oklch(0.09,0.025,285), .oklch(0.58,0.24,285), .oklch(0.62,0.25,325), .oklch(0.72,0.18,310))
        case .plink: return (.oklch(0.09,0.02,190), .oklch(0.64,0.18,185), .oklch(0.50,0.22,258), .oklch(0.65,0.18,326))
        case .bloom: return (.oklch(0.10,0.03,320), .oklch(0.61,0.26,330), .oklch(0.62,0.26,15), .oklch(0.71,0.20,350))
        }
    }
    /// Primary accent color — used by AI orb glow, buttons, etc.
    var accentColor: Color { colors.1 }
    /// Secondary accent color.
    var secondaryAccent: Color { colors.3 }
    /// Button text color — black for light accents (ember), white for dark.
    var buttonTextColor: Color {
        switch self {
        case .ember: return .black
        default: return .white
        }
    }
}

// MARK: - Plink+ Live Themes
enum PlinkPlusLiveTheme: Int, CaseIterable, Identifiable {
    case aurora = 1, cosmos = 2, verdant = 3, magma = 4
    var id: Int { rawValue }
    var name: String { ["Aurora","Cosmos","Verdant","Magma"][rawValue-1] }
    var videoFileName: String? { "live_theme_\(name.lowercased())" }
    var colors: (Color, Color, Color, Color) {
        switch self {
        case .aurora: return (Color(red:40/255,green:15/255,blue:33/255), Color(red:252/255,green:99/255,blue:152/255), Color(red:224/255,green:72/255,blue:114/255), Color(red:182/255,green:48/255,blue:84/255))
        case .cosmos: return (Color(red:0,green:0,blue:0), Color(red:1/255,green:44/255,blue:237/255), Color(red:8/255,green:82/255,blue:242/255), Color(red:19/255,green:112/255,blue:252/255))
        case .verdant: return (Color(red:14/255,green:16/255,blue:11/255), Color(red:158/255,green:244/255,blue:89/255), Color(red:126/255,green:226/255,blue:99/255), Color(red:164/255,green:255/255,blue:131/255))
        case .magma: return (Color(red:0,green:0,blue:0), Color(red:174/255,green:0,blue:0), Color(red:142/255,green:0,blue:0), Color(red:105/255,green:0,blue:3/255))
        }
    }
    var accentColor: Color { colors.1 }
    var secondaryAccent: Color { colors.3 }
    var buttonTextColor: Color {
        switch self {
        case .verdant, .aurora: return .black
        default: return .white
        }
    }
    var closestStandardTheme: V4Theme {
        switch self { case .aurora: return .bloom; case .cosmos: return .electric; case .verdant: return .plink; case .magma: return .ember }
    }
    static func resolve(_ index: Int) -> PlinkPlusLiveTheme? { guard index >= 1, index <= 4 else { return nil }; return PlinkPlusLiveTheme(rawValue: index) }
}

struct PlinkPlusStaticGradient: View {
    let theme: PlinkPlusLiveTheme
    var body: some View {
        let (bg, c1, c2, c3) = theme.colors
        ZStack { bg; LinearGradient(colors:[c1.opacity(0.35),c2.opacity(0.25),c3.opacity(0.15)],startPoint:.topLeading,endPoint:.bottomTrailing); RadialGradient(colors:[.clear,bg.opacity(0.6)],center:.center,startRadius:0,endRadius:600) }.ignoresSafeArea().allowsHitTesting(false)
    }
}



