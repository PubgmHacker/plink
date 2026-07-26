// PlinkTests/M35RegressionTests.swift — M35: регрессионные тесты на восстановленные системы

import XCTest
@testable import Plink

final class M35RegressionTests: XCTestCase {

    // M30: фильтры главной — порядок и названия пилюль
    func testHomeFilterCases() {
        XCTAssertEqual(
            HomeFilter.allCases.map(\.rawValue),
            ["Всё", "Популярное", "Смотрят", "Друзья"]
        )
    }

    // M32: прогресс истории просмотров ограничен 1.0
    func testWatchHistoryProgressClamped() {
        let item = WatchHistoryItem(
            id: "1", mediaItemId: "m", title: "t",
            thumbnailURL: nil, streamURL: "s",
            mediaType: "movie", source: "youtube",
            watchedAt: Date(), watchedDuration: 120, totalDuration: 60
        )
        XCTAssertEqual(item.progress, 1.0)
    }

    // M32: прогресс неизвестен без общей длительности
    func testWatchHistoryProgressNilWithoutTotal() {
        let item = WatchHistoryItem(
            id: "2", mediaItemId: "m", title: "t",
            thumbnailURL: nil, streamURL: "s",
            mediaType: "movie", source: "youtube",
            watchedAt: Date(), watchedDuration: 30, totalDuration: nil
        )
        XCTAssertNil(item.progress)
    }
}
