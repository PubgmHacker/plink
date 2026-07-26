//  AuthTokenStore.swift
//  Plink — M39
//
//  Фикс ℗ 9 из аудита: токен хранился под ключом `rave_auth_token`.
//  Имя чужого бренда в Keychain — и репутационный, и юридический риск.
//  Миграция прозрачная: никто не будет разлогинен при обновлении.

import Foundation
import Security

final class AuthTokenStore {
    static let shared = AuthTokenStore()

    private let service = "app.plink.auth"
    private let account = "plink_auth_token"
    private let legacyAccount = "rave_auth_token"

    private var cached: String?
    private var didMigrate = false

    private init() {}

    var token: String? {
        if let cached { return cached }
        migrateIfNeeded()
        cached = read(account: account)
        return cached
    }

    func save(_ token: String) {
        cached = token
        write(token, account: account)
    }

    func clear() {
        cached = nil
        delete(account: account)
        delete(account: legacyAccount)
    }

    private func migrateIfNeeded() {
        guard !didMigrate else { return }
        didMigrate = true
        guard read(account: account) == nil, let legacy = read(account: legacyAccount) else { return }
        write(legacy, account: account)
        delete(account: legacyAccount)
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
