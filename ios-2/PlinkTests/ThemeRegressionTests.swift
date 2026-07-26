// PlinkTests/ThemeRegressionTests.swift
// M12: снапшот-тесты каталога тем — защита от случайной потери/переименования
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
}
