import Foundation
import Testing
import LifeOSCore
@testable import LifeOSData

/// Regression for the first on-device migration (3 Oct 2026). Re-logging a
/// recent food reused its UUID, so v1 skipped 6 real meals as `food.duplicateID`.
@Suite("Duplicate legacy IDs")
struct DuplicateIDMigrationTests {
    private let oct1 = DayKey("2026-10-01")!
    private let oct2 = DayKey("2026-10-02")!

    private func migrator(_ db: LifeOSDatabase) -> LegacyMigrator {
        LegacyMigrator(database: db, now: LegacyFixture.now, timeZone: LegacyFixture.utc,
                       locales: [Locale(identifier: "en_US_POSIX")])
    }

    /// The same "Protein Shake" UUID logged on Oct 1, and twice on Oct 2.
    private func snapshot() -> (LegacySnapshot, UUID) {
        let shake = LegacyFixture.FoodItem(name: "Protein Shake", calories: 120, mealType: "Breakfast",
                                           timestamp: LegacyFixture.now)
        let logs: [String: LegacyFixture.DailyFoodLog] = [
            "2026-10-01": .init(breakfast: [shake]),
            "2026-10-02": .init(breakfast: [shake], snacks: [shake])
        ]
        return (LegacySnapshot(capturedAt: LegacyFixture.now, blobs: ["allDailyFoodLogs": LegacyFixture.blob(logs)],
                               waterCounts: ["2026-10-02": 4]), shake.id)
    }

    private func allFood(_ db: LifeOSDatabase) async throws -> [FoodEntry] {
        try await LifeOSDatabase(backend: db.backend).stores.food.allRecords()
    }

    @Test func everyCopyIsImportedWithStableIDs() async throws {
        let (legacy, shakeID) = snapshot()
        let db = LifeOSDatabase.inMemory()
        guard case .migrated(let report) = try await migrator(db).run(snapshot: legacy) else {
            Issue.record("expected .migrated")
            return
        }
        #expect(report.skipped.isEmpty)
        #expect(report.reassignedIDs == ["food": 2])
        let food = try await allFood(db)
        #expect(food.count == 3)
        #expect(Set(food.map(\.id)).count == 3)
        #expect(food.first { $0.id == shakeID }?.dayKey == oct1) // earliest day keeps the original ID
        #expect(NutritionTotals(food).calories == 360)

        // A second, independent migration produces identical IDs.
        let again = LifeOSDatabase.inMemory()
        _ = try await migrator(again).run(snapshot: legacy)
        #expect(Set(try await allFood(again).map(\.id)) == Set(food.map(\.id)))
    }

    @Test func repairsADeviceThatRanV1() async throws {
        let (legacy, shakeID) = snapshot()
        let db = LifeOSDatabase.inMemory()
        // State left by v1: random dict order kept the Oct 2 copy, skipped 2,
        // then the user changed water after migrating.
        try await db.stores.food.upsert(FoodEntry(id: shakeID, dayKey: oct2, loggedAt: LegacyFixture.now, meal: .breakfast,
                                                  name: "Protein Shake", calories: 120, source: .manual))
        let newMeal = FoodEntry(dayKey: oct2, loggedAt: LegacyFixture.now, meal: .dinner, name: "Logged after v1",
                                calories: 500, source: .manual)
        try await db.food.save(newMeal)
        try await db.water.setGlasses(9, on: oct2, source: .manual)
        let v1 = LegacyMigrationReport(completedAt: LegacyFixture.now, referenceDay: oct2,
                                       counts: ["food": 1, "water": 1], skipped: ["food.duplicateID": 2],
                                       inferredFromWeekday: 0, checksum: "v1", backupPath: nil, reassignedIDs: nil)
        try db.backend.write(try JSONEncoder().encode(v1), to: LegacyMigrator.v1MarkerPath)

        guard case .migrated(let report) = try await migrator(db).run(snapshot: legacy) else {
            Issue.record("expected .migrated")
            return
        }
        #expect(report.counts == ["food": 3])
        let food = try await allFood(db)
        #expect(food.count == 4) // 3 legacy copies + the meal logged after v1
        #expect(food.filter { $0.id == shakeID }.count == 1)
        #expect(food.contains { $0.id == newMeal.id })
        #expect(try await db.water.glasses(on: oct2) == 9) // post-v1 edit not overwritten
        guard case .alreadyCompleted = try await migrator(db).run(snapshot: legacy) else {
            Issue.record("v2 should now be complete")
            return
        }
        #expect(try await allFood(db).count == 4)
    }

    @Test func cleanV1RunIsAdoptedWithoutChanges() async throws {
        let db = LifeOSDatabase.inMemory()
        try await db.water.setGlasses(9, on: oct2, source: .manual)
        let v1 = LegacyMigrationReport(completedAt: LegacyFixture.now, referenceDay: oct2, counts: ["water": 1],
                                       skipped: [:], inferredFromWeekday: 0, checksum: "v1", backupPath: nil,
                                       reassignedIDs: nil)
        try db.backend.write(try JSONEncoder().encode(v1), to: LegacyMigrator.v1MarkerPath)
        #expect(try await migrator(db).run(snapshot: snapshot().0) == .alreadyCompleted(v1))
        #expect(try await db.water.glasses(on: oct2) == 9)
        #expect(try await allFood(db).isEmpty)
    }
}
