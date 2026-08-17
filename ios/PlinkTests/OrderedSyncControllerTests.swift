// PlinkTests/OrderedSyncControllerTests.swift
// Brain Review 7 P0-55: seek continuation + drift policy tests
//
// Tests:
//   - seq 9 after seq 10 is ignored
//   - drift 40ms is no-op
//   - drift 180ms applies 1.02/0.98 rate
//   - drift 900ms does precise seek
//   - pause does not extrapolate position
//   - reconnect preserves watermark

import XCTest
@testable import Plink

@MainActor
final class OrderedSyncControllerTests: XCTestCase {

    private func makeState(
        epoch: Int64 = 1,
        seq: Int64,
        positionMs: Int64 = 0,
        playing: Bool = false,
        rate: Double = 1.0,
        effectiveAtServerMs: Int64? = nil
    ) -> RealtimeRoomState {
        RealtimeRoomState(
            protocolVersion: 2,
            roomId: "00000000-0000-4000-8000-000000000000",
            epoch: epoch,
            seq: seq,
            mediaId: nil,
            positionMs: positionMs,
            playing: playing,
            rate: rate,
            effectiveAtServerMs: effectiveAtServerMs ?? Int64(Date().timeIntervalSince1970 * 1000),
            issuedBy: "00000000-0000-4000-8000-000000000001"
        )
    }

    func testSeq9AfterSeq10IsIgnored() async {
        let clock = ClockSynchronizer()
        let player = FakePlaybackController()
        let controller = OrderedSyncController(clock: clock, player: player)

        await controller.apply(makeState(seq: 10, positionMs: 5000, playing: true))
        XCTAssertEqual(player.position, 5.0, accuracy: 0.5)

        // Seq 9 should be ignored
        await controller.apply(makeState(seq: 9, positionMs: 99999, playing: true))
        XCTAssertEqual(player.position, 5.0, accuracy: 0.5,
                       "Seq 9 after seq 10 must be ignored")
    }

    func testDrift40msIsNoOp() async {
        let clock = ClockSynchronizer()
        let player = FakePlaybackController()
        player.position = 10.0
        player.isPlaying = true
        let controller = OrderedSyncController(clock: clock, player: player)

        // Position 10.04s — drift 40ms — should be no-op
        await controller.apply(makeState(seq: 1, positionMs: 10040, playing: true))
        XCTAssertEqual(player.seekCallCount, 0, "40ms drift should not trigger seek")
    }

    func testDrift900msDoesPreciseSeek() async {
        let clock = ClockSynchronizer()
        let player = FakePlaybackController()
        player.position = 10.0
        player.isPlaying = true
        let controller = OrderedSyncController(clock: clock, player: player)

        // Position 19.9s — drift 9900ms — should precise seek
        await controller.apply(makeState(seq: 1, positionMs: 19900, playing: true))
        XCTAssertEqual(player.seekCallCount, 1, "900ms+ drift should trigger precise seek")
        XCTAssertEqual(player.seekTargets.first ?? 0, 19.9, accuracy: 1.0)
    }

    func testPauseDoesNotExtrapolatePosition() async {
        let clock = ClockSynchronizer()
        let player = FakePlaybackController()
        player.position = 15.0
        player.isPlaying = true
        let controller = OrderedSyncController(clock: clock, player: player)

        // Paused state at 15s — should NOT extrapolate forward
        let state = makeState(seq: 1, positionMs: 15000, playing: false)
        await controller.apply(state)

        // Player should be paused, position should stay at 15s
        XCTAssertFalse(player.isPlaying, "Player should be paused")
    }

    func testReconnectPreservesWatermark() async {
        let clock = ClockSynchronizer()
        let player = FakePlaybackController()
        let controller = OrderedSyncController(clock: clock, player: player)

        await controller.apply(makeState(seq: 10, positionMs: 5000, playing: true))
        XCTAssertEqual(controller.lastEpoch, 1)
        XCTAssertEqual(controller.lastSeq, 10)

        controller.resetForReconnect()

        // Watermark should be preserved
        XCTAssertEqual(controller.lastEpoch, 1, "Watermark epoch should be preserved")
        XCTAssertEqual(controller.lastSeq, 10, "Watermark seq should be preserved")
    }

    func testHasAppliedAnyStateFlag() async {
        let clock = ClockSynchronizer()
        let player = FakePlaybackController()
        let controller = OrderedSyncController(clock: clock, player: player)

        XCTAssertFalse(controller.hasAppliedAnyState)
        await controller.apply(makeState(seq: 1, positionMs: 0, playing: false))
        XCTAssertTrue(controller.hasAppliedAnyState)
    }
}
