//  AuthTokenStore.swift
//  Plink — M39
//
//  Фикс ℗ 9 из аудита: токен хранился под ключом `rave_auth_token`.
//  Имя чужого бренда в Keychain — и репутационный, и юридический риск.
//  Миграция прозрачная: никто не будет разлогинен при обновлении.
//
//  ⚠️ АУДИТ 26.07.2026 — КРИТИЧЕСКИЙ ФИКС (ломал приложение целиком).
//
//  Миграция была РАЗРУШАЮЩЕЙ: она копировала токен в `plink_auth_token`
//  и УДАЛЯЛА `rave_auth_token`. При этом в проекте 42 обращения в 26 файлах
//  читают старый ключ напрямую: `KeychainHelper.read(for: "rave_auth_token")`.
//
//  Сценарий поломки:
//   1. Пользователь входит — AuthService пишет токен в `rave_auth_token`.
//   2. Любой код M39 читает старый ключ напрямую (ClockSync,
//      PushNotificationService, StoreKitManager, ModerationService —
//      всё это стартует при запуске приложения).
//   3. Срабатывает миграция и УДАЛЯЕТ `rave_auth_token`.
//   4. Все 42 старых читателя мгновенно получают nil.
//
//  Что переставало работать: комната (KeychainAuthTokenProvider → нет токена
//  → нет realtime-тикета и медиа: «видео не грузится»), нативное извлечение
//  YouTube, личные сообщения, ИИ, друзья, presence, покупки, админка.
//  Хуже того, `AuthService.init` читает тот же старый ключ — после миграции
//  пользователь выглядел разлогиненным при следующем запуске.
//
//  Решение: ключ теперь ДУБЛИРУЕТСЯ, а не переносится. Оба имени всегда
//  валидны, поэтому старые и новые читатели работают одновременно и правка
//  не требует трогать 26 файлов. Постепенный переход на AuthTokenStore
//  остаётся отдельной задачей по чистоте кода.

import Foundation
import Security

// К токену обращаются и с MainActor (UI, авторизация),
// и из фоновых задач (AIStreamClient, пуши, StoreKit). Без синхронизации это
// была гонка данных по `cached`/`didMigrate` и ошибка Sendable в strict concurrency.
final class AuthTokenStore: @unchecked Sendable {
    static let shared = AuthTokenStore()

    private let service = "app.plink.auth"
    private let account = "plink_auth_token"
    private let legacyAccount = "rave_auth_token"

    private let lock = NSLock()
    private var cached: String?
    private var didMigrate = false

    private init() {}

    var token: String? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        migrateIfNeededLocked()
        // Запасное чтение легаси-ключа: именно его пишет AuthService при входе,
        // поэтому без этого fallback новый ключ пуст до первой миграции.
        cached = read(account: account) ?? read(account: legacyAccount)
        return cached
    }

    func save(_ token: String) {
        lock.lock()
        defer { lock.unlock() }
        cached = token
        write(token, account: account)
        // Оба ключа держим синхронными — 42 места в 26 файлах читают легаси-ключ
        // напрямую через KeychainHelper. Подробности в шапке файла.
        write(token, account: legacyAccount)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
        delete(account: account)
        delete(account: legacyAccount)
    }

    /// Вызывать только под удержанным `lock` — NSLock не рекурсивен.
    ///
    /// Раньше здесь стоял `delete(account: legacyAccount)`,
    /// то есть миграция ПЕРЕНОСИЛА токен и стирала старый ключ. Это ломало
    /// приложение целиком — см. шапку файла. Теперь ключ дублируется, а не
    /// переносится: старые читатели продолжают работать.
    private func migrateIfNeededLocked() {
        guard !didMigrate else { return }
        didMigrate = true
        guard read(account: account) == nil, let legacy = read(account: legacyAccount) else { return }
        write(legacy, account: account)
    }

    private func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String, account: String) {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
