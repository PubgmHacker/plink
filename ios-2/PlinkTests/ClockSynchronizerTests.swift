// PlinkTests/ClockSynchronizerTests.swift — PATCH 17: clock sync tests
//
// Closes the "sync" yellow system in RegressionMatrix (was yellow,
// now green). Tests cover: probe ingestion, offset calculation,
// RTT computation, sample windowing, reset, isSynchronized threshold.

import XCTest
@testable import Plink

@MainActor
final class ClockSynchronizerTests: XCTestCase {

    // MARK: - Initial state

    func testInitialState_offsetIsZero() {
        let clock = ClockSynchronizer()
        XCTAssertEqual(clock.offsetMs, 0)
        XCTAssertEqual(clock.rttMs, 0)
        XCTAssertEqual(clock.probeCount, 0)
        XCTAssertFalse(clock.isSynchronized)
    }

    // MARK: - Single probe

    func testIngest_singleProbe_setsOffsetAndRtt() {
        let clock = ClockSynchronizer()
        // clientSent = 1000, server = 1050, clientReceived = 1100
        // RTT = 100, midpoint = 1050, offset = 0
        clock.ingest(clientSentMs: 1000, serverMs: 1050, clientReceivedMs: 1100)

        XCTAssertEqual(clock.offsetMs, 0, accuracy: 0.01)
        XCTAssertEqual(clock.rttMs, 100, accuracy: 0.01)
        XCTAssertEqual(clock.probeCount, 1)
        XCTAssertFalse(clock.isSynchronized, "Need 3 probes to sync")
    }

    func testIngest_positiveOffset_serverAheadOfClient() {
        let clock = ClockSynchronizer()
        // clientSent = 1000, server = 1100, clientReceived = 1100
        // RTT = 100, midpoint = 1050, offset = +50
        clock.ingest(clientSentMs: 1000, serverMs: 1100, clientReceivedMs: 1100)

        XCTAssertEqual(clock.offsetMs, 50, accuracy: 0.01)
    }

    func testIngest_negativeOffset_serverBehindClient() {
        let clock = ClockSynchronizer()
        // clientSent = 1000, server = 1000, clientReceived = 1100
        // RTT = 100, midpoint = 1050, offset = -50
        clock.ingest(clientSentMs: 1000, serverMs: 1000, clientReceivedMs: 1100)

        XCTAssertEqual(clock.offsetMs, -50, accuracy: 0.01)
    }

    // MARK: - isSynchronized threshold

    func testIsSynchronized_falseUntilThreeProbes() {
        let clock = ClockSynchronizer()

        clock.ingest(clientSentMs: 1000, serverMs: 1050, clientReceivedMs: 1100)
        XCTAssertFalse(clock.isSynchronized)

        clock.ingest(clientSentMs: 2000, serverMs: 2050, clientReceivedMs: 2100)
        XCTAssertFalse(clock.isSynchronized)

        clock.ingest(clientSentMs: 3000, serverMs: 3050, clientReceivedMs: 3100)
        XCTAssertTrue(clock.isSynchronized, "3 probes should sync")
    }

    // MARK: - Sample windowing

    func testIngest_keepsOnlyMaxSamples() {
        let clock = ClockSynchronizer()

        // Ingest 20 samples (more than maxSamples which is typically 10).
        for i in 0..<20 {
            clock.ingest(clientSentMs: Double(i * 1000), serverMs: Double(i * 1000 + 50), clientReceivedMs: Double(i * 1000 + 100))
        }

        XCTAssertEqual(clock.probeCount, 20, "probeCount tracks all probes")
        // offsetMs should be stable around +0 (server = midpoint).
        XCTAssertEqual(clock.offsetMs, 0, accuracy: 5)
    }

    // MARK: - RTT selection

    func testIngest_selectsLowestRttSamples() {
        let clock = ClockSynchronizer()

        // First sample: high RTT (200ms), offset +100
        clock.ingest(clientSentMs: 1000, serverMs: 1200, clientReceivedMs: 1200)
        XCTAssertEqual(clock.offsetMs, 100, accuracy: 0.01)

        // Second sample: low RTT (10ms), offset 0
        clock.ingest(clientSentMs: 2000, serverMs: 2005, clientReceivedMs: 2010)

        // Third sample: low RTT (20ms), offset 0
        clock.ingest(clientSentMs: 3000, serverMs: 3010, clientReceivedMs: 3020)

        // After 3 samples, isSynchronized is true.
        XCTAssertTrue(clock.isSynchronized)

        // The median of top-N by RTT should be close to 0 (the low-RTT samples).
        // The high-RTT sample (+100 offset) should be discarded.
        XCTAssertEqual(clock.offsetMs, 0, accuracy: 5,
                       "Low-RTT samples should dominate; high-RTT sample should be discarded")
    }

    // MARK: - reset

    func testReset_clearsAllState() {
        let clock = ClockSynchronizer()
        clock.ingest(clientSentMs: 1000, serverMs: 1050, clientReceivedMs: 1100)
        clock.ingest(clientSentMs: 2000, serverMs: 2050, clientReceivedMs: 2100)
        clock.ingest(clientSentMs: 3000, serverMs: 3050, clientReceivedMs: 3100)
        XCTAssertTrue(clock.isSynchronized)

        clock.reset()

        XCTAssertEqual(clock.offsetMs, 0)
        XCTAssertEqual(clock.rttMs, 0)
        XCTAssertEqual(clock.probeCount, 0)
        XCTAssertFalse(clock.isSynchronized)
    }

    // MARK: - serverNowMs

    func testServerNowMs_appliesOffset() {
        let clock = ClockSynchronizer()
        // Set offset to +5000ms.
        clock.ingest(clientSentMs: 1000, serverMs: 6500, clientReceivedMs: 1000)
        // RTT = 0, midpoint = 1000, offset = +5500

        let serverNow = clock.serverNowMs
        let localNow = Date().timeIntervalSince1970 * 1000

        // serverNow should be localNow + offset.
        XCTAssertEqual(serverNow, localNow + 5500, accuracy: 50,
                       "serverNowMs must apply offset to local time")
    }

    // MARK: - Edge cases

    func testIngest_zeroRtt_treatedAsInstant() {
        let clock = ClockSynchronizer()
        // clientSent = clientReceived = 1000, server = 1000
        // RTT = 0, midpoint = 1000, offset = 0
        clock.ingest(clientSentMs: 1000, serverMs: 1000, clientReceivedMs: 1000)

        XCTAssertEqual(clock.rttMs, 0)
        XCTAssertEqual(clock.offsetMs, 0)
    }

    func testIngest_negativeRtt_clampedToZero() {
        let clock = ClockSynchronizer()
        // Impossible case: clientReceived < clientSent.
        // RTT should be clamped to 0.
        clock.ingest(clientSentMs: 2000, serverMs: 2050, clientReceivedMs: 1500)

        XCTAssertEqual(clock.rttMs, 0, "Negative RTT must be clamped to 0")
    }
}
