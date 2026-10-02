import Foundation

/// MET-based estimate of training energy. Moved unchanged from the app target.
///
/// This is the C2 estimate (2.5 min per set). Doc 02/03 replace it with Apple
/// Watch / HealthKit energy in P1. Until then it stays the only source.
public enum CalorieCalculator {
    public static let exerciseMETs: [BodyPart: Double] = [
        .chest: 6.0,
        .back: 6.0,
        .shoulders: 5.5,
        .arms: 5.0,
        .legs: 6.5,
        .abs: 5.0,
        .cardio: 8.0
    ]

    public static func caloriesPerSet(bodyPart: BodyPart, weightKg: Double) -> Double {
        let met = exerciseMETs[bodyPart] ?? 5.0
        let durationMinutes = 2.5
        return (met * 3.5 * weightKg / 200.0) * durationMinutes
    }

    public static func treadmillCalories(weightKg: Double, durationMinutes: Double) -> Double {
        let met = 8.5
        return (met * 3.5 * weightKg / 200.0) * durationMinutes
    }

    public static func totalWorkoutCalories(workout: WorkoutDay, weightKg: Double) -> Double {
        var total = workout.exercises.reduce(0.0) {
            $0 + caloriesPerSet(bodyPart: $1.bodyPart, weightKg: weightKg) * Double($1.setsCompleted)
        }
        if workout.treadmillDone {
            total += treadmillCalories(weightKg: weightKg, durationMinutes: workout.treadmillMinutes)
        }
        return total
    }
}

/// Training intensity bucket used by streaks. Raw values are persisted in
/// `DailySummary.gymIntensity`.
public enum WorkoutIntensity: String, Codable, Sendable, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case rest = "Rest"

    /// Same thresholds as the legacy `DayWorkout.intensity(weightKg:)`.
    public init(estimatedCalories: Double) {
        switch estimatedCalories {
        case 450...: self = .high
        case 300..<450: self = .medium
        case 120..<300: self = .low
        default: self = .rest
        }
    }

    public init(workout: WorkoutDay, weightKg: Double) {
        self.init(estimatedCalories: CalorieCalculator.totalWorkoutCalories(workout: workout, weightKg: weightKg))
    }
}
