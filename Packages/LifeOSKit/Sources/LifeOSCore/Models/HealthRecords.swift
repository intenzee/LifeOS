import Foundation

// Phase 1 records (doc 02 §3.1, doc 03 §3.3): workouts imported from Apple Health
// and the per-day energy totals the calorie budget is built from.

/// Broad workout category. Maps from `HKWorkoutActivityType` in LifeOSHealth.
public enum ActivityKind: String, Codable, Sendable, CaseIterable {
    case strength, run, walk, cycle, hiit, yoga, swim, other

    /// Activities whose Watch workout can absorb a manual LifeOS gym log (WCH-06).
    public var mergesWithGymLog: Bool {
        self == .strength || self == .hiit
    }

    public var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .run: return "Run"
        case .walk: return "Walk"
        case .cycle: return "Cycle"
        case .hiit: return "HIIT"
        case .yoga: return "Yoga"
        case .swim: return "Swim"
        case .other: return "Workout"
        }
    }
}

/// One workout session: an Apple Health workout, or a LifeOS gym log that a
/// Watch workout was merged into (doc 02 §3.3).
public struct WorkoutSession: DayRecord, Equatable, Hashable {
    public static let collection = "workoutSessions"

    public let id: UUID
    /// `dayKey` of the **start** time (a run past midnight belongs to the day it began).
    public var dayKey: DayKey
    public var start: Date
    public var end: Date
    public var kind: ActivityKind
    /// Measured active energy from the workout record, if any.
    public var activeEnergyKcal: Double?
    public var distanceMeters: Double?
    public var avgHeartRate: Double?
    /// `.watch` (Apple Watch), `.healthKit` (another app or iPhone), or `.manual`.
    public var source: EntrySource
    /// The recording app or device as Health shows it ("Workout", "Strava").
    public var sourceName: String?
    public var sourceBundleID: String?
    /// `HKWorkout.uuid`, the dedupe key. `nil` for LifeOS-only sessions.
    public var healthKitUUID: UUID?
    /// The `WorkoutDay` exercises this session absorbed, if a manual log was merged in.
    public var mergedExerciseIDs: [UUID]

    public init(id: UUID = UUID(), dayKey: DayKey, start: Date, end: Date, kind: ActivityKind,
                activeEnergyKcal: Double? = nil, distanceMeters: Double? = nil, avgHeartRate: Double? = nil,
                source: EntrySource, sourceName: String? = nil, sourceBundleID: String? = nil,
                healthKitUUID: UUID? = nil, mergedExerciseIDs: [UUID] = []) {
        self.id = id
        self.dayKey = dayKey
        self.start = start
        self.end = end
        self.kind = kind
        self.activeEnergyKcal = activeEnergyKcal
        self.distanceMeters = distanceMeters
        self.avgHeartRate = avgHeartRate
        self.source = source
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
        self.healthKitUUID = healthKitUUID
        self.mergedExerciseIDs = mergedExerciseIDs
    }

    public var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }

    /// Badge text for the Train feed (WCH-09).
    public var sourceBadge: String {
        switch source {
        case .watch: return "Apple Watch"
        case .healthKit: return sourceName ?? "Apple Health"
        case .manual: return "Estimated"
        default: return sourceName ?? "LifeOS"
        }
    }
}

/// One day's energy (doc 01 §4.2, doc 03 §3.3). Energy comes from HealthKit
/// statistics, which de-duplicate overlapping iPhone and Watch samples. Workouts
/// are never summed for energy.
public struct EnergyDay: DayRecord, Equatable {
    public static let collection = "energy"

    public var id: DayKey { dayKey }
    public var dayKey: DayKey
    /// All-day active energy, all sources merged. `nil` = no HealthKit data.
    public var activeKcal: Double?
    public var basalKcal: Double?
    /// Active energy recorded by an Apple Watch. Drives the measured-mode check.
    public var watchActiveKcal: Double?
    public var steps: Double?
    /// The day had at least one workout session (CAL-04 excludes these days).
    public var hadWorkout: Bool
    /// MET estimate of LifeOS-only sessions that day (estimated mode).
    public var estimatedSessionKcal: Double

    /// The budget, written only by `BudgetService` (CAL-02). Every consumer reads this.
    public var budgetKcal: Double?
    public var budgetMode: BudgetMode?
    public var formulaVersion: Int?
    /// Set once a past day's budget is final (doc 03 §3.3).
    public var frozenAt: Date?
    /// Late HealthKit data may unfreeze a day once.
    public var unfrozenOnce: Bool
    public var lastSyncedAt: Date?

    public init(dayKey: DayKey, activeKcal: Double? = nil, basalKcal: Double? = nil, watchActiveKcal: Double? = nil,
                steps: Double? = nil, hadWorkout: Bool = false, estimatedSessionKcal: Double = 0,
                budgetKcal: Double? = nil, budgetMode: BudgetMode? = nil, formulaVersion: Int? = nil,
                frozenAt: Date? = nil, unfrozenOnce: Bool = false, lastSyncedAt: Date? = nil) {
        self.dayKey = dayKey
        self.activeKcal = activeKcal
        self.basalKcal = basalKcal
        self.watchActiveKcal = watchActiveKcal
        self.steps = steps
        self.hadWorkout = hadWorkout
        self.estimatedSessionKcal = estimatedSessionKcal
        self.budgetKcal = budgetKcal
        self.budgetMode = budgetMode
        self.formulaVersion = formulaVersion
        self.frozenAt = frozenAt
        self.unfrozenOnce = unfrozenOnce
        self.lastSyncedAt = lastSyncedAt
    }

    public var isFrozen: Bool { frozenAt != nil }

    /// The day has Watch-measured activity (measured-mode eligibility, doc 03 §3.1).
    public var hasWatchEnergy: Bool { (watchActiveKcal ?? 0) > 0 }
}
