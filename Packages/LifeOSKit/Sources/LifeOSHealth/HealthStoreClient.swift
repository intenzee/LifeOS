import Foundation
import LifeOSCore

// The seam between LifeOS and HealthKit (WCH-01). The ingestion service only
// sees these value types, so it is unit-tested with `FakeHealthStore` and never
// touches `HKHealthStore` in tests. `HKHealthStoreClient` is the live implementation.

/// A workout as LifeOS needs it, mapped from `HKWorkout`.
public struct HealthWorkoutSample: Sendable, Equatable {
    public var uuid: UUID
    public var start: Date
    public var end: Date
    public var kind: ActivityKind
    public var activeEnergyKcal: Double?
    public var distanceMeters: Double?
    public var avgHeartRate: Double?
    public var sourceName: String?
    public var sourceBundleID: String?
    /// Recorded on an Apple Watch (device model "Watch").
    public var recordedByWatch: Bool

    public init(uuid: UUID, start: Date, end: Date, kind: ActivityKind, activeEnergyKcal: Double? = nil,
                distanceMeters: Double? = nil, avgHeartRate: Double? = nil, sourceName: String? = nil,
                sourceBundleID: String? = nil, recordedByWatch: Bool = false) {
        self.uuid = uuid
        self.start = start
        self.end = end
        self.kind = kind
        self.activeEnergyKcal = activeEnergyKcal
        self.distanceMeters = distanceMeters
        self.avgHeartRate = avgHeartRate
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
        self.recordedByWatch = recordedByWatch
    }
}

/// The result of one anchored workout query.
public struct WorkoutChanges: Sendable, Equatable {
    public var added: [HealthWorkoutSample]
    public var deleted: [UUID]
    /// The archived `HKQueryAnchor` to pass next time.
    public var anchor: Data?

    public init(added: [HealthWorkoutSample] = [], deleted: [UUID] = [], anchor: Data? = nil) {
        self.added = added
        self.deleted = deleted
        self.anchor = anchor
    }
}

/// One day of HealthKit statistics (cumulative sums, sources merged by HealthKit).
public struct DailyEnergyStat: Sendable, Equatable {
    public var dayKey: DayKey
    public var activeKcal: Double?
    public var basalKcal: Double?
    /// Active energy from Apple Watch devices only.
    public var watchActiveKcal: Double?
    public var steps: Double?

    public init(dayKey: DayKey, activeKcal: Double? = nil, basalKcal: Double? = nil,
                watchActiveKcal: Double? = nil, steps: Double? = nil) {
        self.dayKey = dayKey
        self.activeKcal = activeKcal
        self.basalKcal = basalKcal
        self.watchActiveKcal = watchActiveKcal
        self.steps = steps
    }
}

/// HealthKit types LifeOS observes for background delivery (WCH-04).
public enum ObservedHealthType: String, Sendable, CaseIterable {
    case workouts, activeEnergy, basalEnergy, steps
}

public protocol HealthStoreClient: Sendable {
    /// `false` on iPad and Macs without Health.
    var isAvailable: Bool { get }

    /// Asks for read access to workouts and energy, and the given write types.
    func requestAuthorization() async throws

    /// Workouts added and deleted since `anchor`, excluding LifeOS's own writes.
    /// With no anchor, returns workouts that started on or after `initialStart`.
    func workoutChanges(since anchor: Data?, initialStart: Date) async throws -> WorkoutChanges

    /// Statistics for each day in `days`, in the given time zone.
    func dailyEnergy(for days: [DayKey], timeZone: TimeZone) async throws -> [DailyEnergyStat]

    /// Registers observer queries and enables background delivery. `onUpdate`
    /// runs for each wake; the client calls HealthKit's completion handler after
    /// it returns, or after 25 s at the latest.
    func startObserving(_ onUpdate: @escaping @Sendable (ObservedHealthType) async -> Void) async
}
