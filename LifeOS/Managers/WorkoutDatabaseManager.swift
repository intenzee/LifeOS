import Foundation
import Combine
import LifeOSData

/// Manual strength/treadmill logs.
///
/// Since FND-04/05 workouts are `WorkoutDay` records keyed by real date in
/// LifeOSData. The weekday-name methods remain for the week picker:
/// "Monday" is the Monday of the *current* week. History is never deleted.
/// (`checkWeeklyReset` used to wipe Sunday every Monday.)
final class WorkoutDatabaseManager: ObservableObject {
    static let shared = WorkoutDatabaseManager()

    /// Keyed by `DayKey.rawValue` (`yyyy-MM-dd`). Views may edit an entry and
    /// then call `saveAllWorkoutsPublic()`.
    @Published var allDailyWorkouts: [String: DayWorkout] = [:]
    @Published var selectedDate: Date = Date()

    private weak var store: LocalStore?
    /// What's on disk, to save only changed days.
    private var persisted: [String: DayWorkout] = [:]

    private init() {}

    func load(from snapshot: DataSnapshot, store: LocalStore) {
        self.store = store
        let loaded = Dictionary(snapshot.workouts.map { ($0.dayKey.rawValue, DayWorkout($0)) },
                                uniquingKeysWith: { _, last in last })
        persisted = loaded
        allDailyWorkouts = loaded
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        objectWillChange.send()
    }

    /// The workout for the browsed date (any week, not only the current one).
    var dailyWorkout: DayWorkout {
        workout(on: DayKey.make(for: selectedDate))
    }

    func getTotalCaloriesBurned(weight: Double) -> Double {
        CalorieCalculator.totalWorkoutCalories(workout: dailyWorkout, weightKg: weight)
    }

    func getCaloriesBurnedForDay(_ day: String, weightKg: Double) -> Double {
        CalorieCalculator.totalWorkoutCalories(workout: loadWorkoutForDay(day), weightKg: weightKg)
    }

    // MARK: Date API

    func workout(on day: DayKey) -> DayWorkout {
        allDailyWorkouts[day.rawValue] ?? DayWorkout()
    }

    /// Applies `change` to the workout on `day` and saves it.
    func updateWorkout(on day: DayKey, _ change: (inout DayWorkout) -> Void) {
        var workout = workout(on: day)
        change(&workout)
        replaceWorkout(workout, on: day)
    }

    func replaceWorkout(_ workout: DayWorkout, on day: DayKey) {
        allDailyWorkouts[day.rawValue] = workout
        saveAllWorkouts()
    }

    // MARK: Week-picker API (weekday names → current week)

    func loadWorkoutForDay(_ day: String) -> DayWorkout {
        allDailyWorkouts[dayToDateKey(day)] ?? DayWorkout()
    }

    func toggleTreadmillForDay(_ day: String, durationMinutes: Double) {
        mutate(day) {
            $0.treadmillDone.toggle()
            $0.treadmillDuration = durationMinutes
        }
    }

    func cycleExerciseSetsForDay(_ day: String, exerciseId: UUID) {
        mutate(day) { workout in
            guard let index = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
            let current = workout.exercises[index].setsCompleted
            let max = workout.exercises[index].maxSets
            workout.exercises[index].setsCompleted = (current + 1) % (max + 1)
        }
    }

    /// Sets an exercise's completed sets to an absolute value, clamped to
    /// `0...maxSets`. The Watch auto-set tracker reports totals.
    func setExerciseSetsForDay(_ day: String, exerciseId: UUID, setsCompleted: Int) {
        mutate(day) { workout in
            guard let index = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
            workout.exercises[index].setsCompleted = min(max(setsCompleted, 0), workout.exercises[index].maxSets)
        }
    }

    func deleteExerciseForDay(_ day: String, exerciseId: UUID) {
        mutate(day) { $0.exercises.removeAll { $0.id == exerciseId } }
    }

    func addExerciseForDay(_ day: String, exercise: Exercise) {
        mutate(day) { $0.exercises.append(exercise) }
    }

    func dayToDateKeyPublic(_ dayName: String) -> String {
        dayToDateKey(dayName)
    }

    func saveAllWorkoutsPublic() {
        saveAllWorkouts()
    }

    // MARK: Private

    private func mutate(_ dayName: String, _ change: (inout DayWorkout) -> Void) {
        let key = dayToDateKey(dayName)
        var workout = allDailyWorkouts[key] ?? DayWorkout()
        change(&workout)
        allDailyWorkouts[key] = workout
        saveAllWorkouts()
    }

    /// "Monday" → this week's Monday as `yyyy-MM-dd`. Unknown names fall back to today.
    private func dayToDateKey(_ dayName: String) -> String {
        (WeekDays.dayKey(for: dayName) ?? .today()).rawValue
    }

    /// Persists every day that differs from what's on disk.
    private func saveAllWorkouts() {
        objectWillChange.send()
        let changed = allDailyWorkouts.filter { persisted[$0.key] != $0.value }
        let removed = Set(persisted.keys).subtracting(allDailyWorkouts.keys)
        guard !changed.isEmpty || !removed.isEmpty else { return }
        persisted = allDailyWorkouts

        guard let store else {
            Log.data.fault("Workout change before the store was ready was not saved")
            return
        }
        let records = changed.compactMap { key, workout in DayKey(key).map { workout.record(on: $0) } }
        let removedDays = removed.compactMap(DayKey.init)
        let db = store.database
        store.enqueue {
            for record in records { try await db.workouts.save(record) }
            for day in removedDays { try await db.workouts.save(WorkoutDay(dayKey: day)) } // empty = delete
        }
    }
}
