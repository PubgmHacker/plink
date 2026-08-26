import Foundation
import os

// MARK: - Logger
/// Centralized structured logging across the app's subsystems.
/// Uses `os.Logger` (unified logging) in release for efficient, filterable logs,
/// and falls back to `print` in debug for readability.
///
/// Levels: info, warn, error.
enum Logger {

    // MARK: - Log Domains

    enum app {
        static func info(_ msg: String)  { Logger.log(msg, domain: "App", level: .info) }
        static func warn(_ msg: String)  { Logger.log(msg, domain: "App", level: .warn) }
        static func error(_ msg: String) { Logger.log(msg, domain: "App", level: .error) }
    }

    enum ws {
        static func info(_ msg: String)  { Logger.log(msg, domain: "WS", level: .info) }
        static func warn(_ msg: String)  { Logger.log(msg, domain: "WS", level: .warn) }
        static func error(_ msg: String) { Logger.log(msg, domain: "WS", level: .error) }
    }

    enum sync {
        static func info(_ msg: String)  { Logger.log(msg, domain: "SYNC", level: .info) }
        static func warn(_ msg: String)  { Logger.log(msg, domain: "SYNC", level: .warn) }
        static func error(_ msg: String) { Logger.log(msg, domain: "SYNC", level: .error) }
    }

    enum store {
        static func info(_ msg: String)  { Logger.log(msg, domain: "StoreKit", level: .info) }
        static func warn(_ msg: String)  { Logger.log(msg, domain: "StoreKit", level: .warn) }
        static func error(_ msg: String) { Logger.log(msg, domain: "StoreKit", level: .error) }
    }

    enum api {
        static func info(_ msg: String)  { Logger.log(msg, domain: "API", level: .info) }
        static func warn(_ msg: String)  { Logger.log(msg, domain: "API", level: .warn) }
        static func error(_ msg: String) { Logger.log(msg, domain: "API", level: .error) }
    }

    // MARK: - Core

    private enum Level: String {
        case info  = "ℹ️"
        case warn  = "⚠️"
        case error = "❌"
    }

    private static let osLog = Logger.makeOSLog()

    private static func makeOSLog() -> OSLog {
        if Bundle.main.bundleIdentifier != nil {
            return OSLog(subsystem: Bundle.main.bundleIdentifier ?? "app.plink", category: "app")
        }
        return OSLog.default
    }

    private static func log(_ message: String, domain: String, level: Level) {
        let formatted = "[\(domain)] \(level.rawValue) \(message)"

        #if DEBUG
        print(formatted)
        #else
        let type: OSLogType = {
            switch level {
            case .info:  return .info
            case .warn:  return .default
            case .error: return .error
            }
        }()
        os_log("%{public}@", log: osLog, type: type, formatted)
        #endif
    }
}
