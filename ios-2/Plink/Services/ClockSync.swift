//  ClockSync.swift
//  Plink — M39
//
//  Синхронизация часов с сервером по упрощённому алгоритму NTP.
//
//  Зачем это вообще нужно: часы на двух iPhone могут расходиться на секунды.
//  Без общей шкалы времени любая «синхронизация просмотра» — самообман.
//  Это и есть то, чего не делают конкуренты на расширениях браузера.

import Foundation

actor ClockSync {
    static let shared = ClockSync()

    enum Quality {
        case excellent, good, poor, unknown

        var label: String {
            switch self {
            case .excellent: return "отличное"
            case .good: return "хорошее"
            case .poor: return "слабое"
            case .unknown: return "неизвестное"
            }
        }
    }

    private(set) var currentOffset: TimeInterval = 0
    private(set) var quality: Quality = .unknown
    private var lastSync: Date?

    private let sampleCount = 5
    private let samplePause: UInt64 = 120_000_000 // 120 мс
    private let resyncInterval: TimeInterval = 300

    private init() {}

    /// Время сервера в текущий момент, с учётом измеренного смещения.
    var serverNow: Date {
        Date().addingTimeInterval(currentOffset)
    }

    func invalidate() {
        lastSync = nil
        quality = .unknown
    }

    func syncIfNeeded() async {
        if let lastSync, Date().timeIntervalSince(lastSync) < resyncInterval { return }
        await sync()
    }

    func sync() async {
        var samples: [(offset: TimeInterval, rtt: TimeInterval)] = []

        for index in 0..<sampleCount {
            if index > 0 { try? await Task.sleep(nanoseconds: samplePause) }
            guard let sample = await measure() else { continue }
            // Отбраковка явно битых замеров: отрицательный или огромный RTT.
            if sample.rtt < 0 || sample.rtt >= 5 { continue }
            samples.append(sample)
        }

        guard !samples.isEmpty else {
            quality = .unknown
            return
        }

        // Берём три замера с наименьшим RTT и считаем медиану — так шум сети не сбивает результат.
        let best = samples.sorted { $0.rtt < $1.rtt }.prefix(3)
        let offsets = best.map(\.offset).sorted()
        currentOffset = offsets[offsets.count / 2]

        let bestRTT = best.first?.rtt ?? 1
        switch bestRTT {
        case ..<0.08: quality = .excellent
        case ..<0.25: quality = .good
        default: quality = .poor
        }

        lastSync = Date()
    }

    private func measure() async -> (offset: TimeInterval, rtt: TimeInterval)? {
        guard let url = URL(string: APIConfig.baseURL + "/api/realtime/time") else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if let token = AuthTokenStore.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 8

        let t0 = Date()
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        let t3 = Date()

        struct TimeResponse: Decodable {
            let serverTime: String
            let t1: Double?
            let t2: Double?
        }

        guard let decoded = try? JSONDecoder().decode(TimeResponse.self, from: data) else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Предпочитаем точки t1/t2 — они учитывают время обработки на сервере.
        let t1: TimeInterval
        let t2: TimeInterval
        if let rawT1 = decoded.t1, let rawT2 = decoded.t2 {
            t1 = rawT1 / 1000
            t2 = rawT2 / 1000
        } else if let parsed = formatter.date(from: decoded.serverTime) {
            // Деградация к serverTime, если сервер старой версии.
            t1 = parsed.timeIntervalSince1970
            t2 = parsed.timeIntervalSince1970
        } else {
            return nil
        }

        let start = t0.timeIntervalSince1970
        let end = t3.timeIntervalSince1970

        let offset = ((t1 - start) + (t2 - end)) / 2
        let rtt = (end - start) - (t2 - t1)

        return (offset, rtt)
    }
}
