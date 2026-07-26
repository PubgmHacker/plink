// PlinkTests/LifecycleTests.swift — PATCH 21: lifecycle system tests

import XCTest
@testable import Plink

@MainActor
final class LifecycleTests: XCTestCase {

    // MARK: - RealtimeConnectionState

    func testRealtimeConnectionState_allCases() {
        let states: [RealtimeConnectionState] = [
            .idle, .connecting, .authenticating, .joining,
            .synchronizing, .connected, .reconnecting(attempt: 1),
            .failed(reason: "test")
        ]
        XCTAssertEqual(states.count, 8)
    }

    func testRealtimeConnectionState_isOnline() {
        XCTAssertTrue(RealtimeConnectionState.connected.isOnline)
        XCTAssertFalse(RealtimeConnectionState.idle.isOnline)
        XCTAssertFalse(RealtimeConnectionState.connecting.isOnline)
    }

    func testRealtimeConnectionState_isTransient() {
        XCTAssertTrue(RealtimeConnectionState.connecting.isTransient)
        XCTAssertTrue(RealtimeConnectionState.authenticating.isTransient)
        XCTAssertTrue(RealtimeConnectionState.joining.isTransient)
        XCTAssertTrue(RealtimeConnectionState.synchronizing.isTransient)
        XCTAssertTrue(RealtimeConnectionState.reconnecting(attempt: 1).isTransient)
        XCTAssertFalse(RealtimeConnectionState.connected.isTransient)
        XCTAssertFalse(RealtimeConnectionState.idle.isTransient)
    }

    // MARK: - Reconnect

    func testReconnect_stateTransitionsThroughConnecting() {
        var state: RealtimeConnectionState = .connected
        XCTAssertTrue(state.isOnline)

        state = .reconnecting(attempt: 1)
        XCTAssertTrue(state.isTransient)
        XCTAssertFalse(state.isOnline)

        state = .connecting
        XCTAssertTrue(state.isTransient)

        state = .connected
        XCTAssertTrue(state.isOnline)
    }

    // MARK: - Clock sync after background

    func testClockSync_resetClearsState() {
        let clock = ClockSynchronizer()
        clock.ingest(clientSentMs: 1000, serverMs: 1050, clientReceivedMs: 1100)
        clock.ingest(clientSentMs: 2000, serverMs: 2050, clientReceivedMs: 2100)
        clock.ingest(clientSentMs: 3000, serverMs: 3050, clientReceivedMs: 3100)
        XCTAssertTrue(clock.isSynchronized)

        clock.reset()

        XCTAssertFalse(clock.isSynchronized)
        XCTAssertEqual(clock.offsetMs, 0)
    }

    // MARK: - PlaybackCoordinator lifecycle

    func testPlaybackCoordinator_initialState() {
        let coordinator = PlaybackCoordinator()
        XCTAssertNil(coordinator.currentSource)
        XCTAssertNil(coordinator.currentController)
        XCTAssertFalse(coordinator.isPreparing)
    }

    func testPlaybackCoordinator_teardown_resetsState() {
        let coordinator = PlaybackCoordinator()
        coordinator.teardown()
        XCTAssertNil(coordinator.currentSource)
        XCTAssertFalse(coordinator.isPreparing)
    }
}
