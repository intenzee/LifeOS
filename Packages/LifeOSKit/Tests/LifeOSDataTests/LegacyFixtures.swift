import Foundation
import LifeOSCore
@testable import LifeOSData

/// Encodable copies of the pre-P0 app types, field-for-field, so fixture
/// blobs have exactly the shape the shipping app wrote to UserDefaults.
enum LegacyFixture {
    struct FoodItem: Encodable {
        var id = UUID()
        var name: String
        var calories: Double
        var protein: Double = 0
        var carbs: Double = 0
        var fat: Double = 0
        var servingSize = "1 serving"
        var barcode: String?
        var mealType: String
        var timestamp: Date
    }

    struct DailyFoodLog: Encodable {
        var breakfast: [FoodItem] = []
        var lunch: [FoodItem] = []
        var dinner: [FoodItem] = []
        var snacks: [FoodItem] = []
    }

    struct Exercise: Encodable {
        var id = UUID()
        var bodyPart: String
        var name: String?
        var setsCompleted: Int
        var maxSets = 3
    }

    struct DayWorkout: Encodable {
        var exercises: [Exercise] = []
        var treadmillDone = false
        var treadmillDuration = 20.0
    }

    struct DayMeals: Encodable {
        var breakfast = false
        var lunch = false
        var dinner = false
        var snacks = false
    }

    struct TodoItem: Encodable {
        var id = UUID()
        var title: String
        var isCompleted = false
        var reminderDate: Date?
    }

    static func blob(_ value: some Encodable) -> Data {
        try! JSONEncoder().encode(value) // swiftlint:disable:this force_try
    }

    static let now = Date(timeIntervalSince1970: 1_791_100_800) // 2026-10-04T08:00:00Z, a Sunday
    static let utc = TimeZone(identifier: "UTC")!

    /// A small but complete snapshot touching every legacy key.
    static func complete() -> (snapshot: LegacySnapshot, foodIDs: [UUID], todoIDs: [UUID]) {
        let oats = FoodItem(name: "Oatmeal (1 cup)", calories: 150, protein: 5, carbs: 27, fat: 3,
                            servingSize: "1 cup", mealType: "Breakfast", timestamp: now.addingTimeInterval(-86_400))
        let bar = FoodItem(name: "Protein bar", calories: 210, protein: 20, barcode: "4006381333931",
                           mealType: "Snacks", timestamp: now.addingTimeInterval(-86_000))
        let rice = FoodItem(name: "Rice", calories: 216, mealType: "Lunch", timestamp: now.addingTimeInterval(-3 * 86_400))
        let foodLogs: [String: DailyFoodLog] = [
            "2026-10-03": DailyFoodLog(breakfast: [oats], snacks: [bar]),
            "2026-10-01": DailyFoodLog(lunch: [rice]),
            "garbage": DailyFoodLog(lunch: [FoodItem(name: "X", calories: 1, mealType: "Lunch", timestamp: now)])
        ]
        let workouts: [String: DayWorkout] = [
            "2026-10-02": DayWorkout(exercises: [Exercise(bodyPart: "Chest", name: "Bench Press", setsCompleted: 3)]),
            "2026-09-30": DayWorkout(exercises: [], treadmillDone: true, treadmillDuration: 30),
            "2026-09-29": DayWorkout() // empty, dropped
        ]
        let weekGym: [String: DayWorkout] = [
            "Friday": DayWorkout(exercises: [Exercise(bodyPart: "Legs", setsCompleted: 1)]), // 10-02 exists → superseded
            "Monday": DayWorkout(exercises: [Exercise(bodyPart: "Back", setsCompleted: 2)])  // 09-28 gap → imported
        ]
        let gym = TodoItem(title: "Gym", isCompleted: true)
        let call = TodoItem(title: "Call mum")
        let todos: [String: [TodoItem]] = ["Sunday": [gym], "Monday": [call], "Tuesday": [], "Blursday": [TodoItem(title: "?")]]
        let meals: [String: DayMeals] = ["Saturday": DayMeals(breakfast: true, dinner: true), "Monday": DayMeals()]
        let summaries: [String: DailySummary] = [
            "2026-10-03": DailySummary(date: "2026-10-03", caloriesConsumed: 1800, calorieLimit: 2000, waterGlasses: 8,
                                       waterTarget: 8, gymIntensity: "High", todosCompleted: 1, todosTotal: 1)
        ]
        let profile = UserProfile(age: 30, heightCm: 175, currentWeightKg: 78, targetWeightKg: 72,
                                  wakeTime: now, sleepTime: now, completedAt: now)
        let recent = [FoodItem(name: "Banana", calories: 105, mealType: "Breakfast", timestamp: now)]

        let snapshot = LegacySnapshot(
            capturedAt: now,
            blobs: [
                "allDailyFoodLogs": blob(foodLogs),
                "allDailyWorkouts": blob(workouts),
                "weekGymLog": blob(weekGym),
                "weekTodoList": blob(todos),
                "weekFoodLog": blob(meals),
                "dailySummaries": blob(summaries),
                "userProfile": blob(profile),
                "recentFoods": blob(recent),
                "customFoods": Data("not json".utf8)
            ],
            waterCounts: ["2026-10-03": 6, "2026-10-02": 0, "bad": 3],
            weightHistory: ["2026-10-01": 78.4, "2026-10-03": 78.1, "2026-10-02": -1]
        )
        return (snapshot, [oats.id, bar.id, rice.id], [gym.id, call.id])
    }

    /// `days` days of heavy logging ending on `now`: 6 foods, a workout, water,
    /// weight and a summary per day.
    static func heavyLogger(days: Int) -> LegacySnapshot {
        let end = DayKey.make(for: now, timeZone: utc)
        var foodLogs: [String: DailyFoodLog] = [:]
        var workouts: [String: DayWorkout] = [:]
        var summaries: [String: DailySummary] = [:]
        var water: [String: Int] = [:]
        var weights: [String: Double] = [:]
        for offset in 0..<days {
            let day = end.adding(days: -offset)
            let stamp = day.startDate(timeZone: utc).addingTimeInterval(9 * 3600)
            func item(_ meal: String, _ index: Int) -> FoodItem {
                FoodItem(name: "\(meal) item \(index)", calories: Double(100 + index), protein: 10, carbs: 20, fat: 5,
                         mealType: meal, timestamp: stamp)
            }
            foodLogs[day.rawValue] = DailyFoodLog(breakfast: [item("Breakfast", 1), item("Breakfast", 2)],
                                                  lunch: [item("Lunch", 1), item("Lunch", 2)],
                                                  dinner: [item("Dinner", 1)], snacks: [item("Snacks", 1)])
            workouts[day.rawValue] = DayWorkout(exercises: [Exercise(bodyPart: "Legs", setsCompleted: 3),
                                                            Exercise(bodyPart: "Arms", setsCompleted: 2)])
            summaries[day.rawValue] = DailySummary(date: day.rawValue, caloriesConsumed: 1900, calorieLimit: 2100,
                                                   waterGlasses: 7, waterTarget: 8, gymIntensity: "Low",
                                                   todosCompleted: 2, todosTotal: 3)
            water[day.rawValue] = 7
            weights[day.rawValue] = 80 - Double(offset) * 0.01
        }
        return LegacySnapshot(capturedAt: now,
                              blobs: ["allDailyFoodLogs": blob(foodLogs), "allDailyWorkouts": blob(workouts),
                                      "dailySummaries": blob(summaries)],
                              waterCounts: water, weightHistory: weights)
    }
}
