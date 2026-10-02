import Foundation

// Schema v1 records (docs/adr/0001-persistence.md). Every record carries a
// `dayKey` stamped at write time. Records that can be user-authored also carry
// a `source`.

/// A record stored in a day-sharded collection.
public protocol DayRecord: Codable, Sendable, Identifiable where ID: Codable & Hashable & Sendable {
    /// Directory name of the collection on disk. Changing it orphans data.
    static var collection: String { get }
    var dayKey: DayKey { get }
}

// MARK: - Food

/// One logged food item. Replaces the legacy `FoodItem` inside `DailyFoodLog`.
public struct FoodEntry: DayRecord, Equatable, Hashable {
    public static let collection = "food"

    public let id: UUID
    public var dayKey: DayKey
    public var loggedAt: Date
    public var meal: MealType
    public var name: String
    public var servingDescription: String
    /// Totals for the serving as logged (already scaled).
    public var calories: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var barcode: String?
    public var source: EntrySource
    /// AI confidence, 0…1. `nil` for non-AI entries.
    public var confidence: Double?

    public init(id: UUID = UUID(), dayKey: DayKey, loggedAt: Date, meal: MealType, name: String,
                servingDescription: String = "1 serving", calories: Double, proteinG: Double = 0,
                carbsG: Double = 0, fatG: Double = 0, barcode: String? = nil,
                source: EntrySource, confidence: Double? = nil) {
        self.id = id
        self.dayKey = dayKey
        self.loggedAt = loggedAt
        self.meal = meal
        self.name = name
        self.servingDescription = servingDescription
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.barcode = barcode
        self.source = source
        self.confidence = confidence
    }
}

/// Totals for a set of food entries.
public struct NutritionTotals: Equatable, Sendable {
    public var calories: Double = 0
    public var proteinG: Double = 0
    public var carbsG: Double = 0
    public var fatG: Double = 0

    public init() {}

    public init(_ entries: some Sequence<FoodEntry>) {
        for entry in entries {
            calories += entry.calories
            proteinG += entry.proteinG
            carbsG += entry.carbsG
            fatG += entry.fatG
        }
    }
}

// MARK: - Training

/// A strength exercise within a day. Field names match the legacy `Exercise`.
public struct Exercise: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public var bodyPart: BodyPart
    /// Specific movement (e.g. "Bench Press"). `nil` for legacy entries.
    public var name: String?
    public var setsCompleted: Int
    public var maxSets: Int

    public init(id: UUID = UUID(), bodyPart: BodyPart, name: String? = nil, setsCompleted: Int = 0, maxSets: Int = 3) {
        self.id = id
        self.bodyPart = bodyPart
        self.name = name
        self.setsCompleted = setsCompleted
        self.maxSets = maxSets
    }

    /// The movement name when set, otherwise the body part.
    public var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return bodyPart.rawValue
    }
}

/// One day's manual training log. Replaces the legacy `DayWorkout` that was
/// keyed by weekday name. HealthKit workouts arrive as separate records in P1 (doc 02).
public struct WorkoutDay: DayRecord, Equatable {
    public static let collection = "workoutDays"

    public var id: DayKey { dayKey }
    public var dayKey: DayKey
    public var exercises: [Exercise]
    public var treadmillDone: Bool
    public var treadmillMinutes: Double
    public var updatedAt: Date

    public init(dayKey: DayKey, exercises: [Exercise] = [], treadmillDone: Bool = false,
                treadmillMinutes: Double = 20, updatedAt: Date = Date()) {
        self.dayKey = dayKey
        self.exercises = exercises
        self.treadmillDone = treadmillDone
        self.treadmillMinutes = treadmillMinutes
        self.updatedAt = updatedAt
    }

    public var totalSets: Int {
        exercises.reduce(0) { $0 + $1.setsCompleted }
    }

    public var isEmpty: Bool { exercises.isEmpty && !treadmillDone }
}

// MARK: - Body & hydration

/// Water for one day. The app counts glasses; `mlPerGlass` converts for
/// HealthKit and future ml-based logging.
public struct WaterDay: DayRecord, Equatable {
    public static let collection = "water"
    public static let mlPerGlass = 250.0

    public var id: DayKey { dayKey }
    public var dayKey: DayKey
    public var glasses: Int
    public var source: EntrySource
    public var updatedAt: Date

    public init(dayKey: DayKey, glasses: Int, source: EntrySource, updatedAt: Date = Date()) {
        self.dayKey = dayKey
        self.glasses = max(0, glasses)
        self.source = source
        self.updatedAt = updatedAt
    }

    public var milliliters: Double { Double(glasses) * Self.mlPerGlass }
}

public struct WeightEntry: DayRecord, Equatable {
    public static let collection = "weight"

    public let id: UUID
    public var dayKey: DayKey
    public var measuredAt: Date
    public var kg: Double
    public var source: EntrySource
    /// `HKQuantitySample.uuid` when imported from Apple Health (dedupe key).
    public var healthKitUUID: UUID?

    public init(id: UUID = UUID(), dayKey: DayKey, measuredAt: Date, kg: Double,
                source: EntrySource, healthKitUUID: UUID? = nil) {
        self.id = id
        self.dayKey = dayKey
        self.measuredAt = measuredAt
        self.kg = kg
        self.source = source
        self.healthKitUUID = healthKitUUID
    }
}

// MARK: - Tasks & habits

/// A to-do for a specific day. Replaces the legacy weekday-keyed `TodoItem`.
public struct TaskItem: DayRecord, Equatable {
    public static let collection = "tasks"

    public let id: UUID
    public var dayKey: DayKey
    public var title: String
    public var isCompleted: Bool
    public var completedAt: Date?
    public var reminderAt: Date?
    public var createdAt: Date
    public var source: EntrySource

    public init(id: UUID = UUID(), dayKey: DayKey, title: String, isCompleted: Bool = false,
                completedAt: Date? = nil, reminderAt: Date? = nil, createdAt: Date = Date(),
                source: EntrySource = .manual) {
        self.id = id
        self.dayKey = dayKey
        self.title = title
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.reminderAt = reminderAt
        self.createdAt = createdAt
        self.source = source
    }
}

/// Per-meal "high protein" checklist. Replaces the legacy weekday-keyed `DayMeals`.
public struct ProteinChecklist: DayRecord, Equatable {
    public static let collection = "proteinChecklist"

    public var id: DayKey { dayKey }
    public var dayKey: DayKey
    public var breakfast: Bool
    public var lunch: Bool
    public var dinner: Bool
    public var snacks: Bool

    public init(dayKey: DayKey, breakfast: Bool = false, lunch: Bool = false,
                dinner: Bool = false, snacks: Bool = false) {
        self.dayKey = dayKey
        self.breakfast = breakfast
        self.lunch = lunch
        self.dinner = dinner
        self.snacks = snacks
    }

    public var highProteinCount: Int {
        [breakfast, lunch, dinner, snacks].filter { $0 }.count
    }

    public var isEmpty: Bool { highProteinCount == 0 }
}
