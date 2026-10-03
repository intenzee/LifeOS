import Foundation
import Testing
import LifeOSCore
@testable import LifeOSData

private let utc = TimeZone(identifier: "UTC")!
private let oct3 = DayKey("2026-10-03")!

/// Persona A from doc 03 §6: BMR 1780, baseline 2136, goal −550, allowance 356.
private let personaA = UserProfile(age: 30, heightCm: 180, currentWeightKg: 80, targetWeightKg: 75, sex: .male)

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private func makeService(_ db: LifeOSDatabase, clock: Clock) -> BudgetService {
    BudgetService(database: db, debounce: .milliseconds(10), timeZone: utc, now: { clock.now })
}

private func watchSession(_ day: DayKey, kind: ActivityKind = .strength, kcal: Double) -> WorkoutSession {
    let start = day.startDate(timeZone: utc).addingTimeInterval(18 * 3600)
    return WorkoutSession(dayKey: day, start: start, end: start.addingTimeInterval(3600), kind: kind,
                          activeEnergyKcal: kcal, source: .watch, healthKitUUID: UUID())
}

@Suite("BudgetService (CAL-02)")
struct BudgetServiceTests {
    @Test func storesMeasuredBudgetForTheDay() async throws {
        let db = LifeOSDatabase.inMemory()
        try await db.profile.save(personaA)
        for offset in 0..<3 {
            try await db.energy.update(oct3.adding(days: -offset)) { $0.activeKcal = 780; $0.watchActiveKcal = 700 }
        }
        let service = makeService(db, clock: Clock(oct3.startDate(timeZone: utc).addingTimeInterval(12 * 3600)))
        try await service.recompute(oct3)

        let day = try #require(try await db.energy.day(oct3))
        #expect(day.budgetKcal == 1798)
        #expect(day.budgetMode == .measured)
        #expect(day.formulaVersion == BudgetBreakdown.formulaVersion)
        #expect(try await service.breakdown(on: oct3)?.budget == 1798)
    }

    @Test func noWatchUsesMETEstimateOfTheManualLog() async throws {
        let db = LifeOSDatabase.inMemory()
        try await db.profile.save(personaA)
        try await db.workouts.addExercise(Exercise(bodyPart: .legs, setsCompleted: 4), on: oct3)
        let service = makeService(db, clock: Clock(oct3.startDate(timeZone: utc)))
        try await service.recompute(oct3)

        let met = CalorieCalculator.caloriesPerSet(bodyPart: .legs, weightKg: 80) * 4
        let day = try #require(try await db.energy.day(oct3))
        #expect(day.budgetMode == .estimated)
        #expect(day.estimatedSessionKcal == met)
        #expect(day.hadWorkout)
        #expect(day.budgetKcal == (1586 + met * 0.5).rounded())
    }

    @Test func watchWorkoutAbsorbsManualLogAndReplacesEstimate() async throws {
        let db = LifeOSDatabase.inMemory()
        try await db.profile.save(personaA)
        let exercise = Exercise(bodyPart: .chest, setsCompleted: 3)
        try await db.workouts.addExercise(exercise, on: oct3)
        try await db.workoutSessions.replaceSessions(on: oct3, with: [watchSession(oct3, kcal: 260)])
        let service = makeService(db, clock: Clock(oct3.startDate(timeZone: utc)))
        try await service.recompute(oct3)

        #expect(try await db.workoutSessions.sessions(on: oct3).first?.mergedExerciseIDs == [exercise.id])
        #expect(try await db.energy.day(oct3)?.estimatedSessionKcal == 260)
    }

    @Test func listensToStoreChangesAndSettles() async throws {
        let db = LifeOSDatabase.inMemory()
        try await db.profile.save(personaA)
        let service = makeService(db, clock: Clock(oct3.startDate(timeZone: utc)))
        await service.start()
        try await db.energy.update(oct3) { $0.activeKcal = 500 }
        try await Task.sleep(for: .milliseconds(150))
        await service.flush()
        #expect(try await db.energy.day(oct3)?.budgetKcal == 1586) // estimated, no logged sessions

        try await db.energySettings.save(EnergySettings(manualTarget: 2000))
        try await Task.sleep(for: .milliseconds(150))
        await service.flush()
        #expect(try await db.energy.day(oct3)?.budgetKcal == 2000)
        #expect(try await db.energy.day(oct3)?.budgetMode == .fixed)
        await service.stop()
    }

    @Test func pastDaysFreezeAfterSyncAndIgnoreProfileChanges() async throws {
        let db = LifeOSDatabase.inMemory()
        try await db.profile.save(personaA)
        let clock = Clock(oct3.startDate(timeZone: utc).addingTimeInterval(40 * 3600))
        try await db.healthSync.save(HealthSyncState(lastCompletedSync: clock.now))
        let service = makeService(db, clock: clock)
        try await service.recompute(oct3)
        let frozen = try #require(try await db.energy.day(oct3))
        #expect(frozen.isFrozen)

        var heavier = personaA
        heavier.currentWeightKg = 95
        try await db.profile.save(heavier)
        try await service.recompute(oct3)
        #expect(try await db.energy.day(oct3)?.budgetKcal == frozen.budgetKcal)
    }

    @Test func dayDoesNotFreezeWithoutACompletedSync() async throws {
        let db = LifeOSDatabase.inMemory()
        try await db.profile.save(personaA)
        let clock = Clock(oct3.startDate(timeZone: utc).addingTimeInterval(72 * 3600))
        try await db.healthSync.save(HealthSyncState(lastCompletedSync: oct3.startDate(timeZone: utc)))
        let service = makeService(db, clock: clock)
        try await service.recompute(oct3)
        #expect(try await db.energy.day(oct3)?.isFrozen == false)
    }

    @Test func budgetComputesOnDemandAndAllowanceRefreshes() async throws {
        let db = LifeOSDatabase.inMemory()
        try await db.profile.save(personaA)
        let clock = Clock(oct3.startDate(timeZone: utc))
        let service = makeService(db, clock: clock)
        #expect(try await service.budget(on: oct3) == 1586)

        #expect(try await service.refreshAllowance() == nil) // no history yet
        for offset in 1...20 {
            try await db.energy.update(oct3.adding(days: -offset)) {
                $0.activeKcal = offset % 3 == 0 ? 900 : 400
                $0.hadWorkout = offset % 3 == 0
            }
        }
        #expect(try await service.refreshAllowance() == 400)
        #expect(try await db.energySettings.load().allowanceKcal == 400)
    }

    @Test func noProfileMeansNoBudgetYet() async throws {
        let db = LifeOSDatabase.inMemory()
        let service = makeService(db, clock: Clock(oct3.startDate(timeZone: utc)))
        #expect(try await service.budget(on: oct3) == nil)
    }
}

@Suite("RecordStore update/replaceAll")
struct RecordStoreUpdateTests {
    @Test func updateWritesOnlyOnChange() async throws {
        let backend = InMemoryStorageBackend()
        let store = RecordStore<EnergyDay>(backend: backend)
        try await store.update(id: oct3, on: oct3, default: { EnergyDay(dayKey: oct3) }) { $0.activeKcal = 10 }
        let writes = backend.writeCount
        try await store.update(id: oct3, on: oct3, default: { EnergyDay(dayKey: oct3) }) { $0.activeKcal = 10 }
        #expect(backend.writeCount == writes)
    }

    @Test func replaceAllSwapsOneDayAndKeepsOthers() async throws {
        let store = RecordStore<WorkoutSession>(backend: InMemoryStorageBackend())
        let other = watchSession(oct3.adding(days: 1), kcal: 100)
        try await store.upsert(contentsOf: [watchSession(oct3, kcal: 1), other])
        let replacement = watchSession(oct3, kind: .run, kcal: 2)
        try await store.replaceAll(on: oct3, with: [replacement])
        #expect(try await store.records(on: oct3) == [replacement])
        #expect(try await store.records(on: other.dayKey) == [other])
    }
}
