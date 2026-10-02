import Foundation
import LifeOSCore

/// Decoding mirrors of the pre-P0 app types stored as JSON blobs in UserDefaults.
/// They decode leniently (`decodeIfPresent` + legacy defaults), so one missing
/// field never blocks a whole migration.
enum Legacy {
    struct FoodItem: Codable, Equatable {
        var id: UUID
        var name: String
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var servingSize: String
        var barcode: String?
        var mealType: MealType
        var timestamp: Date

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            calories = try c.decodeIfPresent(Double.self, forKey: .calories) ?? 0
            protein = try c.decodeIfPresent(Double.self, forKey: .protein) ?? 0
            carbs = try c.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
            fat = try c.decodeIfPresent(Double.self, forKey: .fat) ?? 0
            servingSize = try c.decodeIfPresent(String.self, forKey: .servingSize) ?? "1 serving"
            barcode = try c.decodeIfPresent(String.self, forKey: .barcode)
            mealType = try c.decodeIfPresent(MealType.self, forKey: .mealType) ?? .snacks
            timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date(timeIntervalSinceReferenceDate: 0)
        }

        var template: FoodTemplate {
            FoodTemplate(id: id, name: name, calories: calories, protein: protein, carbs: carbs, fat: fat,
                         servingSize: servingSize, barcode: barcode, defaultMeal: mealType)
        }
    }

    struct DailyFoodLog: Codable {
        var breakfast: [FoodItem]
        var lunch: [FoodItem]
        var dinner: [FoodItem]
        var snacks: [FoodItem]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            breakfast = try c.decodeIfPresent([FoodItem].self, forKey: .breakfast) ?? []
            lunch = try c.decodeIfPresent([FoodItem].self, forKey: .lunch) ?? []
            dinner = try c.decodeIfPresent([FoodItem].self, forKey: .dinner) ?? []
            snacks = try c.decodeIfPresent([FoodItem].self, forKey: .snacks) ?? []
        }

        /// Items with the slot they were filed under (the list wins over `mealType`).
        var slotted: [(MealType, FoodItem)] {
            breakfast.map { (.breakfast, $0) } + lunch.map { (.lunch, $0) }
                + dinner.map { (.dinner, $0) } + snacks.map { (.snacks, $0) }
        }
    }

    struct Exercise: Codable {
        var id: UUID
        var bodyPart: BodyPart
        var name: String?
        var setsCompleted: Int
        var maxSets: Int

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            bodyPart = try c.decode(BodyPart.self, forKey: .bodyPart)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            setsCompleted = try c.decodeIfPresent(Int.self, forKey: .setsCompleted) ?? 0
            maxSets = try c.decodeIfPresent(Int.self, forKey: .maxSets) ?? 3
        }

        var current: LifeOSCore.Exercise {
            LifeOSCore.Exercise(id: id, bodyPart: bodyPart, name: name, setsCompleted: setsCompleted, maxSets: maxSets)
        }
    }

    struct DayWorkout: Codable {
        var exercises: [Exercise]
        var treadmillDone: Bool
        var treadmillDuration: Double

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            exercises = try c.decodeIfPresent([Exercise].self, forKey: .exercises) ?? []
            treadmillDone = try c.decodeIfPresent(Bool.self, forKey: .treadmillDone) ?? false
            treadmillDuration = try c.decodeIfPresent(Double.self, forKey: .treadmillDuration) ?? 20
        }

        func workoutDay(_ day: DayKey, at date: Date) -> WorkoutDay {
            WorkoutDay(dayKey: day, exercises: exercises.map(\.current), treadmillDone: treadmillDone,
                       treadmillMinutes: treadmillDuration, updatedAt: date)
        }
    }

    struct DayMeals: Codable {
        var breakfast: Bool
        var lunch: Bool
        var dinner: Bool
        var snacks: Bool

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            breakfast = try c.decodeIfPresent(Bool.self, forKey: .breakfast) ?? false
            lunch = try c.decodeIfPresent(Bool.self, forKey: .lunch) ?? false
            dinner = try c.decodeIfPresent(Bool.self, forKey: .dinner) ?? false
            snacks = try c.decodeIfPresent(Bool.self, forKey: .snacks) ?? false
        }
    }

    struct TodoItem: Codable {
        var id: UUID
        var title: String
        var isCompleted: Bool
        var reminderDate: Date?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
            reminderDate = try c.decodeIfPresent(Date.self, forKey: .reminderDate)
        }
    }
}
