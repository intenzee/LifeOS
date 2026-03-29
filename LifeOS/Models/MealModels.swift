import Foundation

// MARK: - Mini Card Type
enum MiniCardType: Hashable {
    case todo, weight, gym, mood, water, food
}

// MARK: - Meal Type
enum MealType: String, CaseIterable, Codable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snacks = "Snacks"
}

// MARK: - Body Part
enum BodyPart: String, CaseIterable, Codable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case arms = "Arms"
    case legs = "Legs"
    case abs = "Abs"
    case cardio = "Cardio"
}

// MARK: - Exercise
struct Exercise: Identifiable, Codable {
    let id: UUID
    var bodyPart: BodyPart
    var setsCompleted: Int
    var maxSets: Int

    init(id: UUID = UUID(), bodyPart: BodyPart, setsCompleted: Int = 0, maxSets: Int = 3) {
        self.id = id
        self.bodyPart = bodyPart
        self.setsCompleted = setsCompleted
        self.maxSets = maxSets
    }
}

// MARK: - Day Workout
struct DayWorkout: Codable {
    var exercises: [Exercise]
    var treadmillDone: Bool
    var treadmillDuration: Double = 20.0

    init(exercises: [Exercise] = [], treadmillDone: Bool = false, treadmillDuration: Double = 20.0) {
        self.exercises = exercises
        self.treadmillDone = treadmillDone
        self.treadmillDuration = treadmillDuration
    }

    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.setsCompleted }
    }

    func intensity(weightKg: Double) -> String {
        let totalCalories = CalorieCalculator.totalWorkoutCalories(workout: self, weightKg: weightKg)

        if totalCalories >= 450 {
            return "High"
        } else if totalCalories >= 300 {
            return "Medium"
        } else if totalCalories >= 120 {
            return "Low"
        } else {
            return "Rest"
        }
    }
}

// MARK: - Day Meals
struct DayMeals: Codable {
    var breakfast: Bool
    var lunch: Bool
    var dinner: Bool
    var snacks: Bool

    init(breakfast: Bool = false, lunch: Bool = false, dinner: Bool = false, snacks: Bool = false) {
        self.breakfast = breakfast
        self.lunch = lunch
        self.dinner = dinner
        self.snacks = snacks
    }

    var highProteinCount: Int {
        [breakfast, lunch, dinner, snacks].filter { $0 }.count
    }

    var summary: String {
        let meals = [
            (breakfast, "Breakfast"),
            (lunch, "Lunch"),
            (dinner, "Dinner"),
            (snacks, "Snacks")
        ].filter { $0.0 }.map { $0.1 }

        if meals.isEmpty {
            return "Low Protein"
        } else if meals.count == 4 {
            return "High Protein"
        } else {
            return meals.joined(separator: ", ")
        }
    }
}

// MARK: - Todo Item
struct TodoItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var reminderDate: Date?

    init(id: UUID = UUID(), title: String, isCompleted: Bool = false, reminderDate: Date? = nil) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.reminderDate = reminderDate
    }
}

// MARK: - Food Item
struct FoodItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var servingSize: String
    var barcode: String?
    var mealType: MealType
    var timestamp: Date

    init(id: UUID = UUID(), name: String, calories: Double, protein: Double = 0, carbs: Double = 0, fat: Double = 0, servingSize: String = "1 serving", barcode: String? = nil, mealType: MealType, timestamp: Date = Date()) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.servingSize = servingSize
        self.barcode = barcode
        self.mealType = mealType
        self.timestamp = timestamp
    }

    func scaled(toGrams grams: Double) -> FoodItem {
        let multiplier = grams / 100.0

        return FoodItem(
            id: self.id,
            name: self.name,
            calories: self.calories * multiplier,
            protein: self.protein * multiplier,
            carbs: self.carbs * multiplier,
            fat: self.fat * multiplier,
            servingSize: "\(Int(grams))g",
            barcode: self.barcode,
            mealType: self.mealType,
            timestamp: self.timestamp
        )
    }
}

// MARK: - Daily Food Log
struct DailyFoodLog: Codable {
    var breakfast: [FoodItem]
    var lunch: [FoodItem]
    var dinner: [FoodItem]
    var snacks: [FoodItem]

    init() {
        self.breakfast = []
        self.lunch = []
        self.dinner = []
        self.snacks = []
    }

    func totalCalories() -> Double {
        (breakfast + lunch + dinner + snacks).reduce(0) { $0 + $1.calories }
    }

    func totalProtein() -> Double {
        (breakfast + lunch + dinner + snacks).reduce(0) { $0 + $1.protein }
    }

    func totalCarbs() -> Double {
        (breakfast + lunch + dinner + snacks).reduce(0) { $0 + $1.carbs }
    }

    func totalFat() -> Double {
        (breakfast + lunch + dinner + snacks).reduce(0) { $0 + $1.fat }
    }

    mutating func addFood(_ food: FoodItem) {
        switch food.mealType {
        case .breakfast:
            breakfast.append(food)
        case .lunch:
            lunch.append(food)
        case .dinner:
            dinner.append(food)
        case .snacks:
            snacks.append(food)
        }
    }

    mutating func removeFood(_ foodId: UUID) {
        breakfast.removeAll { $0.id == foodId }
        lunch.removeAll { $0.id == foodId }
        dinner.removeAll { $0.id == foodId }
        snacks.removeAll { $0.id == foodId }
    }
}

// MARK: - Quick Action Type
enum QuickActionType {
    case breakfast, lunch, dinner, snacks, exercise, water, weight, barcodeScan, aiMealScan
}