import Foundation

/// P1 audit fix: single source of truth for backend endpoints.
/// The production host was hardcoded in 16 files; now every call site
/// resolves through this config. Override for staging/local runs by
/// setting the UserDefaults key "plink.backend_base_url" (DEBUG builds,
/// e.g. via launch argument -plink.backend_base_url http://localhost:3000).
enum PlinkConfig {
    /// Base host, no trailing slash, no /api suffix.
    static var baseURLString: String {
        if let override = UserDefaults.standard.string(forKey: "plink.backend_base_url"),
           !override.isEmpty {
            return override
        }
        return "https://plink-backend-production-ef31.up.railway.app"
    }

    /// REST API base: <host>/api
    static var apiURLString: String { baseURLString + "/api" }

    /// Realtime WebSocket endpoint: wss://<host>/ws
    static var wsURLString: String {
        baseURLString
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://") + "/ws"
    }
}
