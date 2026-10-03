import Foundation
import Testing
import LifeOSCore
import LifeOSData
@testable import LifeOSHealth

private let utc = TimeZone(identifier: "UTC")!
private let oct3 = DayKey("2026-10-03")!
private let noon = oct3.startDate(timeZone: utc).addingTimeInterval(12 * 3600)

/// An in-memory HealthKit stand-in. Workouts are versioned so anchors behave
/// like `HKQueryAnchor`: each query returns only what changed since.
final class FakeHealthStore: HealthStoreClient, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [(version: Int, change: Change)] = []
    private var version = 0
    private var energy: [DayKey: DailyEnergyStat] = [:]
    private(set) var workoutQueries = 0
    var available = true
    /// Makes `workoutChanges` slow, to test coalescing.
    var queryDelay: Duration = .zero
    var failNextQuery = false

    enum Change { case add(HealthWorkoutSample), delete(UUID) }

    var isAvailable: Bool { available }

    func add(_ sample: HealthWorkoutSample) { lock.withLock { version += 1; log.append((version, .add(sample))) } }
    func delete(_ uuid: UUID) { lock.withLock { version += 1; log.append((version, .delete(uuid))) } }
    func setEnergy(_ stat: DailyEnergyStat) { lock.withLock { energy[stat.dayKey] = stat } }

    func requestAuthorization() async throws {}

    func workoutChanges(since anchor: Data?, initialStart: Date) async throws -> WorkoutChanges {
        if queryDelay > .zero { try await Task.sleep(for: queryDelay) }
        return try lock.withLock {
            workoutQueries += 1
            if failNextQuery { failNextQuery = false; throw CocoaError(.fileReadUnknown) }
            let since = anchor.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
            var added: [UUID: HealthWorkoutSample] = [:]
            var deleted: [UUID] = []
            for entry in log where entry.version > since {
                switch entry.change {
                case .add(let sample):
                    if anchor != nil || sample.start >= initialStart { added[sample.uuid] = sample }
                case .delete(let uuid):
                    added[uuid] = nil
                    deleted.append(uuid)
                }
            }
            return WorkoutChanges(added: added.values.sorted { $0.start < $1.start }, deleted: deleted,
                                  anchor: Data(String(version).utf8))
        }
    }

    func dailyEnergy(for days: [DayKey], timeZone: TimeZone) async throws -> [DailyEnergyStat] {
        lock.withLock { days.compactMap { energy[$0] } }
    }

    func startObserving(_ onUpdate: @escaping @Sendable (ObservedHealthType) async -> Void) async {}
}

private func workout(_ day: DayKey, hour: Double, kind: ActivityKind = .run, kcal: Double = 300,
                     watch: Bool = true, uuid: UUID = UUID()) -> HealthWorkoutSample {
    let start = day.startDate(timeZone: utc).addingTimeInterval(hour * 3600)
    return HealthWorkoutSample(uuid: uuid, start: start, end: start.addingTimeInterval(1800), kind: kind,
                               activeEnergyKcal: kcal, sourceName: watch ? "Workout" : "Strava",
                               sourceBundleID: watch ? "com.apple.health" : "com.strava", recordedByWatch: watch)
}

private func makeService(_ fake: FakeHealthStore, _ db: LifeOSDatabase, now: Date = noon) -> HealthIngestionService {
    HealthIngestionService(client: fake, database: db, timeZone: utc, now: { now })
}

@Suite("HealthIngestionService (WCH-01/02/03/05)")
struct HealthIngestionTests {
    @Test func importsWorkoutsAndEnergy() async throws {
        let fake = FakeHealthStore(), db = LifeOSDatabase.inMemory()
        let run = workout(oct3, hour: 7)
        fake.add(run)
        fake.add(workout(oct3, hour: 18, kind: .cycle, kcal: 200, watch: false))
        fake.setEnergy(DailyEnergyStat(dayKey: oct3, activeKcal: 780, basalKcal: 1700, watchActiveKcal: 700, steps: 9000))

        let report = try await makeService(fake, db).syncAll(trigger: .launch)
        #expect(report.workoutsAdded == 2)
        #expect(report.newWorkouts.count == 2)
        #expect(report.touchedDays.contains(oct3))

        let sessions = try await db.workoutSessions.sessions(on: oct3)
        #expect(sessions.map(\.kind) == [.run, .cycle])
        #expect(sessions[0].source == .watch)
        #expect(sessions[0].sourceBadge == "Apple Watch")
        #expect(sessions[1].source == .healthKit)
        #expect(sessions[1].sourceBadge == "Strava")
        #expect(sessions[0].healthKitUUID == run.uuid)

        let energy = try #require(try await db.energy.day(oct3))
        #expect(energy.activeKcal == 780)
        #expect(energy.watchActiveKcal == 700)
        #expect(energy.basalKcal == 1700)
        #expect(energy.lastSyncedAt == noon)
        #expect(try await db.healthSync.load().lastCompletedSync == noon)
    }

    @Test func secondSyncOnlyAppliesTheDelta() async throws {
        let fake = FakeHealthStore(), db = LifeOSDatabase.inMemory()
        let service = makeService(fake, db)
        let first = workout(oct3, hour: 7)
        fake.add(first)
        try await service.syncAll(trigger: .launch)

        let report = try await service.syncAll(trigger: .foreground)
        #expect(report.workoutsAdded == 0)
        #expect(report.newWorkouts.isEmpty)
        #expect(try await db.workoutSessions.sessions(on: oct3).count == 1)
    }

    @Test func deletionInHealthRemovesTheSession() async throws {
        let fake = FakeHealthStore(), db = LifeOSDatabase.inMemory()
        let service = makeService(fake, db)
        let keep = workout(oct3, hour: 7), drop = workout(oct3.adding(days: -1), hour: 9)
        fake.add(keep)
        fake.add(drop)
        try await service.syncAll(trigger: .launch)
        #expect(try await db.workoutSessions.sessions(on: drop.start.dayKey).count == 1)

        fake.delete(drop.uuid)
        let report = try await service.syncAll(trigger: .observer)
        #expect(report.workoutsDeleted == 1)
        #expect(report.touchedDays.contains(oct3.adding(days: -1)))
        #expect(try await db.workoutSessions.sessions(on: oct3.adding(days: -1)).isEmpty)
        #expect(try await db.workoutSessions.sessions(on: oct3).count == 1)
        #expect(try await db.healthSync.load().workoutDays[drop.uuid] == nil)
    }

    @Test func editedWorkoutMovingDaysLeavesNoDuplicate() async throws {
        let fake = FakeHealthStore(), db = LifeOSDatabase.inMemory()
        let service = makeService(fake, db)
        let id = UUID()
        fake.add(workout(oct3.adding(days: -1), hour: 23, uuid: id))
        try await service.syncAll(trigger: .launch)
        fake.add(workout(oct3, hour: 1, uuid: id)) // same workout, corrected start
        try await service.syncAll(trigger: .observer)
        #expect(try await db.workoutSessions.sessions(on: oct3.adding(days: -1)).isEmpty)
        #expect(try await db.workoutSessions.sessions(on: oct3).count == 1)
    }

    @Test func workoutAcrossMidnightBelongsToItsStartDay() async throws {
        let fake = FakeHealthStore(), db = LifeOSDatabase.inMemory()
        fake.add(workout(oct3.adding(days: -1), hour: 23.75))
        try await makeService(fake, db).syncAll(trigger: .launch)
        #expect(try await db.workoutSessions.sessions(on: oct3.adding(days: -1)).count == 1)
        #expect(try await db.workoutSessions.sessions(on: oct3).isEmpty)
    }

    @Test func firstSyncLimitsHistoryToTheInitialWindow() async throws {
        let fake = FakeHealthStore(), db = LifeOSDatabase.inMemory()
        fake.add(workout(oct3.adding(days: -60), hour: 7))
        fake.add(workout(oct3.adding(days: -10), hour: 7))
        let report = try await makeService(fake, db).syncAll(trigger: .launch)
        #expect(report.workoutsAdded == 1)
    }

    @Test func failedSyncKeepsTheOldAnchorSoNothingIsLost() async throws {
        let fake = FakeHealthStore(), db = LifeOSDatabase.inMemory()
        let service = makeService(fake, db)
        try await service.syncAll(trigger: .launch)
        fake.add(workout(oct3, hour: 7))
        fake.failNextQuery = true
        await #expect(throws: (any Error).self) { try await service.syncAll(trigger: .observer) }
        let report = try await service.syncAll(trigger: .foreground)
        #expect(report.workoutsAdded == 1)
    }

    @Test func concurrentTriggersCoalesce() async throws {
        let fake = FakeHealthStore(), db = LifeOSDatabase.inMemory()
        fake.queryDelay = .milliseconds(100)
        let service = makeService(fake, db)
        try await withThrowingTaskGroup(of: SyncReport.self) { group in
            for trigger in [SyncTrigger.launch, .foreground, .observer, .pullToRefresh, .watchWorkoutEnded] {
                group.addTask { try await service.syncAll(trigger: trigger) }
                try await Task.sleep(for: .milliseconds(5))
            }
            for try await _ in group {}
        }
        // One run, plus at most one shared follow-up run.
        #expect(fake.workoutQueries <= 2)
        #expect(fake.workoutQueries >= 1)
    }

    @Test func unavailableHealthIsANoOp() async throws {
        let fake = FakeHealthStore(), db = LifeOSDatabase.inMemory()
        fake.available = false
        let report = try await makeService(fake, db).syncAll(trigger: .launch)
        #expect(report.touchedDays.isEmpty)
        #expect(fake.workoutQueries == 0)
    }

    @Test func lateDataUnfreezesADayOnlyOnce() {
        var day = EnergyDay(dayKey: oct3, activeKcal: 500, frozenAt: noon)
        HealthIngestionService.apply(DailyEnergyStat(dayKey: oct3, activeKcal: 600), to: &day, syncedAt: noon)
        #expect(!day.isFrozen)
        #expect(day.unfrozenOnce)
        day.frozenAt = noon
        HealthIngestionService.apply(DailyEnergyStat(dayKey: oct3, activeKcal: 650), to: &day, syncedAt: noon)
        #expect(day.isFrozen)
        #expect(day.activeKcal == 650) // the data is kept, the budget stays frozen
    }

    @Test func ingestionFeedsTheBudgetEndToEnd() async throws {
        let fake = FakeHealthStore(), db = LifeOSDatabase.inMemory()
        try await db.profile.save(UserProfile(age: 30, heightCm: 180, currentWeightKg: 80, targetWeightKg: 75, sex: .male))
        for offset in 0..<3 {
            fake.setEnergy(DailyEnergyStat(dayKey: oct3.adding(days: -offset), activeKcal: 780, watchActiveKcal: 700))
        }
        let budget = BudgetService(database: db, debounce: .milliseconds(5), timeZone: utc, now: { noon })
        await budget.start()
        try await makeService(fake, db).syncAll(trigger: .launch)
        try await Task.sleep(for: .milliseconds(100))
        await budget.flush()
        #expect(try await db.energy.day(oct3)?.budgetKcal == 1798) // doc 03 persona A
        await budget.stop()
    }
}

private extension Date {
    var dayKey: DayKey { DayKey.make(for: self, timeZone: utc) }
}
