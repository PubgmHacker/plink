// Регрессионные тесты на восстановленные системы

import XCTest
@testable import Plink

final class M35RegressionTests: XCTestCase {

    // Home no longer duplicates Rooms filters. Discovery is a content feed;
    // room filtering and management belong to the Rooms destination.

    // Прогресс истории просмотров ограничен 1.0
    func testWatchHistoryProgressClamped() {
        let item = WatchHistoryItem(
            id: "1", mediaItemId: "m", title: "t",
            thumbnailURL: nil, streamURL: "s",
            mediaType: "movie", source: "youtube",
            watchedAt: Date(), watchedDuration: 120, totalDuration: 60
        )
        XCTAssertEqual(item.progress, 1.0)
    }

    // Прогресс неизвестен без общей длительности
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
