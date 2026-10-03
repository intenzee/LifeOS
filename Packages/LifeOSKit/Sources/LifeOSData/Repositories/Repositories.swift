import Foundation
import LifeOSCore

// Repository protocols (FND-03). Feature code depends on these, never on the
// storage engine, so the engine can later be swapped (e.g. for SwiftData)
// without touching callers. Every method takes a `DayKey` or a `Date`.
// There are no weekday names anywhere (FND-05).

public protocol FoodLogRepository: Sendable {
    func entries(on day: DayKey) async throws -> [FoodEntry]
    func entries(from start: DayKey, through end: DayKey) async throws -> [FoodEntry]
    /// Inserts or replaces by id.
    func save(_ entry: FoodEntry) async throws
    @discardableResult func delete(id: UUID, on day: DayKey) async throws -> Bool
}

public protocol WorkoutRepository: Sendable {
    /// The day's log, or an empty one.
    func day(_ day: DayKey) async throws -> WorkoutDay
    func days(from start: DayKey, through end: DayKey) async throws -> [WorkoutDay]
    func save(_ workout: WorkoutDay) async throws
}

public protocol WaterRepository: Sendable {
    func glasses(on day: DayKey) async throws -> Int
    func setGlasses(_ glasses: Int, on day: DayKey, source: EntrySource) async throws
    func days(from start: DayKey, through end: DayKey) async throws -> [WaterDay]
}

public protocol WeightRepository: Sendable {
    func entries(from start: DayKey, through end: DayKey) async throws -> [WeightEntry]
    /// One reading per day per source: replaces that day's reading from `source`.
    func setDailyWeight(_ kg: Double, on day: DayKey, measuredAt: Date, source: EntrySource) async throws
    /// Most recent reading on or before `day`, searching back `lookbackDays`.
    func latest(onOrBefore day: DayKey, lookbackDays: Int) async throws -> WeightEntry?
}

public protocol TaskRepository: Sendable {
    func tasks(on day: DayKey) async throws -> [TaskItem]
    func tasks(from start: DayKey, through end: DayKey) async throws -> [TaskItem]
    func save(_ task: TaskItem) async throws
    @discardableResult func delete(id: UUID, on day: DayKey) async throws -> Bool
}

public protocol ProteinChecklistRepository: Sendable {
    func checklist(on day: DayKey) async throws -> ProteinChecklist
    func save(_ checklist: ProteinChecklist) async throws
}

public protocol SummaryRepository: Sendable {
    func summary(on day: DayKey) async throws -> DailySummary?
    func summaries(from start: DayKey, through end: DayKey) async throws -> [DailySummary]
    func save(_ summary: DailySummary) async throws
}

public protocol ProfileRepository: Sendable {
    func load() async throws -> UserProfile?
    func save(_ profile: UserProfile) async throws
}

public protocol FoodLibraryRepository: Sendable {
    func load() async throws -> FoodLibrary
    func save(_ library: FoodLibrary) async throws
}

/// The meal scanner's learned corrections (FOOD-14).
public protocol MealCorrectionRepository: Sendable {
    func load() async throws -> CorrectionLibrary
    func save(_ library: CorrectionLibrary) async throws
    /// `false` until the first save, so the legacy file is migrated exactly once.
    func exists() async throws -> Bool
}

// MARK: - Workout mutations
//
// Date-keyed replacements for WorkoutDatabaseManager's weekday-name methods
// (`addExerciseForDay("Monday", …)` → `addExercise(…, on: dayKey)`).

public extension WorkoutRepository {
    func addExercise(_ exercise: Exercise, on day: DayKey) async throws {
        var workout = try await self.day(day)
        workout.exercises.append(exercise)
        workout.updatedAt = Date()
        try await save(workout)
    }

    func deleteExercise(id: UUID, on day: DayKey) async throws {
        var workout = try await self.day(day)
        workout.exercises.removeAll { $0.id == id }
        workout.updatedAt = Date()
        try await save(workout)
    }

    /// 0 → 1 → … → maxSets → 0, like tapping the set ring.
    func cycleSets(exerciseID: UUID, on day: DayKey) async throws {
        var workout = try await self.day(day)
        guard let index = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let exercise = workout.exercises[index]
        workout.exercises[index].setsCompleted = (exercise.setsCompleted + 1) % (exercise.maxSets + 1)
        workout.updatedAt = Date()
        try await save(workout)
    }

    /// Absolute set count, clamped to `0...maxSets` (the Watch reports totals).
    func setSets(_ sets: Int, exerciseID: UUID, on day: DayKey) async throws {
        var workout = try await self.day(day)
        guard let index = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        workout.exercises[index].setsCompleted = min(max(sets, 0), workout.exercises[index].maxSets)
        workout.updatedAt = Date()
        try await save(workout)
    }

    func toggleTreadmill(minutes: Double, on day: DayKey) async throws {
        var workout = try await self.day(day)
        workout.treadmillDone.toggle()
        workout.treadmillMinutes = minutes
        workout.updatedAt = Date()
        try await save(workout)
    }
}

public extension TaskRepository {
    func toggleCompletion(id: UUID, on day: DayKey, at now: Date = Date()) async throws {
        guard var task = try await tasks(on: day).first(where: { $0.id == id }) else { return }
        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? now : nil
        try await save(task)
    }
}

public extension FoodLibraryRepository {
    func update(_ mutate: @Sendable (inout FoodLibrary) -> Void) async throws {
        var library = try await load()
        mutate(&library)
        try await save(library)
    }
}
