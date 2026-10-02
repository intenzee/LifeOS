import Foundation

/// Every pre-P0 user-data value from UserDefaults, captured in one pass.
///
/// It is also the backup format: the migrator writes it verbatim to
/// `backups/legacy-<timestamp>.json` before touching anything. Preferences
/// (theme, reminder toggles, calorie limit, eat-back %) stay in UserDefaults
/// and aren't part of it.
public struct LegacySnapshot: Codable, Sendable, Equatable {
    /// UserDefaults keys that hold JSON-encoded blobs.
    public static let blobKeys = [
        "allDailyFoodLogs", "allDailyWorkouts", "weekTodoList", "weekGymLog", "weekFoodLog",
        "dailySummaries", "userProfile", "recentFoods", "favoriteFoods", "customFoods"
    ]
    public static let waterKeyPrefix = "waterCount_"
    public static let weightHistoryKey = "weightHistory"

    public var capturedAt: Date
    /// Raw JSON blobs by UserDefaults key.
    public var blobs: [String: Data]
    /// `waterCount_<yyyy-MM-dd>` values, keyed by the date part.
    public var waterCounts: [String: Int]
    /// `weightHistory`: `yyyy-MM-dd` → kg.
    public var weightHistory: [String: Double]

    public init(capturedAt: Date = Date(), blobs: [String: Data] = [:],
                waterCounts: [String: Int] = [:], weightHistory: [String: Double] = [:]) {
        self.capturedAt = capturedAt
        self.blobs = blobs
        self.waterCounts = waterCounts
        self.weightHistory = weightHistory
    }

    public var isEmpty: Bool {
        blobs.isEmpty && waterCounts.isEmpty && weightHistory.isEmpty
    }

    /// Reads the legacy keys. Call it on the main thread before handing off:
    /// UserDefaults is fast for this, and the snapshot itself is `Sendable`.
    public static func capture(from defaults: UserDefaults, now: Date = Date()) -> LegacySnapshot {
        var snapshot = LegacySnapshot(capturedAt: now)
        for key in blobKeys {
            if let data = defaults.data(forKey: key) { snapshot.blobs[key] = data }
        }
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(waterKeyPrefix) {
            if let count = value as? Int {
                snapshot.waterCounts[String(key.dropFirst(waterKeyPrefix.count))] = count
            }
        }
        if let history = defaults.dictionary(forKey: weightHistoryKey) {
            for (key, value) in history {
                if let kg = value as? Double { snapshot.weightHistory[key] = kg }
            }
        }
        return snapshot
    }
}
