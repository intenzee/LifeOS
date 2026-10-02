import Foundation
import Security

final class CalorieSettings {
    static let shared = CalorieSettings()

    private let percentageKey = "caloriePercentage"

    func savePercentage(_ percentage: Double) {
        UserDefaults.standard.set(percentage, forKey: percentageKey)
    }

    func loadPercentage() -> Double {
        let saved = UserDefaults.standard.double(forKey: percentageKey)
        return saved > 0 ? saved : 0.5
    }
}

/// Stores the user's baseline daily calorie target.
///
/// The target has two modes:
/// - **Auto**: derived scientifically from the profile via Mifflin-St Jeor
///   (`CalorieGoalCalculator`). It re-tracks the profile whenever body weight or
///   any other input changes, so logging a new weight moves the target by a
///   predictable amount instead of drifting.
/// - **Manual**: the user typed a custom number; we stop re-deriving it so their
///   override is never silently overwritten.
final class CalorieLimitSettings {
    static let shared = CalorieLimitSettings()

    private let limitKey = "dailyCalorieLimit"
    private let manualKey = "dailyCalorieLimitManual"
    private let defaultLimit = 2200.0

    /// `true` when the user has set a custom target that should not be auto-updated.
    var isManual: Bool {
        UserDefaults.standard.bool(forKey: manualKey)
    }

    /// Persists a target derived from the profile and keeps auto-tracking enabled.
    func saveAutoLimit(_ limit: Double) {
        UserDefaults.standard.set(limit, forKey: limitKey)
        UserDefaults.standard.set(false, forKey: manualKey)
    }

    /// Persists a user-entered custom target and disables auto-tracking.
    func saveManualLimit(_ limit: Double) {
        UserDefaults.standard.set(limit, forKey: limitKey)
        UserDefaults.standard.set(true, forKey: manualKey)
    }

    /// Legacy entry point — treated as an auto (profile-derived) save.
    func saveLimit(_ limit: Double) {
        saveAutoLimit(limit)
    }

    func loadLimit() -> Double {
        let saved = UserDefaults.standard.double(forKey: limitKey)
        return saved > 0 ? saved : defaultLimit
    }

    /// Recomputes the baseline target from the current profile using
    /// Mifflin-St Jeor, unless the user has a manual override. Call this whenever
    /// weight or profile inputs change so the target stays scientifically correct.
    @discardableResult
    func recomputeFromProfileIfAuto() -> Double {
        guard !isManual, let profile = PersistenceManager.shared.loadUserProfile() else {
            return loadLimit()
        }
        let goal = CalorieGoalCalculator.dailyCalorieGoal(profile: profile)
        UserDefaults.standard.set(goal, forKey: limitKey)
        return goal
    }
}

final class SmokingSettings {
    static let shared = SmokingSettings()

    private let smokingKey = "smokingEnabled"

    func saveSmokingEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: smokingKey)
    }

    func loadSmokingEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: smokingKey)
    }
}

/// Securely persists AI meal-scan API keys in the Keychain so the user only
/// enters them once. Keys are stored per provider (e.g. "ChatGPT", "Perplexity").
final class AIKeyStore {
    static let shared = AIKeyStore()

    private let service = "app.lifeos.aiscan.apikey"
    private let instructionsSeenKey = "aiScanInstructionsSeen"

    // MARK: Keychain

    func save(_ key: String, provider: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }

        // Remove any existing value first so we overwrite cleanly.
        delete(provider: provider)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func load(provider: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    func delete(provider: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider
        ]
        SecItemDelete(query as CFDictionary)
    }

    func hasKey(provider: String) -> Bool {
        load(provider: provider) != nil
    }

    // MARK: One-time instructions

    /// Whether the "how to add a ChatGPT key" card has already been dismissed.
    var hasSeenInstructions: Bool {
        get { UserDefaults.standard.bool(forKey: instructionsSeenKey) }
        set { UserDefaults.standard.set(newValue, forKey: instructionsSeenKey) }
    }
}
