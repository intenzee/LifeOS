import Foundation

final class CalorieCalculator {
    static let exerciseMETs: [BodyPart: Double] = [
        .chest: 6.0,
        .back: 6.0,
        .shoulders: 5.5,
        .arms: 5.0,
        .legs: 6.5,
        .abs: 5.0,
        .cardio: 8.0
    ]

    static func caloriesPerSet(bodyPart: BodyPart, weightKg: Double) -> Double {
        let met = exerciseMETs[bodyPart] ?? 5.0
        let durationMinutes = 2.5
        return (met * 3.5 * weightKg / 200.0) * durationMinutes
    }

    static func treadmillCalories(weightKg: Double, durationMinutes: Double) -> Double {
        let met = 8.5
        return (met * 3.5 * weightKg / 200.0) * durationMinutes
    }

    static func totalWorkoutCalories(workout: DayWorkout, weightKg: Double) -> Double {
        var total: Double = 0

        for exercise in workout.exercises {
            let caloriesPerSet = caloriesPerSet(bodyPart: exercise.bodyPart, weightKg: weightKg)
            total += caloriesPerSet * Double(exercise.setsCompleted)
        }

        if workout.treadmillDone {
            total += treadmillCalories(weightKg: weightKg, durationMinutes: workout.treadmillDuration)
        }

        return total
    }
}