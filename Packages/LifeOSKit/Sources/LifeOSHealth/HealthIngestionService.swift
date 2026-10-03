import Foundation
import LifeOSCore
import LifeOSData

/// What started a sync (WCH-05). Logged, and used to size the energy window.
public enum SyncTrigger: String, Sendable {
    case launch, foreground, observer, backgroundRefresh, pullToRefresh, watchWorkoutEnded, manual
}

public struct SyncReport: Sendable, Equatable {
    public var trigger: SyncTrigger
    public var workoutsAdded: Int
    public var workoutsDeleted: Int
    /// Days whose sessions or energy changed.
    public var touchedDays: Set<DayKey>
    /// Workouts first seen in this pass (the "Workout synced" moment, WCH-10).
    public var newWorkouts: [WorkoutSession]
    public var finishedAt: Date
}

/// Pulls Apple Health workouts and energy into the store (WCH-01/02/03/05).
///
/// - Workouts: an anchored query. New ones are upserted by `healthKitUUID`,
///   deleted ones removed. LifeOS's own writes are excluded by the client.
/// - Energy: daily statistics (HealthKit merges iPhone and Watch samples) for
///   every day a workout touched plus the recent window.
/// - The anchor is saved only after the store writes succeed, so a crash
///   re-delivers the same changes, which upsert idempotently.
/// - Concurrent requests coalesce: callers during a run share it, and one
///   follow-up run covers anything that arrived meanwhile.
public actor HealthIngestionService {
    public static let workoutsAnchorKey = "workouts"
    /// History pulled on the first sync (and the allowance window, CAL-04).
    public static let initialHistoryDays = 28
    /// Days re-read on every sync: late Watch data mostly lands within a day.
    public static let recentDays = 2

    private let client: any HealthStoreClient
    private let database: LifeOSDatabase
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date

    private var current: Task<SyncReport, Error>?
    private var queued: Task<SyncReport, Error>?
    public private(set) var lastReport: SyncReport?

    public init(client: any HealthStoreClient, database: LifeOSDatabase, timeZone: TimeZone = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.database = database
        self.timeZone = timeZone
        self.now = now
    }

    /// Syncs workouts and energy. Safe to call from any trigger, any number of times.
    @discardableResult
    public func syncAll(trigger: SyncTrigger) async throws -> SyncReport {
        guard client.isAvailable else {
            return SyncReport(trigger: trigger, workoutsAdded: 0, workoutsDeleted: 0, touchedDays: [],
                              newWorkouts: [], finishedAt: now())
        }
        // Everyone arriving during a run shares one follow-up run.
        if let queued { return try await queued.value }
        if let current {
            let next = Task { () async throws -> SyncReport in
                _ = try? await current.value
                return try await self.runQueued(trigger)
            }
            queued = next
            return try await next.value
        }
        return try await run(trigger)
    }

    private func runQueued(_ trigger: SyncTrigger) async throws -> SyncReport {
        queued = nil
        return try await run(trigger)
    }

    private func run(_ trigger: SyncTrigger) async throws -> SyncReport {
        let task = Task { try await self.performSync(trigger) }
        current = task
        defer { if current == task { current = nil } }
        let report = try await task.value
        lastReport = report
        return report
    }

    // MARK: Sync pass

    private func performSync(_ trigger: SyncTrigger) async throws -> SyncReport {
        var state = try await database.healthSync.load()
        let today = DayKey.today(now: now(), timeZone: timeZone)
        let firstSync = state.lastCompletedSync == nil

        let changes = try await client.workoutChanges(
            since: state.anchors[Self.workoutsAnchorKey],
            initialStart: today.adding(days: -Self.initialHistoryDays).startDate(timeZone: timeZone))
        let workouts = try await applyWorkouts(changes, state: &state)
        var touched = workouts.touched

        let windowStart: DayKey
        if firstSync {
            windowStart = today.adding(days: -Self.initialHistoryDays)
        } else {
            let lastDay = DayKey.make(for: state.lastCompletedSync ?? now(), timeZone: timeZone)
            windowStart = max(min(lastDay, today.adding(days: -Self.recentDays)),
                              today.adding(days: -Self.initialHistoryDays))
        }
        let syncedAt = now()
        let energyDays = Set(DayKey.range(from: windowStart, through: today)).union(touched.filter { $0 <= today })
        touched.formUnion(try await applyEnergy(for: energyDays, syncedAt: syncedAt))

        // Bookkeeping last, so a failure above re-delivers the same changes next time.
        state.anchors[Self.workoutsAnchorKey] = changes.anchor ?? state.anchors[Self.workoutsAnchorKey]
        state.lastCompletedSync = syncedAt
        try await database.healthSync.save(state)

        let report = SyncReport(trigger: trigger, workoutsAdded: changes.added.count,
                                workoutsDeleted: changes.deleted.count, touchedDays: touched,
                                newWorkouts: workouts.new.sorted { $0.start < $1.start }, finishedAt: syncedAt)
        let (added, removed, days) = (report.workoutsAdded, report.workoutsDeleted, touched.count)
        Log.health.info("Health sync (\(trigger.rawValue, privacy: .public)): +\(added) −\(removed) workouts, \(days) days")
        return report
    }

    /// Upserts added workouts and removes deleted ones, day by day. Returns the
    /// days that changed and the workouts seen for the first time.
    private func applyWorkouts(_ changes: WorkoutChanges,
                               state: inout HealthSyncState) async throws -> (touched: Set<DayKey>, new: [WorkoutSession]) {
        var touched = Set<DayKey>()
        var newWorkouts: [WorkoutSession] = []
        var byDay: [DayKey: [WorkoutSession]] = [:]
        for sample in changes.added {
            let session = Self.session(from: sample, timeZone: timeZone)
            if let previous = state.workoutDays[sample.uuid] {
                // An edit can move a workout to another day: drop it from the old one.
                if previous != session.dayKey { touched.insert(previous) }
            } else {
                newWorkouts.append(session)
            }
            byDay[session.dayKey, default: []].append(session)
            touched.insert(session.dayKey)
        }
        let deleted = Set(changes.deleted)
        touched.formUnion(deleted.compactMap { state.workoutDays[$0] })

        let replaced = deleted.union(changes.added.map(\.uuid))
        for day in touched.sorted() {
            let kept = try await database.workoutSessions.sessions(on: day).filter { existing in
                existing.healthKitUUID.map { !replaced.contains($0) } ?? true
            }
            try await database.workoutSessions.replaceSessions(on: day, with: kept + (byDay[day] ?? []))
        }
        for uuid in deleted { state.workoutDays[uuid] = nil }
        for session in byDay.values.joined() {
            if let uuid = session.healthKitUUID { state.workoutDays[uuid] = session.dayKey }
        }
        return (touched, newWorkouts)
    }

    /// Writes HealthKit statistics into `EnergyDay`s. Returns days whose energy changed.
    private func applyEnergy(for days: Set<DayKey>, syncedAt: Date) async throws -> Set<DayKey> {
        var changed = Set<DayKey>()
        let stats = try await client.dailyEnergy(for: days.sorted(), timeZone: timeZone)
        for stat in stats {
            let before = try await database.energy.day(stat.dayKey)
            try await database.energy.update(stat.dayKey) { day in
                Self.apply(stat, to: &day, syncedAt: syncedAt)
            }
            if before?.activeKcal != stat.activeKcal || before?.watchActiveKcal != stat.watchActiveKcal {
                changed.insert(stat.dayKey)
            }
        }
        return changed
    }

    // MARK: Mapping

    static func session(from sample: HealthWorkoutSample, timeZone: TimeZone) -> WorkoutSession {
        WorkoutSession(id: StableID.make("hk-workout", sample.uuid.uuidString),
                       dayKey: DayKey.make(for: sample.start, timeZone: timeZone),
                       start: sample.start, end: max(sample.end, sample.start), kind: sample.kind,
                       activeEnergyKcal: sample.activeEnergyKcal, distanceMeters: sample.distanceMeters,
                       avgHeartRate: sample.avgHeartRate, source: sample.recordedByWatch ? .watch : .healthKit,
                       sourceName: sample.sourceName, sourceBundleID: sample.sourceBundleID,
                       healthKitUUID: sample.uuid)
    }

    /// Writes HealthKit fields only. A frozen day takes late data once
    /// (doc 03 §3.3): it unfreezes so `BudgetService` recomputes it, then stays put.
    static func apply(_ stat: DailyEnergyStat, to day: inout EnergyDay, syncedAt: Date) {
        let changed = day.activeKcal != stat.activeKcal || day.watchActiveKcal != stat.watchActiveKcal
        day.activeKcal = stat.activeKcal
        day.basalKcal = stat.basalKcal
        day.watchActiveKcal = stat.watchActiveKcal
        day.steps = stat.steps
        day.lastSyncedAt = syncedAt
        if changed, day.isFrozen, !day.unfrozenOnce {
            day.frozenAt = nil
            day.unfrozenOnce = true
            let key = day.dayKey.rawValue
            Log.health.notice("Late Health data unfroze \(key, privacy: .public)")
        }
    }
}
