#if DEBUG
import Foundation
import LifeOSCore

/// DEBUG-only helper that seeds a realistic day of data so the populated UI
/// states (filled orb, timeline, macros, workout) can be reviewed on device.
///
/// Triggered by the `LX_SEED_SAMPLE_DAY` launch argument and idempotent — it
/// clears today's existing food first, so repeated launches don't pile up. No
/// production code path reaches it.
enum SampleDaySeeder {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("LX_SEED_SAMPLE_DAY")
    }

    static var clearRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("LX_CLEAR_SAMPLE_DAY")
    }

    /// The sample meals. Logging adds them to Recent foods too, so `clear` removes
    /// exactly these (same name, calories and serving) from there as well.
    private static var sampleFoods: [FoodItem] {
        [
            FoodItem(name: "Greek Yogurt & Berries", calories: 240, protein: 20, carbs: 28, fat: 6,
                     servingSize: "1 bowl", mealType: .breakfast),
            FoodItem(name: "Scrambled Eggs", calories: 220, protein: 16, carbs: 2, fat: 16,
                     servingSize: "3 eggs", mealType: .breakfast),
            FoodItem(name: "Grilled Chicken Salad", calories: 430, protein: 38, carbs: 22, fat: 20,
                     servingSize: "1 plate", mealType: .lunch),
            FoodItem(name: "Protein Shake", calories: 180, protein: 30, carbs: 8, fat: 3,
                     servingSize: "1 scoop", mealType: .snacks),
        ]
    }

    /// Removes everything `seed` added for today, restoring an empty day.
    @MainActor
    static func clear(_ dependencies: AppDependencies) {
        let food = dependencies.foodDatabase
        food.selectDate(Date())
        let existing = food.dailyLog.breakfast + food.dailyLog.lunch
            + food.dailyLog.dinner + food.dailyLog.snacks
        existing.forEach { food.removeFood($0.id) }
        let samples = sampleFoods
        food.removeRecents { recent in
            samples.contains { $0.name == recent.name && $0.calories == recent.calories && $0.servingSize == recent.servingSize }
        }
        dependencies.dailyMetricsRepository.saveWaterCount(0, for: Date())
        dependencies.workoutDatabase.replaceWorkout(DayWorkout(), on: DayKey.make(for: Date()))
        NotificationCenter.default.post(name: .watchDidMutateData, object: nil)
    }

    @MainActor
    static func seed(_ dependencies: AppDependencies) {
        let food = dependencies.foodDatabase
        food.selectDate(Date())

        // Idempotent: clear today's existing items first.
        let existing = food.dailyLog.breakfast + food.dailyLog.lunch
            + food.dailyLog.dinner + food.dailyLog.snacks
        existing.forEach { food.removeFood($0.id) }

        sampleFoods.forEach { food.addFood($0) }

        // Water and a logged strength session for today.
        dependencies.dailyMetricsRepository.saveWaterCount(6, for: Date())
        let workout = DayWorkout(exercises: [
            Exercise(bodyPart: .chest, name: "Bench Press", setsCompleted: 3, maxSets: 4),
            Exercise(bodyPart: .back, name: "Lat Pulldown", setsCompleted: 3, maxSets: 3),
            Exercise(bodyPart: .arms, name: "Dumbbell Curl", setsCompleted: 2, maxSets: 3),
        ], treadmillDone: true, treadmillDuration: 15)
        dependencies.workoutDatabase.replaceWorkout(workout, on: DayKey.make(for: Date()))

        // Nudge the experience store / widgets / watch to re-read.
        NotificationCenter.default.post(name: .watchDidMutateData, object: nil)
    }
}
#endif
