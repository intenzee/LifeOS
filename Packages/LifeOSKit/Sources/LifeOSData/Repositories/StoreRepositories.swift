import Foundation
import LifeOSCore

// Repository implementations over `RecordStore` / `DocumentStore`. The same
// types back tests: give `LifeOSDatabase.inMemory()` an in-memory backend.

struct StoreFoodLogRepository: FoodLogRepository {
    let store: RecordStore<FoodEntry>

    func entries(on day: DayKey) async throws -> [FoodEntry] { try await store.records(on: day) }
    func entries(from start: DayKey, through end: DayKey) async throws -> [FoodEntry] {
        try await store.records(from: start, through: end)
    }
    func save(_ entry: FoodEntry) async throws { try await store.upsert(entry) }
    func delete(id: UUID, on day: DayKey) async throws -> Bool { try await store.delete(id: id, on: day) }
}

struct StoreWorkoutRepository: WorkoutRepository {
    let store: RecordStore<WorkoutDay>

    func day(_ day: DayKey) async throws -> WorkoutDay {
        try await store.record(id: day, on: day) ?? WorkoutDay(dayKey: day)
    }
    func days(from start: DayKey, through end: DayKey) async throws -> [WorkoutDay] {
        try await store.records(from: start, through: end)
    }
    func save(_ workout: WorkoutDay) async throws {
        if workout.isEmpty {
            try await store.delete(id: workout.dayKey, on: workout.dayKey)
        } else {
            try await store.upsert(workout)
        }
    }
}

struct StoreWaterRepository: WaterRepository {
    let store: RecordStore<WaterDay>

    func glasses(on day: DayKey) async throws -> Int {
        try await store.record(id: day, on: day)?.glasses ?? 0
    }
    func setGlasses(_ glasses: Int, on day: DayKey, source: EntrySource) async throws {
        if glasses <= 0 {
            try await store.delete(id: day, on: day)
        } else {
            try await store.upsert(WaterDay(dayKey: day, glasses: glasses, source: source))
        }
    }
    func days(from start: DayKey, through end: DayKey) async throws -> [WaterDay] {
        try await store.records(from: start, through: end)
    }
}

struct StoreWeightRepository: WeightRepository {
    let store: RecordStore<WeightEntry>

    func entries(from start: DayKey, through end: DayKey) async throws -> [WeightEntry] {
        try await store.records(from: start, through: end)
    }

    func setDailyWeight(_ kg: Double, on day: DayKey, measuredAt: Date, source: EntrySource) async throws {
        guard kg > 0, kg.isFinite else {
            throw AppError(.invalidInput, userMessage: "Enter a weight above zero.", category: .data)
        }
        let existing = try await store.records(on: day).first { $0.source == source && $0.healthKitUUID == nil }
        let entry = WeightEntry(id: existing?.id ?? StableID.make("weight", day.rawValue, source.rawValue),
                                dayKey: day, measuredAt: measuredAt, kg: kg, source: source)
        try await store.upsert(entry)
    }

    func latest(onOrBefore day: DayKey, lookbackDays: Int) async throws -> WeightEntry? {
        try await store.records(from: day.adding(days: -lookbackDays), through: day)
            .max { ($0.dayKey, $0.measuredAt) < ($1.dayKey, $1.measuredAt) }
    }
}

struct StoreTaskRepository: TaskRepository {
    let store: RecordStore<TaskItem>

    func tasks(on day: DayKey) async throws -> [TaskItem] { try await store.records(on: day) }
    func tasks(from start: DayKey, through end: DayKey) async throws -> [TaskItem] {
        try await store.records(from: start, through: end)
    }
    func save(_ task: TaskItem) async throws { try await store.upsert(task) }
    func delete(id: UUID, on day: DayKey) async throws -> Bool { try await store.delete(id: id, on: day) }
}

struct StoreProteinChecklistRepository: ProteinChecklistRepository {
    let store: RecordStore<ProteinChecklist>

    func checklist(on day: DayKey) async throws -> ProteinChecklist {
        try await store.record(id: day, on: day) ?? ProteinChecklist(dayKey: day)
    }
    func save(_ checklist: ProteinChecklist) async throws {
        if checklist.isEmpty {
            try await store.delete(id: checklist.dayKey, on: checklist.dayKey)
        } else {
            try await store.upsert(checklist)
        }
    }
}

struct StoreSummaryRepository: SummaryRepository {
    let store: RecordStore<DailySummary>

    func summary(on day: DayKey) async throws -> DailySummary? {
        try await store.record(id: day.rawValue, on: day)
    }
    func summaries(from start: DayKey, through end: DayKey) async throws -> [DailySummary] {
        try await store.records(from: start, through: end)
    }
    func save(_ summary: DailySummary) async throws {
        guard DayKey(summary.date) != nil else {
            throw AppError(.invalidInput, userMessage: "Invalid summary date.", category: .data)
        }
        try await store.upsert(summary)
    }
}

struct StoreProfileRepository: ProfileRepository {
    let store: DocumentStore<UserProfile>

    func load() async throws -> UserProfile? { try await store.load() }
    func save(_ profile: UserProfile) async throws { try await store.save(profile) }
}

struct StoreFoodLibraryRepository: FoodLibraryRepository {
    let store: DocumentStore<FoodLibrary>

    func load() async throws -> FoodLibrary { try await store.load() ?? FoodLibrary() }
    func save(_ library: FoodLibrary) async throws { try await store.save(library) }
}

struct StoreMealCorrectionRepository: MealCorrectionRepository {
    let store: DocumentStore<CorrectionLibrary>

    func load() async throws -> CorrectionLibrary { try await store.load() ?? CorrectionLibrary() }
    func save(_ library: CorrectionLibrary) async throws { try await store.save(library) }
    func exists() async throws -> Bool { try await store.load() != nil }
}
