import Foundation
import CryptoKit
import LifeOSCore

/// What a migration run did. Persisted as the completion marker.
public struct LegacyMigrationReport: Codable, Sendable, Equatable {
    public var completedAt: Date
    /// The week weekday-named legacy data was mapped into.
    public var referenceDay: DayKey
    /// Records written per collection.
    public var counts: [String: Int]
    /// Records not migrated, by reason (e.g. `tasks.unknownWeekday`).
    public var skipped: [String: Int]
    /// Records whose date was inferred from a weekday name (ambiguous by nature).
    public var inferredFromWeekday: Int
    /// SHA-256 over every migrated record, verified against a fresh read-back.
    public var checksum: String
    public var backupPath: String?
    /// Legacy records whose duplicated ID was replaced by a stable new one
    /// (e.g. a recent food logged twice with the same UUID). `nil` in v1 reports.
    public var reassignedIDs: [String: Int]?
}

public enum LegacyMigrationOutcome: Sendable, Equatable {
    case alreadyCompleted(LegacyMigrationReport)
    case nothingToMigrate
    case migrated(LegacyMigrationReport)
}

/// One-time move of UserDefaults blobs into the file store (FND-04).
///
/// 1. If the completion marker exists, it does nothing (idempotent).
/// 2. It writes the full snapshot to `backups/` before writing anything else.
/// 3. It maps every legacy value to a date-keyed record. Weekday-keyed data
///    goes into the current week, which is all the legacy model could represent.
/// 4. It writes with upserts and stable IDs, so a crashed half-run is safe to repeat.
/// 5. It re-reads everything through a *fresh* store (no caches) and compares
///    counts and a checksum. The marker is written only if that passes.
///
/// Legacy keys are left in place, read-only, for two releases (doc 01 §4.3).
public struct LegacyMigrator: Sendable {
    public static let markerPath = "migration/legacy-v2.json"
    /// Written by the first release of the migrator. That version *skipped*
    /// food and todos with duplicated IDs. v2 re-imports them (see `run`).
    public static let v1MarkerPath = "migration/legacy-v1.json"

    private let database: LifeOSDatabase
    private let now: Date
    private let timeZone: TimeZone
    private let locales: [Locale]

    public init(database: LifeOSDatabase, now: Date = Date(), timeZone: TimeZone = .current,
                locales: [Locale] = [Locale(identifier: "en_US_POSIX"), .current]) {
        self.database = database
        self.now = now
        self.timeZone = timeZone
        self.locales = locales
    }

    /// The report of a previous successful run, if any.
    public func completedReport() throws -> LegacyMigrationReport? {
        guard let data = try database.backend.read(Self.markerPath) else { return nil }
        return try JSONDecoder().decode(LegacyMigrationReport.self, from: data)
    }

    public func run(snapshot: LegacySnapshot) async throws -> LegacyMigrationOutcome {
        if let report = try completedReport() {
            return .alreadyCompleted(report)
        }
        // A v1 run already moved everything except duplicated-ID food/todos.
        // Repair only those collections, so edits made since v1 aren't overwritten.
        var only: Set<String>?
        if let data = try database.backend.read(Self.v1MarkerPath) {
            let v1 = try JSONDecoder().decode(LegacyMigrationReport.self, from: data)
            only = []
            if (v1.skipped["food.duplicateID"] ?? 0) > 0 { only?.insert(FoodEntry.collection) }
            if (v1.skipped["tasks.duplicateID"] ?? 0) > 0 { only?.insert(TaskItem.collection) }
            if only?.isEmpty == true {
                try writeMarker(v1)
                return .alreadyCompleted(v1)
            }
        }
        func includes(_ collection: String) -> Bool { only?.contains(collection) ?? true }

        let reference = DayKey.make(for: now, timeZone: timeZone)
        guard !snapshot.isEmpty else {
            try writeMarker(LegacyMigrationReport(completedAt: now, referenceDay: reference, counts: [:],
                                                  skipped: [:], inferredFromWeekday: 0,
                                                  checksum: Self.checksum([Data]()), backupPath: nil))
            return .nothingToMigrate
        }

        let backupPath = try writeBackup(snapshot)
        var plan = try MigrationPlan.build(from: snapshot, reference: reference, now: now,
                                           timeZone: timeZone, locales: locales)
        if let only {
            plan.restrict(to: only)
        }
        let stores = database.stores
        if includes(FoodEntry.collection) {
            // Clear any earlier copy of these legacy IDs first. A previous run
            // (v1, or a crashed v2) may have filed a duplicated ID on another day.
            for day in plan.legacyFoodDays {
                try await stores.food.deleteAll(on: day) { plan.legacyFoodIDs.contains($0.id) }
            }
            try await stores.food.upsert(contentsOf: plan.food)
        }
        if includes(TaskItem.collection) {
            for day in plan.legacyTaskDays {
                try await stores.tasks.deleteAll(on: day) { plan.legacyTaskIDs.contains($0.id) }
            }
            try await stores.tasks.upsert(contentsOf: plan.tasks)
        }
        if only == nil {
            try await stores.workouts.upsert(contentsOf: plan.workouts)
            try await stores.water.upsert(contentsOf: plan.water)
            try await stores.weight.upsert(contentsOf: plan.weight)
            try await stores.proteinChecklist.upsert(contentsOf: plan.proteinChecklist)
            try await stores.summaries.upsert(contentsOf: plan.summaries)
            if let profile = plan.profile { try await stores.profile.save(profile) }
            if let library = plan.foodLibrary { try await stores.foodLibrary.save(library) }
        }

        let checksum = try await verify(plan)
        plan.report.checksum = checksum
        plan.report.backupPath = backupPath
        plan.report.completedAt = now
        try writeMarker(plan.report)
        Log.data.notice("Legacy migration complete: \(plan.report.counts.values.reduce(0, +)) records")
        return .migrated(plan.report)
    }

    // MARK: Verification

    /// Re-reads through a new database on the same backend, so nothing comes from cache.
    private func verify(_ plan: MigrationPlan) async throws -> String {
        let fresh = LifeOSDatabase(backend: database.backend).stores
        var expected: [Data] = []
        var actual: [Data] = []

        func compare<R: DayRecord & Equatable>(_ planned: [R], _ stored: [R], _ name: String) throws {
            let storedByID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let missing = planned.filter { storedByID[$0.id] != $0 }
            guard missing.isEmpty else {
                throw AppError(.migrationVerificationFailed,
                               userMessage: "Your data couldn't be upgraded. Nothing was lost.",
                               recoverySuggestion: "Restart LifeOS to try again.",
                               category: .data,
                               underlying: StringError("\(missing.count) \(name) records missing after write"))
            }
            expected += try planned.map(Self.encode)
            actual += try planned.compactMap { storedByID[$0.id] }.map(Self.encode)
        }

        try compare(plan.food, try await fresh.food.allRecords(), FoodEntry.collection)
        try compare(plan.workouts, try await fresh.workouts.allRecords(), WorkoutDay.collection)
        try compare(plan.water, try await fresh.water.allRecords(), WaterDay.collection)
        try compare(plan.weight, try await fresh.weight.allRecords(), WeightEntry.collection)
        try compare(plan.tasks, try await fresh.tasks.allRecords(), TaskItem.collection)
        try compare(plan.proteinChecklist, try await fresh.proteinChecklist.allRecords(), ProteinChecklist.collection)
        try compare(plan.summaries, try await fresh.summaries.allRecords(), DailySummary.collection)

        if let profile = plan.profile {
            guard try await fresh.profile.load() == profile else {
                throw AppError(.migrationVerificationFailed, userMessage: "Your profile couldn't be upgraded.",
                               category: .data)
            }
        }
        if let library = plan.foodLibrary {
            guard try await fresh.foodLibrary.load() == library else {
                throw AppError(.migrationVerificationFailed, userMessage: "Your saved foods couldn't be upgraded.",
                               category: .data)
            }
        }

        let expectedSum = Self.checksum(expected)
        guard expectedSum == Self.checksum(actual) else {
            throw AppError(.migrationVerificationFailed, userMessage: "Your data couldn't be upgraded. Nothing was lost.",
                           recoverySuggestion: "Restart LifeOS to try again.", category: .data,
                           underlying: StringError("checksum mismatch"))
        }
        return expectedSum
    }

    // MARK: Files

    private func writeBackup(_ snapshot: LegacySnapshot) throws -> String {
        let path = "backups/legacy-\(Int(now.timeIntervalSince1970)).json"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            try database.backend.write(try encoder.encode(snapshot), to: path)
        } catch {
            throw AppError(.migrationFailed, userMessage: "Your data couldn't be backed up, so nothing was changed.",
                           recoverySuggestion: "Free up storage on your iPhone, then restart LifeOS.",
                           category: .data, underlying: error)
        }
        return path
    }

    private func writeMarker(_ report: LegacyMigrationReport) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try database.backend.write(try encoder.encode(report), to: Self.markerPath)
    }

    static func encode<R: Encodable>(_ record: R) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(record)
    }

    static func checksum(_ items: [Data]) -> String {
        var hasher = SHA256()
        for item in items.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            hasher.update(data: item)
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Legacy snapshot → records. Pure: no I/O, so it's unit-testable on its own.
struct MigrationPlan {
    var food: [FoodEntry] = []
    var workouts: [WorkoutDay] = []
    var water: [WaterDay] = []
    var weight: [WeightEntry] = []
    var tasks: [TaskItem] = []
    var proteinChecklist: [ProteinChecklist] = []
    var summaries: [DailySummary] = []
    var profile: UserProfile?
    var foodLibrary: FoodLibrary?
    var report: LegacyMigrationReport
    /// Original legacy IDs and the days they appeared on (for re-run cleanup).
    var legacyFoodIDs = Set<UUID>()
    var legacyFoodDays = Set<DayKey>()
    var legacyTaskIDs = Set<UUID>()
    var legacyTaskDays = Set<DayKey>()

    /// Keeps only `collections` (a v1 → v2 repair).
    mutating func restrict(to collections: Set<String>) {
        if !collections.contains(FoodEntry.collection) { food = []; legacyFoodIDs = []; legacyFoodDays = [] }
        if !collections.contains(TaskItem.collection) { tasks = []; legacyTaskIDs = []; legacyTaskDays = [] }
        workouts = []; water = []; weight = []; proteinChecklist = []; summaries = []
        profile = nil; foodLibrary = nil
        report.counts = report.counts.filter { collections.contains($0.key) }
    }

    // swiftlint:disable:next function_body_length
    static func build(from snapshot: LegacySnapshot, reference: DayKey, now: Date,
                      timeZone: TimeZone, locales: [Locale]) throws -> MigrationPlan {
        var plan = MigrationPlan(report: LegacyMigrationReport(
            completedAt: now, referenceDay: reference, counts: [:], skipped: [:],
            inferredFromWeekday: 0, checksum: "", backupPath: nil))
        let decoder = JSONDecoder()

        func reassign(_ collection: String) {
            plan.report.reassignedIDs = plan.report.reassignedIDs ?? [:]
            plan.report.reassignedIDs?[collection, default: 0] += 1
        }
        func skip(_ reason: String, _ count: Int = 1) {
            guard count > 0 else { return }
            plan.report.skipped[reason, default: 0] += count
        }
        func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
            guard let data = snapshot.blobs[key] else { return nil }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                skip("\(key).undecodable")
                Log.data.error("Legacy key \(key, privacy: .public) undecodable: \(String(describing: error), privacy: .private)")
                return nil
            }
        }
        func weekdayDay(_ name: String) -> DayKey? {
            LegacyWeekdayName.dayKey(for: name, inWeekOf: reference, locales: locales)
        }

        // Food log: [yyyy-MM-dd: DailyFoodLog]. Days are visited in date order, so
        // which copy of a duplicated ID keeps it is deterministic across runs.
        // Later copies get a stable new ID. (Re-logging a recent food reused its UUID.)
        var seenFood = Set<UUID>()
        let foodLogs = decode([String: Legacy.DailyFoodLog].self, "allDailyFoodLogs") ?? [:]
        for key in foodLogs.keys.sorted() {
            guard let log = foodLogs[key] else { continue }
            guard let day = DayKey(key) else { skip("food.badDate", log.slotted.count); continue }
            for (index, (slot, item)) in log.slotted.enumerated() {
                plan.legacyFoodIDs.insert(item.id)
                plan.legacyFoodDays.insert(day)
                var id = item.id
                if !seenFood.insert(item.id).inserted {
                    id = StableID.make("legacy-food", item.id.uuidString, day.rawValue, slot.rawValue, String(index))
                    reassign(FoodEntry.collection)
                }
                plan.food.append(FoodEntry(
                    id: id, dayKey: day, loggedAt: item.timestamp, meal: slot, name: item.name,
                    servingDescription: item.servingSize, calories: item.calories, proteinG: item.protein,
                    carbsG: item.carbs, fatG: item.fat, barcode: item.barcode,
                    source: item.barcode == nil ? .manual : .barcode))
            }
        }

        // Workouts: date-keyed first, then the older weekday-keyed log fills gaps.
        var workoutDays = Set<DayKey>()
        for (key, legacy) in (decode([String: Legacy.DayWorkout].self, "allDailyWorkouts") ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard let day = DayKey(key) else { skip("workouts.badDate"); continue }
            let workout = legacy.workoutDay(day, at: now)
            guard !workout.isEmpty else { continue }
            plan.workouts.append(workout)
            workoutDays.insert(day)
        }
        for (name, legacy) in (decode([String: Legacy.DayWorkout].self, "weekGymLog") ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard let day = weekdayDay(name) else { skip("workouts.unknownWeekday"); continue }
            let workout = legacy.workoutDay(day, at: now)
            guard !workout.isEmpty else { continue }
            guard !workoutDays.contains(day) else { skip("workouts.supersededWeekdayLog"); continue }
            plan.workouts.append(workout)
            workoutDays.insert(day)
            plan.report.inferredFromWeekday += 1
        }

        // Todos: [weekday: [TodoItem]]
        var seenTasks = Set<UUID>()
        var weekTodos: [(day: DayKey, todos: [Legacy.TodoItem])] = []
        for (name, todos) in decode([String: [Legacy.TodoItem]].self, "weekTodoList") ?? [:] {
            guard let day = weekdayDay(name) else { skip("tasks.unknownWeekday", todos.count); continue }
            weekTodos.append((day, todos))
        }
        for (day, todos) in weekTodos.sorted(by: { $0.day < $1.day }) {
            for (index, todo) in todos.enumerated() {
                plan.legacyTaskIDs.insert(todo.id)
                plan.legacyTaskDays.insert(day)
                var id = todo.id
                if !seenTasks.insert(todo.id).inserted {
                    id = StableID.make("legacy-task", todo.id.uuidString, day.rawValue, String(index))
                    reassign(TaskItem.collection)
                }
                plan.tasks.append(TaskItem(id: id, dayKey: day, title: todo.title,
                                           isCompleted: todo.isCompleted, completedAt: nil,
                                           reminderAt: todo.reminderDate, createdAt: now, source: .manual))
                plan.report.inferredFromWeekday += 1
            }
        }

        // Protein checklist: [weekday: DayMeals]
        for (name, meals) in decode([String: Legacy.DayMeals].self, "weekFoodLog") ?? [:] {
            guard let day = weekdayDay(name) else { skip("proteinChecklist.unknownWeekday"); continue }
            let checklist = ProteinChecklist(dayKey: day, breakfast: meals.breakfast, lunch: meals.lunch,
                                             dinner: meals.dinner, snacks: meals.snacks)
            guard !checklist.isEmpty else { continue }
            plan.proteinChecklist.append(checklist)
            plan.report.inferredFromWeekday += 1
        }

        // Water: waterCount_<yyyy-MM-dd>
        for (key, glasses) in snapshot.waterCounts {
            guard let day = DayKey(key) else { skip("water.badDate"); continue }
            guard glasses > 0 else { continue }
            plan.water.append(WaterDay(dayKey: day, glasses: glasses, source: .manual,
                                       updatedAt: day.startDate(timeZone: timeZone)))
        }

        // Weight history: one point per day.
        for (key, kg) in snapshot.weightHistory {
            guard let day = DayKey(key) else { skip("weight.badDate"); continue }
            guard kg > 0, kg.isFinite else { skip("weight.invalidValue"); continue }
            plan.weight.append(WeightEntry(
                id: StableID.make("weight", day.rawValue, EntrySource.manual.rawValue), dayKey: day,
                measuredAt: day.startDate(timeZone: timeZone).addingTimeInterval(12 * 3600),
                kg: kg, source: .manual))
        }

        // Daily summaries (streak history can't be recomputed, so keep it).
        for (_, summary) in decode([String: DailySummary].self, "dailySummaries") ?? [:] {
            guard DayKey(summary.date) != nil else { skip("dailySummaries.badDate"); continue }
            plan.summaries.append(summary)
        }

        plan.profile = decode(UserProfile.self, "userProfile")

        let recent = decode([Legacy.FoodItem].self, "recentFoods")
        let favorites = decode([Legacy.FoodItem].self, "favoriteFoods")
        let custom = decode([Legacy.FoodItem].self, "customFoods")
        if recent != nil || favorites != nil || custom != nil {
            plan.foodLibrary = FoodLibrary(recent: (recent ?? []).map(\.template),
                                           favorites: (favorites ?? []).map(\.template),
                                           custom: (custom ?? []).map(\.template))
        }

        // Deterministic order makes reruns and diffs stable.
        plan.food.sort { ($0.dayKey, $0.loggedAt.timeIntervalSinceReferenceDate, $0.id.uuidString)
            < ($1.dayKey, $1.loggedAt.timeIntervalSinceReferenceDate, $1.id.uuidString) }
        plan.workouts.sort { $0.dayKey < $1.dayKey }
        plan.water.sort { $0.dayKey < $1.dayKey }
        plan.weight.sort { $0.dayKey < $1.dayKey }
        plan.tasks.sort { ($0.dayKey, $0.id.uuidString) < ($1.dayKey, $1.id.uuidString) }
        plan.proteinChecklist.sort { $0.dayKey < $1.dayKey }
        plan.summaries.sort { $0.date < $1.date }

        plan.report.counts = [
            FoodEntry.collection: plan.food.count,
            WorkoutDay.collection: plan.workouts.count,
            WaterDay.collection: plan.water.count,
            WeightEntry.collection: plan.weight.count,
            TaskItem.collection: plan.tasks.count,
            ProteinChecklist.collection: plan.proteinChecklist.count,
            DailySummary.collection: plan.summaries.count,
            "profile": plan.profile == nil ? 0 : 1,
            "foodLibrary": plan.foodLibrary == nil ? 0 : 1
        ]
        return plan
    }
}
