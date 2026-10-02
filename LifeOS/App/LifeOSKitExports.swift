// Makes the shared LifeOSKit core visible to every file in the app target,
// so moved types (BodyPart, MealType, Exercise, UserProfile, DailySummary, the
// calculators…) resolve without per-file imports. See docs/adr/0002-module-structure.md.
@_exported import LifeOSCore
// `Log.<category>` is an os.Logger. Re-export `os` so its interpolation
// (`privacy: .private`) resolves under MemberImportVisibility.
@_exported import os

// MARK: - Legacy adapters (delete with DayWorkout once workouts use LifeOSData, FND-05)

extension CalorieCalculator {
    /// MET estimate for the legacy weekday-keyed `DayWorkout`. Same maths as
    /// `totalWorkoutCalories(workout: WorkoutDay, weightKg:)`.
    static func totalWorkoutCalories(workout: DayWorkout, weightKg: Double) -> Double {
        var total = workout.exercises.reduce(0.0) {
            $0 + caloriesPerSet(bodyPart: $1.bodyPart, weightKg: weightKg) * Double($1.setsCompleted)
        }
        if workout.treadmillDone {
            total += treadmillCalories(weightKg: weightKg, durationMinutes: workout.treadmillDuration)
        }
        return total
    }
}
