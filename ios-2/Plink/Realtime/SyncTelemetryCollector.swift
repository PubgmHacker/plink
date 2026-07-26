//
//  SyncTelemetryCollector.swift
//  Plink
//
//  B3 (GPT-5.6 ADR-004/005): Client-side sync drift telemetry.
//  Collects samples every 2s + on playback events, sends to backend.
//

import Foundation
import Network

@MainActor
@Observable
final class SyncTelemetryCollector {
    private let apiBase = PlinkConfig.baseURLString
    private var sessionId: String = UUID().uuidString
    private var roomId: String = ""
    private var role: String = "participant"
    private var provider: String = "youtube"
    private var sampleTimer: Task<Void, Never>?
    private var samples: [SyncSample] = []
    private var corrections: Int = 0
    private var reconnectStart: Date?
    private var reconnectDurations: [TimeInterval] = []

    struct SyncSample: Codable {
        let sessionId: String
        let roomId: String
        let role: String
        let absoluteDriftMs: Double
        let signedDriftMs: Double?
        let correctionType: String?
        let correctionMagnitude: Double?
        let playbackState: String
        let networkType: String
        let provider: String
        let appBuild: String
    }

    struct SessionAggregate: Codable {
        let sessionId: String
        let roomId: String
        let sampleCount: Int
        let medianDriftMs: Double
        let p95DriftMs: Double
        let maxDriftMs: Double
        let correctionCount: Int
        let reconnectDurations: [Double]
        let bufferingDurationMs: Double
        let provider: String
        let networkTypes: [String]
        let appBuild: String
        let duration: Double
    }

    func startSession(roomId: String, role: String, provider: String) {
        self.sessionId = UUID().uuidString
        self.roomId = roomId
        self.role = role
        self.provider = provider
        self.samples = []
        self.corrections = 0
        self.reconnectDurations = []

        sampleTimer?.cancel()
        sampleTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2s
                await self?.collectSample()
            }
        }
    }

    func stopSession() async {
        sampleTimer?.cancel()
        sampleTimer = nil
        await sendAggregate()
    }

    func recordCorrection(type: String, magnitude: Double) {
        corrections += 1
        // Send immediate sample for correction event
        Task { await collectSample(correctionType: type, correctionMagnitude: magnitude) }
    }

    func recordReconnectStart() {
        reconnectStart = Date()
    }

    func recordReconnectEnd() {
        if let start = reconnectStart {
            reconnectDurations.append(Date().timeIntervalSince(start))
            reconnectStart = nil
        }
    }

    private var currentDriftMs: Double = 0
    private var currentPlaybackState: String = "idle"

    /// Called by WatchRoomModel when sync state updates.
    func updateDrift(_ driftMs: Double, playbackState: String) {
        currentDriftMs = driftMs
        currentPlaybackState = playbackState
    }

    private func collectSample(correctionType: String? = nil, correctionMagnitude: Double? = nil) async {
        let drift = currentDriftMs
        let state = currentPlaybackState
        let network = await currentNetworkType()

        let sample = SyncSample(
            sessionId: sessionId,
            roomId: roomId,
            role: role,
            absoluteDriftMs: abs(drift),
            signedDriftMs: drift,
            correctionType: correctionType,
            correctionMagnitude: correctionMagnitude,
            playbackState: state,
            networkType: network,
            provider: provider,
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        )

        samples.append(sample)
        await sendSample(sample)
    }

    private func sendSample(_ sample: SyncSample) async {
        guard let url = URL(string: "\(apiBase)/api/telemetry/sync-sample") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainHelper.read(for: "rave_auth_token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONEncoder().encode(sample)
        _ = try? await URLSession.shared.data(for: req)
    }

    private func sendAggregate() async {
        guard !samples.isEmpty else { return }

        let drifts = samples.map { $0.absoluteDriftMs }.sorted()
        let count = drifts.count
        let median = count > 0 ? drifts[count / 2] : 0
        let p95Index = Int(Double(count) * 0.95)
        let p95 = p95Index < count ? drifts[p95Index] : drifts.last ?? 0
        let max = drifts.last ?? 0

        let networkTypes = Array(Set(samples.map { $0.networkType }))
        let bufferingDuration = samples.filter { $0.playbackState == "buffering" }.count * 2 * 1000  // 2s per sample

        let aggregate = SessionAggregate(
            sessionId: sessionId,
            roomId: roomId,
            sampleCount: count,
            medianDriftMs: median,
            p95DriftMs: p95,
            maxDriftMs: max,
            correctionCount: corrections,
            reconnectDurations: reconnectDurations,
            bufferingDurationMs: Double(bufferingDuration),
            provider: provider,
            networkTypes: networkTypes,
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            duration: Double(count * 2)  // 2s per sample
        )

        guard let url = URL(string: "\(apiBase)/api/telemetry/sync-session") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainHelper.read(for: "rave_auth_token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONEncoder().encode(aggregate)
        _ = try? await URLSession.shared.data(for: req)
    }

    private func currentNetworkType() async -> String {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.pathUpdateHandler = nil
                monitor.cancel()
                let type: String
                if path.usesInterfaceType(.wifi) { type = "wifi" }
                else if path.usesInterfaceType(.cellular) { type = "cellular" }
                else if path.usesInterfaceType(.wiredEthernet) { type = "ethernet" }
                else { type = "other" }
                continuation.resume(returning: type)
            }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
        }
    }
}
