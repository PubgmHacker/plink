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
