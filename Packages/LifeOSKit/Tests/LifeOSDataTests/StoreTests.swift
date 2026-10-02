import Foundation
import Testing
import LifeOSCore
@testable import LifeOSData

private let oct3 = DayKey("2026-10-03")!

private func food(_ name: String, _ day: DayKey, calories: Double = 100) -> FoodEntry {
    FoodEntry(dayKey: day, loggedAt: day.startDate(), meal: .lunch, name: name, calories: calories, source: .manual)
}

@Suite("RecordStore")
struct RecordStoreTests {
    @Test func roundTripsAndKeepsInsertionOrder() async throws {
        let store = RecordStore<FoodEntry>(backend: InMemoryStorageBackend())
        let a = food("A", oct3), b = food("B", oct3), c = food("C", oct3.adding(days: 1))
        try await store.upsert(contentsOf: [a, b, c])
        #expect(try await store.records(on: oct3).map(\.name) == ["A", "B"])
        var edited = a
        edited.calories = 999
        try await store.upsert(edited)
        #expect(try await store.records(on: oct3).map(\.calories) == [999, 100])
    }

    @Test func shardsByMonthAndBatchesWrites() async throws {
        let backend = InMemoryStorageBackend()
        let store = RecordStore<FoodEntry>(backend: backend)
        let days = DayKey.range(from: DayKey("2026-09-25")!, through: DayKey("2026-10-05")!)
        try await store.upsert(contentsOf: days.map { food($0.rawValue, $0) })
        #expect(backend.writeCount == 2) // one write per touched month
        #expect(try backend.list("food").sorted() == ["2026-09.json", "2026-10.json"])

        let range = try await store.records(from: DayKey("2026-09-29")!, through: DayKey("2026-10-02")!)
        #expect(range.map(\.name) == ["2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02"])
        #expect(try await store.allRecords().count == days.count)
    }

    @Test func rangeAcrossYearBoundary() async throws {
        let store = RecordStore<FoodEntry>(backend: InMemoryStorageBackend())
        try await store.upsert(contentsOf: [food("dec", DayKey("2025-12-31")!), food("jan", DayKey("2026-01-01")!)])
        let found = try await store.records(from: DayKey("2025-12-01")!, through: DayKey("2026-01-31")!)
        #expect(found.map(\.name) == ["dec", "jan"])
        #expect(RecordStore<FoodEntry>.monthKeys(from: DayKey("2025-11-15")!, through: DayKey("2026-02-01")!)
                == ["2025-11", "2025-12", "2026-01", "2026-02"])
    }

    @Test func deleteRemovesEmptyShards() async throws {
        let backend = InMemoryStorageBackend()
        let store = RecordStore<FoodEntry>(backend: backend)
        let entry = food("A", oct3)
        try await store.upsert(entry)
        #expect(try await store.delete(id: entry.id, on: oct3))
        #expect(try await !store.delete(id: entry.id, on: oct3))
        #expect(try backend.list("food").isEmpty)
    }

    @Test func dataSurvivesANewStoreInstance() async throws {
        let backend = InMemoryStorageBackend()
        try await RecordStore<FoodEntry>(backend: backend).upsert(food("persisted", oct3))
        let reopened = RecordStore<FoodEntry>(backend: backend)
        #expect(try await reopened.records(on: oct3).map(\.name) == ["persisted"])
    }

    @Test func corruptShardIsQuarantinedNotFatal() async throws {
        let backend = InMemoryStorageBackend()
        try backend.write(Data("{ broken".utf8), to: "food/2026-10.json")
        let store = RecordStore<FoodEntry>(backend: backend)
        #expect(try await store.records(on: oct3).isEmpty)
        #expect(await store.quarantined.count == 1)
        // The user can keep logging, and the damaged bytes are kept for recovery.
        try await store.upsert(food("new", oct3))
        #expect(try backend.list("food").contains { $0.hasPrefix("2026-10.json.corrupt-") })
        #expect(try await RecordStore<FoodEntry>(backend: backend).records(on: oct3).map(\.name) == ["new"])
    }

    @Test func fileBackendWritesRealFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lifeos-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = try FileStorageBackend(root: root)
        let store = RecordStore<FoodEntry>(backend: backend)
        try await store.upsert(food("disk", oct3))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("food/2026-10.json").path))
        #expect(try await RecordStore<FoodEntry>(backend: backend).records(on: oct3).map(\.name) == ["disk"])
        try backend.move("food/2026-10.json", to: "archive/x.json")
        #expect(try backend.list("archive") == ["x.json"])
    }

    @Test func changesArePublished() async throws {
        let db = LifeOSDatabase.inMemory()
        let stream = db.changes.changes()
        try await db.food.save(food("A", oct3))
        var iterator = stream.makeAsyncIterator()
        let change = await iterator.next()
        #expect(change == StoreChange(collection: "food", days: [oct3]))
    }
}

@Suite("Repositories")
struct RepositoryTests {
    @Test func workoutMutationsAreDateKeyed() async throws {
        let db = LifeOSDatabase.inMemory()
        let monday = DayKey("2026-09-28")!
        let lastMonday = monday.adding(days: -7)
        let bench = Exercise(bodyPart: .chest, name: "Bench Press", maxSets: 3)
        try await db.workouts.addExercise(bench, on: monday)
        try await db.workouts.addExercise(Exercise(bodyPart: .back), on: lastMonday)

        // Two Mondays stay separate. This is the C1 bug the weekday keys had.
        #expect(try await db.workouts.day(monday).exercises.map(\.displayName) == ["Bench Press"])
        #expect(try await db.workouts.day(lastMonday).exercises.map(\.displayName) == ["Back"])

        for _ in 0..<4 { try await db.workouts.cycleSets(exerciseID: bench.id, on: monday) }
        #expect(try await db.workouts.day(monday).exercises[0].setsCompleted == 0) // 1,2,3 → wraps to 0
        try await db.workouts.setSets(10, exerciseID: bench.id, on: monday)
        #expect(try await db.workouts.day(monday).exercises[0].setsCompleted == 3) // clamped
        try await db.workouts.toggleTreadmill(minutes: 25, on: monday)
        #expect(try await db.workouts.day(monday).treadmillMinutes == 25)
        try await db.workouts.deleteExercise(id: bench.id, on: monday)
        try await db.workouts.toggleTreadmill(minutes: 25, on: monday)
        #expect(try await db.workouts.days(from: monday, through: monday).isEmpty) // empty days aren't stored
    }

    @Test func waterWeightTasksAndChecklist() async throws {
        let db = LifeOSDatabase.inMemory()
        try await db.water.setGlasses(5, on: oct3, source: .watch)
        #expect(try await db.water.glasses(on: oct3) == 5)
        try await db.water.setGlasses(0, on: oct3, source: .manual)
        #expect(try await db.water.glasses(on: oct3) == 0)

        try await db.weight.setDailyWeight(80, on: oct3, measuredAt: oct3.startDate(), source: .manual)
        try await db.weight.setDailyWeight(79.6, on: oct3, measuredAt: oct3.startDate(), source: .manual)
        try await db.weight.setDailyWeight(79.9, on: oct3.adding(days: -3), measuredAt: oct3.adding(days: -3).startDate(), source: .manual)
        #expect(try await db.weight.entries(from: oct3, through: oct3).map(\.kg) == [79.6]) // replaced, not appended
        #expect(try await db.weight.latest(onOrBefore: oct3.adding(days: 2), lookbackDays: 30)?.kg == 79.6)
        await #expect(throws: AppError.self) {
            try await db.weight.setDailyWeight(0, on: oct3, measuredAt: Date(), source: .manual)
        }

        let task = TaskItem(dayKey: oct3, title: "Stretch")
        try await db.tasks.save(task)
        try await db.tasks.toggleCompletion(id: task.id, on: oct3, at: oct3.startDate())
        let saved = try await db.tasks.tasks(on: oct3)
        #expect(saved.first?.isCompleted == true && saved.first?.completedAt == oct3.startDate())

        var checklist = try await db.proteinChecklist.checklist(on: oct3)
        checklist.lunch = true
        try await db.proteinChecklist.save(checklist)
        #expect(try await db.proteinChecklist.checklist(on: oct3).highProteinCount == 1)
    }

    @Test func profileAndLibraryDocuments() async throws {
        let db = LifeOSDatabase.inMemory()
        #expect(try await db.profile.load() == nil)
        let profile = UserProfile(age: 40, completedAt: Date(timeIntervalSince1970: 0))
        try await db.profile.save(profile)
        #expect(try await db.profile.load() == profile)

        try await db.foodLibrary.update { $0.noteRecent(FoodTemplate(name: "Dal", calories: 180, defaultMeal: .lunch)) }
        #expect(try await db.foodLibrary.load().recent.map(\.name) == ["Dal"])
    }

    @Test func summariesRejectBadDates() async throws {
        let db = LifeOSDatabase.inMemory()
        let bad = DailySummary(date: "Monday", caloriesConsumed: 0, calorieLimit: 0, waterGlasses: 0,
                               waterTarget: 8, gymIntensity: "Rest", todosCompleted: 0, todosTotal: 0)
        await #expect(throws: AppError.self) { try await db.summaries.save(bad) }
    }

    @Test func stableIDsAreDeterministic() {
        #expect(StableID.make("weight", "2026-10-03") == StableID.make("weight", "2026-10-03"))
        #expect(StableID.make("weight", "2026-10-03") != StableID.make("weight", "2026-10-04"))
    }
}

@Suite("SummaryService")
struct SummaryServiceTests {
    actor Calls {
        var days: [DayKey] = []
        func add(_ day: DayKey) { days.append(day) }
    }

    @Test func burstOfChangesRecomputesOncePerDay() async throws {
        let db = LifeOSDatabase.inMemory()
        let calls = Calls()
        let service = SummaryService(database: db, debounce: .milliseconds(150)) { day in
            await calls.add(day)
            let consumed = NutritionTotals(try await db.food.entries(on: day)).calories
            return DailySummary(date: day.rawValue, caloriesConsumed: consumed, calorieLimit: 2000, waterGlasses: 0,
                                waterTarget: 8, gymIntensity: "Rest", todosCompleted: 0, todosTotal: 0)
        }
        await service.start()
        try await Task.sleep(for: .milliseconds(20)) // let the listener subscribe

        // Seven rapid edits: what HomeView's seven .onChange handlers used to turn into seven saves.
        for index in 0..<5 { try await db.food.save(food("item \(index)", oct3)) }
        try await db.water.setGlasses(3, on: oct3, source: .manual)
        try await db.workouts.addExercise(Exercise(bodyPart: .abs), on: oct3.adding(days: -1))

        try await Task.sleep(for: .milliseconds(600))
        #expect(await service.passes == 1)
        #expect(await calls.days.sorted() == [oct3.adding(days: -1), oct3])
        #expect(try await db.summaries.summary(on: oct3)?.caloriesConsumed == 500)
        await service.stop()
    }

    @Test func summaryWritesDoNotRetrigger() async throws {
        let db = LifeOSDatabase.inMemory()
        let service = SummaryService(database: db, debounce: .milliseconds(50)) { day in
            DailySummary(date: day.rawValue, caloriesConsumed: 1, calorieLimit: 2, waterGlasses: 0, waterTarget: 8,
                         gymIntensity: "Rest", todosCompleted: 0, todosTotal: 0)
        }
        await service.start()
        try await Task.sleep(for: .milliseconds(20))
        try await db.food.save(food("A", oct3))
        try await Task.sleep(for: .milliseconds(400))
        #expect(await service.passes == 1)
        await service.stop()
    }

    @Test func manualInvalidateAndFlush() async throws {
        let db = LifeOSDatabase.inMemory()
        let calls = Calls()
        let service = SummaryService(database: db, debounce: .seconds(60)) { day in
            await calls.add(day)
            return nil
        }
        await service.invalidate([oct3])
        await service.flush()
        #expect(await calls.days == [oct3])
        #expect(await service.passes == 1)
    }
}
