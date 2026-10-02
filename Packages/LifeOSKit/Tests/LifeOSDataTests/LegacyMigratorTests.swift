import Foundation
import Testing
import LifeOSCore
@testable import LifeOSData

@Suite("LegacyMigrator")
struct LegacyMigratorTests {
    private func migrator(_ db: LifeOSDatabase) -> LegacyMigrator {
        LegacyMigrator(database: db, now: LegacyFixture.now, timeZone: LegacyFixture.utc,
                       locales: [Locale(identifier: "en_US_POSIX")])
    }

    @Test func migratesEveryLegacyKey() async throws {
        let (snapshot, foodIDs, todoIDs) = LegacyFixture.complete()
        let db = LifeOSDatabase.inMemory()
        guard case .migrated(let report) = try await migrator(db).run(snapshot: snapshot) else {
            Issue.record("expected .migrated")
            return
        }

        #expect(report.counts == ["food": 3, "workoutDays": 3, "water": 1, "weight": 2, "tasks": 2,
                                  "proteinChecklist": 1, "dailySummaries": 1, "profile": 1, "foodLibrary": 1])
        #expect(report.skipped == ["food.badDate": 1, "workouts.supersededWeekdayLog": 1, "tasks.unknownWeekday": 1,
                                   "water.badDate": 1, "weight.invalidValue": 1, "customFoods.undecodable": 1])
        #expect(report.inferredFromWeekday == 4)
        #expect(report.referenceDay.rawValue == "2026-10-04")

        // Food keeps its IDs, slots and sources.
        let oct3 = DayKey("2026-10-03")!
        let food = try await db.food.entries(on: oct3)
        #expect(food.map(\.id) == [foodIDs[0], foodIDs[1]])
        #expect(food.map(\.meal) == [.breakfast, .snacks])
        #expect(food.map(\.source) == [.manual, .barcode])
        #expect(try await db.food.entries(on: DayKey("2026-10-01")!).first?.id == foodIDs[2])

        // Date-keyed workouts win. Weekday-keyed ones only fill gaps in the current week.
        #expect(try await db.workouts.day(DayKey("2026-10-02")!).exercises.map(\.displayName) == ["Bench Press"])
        #expect(try await db.workouts.day(DayKey("2026-09-28")!).exercises.map(\.displayName) == ["Back"])
        #expect(try await db.workouts.day(DayKey("2026-09-30")!).treadmillMinutes == 30)

        // Weekday-keyed todos land in the week containing "now" (Mon 09-28 … Sun 10-04).
        #expect(try await db.tasks.tasks(on: DayKey("2026-10-04")!).map(\.id) == [todoIDs[0]])
        #expect(try await db.tasks.tasks(on: DayKey("2026-09-28")!).map(\.title) == ["Call mum"])
        #expect(try await db.proteinChecklist.checklist(on: oct3).highProteinCount == 2)

        #expect(try await db.water.glasses(on: oct3) == 6)
        #expect(try await db.weight.entries(from: DayKey("2026-09-01")!, through: oct3).map(\.kg) == [78.4, 78.1])
        #expect(try await db.summaries.summary(on: oct3)?.isPerfectDay == true)
        #expect(try await db.profile.load()?.targetWeightKg == 72)
        #expect(try await db.foodLibrary.load().recent.map(\.name) == ["Banana"])
    }

    @Test func loadAllReturnsEveryCollection() async throws {
        let (snapshot, _, _) = LegacyFixture.complete()
        let db = LifeOSDatabase.inMemory()
        _ = try await migrator(db).run(snapshot: snapshot)
        let all = try await LifeOSDatabase(backend: db.backend).loadAll()
        #expect(all.food.count == 3 && all.workouts.count == 3 && all.water.count == 1 && all.weight.count == 2)
        #expect(all.tasks.count == 2 && all.proteinChecklist.count == 1 && all.summaries.count == 1)
        #expect(all.profile?.age == 30 && all.foodLibrary.recent.count == 1)
    }

    @Test func writesBackupBeforeDataAndMarkerAfter() async throws {
        let (snapshot, _, _) = LegacyFixture.complete()
        let db = LifeOSDatabase.inMemory()
        guard case .migrated(let report) = try await migrator(db).run(snapshot: snapshot) else {
            Issue.record("expected .migrated")
            return
        }
        let backupPath = try #require(report.backupPath)
        let backup = try JSONDecoder().decode(LegacySnapshot.self, from: try #require(try db.backend.read(backupPath)))
        #expect(backup == snapshot) // the backup is lossless, including undecodable blobs
        #expect(try migrator(db).completedReport() == report)
    }

    @Test func isIdempotent() async throws {
        let (snapshot, _, _) = LegacyFixture.complete()
        let db = LifeOSDatabase.inMemory()
        _ = try await migrator(db).run(snapshot: snapshot)
        let second = try await migrator(db).run(snapshot: snapshot)
        guard case .alreadyCompleted = second else {
            Issue.record("second run should be a no-op, got \(second)")
            return
        }
        #expect(try await db.food.entries(from: DayKey("2026-01-01")!, through: DayKey("2026-12-31")!).count == 3)
    }

    @Test func rerunAfterCrashBeforeMarkerDoesNotDuplicate() async throws {
        let (snapshot, _, _) = LegacyFixture.complete()
        let db = LifeOSDatabase.inMemory()
        _ = try await migrator(db).run(snapshot: snapshot)
        try db.backend.remove(LegacyMigrator.markerPath) // simulate dying before the marker was written
        guard case .migrated(let report) = try await migrator(db).run(snapshot: snapshot) else {
            Issue.record("expected .migrated")
            return
        }
        #expect(report.counts["food"] == 3)
        let all = try await db.stores.weight.allRecords()
        #expect(all.count == 2) // stable IDs → upserts, not duplicates
        #expect(try await db.stores.tasks.allRecords().count == 2)
    }

    @Test func freshInstallWritesMarkerOnly() async throws {
        let db = LifeOSDatabase.inMemory()
        #expect(try await migrator(db).run(snapshot: LegacySnapshot(capturedAt: LegacyFixture.now)) == .nothingToMigrate)
        #expect(try migrator(db).completedReport() != nil)
        #expect(try db.backend.list("backups").isEmpty)
    }

    @Test func checksumMatchesIndependentRecomputation() async throws {
        let (snapshot, _, _) = LegacyFixture.complete()
        let db = LifeOSDatabase.inMemory()
        guard case .migrated(let report) = try await migrator(db).run(snapshot: snapshot) else {
            Issue.record("expected .migrated")
            return
        }
        let fresh = LifeOSDatabase(backend: db.backend).stores
        var blobs: [Data] = []
        blobs += try await fresh.food.allRecords().map(LegacyMigrator.encode)
        blobs += try await fresh.workouts.allRecords().map(LegacyMigrator.encode)
        blobs += try await fresh.water.allRecords().map(LegacyMigrator.encode)
        blobs += try await fresh.weight.allRecords().map(LegacyMigrator.encode)
        blobs += try await fresh.tasks.allRecords().map(LegacyMigrator.encode)
        blobs += try await fresh.proteinChecklist.allRecords().map(LegacyMigrator.encode)
        blobs += try await fresh.summaries.allRecords().map(LegacyMigrator.encode)
        #expect(LegacyMigrator.checksum(blobs) == report.checksum)
    }

    @Test func capturesFromUserDefaults() throws {
        let suite = "lifeos.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("{}".utf8), forKey: "allDailyFoodLogs")
        defaults.set(4, forKey: "waterCount_2026-10-03")
        defaults.set(["2026-10-03": 80.5], forKey: "weightHistory")
        defaults.set("dark", forKey: "appTheme") // a preference, not captured

        let snapshot = LegacySnapshot.capture(from: defaults, now: LegacyFixture.now)
        #expect(snapshot.blobs.keys.sorted() == ["allDailyFoodLogs"])
        #expect(snapshot.waterCounts == ["2026-10-03": 4])
        #expect(snapshot.weightHistory == ["2026-10-03": 80.5])
    }

    /// Doc 01 §4.3: 365 days of synthetic data in < 2 s on an iPhone 13.
    /// Asserted with headroom on the CI Mac. Device timing is QA-11.
    @Test func migratesAYearOfHeavyLoggingQuickly() async throws {
        let snapshot = LegacyFixture.heavyLogger(days: 365)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lifeos-perf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let db = LifeOSDatabase(backend: try FileStorageBackend(root: root))

        let clock = ContinuousClock()
        let started = clock.now
        let outcome = try await migrator(db).run(snapshot: snapshot)
        let elapsed = clock.now - started

        guard case .migrated(let report) = outcome else {
            Issue.record("expected .migrated")
            return
        }
        #expect(report.counts["food"] == 365 * 6)
        #expect(report.counts["workoutDays"] == 365)
        #expect(report.counts["water"] == 365 && report.counts["weight"] == 365 && report.counts["dailySummaries"] == 365)
        #expect(report.skipped.isEmpty)
        #expect(elapsed < .seconds(2), "migration took \(elapsed)")
    }
}
