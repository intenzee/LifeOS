import Foundation
import Security

/// Supplies BYOK API keys to T3 providers. Keys are never compiled into the
/// binary, never logged, and never leave the Keychain except in the request.
nonisolated protocol AICredentialProviding: Sendable {
    func apiKey(for provider: ProviderID) -> String?
}

/// Keychain-backed keys, readable by the gateway (F01 §7).
///
/// Uses the same service/account layout as the app's existing `AIKeyStore`
/// (`app.lifeos.aiscan.apikey` / "Groq"), so keys users already saved keep
/// working with no migration. Items are `AfterFirstUnlockThisDeviceOnly`: not in
/// backups, not synced, readable by background tasks after first unlock.
nonisolated struct KeychainCredentialStore: AICredentialProviding {
    static let service = "app.lifeos.aiscan.apikey"

    static func account(for provider: ProviderID) -> String? {
        switch provider {
        case .groqBYOK: "Groq"
        case .geminiBYOK: "Gemini"
        default: nil
        }
    }

    func apiKey(for provider: ProviderID) -> String? {
        guard let account = Self.account(for: provider) else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    @discardableResult
    func save(_ key: String, for provider: ProviderID) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let account = Self.account(for: provider), !trimmed.isEmpty else { return false }
        delete(provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(trimmed.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func delete(_ provider: ProviderID) {
        guard let account = Self.account(for: provider) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Fixed keys — tests, previews, and the `ai-eval` CLI (reads env vars).
nonisolated struct StaticCredentials: AICredentialProviding {
    var keys: [ProviderID: String]

    init(_ keys: [ProviderID: String] = [:]) { self.keys = keys }

    func apiKey(for provider: ProviderID) -> String? {
        guard let key = keys[provider]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        return key
    }

    /// `GROQ_API_KEY`, `GEMINI_API_KEY`.
    static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> StaticCredentials {
        var keys: [ProviderID: String] = [:]
        if let groq = env["GROQ_API_KEY"] { keys[.groqBYOK] = groq }
        if let gemini = env["GEMINI_API_KEY"] ?? env["GOOGLE_API_KEY"] { keys[.geminiBYOK] = gemini }
        return StaticCredentials(keys)
    }
}
