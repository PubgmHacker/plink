// PlinkTests/ThemeRegressionTests.swift
// снапшот-тесты каталога тем — защита от случайной потери/переименования
// тем оформления при рефакторингах (как было с откатом на V5).

import XCTest
import SwiftUI
@testable import Plink

final class ThemeRegressionTests: XCTestCase {

    // MARK: - V4 темы (бесплатные)

    func testV4ThemeCatalogIsStable() {
        XCTAssertEqual(V4Theme.allCases.count, 5, "должно быть ровно 5 бесплатных тем")
        XCTAssertEqual(
            V4Theme.allCases.map(\.name),
            ["Electric", "Ember", "Violet", "Plink", "Bloom"],
            "имена и порядок тем не должны меняться"
        )
    }

    func testV4ThemeAccentIsSecondGradientColor() {
        for theme in V4Theme.allCases {
            XCTAssertEqual(
                theme.accentColor, theme.colors.1,
                "\(theme.name): accentColor должен быть colors.1"
            )
        }
    }

    func testV4ThemeBackgroundsAreDistinct() {
        let backgrounds = V4Theme.allCases.map { "\($0.colors.0)" }
        XCTAssertEqual(
            Set(backgrounds).count, backgrounds.count,
            "фоны тем должны быть уникальными"
        )
    }

    func testV4ThemeAccentsAreDistinct() {
        let accents = V4Theme.allCases.map { "\($0.colors.1)" }
        XCTAssertEqual(
            Set(accents).count, accents.count,
            "акценты тем должны быть уникальными"
        )
    }

    // MARK: - Plink+ live-темы (премиум)

    func testPlinkPlusCatalogIsStable() {
        XCTAssertEqual(PlinkPlusLiveTheme.allCases.count, 4, "должно быть ровно 4 live-темы")
        XCTAssertEqual(
            PlinkPlusLiveTheme.allCases.map(\.name),
            ["Aurora", "Cosmos", "Verdant", "Magma"]
        )
        XCTAssertEqual(
            PlinkPlusLiveTheme.allCases.map(\.videoFileName),
            ["live_theme_aurora", "live_theme_cosmos", "live_theme_verdant", "live_theme_magma"]
        )
    }

    func testPlinkPlusResolveBounds() {
        XCTAssertNil(PlinkPlusLiveTheme.resolve(0), "0 = стандартная тема, не live")
        XCTAssertEqual(PlinkPlusLiveTheme.resolve(1), .aurora)
        XCTAssertEqual(PlinkPlusLiveTheme.resolve(2), .cosmos)
        XCTAssertEqual(PlinkPlusLiveTheme.resolve(3), .verdant)
        XCTAssertEqual(PlinkPlusLiveTheme.resolve(4), .magma)
        XCTAssertNil(PlinkPlusLiveTheme.resolve(5), "индекс вне диапазона → nil")
        XCTAssertNil(PlinkPlusLiveTheme.resolve(-1))
    }

    func testPlinkPlusAccentIsSecondGradientColor() {
        for theme in PlinkPlusLiveTheme.allCases {
            XCTAssertEqual(
                theme.accentColor, theme.colors.1,
                "\(theme.name): accentColor должен быть colors.1"
            )
        }
    }

    func testPlinkPlusBackgroundsAreDistinct() {
        let backgrounds = PlinkPlusLiveTheme.allCases.map { "\($0.colors.0)" }
        XCTAssertEqual(Set(backgrounds).count, backgrounds.count)
    }

    // MARK: - Класс устройства

    /// Класс определяется по экрану ИЛИ по памяти, и одного признака мало:
    /// iPhone 11 проходит только по экрану (4 ГБ, но LCD 2×), iPhone X —
    /// только по памяти (3× OLED, но 3 ГБ). Проверяем обе двери отдельно.
    func testDeviceTierResolvesByScale() {
        XCTAssertEqual(PlinkDeviceTier.resolve(displayScale: 2), .classic, "2× — LCD-класс")
        XCTAssertEqual(PlinkDeviceTier.resolve(displayScale: 1), .classic)
        // На 3× решает память, а она у машины теста своя — поэтому здесь
        // сверяемся с тем же признаком, а не с константой.
        XCTAssertEqual(
            PlinkDeviceTier.resolve(displayScale: 3),
            PlinkDeviceTier.hasScarceMemory ? .classic : .modern
        )
    }

    func testDeviceTierOverrideWins() {
        XCTAssertEqual(
            PlinkDeviceTier.resolve(displayScale: 3, override: .classic), .classic,
            "снимки дизайна обязаны уметь принудить класс"
        )
        XCTAssertEqual(PlinkDeviceTier.resolve(displayScale: 2, override: .modern), .modern)
    }

    /// Волосяная линия — ровно один физический пиксель, а не «1 pt».
    func testDeviceTierHairlineIsOnePixel() {
        XCTAssertEqual(PlinkDeviceTier.classic.hairline(displayScale: 2), 0.5)
        XCTAssertEqual(PlinkDeviceTier.modern.hairline(displayScale: 3), 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(PlinkDeviceTier.modern.hairline(displayScale: 0), 0.5, "деления на ноль быть не должно")
    }

    /// Классика рисует дешевле и плотнее, современный класс — без изменений.
    /// Второе важнее первого: правка не имела права затронуть 17 Pro.
    func testDeviceTierModernIsUntouched() {
        let modern = PlinkDeviceTier.modern
        XCTAssertEqual(modern.glassFillBoost, 0)
        XCTAssertEqual(modern.glassEdgeGain, 1)
        XCTAssertTrue(modern.drawsGlassSpecular)
        XCTAssertTrue(modern.usesBlurredOrbs)
        XCTAssertEqual(modern.decorativeOrbCount, 3)
        XCTAssertEqual(modern.decorativeFrameInterval, 1.0 / 30, accuracy: 0.0001)
    }

    func testDeviceTierClassicIsCheaperAndDenser() {
        let classic = PlinkDeviceTier.classic
        XCTAssertGreaterThan(classic.glassFillBoost, 0, "на LCD подложка обязана быть плотнее")
        XCTAssertGreaterThan(classic.glassEdgeGain, 1, "кромка заметнее — у панели должен быть край")
        XCTAssertFalse(classic.drawsGlassSpecular, "overlay-блик снят: офскрин на каждую поверхность")
        XCTAssertFalse(classic.usesBlurredOrbs, "гауссов проход снят целиком, а не урезан")
        XCTAssertLessThan(classic.decorativeOrbCount, PlinkDeviceTier.modern.decorativeOrbCount)
        XCTAssertGreaterThan(
            classic.decorativeFrameInterval, PlinkDeviceTier.modern.decorativeFrameInterval,
            "шаг больше = кадров меньше"
        )
    }
}
