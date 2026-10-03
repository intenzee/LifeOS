import Foundation
import Testing
import LifeOSCore
import LifeOSData
@testable import LifeOSHealth

private let utc = TimeZone(identifier: "UTC")!
private let oct3 = DayKey("2026-10-03")!
private let oct2 = DayKey("2026-10-02")!
private let noon = oct3.startDate(timeZone: utc).addingTimeInterval(12 * 3600)

/// An in-memory Health that holds samples by write id, like the real store
/// does with LifeOS's metadata.
final class FakeHealthWriter: HealthWriteClient, @unchecked Sendable {
    private let lock = NSLock()
    private var foodByID: [UUID: NutritionSample] = [:]
    private var waterByID: [UUID: WaterSample] = [:]
    var allowed: Set<HealthWriteKind> = [.food, .water]
    var failNextSave = false
    private(set) var authorizationRequests = 0
    private(set) var saves = 0

    var isAvailable: Bool { true }
    var food: [NutritionSample] { lock.withLock { foodByID.values.sorted { $0.date < $1.date } } }
    var waterML: Double { lock.withLock { waterByID.values.reduce(0) { $0 + $1.ml } } }
    var waterSamples: Int { lock.withLock { waterByID.count } }

    func requestWriteAuthorization() async throws { lock.withLock { authorizationRequests += 1 } }
    func canWrite(_ kind: HealthWriteKind) -> Bool { lock.withLock { allowed.contains(kind) } }

    func save(food: [NutritionSample], water: [WaterSample]) async throws {
        try lock.withLock {
            if failNextSave { failNextSave = false; throw CocoaError(.fileWriteUnknown) }
            saves += 1
            // Health appends: saving an id twice really would duplicate, so the
            // fake refuses it to prove the service always deletes first.
            for sample in food {
                precondition(foodByID[sample.id] == nil, "duplicate food write")
                foodByID[sample.id] = sample
            }
            for sample in water {
                precondition(waterByID[sample.id] == nil, "duplicate water write")
                waterByID[sample.id] = sample
            }
        }
    }

    func deleteSamples(writeIDs: [UUID]) async throws {
        lock.withLock {
            for id in writeIDs {
                foodByID[id] = nil
                waterByID[id] = nil
            }
        }
    }
}

private func entry(_ name: String, kcal: Double, protein: Double = 10, day: DayKey = oct3, hour: Double = 9,
                   meal: MealType = .breakfast, source: EntrySource = .manual, id: UUID = UUID()) -> FoodEntry {
    FoodEntry(id: id, dayKey: day, loggedAt: day.startDate(timeZone: utc).addingTimeInterval(hour * 3600), meal: meal,
              name: name, calories: kcal, proteinG: protein, carbsG: 20, fatG: 5, source: source)
}

private func makeService(_ writer: FakeHealthWriter, _ db: LifeOSDatabase, now: Date = noon) -> HealthWriteBackService {
    HealthWriteBackService(client: writer, database: db, debounce: .milliseconds(10), timeZone: utc, now: { now })
}

@Suite("Health write-back (WCH-08)")
struct HealthWriteBackTests {
    // MARK: Planner

    @Test func newEntriesAreWrittenAndUnchangedOnesAreLeftAlone() {
        let oats = entry("Oats", kcal: 300)
        let first = HealthWritePlanner.plan(day: oct3, entries: [oats], water: nil, ledger: HealthWriteDay(),
                                            kinds: [.food, .water], now: noon, timeZone: utc)
        #expect(first.food.map(\.name) == ["Oats"])
        #expect(first.deletes == first.food.map(\.id), "delete-before-save makes a retry safe")
        #expect(first.ledger.food[oats.id] == first.food[0].id)

        let again = HealthWritePlanner.plan(day: oct3, entries: [oats], water: nil, ledger: first.ledger,
                                            kinds: [.food, .water], now: noon, timeZone: utc)
        #expect(again.isEmpty)
    }

    @Test func editsReplaceAndDeletesRemove() {
        var oats = entry("Oats", kcal: 300)
        let eggs = entry("Eggs", kcal: 140, hour: 10)
        let first = HealthWritePlanner.plan(day: oct3, entries: [oats, eggs], water: nil, ledger: HealthWriteDay(),
                                            kinds: [.food], now: noon, timeZone: utc)
        let oldOats = try! #require(first.ledger.food[oats.id])

        oats.calories = 350
        let edited = HealthWritePlanner.plan(day: oct3, entries: [oats], water: nil, ledger: first.ledger,
                                             kinds: [.food], now: noon, timeZone: utc)
        #expect(edited.food.map(\.kcal) == [350])
        #expect(edited.deletes.contains(oldOats))
        #expect(edited.deletes.contains(try! #require(first.ledger.food[eggs.id])), "eggs were deleted from the log")
        #expect(edited.ledger.food.count == 1)
    }

    @Test func importedAndEmptyEntriesAreNotWritten() {
        let imported = entry("From Health", kcal: 200, source: .healthKit)
        let empty = FoodEntry(dayKey: oct3, loggedAt: noon, meal: .snacks, name: "Water", calories: 0, source: .manual)
        let plan = HealthWritePlanner.plan(day: oct3, entries: [imported, empty], water: nil, ledger: HealthWriteDay(),
                                           kinds: [.food], now: noon, timeZone: utc)
        #expect(plan.isEmpty)
    }

    @Test func entryLoggedOnAnotherDayUsesTheMealTime() {
        // Yesterday's dinner, added this morning.
        let dinner = FoodEntry(dayKey: oct2, loggedAt: noon, meal: .dinner, name: "Curry", calories: 600,
                               source: .manual)
        let sample = HealthWritePlanner.nutrition(for: dinner, on: oct2, timeZone: utc)
        #expect(sample.date == oct2.startDate(timeZone: utc).addingTimeInterval(19 * 3600))
    }

    @Test func movingAnEntryToAnotherDayChangesItsWriteID() {
        let lunch = entry("Wrap", kcal: 450, meal: .lunch)
        var moved = lunch
        moved.dayKey = oct2
        moved.loggedAt = lunch.loggedAt // same timestamp, different day
        #expect(HealthWritePlanner.nutrition(for: lunch, on: oct3, timeZone: utc).id
                != HealthWritePlanner.nutrition(for: moved, on: oct2, timeZone: utc).id)
    }

    @Test func waterIsWrittenAsIncrementsAndTrimmedFromTheNewest() {
        let three = WaterDay(dayKey: oct3, glasses: 3, source: .manual, updatedAt: noon)
        let first = HealthWritePlanner.plan(day: oct3, entries: [], water: three, ledger: HealthWriteDay(),
                                            kinds: [.water], now: noon, timeZone: utc)
        #expect(first.water.map(\.ml) == [750])

        let five = WaterDay(dayKey: oct3, glasses: 5, source: .manual)
        let more = HealthWritePlanner.plan(day: oct3, entries: [], water: five, ledger: first.ledger,
                                           kinds: [.water], now: noon.addingTimeInterval(3600), timeZone: utc)
        #expect(more.water.map(\.ml) == [500])
        #expect(more.ledger.water.map(\.ml) == [750, 500])
        #expect(more.water[0].date == noon.addingTimeInterval(3600), "drunk now, not at the first glass")

        let four = WaterDay(dayKey: oct3, glasses: 4, source: .manual)
        let fewer = HealthWritePlanner.plan(day: oct3, entries: [], water: four, ledger: more.ledger,
                                            kinds: [.water], now: noon, timeZone: utc)
        #expect(fewer.deletes.contains(more.ledger.water[1].id))
        #expect(fewer.ledger.water.map(\.ml) == [750, 250])

        let none = HealthWritePlanner.plan(day: oct3, entries: [], water: nil, ledger: fewer.ledger,
                                           kinds: [.water], now: noon, timeZone: utc)
        #expect(none.ledger.water.isEmpty)
        #expect(none.water.isEmpty)
    }

    @Test func kindWithoutPermissionKeepsItsLedger() {
        let ledger = HealthWriteDay(food: [UUID(): UUID()], water: [])
        let plan = HealthWritePlanner.plan(day: oct3, entries: [], water: nil, ledger: ledger, kinds: [.water],
                                           now: noon, timeZone: utc)
        #expect(plan.isEmpty)
        #expect(plan.ledger.food == ledger.food)
    }

    // MARK: Service

    @Test func offByDefaultAndWritesNothing() async throws {
        let writer = FakeHealthWriter(), db = LifeOSDatabase.inMemory()
        try await db.food.save(entry("Oats", kcal: 300))
        let service = makeService(writer, db)
        await service.invalidate([oct3])
        await service.flush()
        #expect(writer.food.isEmpty)
        #expect(try await service.isEnabled() == false)
    }

    @Test func mirrorsLogChangesOnceEnabled() async throws {
        let writer = FakeHealthWriter(), db = LifeOSDatabase.inMemory()
        let service = makeService(writer, db)
        await service.start()
        try await db.food.save(entry("Already logged", kcal: 200))

        try await service.setEnabled(true)
        #expect(writer.authorizationRequests == 1)
        #expect(writer.food.map(\.name) == ["Already logged"], "today's log is written on enable")

        var oats = entry("Oats", kcal: 300, hour: 8)
        try await db.food.save(oats)
        try await db.water.setGlasses(2, on: oct3, source: .watch)
        try await waitUntil { writer.food.count == 2 && writer.waterML == 500 }

        oats.calories = 320
        try await db.food.save(oats)
        try await db.food.delete(id: oats.id, on: oct3)
        try await db.water.setGlasses(1, on: oct3, source: .manual)
        try await waitUntil { writer.food.map(\.name) == ["Already logged"] && writer.waterML == 250 }
        await service.stop()
    }

    @Test func daysBeforeEnablingAreNotBackfilled() async throws {
        let writer = FakeHealthWriter(), db = LifeOSDatabase.inMemory()
        try await db.food.save(entry("Yesterday", kcal: 500, day: oct2))
        let service = makeService(writer, db)
        try await service.setEnabled(true)
        await service.invalidate([oct2])
        await service.flush()
        #expect(writer.food.isEmpty)
    }

    @Test func failedSaveIsRetriedWithoutDuplicates() async throws {
        let writer = FakeHealthWriter(), db = LifeOSDatabase.inMemory()
        let service = makeService(writer, db)
        try await db.food.save(entry("Oats", kcal: 300))
        writer.failNextSave = true
        try await service.setEnabled(true)
        #expect(writer.food.isEmpty)
        #expect(try await db.healthWrites.load().days[oct3] == nil, "ledger only moves after Health accepts")

        await service.invalidateOpenDays()
        await service.flush()
        #expect(writer.food.count == 1)
    }

    @Test func turningOffStopsWritingAndKeepsTheLedger() async throws {
        let writer = FakeHealthWriter(), db = LifeOSDatabase.inMemory()
        let service = makeService(writer, db)
        try await db.food.save(entry("Oats", kcal: 300))
        try await service.setEnabled(true)
        try await service.setEnabled(false)
        try await db.food.save(entry("Toast", kcal: 150))
        await service.invalidate([oct3])
        await service.flush()
        #expect(writer.food.map(\.name) == ["Oats"])

        // Back on the same day: nothing is written twice.
        try await service.setEnabled(true)
        #expect(writer.food.map(\.name).sorted() == ["Oats", "Toast"])
    }

    @Test func foodDeniedStillWritesWater() async throws {
        let writer = FakeHealthWriter(), db = LifeOSDatabase.inMemory()
        writer.allowed = [.water]
        let service = makeService(writer, db)
        try await db.food.save(entry("Oats", kcal: 300))
        try await db.water.setGlasses(3, on: oct3, source: .manual)
        try await service.setEnabled(true)
        #expect(writer.food.isEmpty)
        #expect(writer.waterML == 750)
        #expect(await service.writableKinds() == [.water])
    }

    @Test func concurrentPassesNeverDoubleWrite() async throws {
        let writer = FakeHealthWriter(), db = LifeOSDatabase.inMemory()
        let service = makeService(writer, db)
        try await service.setEnabled(true)
        try await db.food.save(entry("Oats", kcal: 300))
        try await db.water.setGlasses(4, on: oct3, source: .manual)
        // The fake traps on a duplicate save, so racing flushes must serialise.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await service.invalidate([oct3])
                    await service.flush()
                }
            }
        }
        #expect(writer.food.count == 1)
        #expect(writer.waterML == 1000)
        #expect(writer.waterSamples == 1)
    }
}

private func waitUntil(_ condition: @escaping () -> Bool, timeout: Duration = .seconds(2)) async throws {
    let clock = ContinuousClock(), deadline = clock.now + timeout
    while !condition() {
        guard clock.now < deadline else {
            Issue.record("Timed out waiting for Health writes")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
