import Foundation

/// Every user-visible P1+ feature ships behind one of these (FND-22).
/// Raw values are the keys used by remote config (doc 07, BE-08).
public enum FeatureFlag: String, CaseIterable, Sendable {
    /// HealthKit anchored workout/energy ingestion (doc 02, P1). A kill switch:
    /// off = no Health import, and the budget falls back to the MET estimate.
    case healthKitIngestion = "healthkit_ingestion"
    /// Save LifeOS-only strength sessions to Apple Health as real `HKWorkout`s
    /// (WCH-07, optional). Bare estimated energy samples are never written.
    case healthKitWorkoutWrite = "healthkit_workout_write"
    /// Typed phone ↔ watch messages (FND-11). A kill switch: on by default.
    /// Off = the phone sends only legacy v1 dictionaries.
    case typedWatchContract = "typed_watch_contract"

    public var defaultValue: Bool {
        switch self {
        case .typedWatchContract, .healthKitIngestion: return true
        case .healthKitWorkoutWrite: return false
        }
    }
}

/// Resolves a flag: local override (debug menu) → remote value → default.
/// Thread-safe. Read it from anywhere.
public final class FeatureFlags: @unchecked Sendable {
    public static let shared = FeatureFlags()

    private let lock = NSLock()
    private var remote: [String: Bool] = [:]
    private var local: [String: Bool] = [:]

    public init(remote: [String: Bool] = [:], local: [String: Bool] = [:]) {
        self.remote = remote
        self.local = local
    }

    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        lock.withLock {
            local[flag.rawValue] ?? remote[flag.rawValue] ?? flag.defaultValue
        }
    }

    /// Replaces all remote values, e.g. after fetching the config endpoint.
    /// Unknown keys are ignored, so the backend can add flags first.
    public func applyRemote(_ values: [String: Bool]) {
        let known = Set(FeatureFlag.allCases.map(\.rawValue))
        lock.withLock { remote = values.filter { known.contains($0.key) } }
    }

    /// Debug-menu override. Pass `nil` to clear it.
    public func setLocalOverride(_ flag: FeatureFlag, _ value: Bool?) {
        lock.withLock { local[flag.rawValue] = value }
    }
}
