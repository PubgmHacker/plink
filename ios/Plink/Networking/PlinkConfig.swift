import Foundation

/// P1 audit fix: single source of truth for backend endpoints.
/// The production host was hardcoded in 16 files; now every call site
/// resolves through this config. Override for staging/local runs by
/// setting the UserDefaults key "plink.backend_base_url" (DEBUG builds,
/// e.g. via launch argument -plink.backend_base_url http://localhost:3000).
enum PlinkConfig {
    /// Base host, no trailing slash, no /api suffix.
    static var baseURLString: String {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "plink.backend_base_url"),
           !override.isEmpty {
            return override
        }
        if ProcessInfo.processInfo.arguments.contains("-plink.uitest") {
            return "http://localhost:8080"
        }
        #endif
        return "https://plink-production.up.railway.app"
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

// MARK: - APIConfig

/// FIX (аудит 26.07.2026): семь вызовов в пяти файлах ссылались на
/// `APIConfig.baseURL` (AccountDeletionView, ClockSync, PushNotificationService,
/// StoreKitManager, AIStreamClient), но самого типа в проекте не было —
/// «Cannot find 'APIConfig' in scope».
///
/// Живёт именно здесь, а не в отдельном файле, потому что Plink.xcodeproj
/// лежит в репозитории и перечисляет файлы явно: новый .swift не попадает
/// в таргет без перегенерации через XcodeGen. PlinkConfig.swift уже в таргете,
/// поэтому фикс работает сразу, без правки проектного файла.
///
/// Это не вторая конфигурация, а тонкий алиас к PlinkConfig.
enum APIConfig {
    /// Хост без завершающего слэша и без суффикса /api.
    /// Вызовы вида `APIConfig.baseURL + "/api/..."` остаются корректными.
    static var baseURL: String { PlinkConfig.baseURLString }

    /// REST-база: <host>/api
    static var apiURL: String { PlinkConfig.apiURLString }

    /// Realtime WebSocket: wss://<host>/ws
    static var wsURL: String { PlinkConfig.wsURLString }
}

// MARK: - App Store compliance

/// App Review 3.1.1 guard, decided at COMPILE time.
///
/// Plink+ is sold on the website (YooKassa, `webpay.ts`). Guideline 3.1.1
/// forbids an App Store build from sending the user out to that web purchase
/// from inside the app. This constant is the primary lock, and it is `true` by
/// default on purpose: the shipped binary is compliant unless someone
/// deliberately builds a non-App-Store distribution and flips it here. Because
/// the default is compliant, a missing or stale `/api/webpay/status` response
/// can never re-enable the external purchase link — the build itself has
/// already said "no".
///
/// The server flag (`/api/webpay/status` → `appStoreCompliant`, default `true`)
/// is a second, remote lock: it can force compliance even on a non-App-Store
/// build, but it cannot loosen this one. The external web-purchase path is
/// therefore shown only when BOTH locks are open — a deliberate double opt-in.
///
/// Native StoreKit 2 (see `StoreManager`) is the eventual in-app purchase path;
/// until App Store products are configured, the compliant build simply presents
/// Plink+ and lets an existing subscriber restore their entitlement.
enum PlinkCompliance {
    /// `true` → App Store build: never surface the external web-purchase link.
    static let appStoreCompliant = true
}
