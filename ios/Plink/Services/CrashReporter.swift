// Plink/Services/CrashReporter.swift
// Локальный crash-репортинг без внешних SDK.
//
// Перехватывает NSException и фатальные сигналы, пишет JSON-отчёт
// на диск и при следующем запуске отправляет на /api/telemetry/crash.
// Работает независимо от Firebase (который включается только при
// наличии реального GoogleService-Info.plist).

import Foundation

final class CrashReporter: @unchecked Sendable {
    static let shared = CrashReporter()
    private var installed = false

    static let reportsDirectory: URL = {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return base.appendingPathComponent("CrashReports", isDirectory: true)
    }()

    private init() {}

    // MARK: - Install handlers

    func install() {
        guard !installed else { return }
        installed = true
        try? FileManager.default.createDirectory(
            at: Self.reportsDirectory, withIntermediateDirectories: true
        )

        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.writeReport(
                kind: "exception",
                name: exception.name.rawValue,
                reason: exception.reason ?? "unknown",
                stack: exception.callStackSymbols
            )
        }

        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(sig) { signalValue in
                CrashReporter.writeReport(
                    kind: "signal",
                    name: CrashReporter.signalName(signalValue),
                    reason: "fatal signal \(signalValue)",
                    stack: Thread.callStackSymbols
                )
                exit(signalValue)
            }
        }
    }

    static func signalName(_ s: Int32) -> String {
        switch s {
        case SIGABRT: return "SIGABRT"
        case SIGSEGV: return "SIGSEGV"
        case SIGBUS: return "SIGBUS"
        case SIGILL: return "SIGILL"
        case SIGFPE: return "SIGFPE"
        case SIGTRAP: return "SIGTRAP"
        default: return "SIG\(s)"
        }
    }

    // MARK: - Write report (called from crash context — keep it minimal)

    static func writeReport(kind: String, name: String, reason: String, stack: [String]) {
        let report: [String: Any] = [
            "kind": kind,
            "name": name,
            "reason": String(reason.prefix(2000)),
            "stack": Array(stack.prefix(50)),
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            "os": "iOS " + ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) else { return }
        let file = reportsDirectory.appendingPathComponent(
            "crash-\(Int(Date().timeIntervalSince1970)).json"
        )
        try? data.write(to: file, options: .atomic)
    }

    // MARK: - Upload pending reports (next launch, best-effort)

    func uploadPendingReports() {
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(
                at: Self.reportsDirectory, includingPropertiesForKeys: nil
            ), !files.isEmpty else { return }
            guard let url = URL(string: PlinkConfig.apiURLString + "/telemetry/crash") else { return }
            let token = AuthTokenStore.shared.token

            for file in files.prefix(10) where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file) else { continue }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let token {
                    req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                }
                req.httpBody = data
                if let (_, resp) = try? await URLSession.shared.data(for: req),
                   let code = (resp as? HTTPURLResponse)?.statusCode,
                   (200..<300).contains(code) {
                    try? fm.removeItem(at: file)
                }
            }
        }
    }
}
