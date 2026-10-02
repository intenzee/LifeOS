import Foundation

// Moved from the app target (LifeOS/Models/UserProfile.swift) unchanged, apart
// from `public`/`Sendable`, so the persisted JSON stays compatible.

public enum BiologicalSex: String, CaseIterable, Codable, Identifiable, Sendable {
    case male = "Male"
    case female = "Female"
    case other = "Other"

    public var id: String { rawValue }

    /// SF Symbol name.
    public var icon: String {
        switch self {
        case .male: return "figure.stand"
        case .female: return "figure.stand.dress"
        case .other: return "figure"
        }
    }
}

public enum FitnessGoal: String, CaseIterable, Codable, Identifiable, Sendable {
    case loseWeight = "Lose Weight"
    case maintain = "Maintain"
    case gainMuscle = "Gain Muscle"
    case improveFitness = "Improve Fitness"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .loseWeight: return "arrow.down.circle.fill"
        case .maintain: return "equal.circle.fill"
        case .gainMuscle: return "dumbbell.fill"
        case .improveFitness: return "bolt.heart.fill"
        }
    }

    /// Daily calorie adjustment applied on top of maintenance (TDEE).
    public var calorieAdjustment: Double {
        switch self {
        case .loseWeight: return -500
        case .maintain: return 0
        case .gainMuscle: return 300
        case .improveFitness: return 0
        }
    }
}

public enum DietType: String, CaseIterable, Codable, Identifiable, Sendable {
    case balanced = "Balanced"
    case vegetarian = "Vegetarian"
    case vegan = "Vegan"
    case keto = "Keto"
    case highProtein = "High Protein"
    case other = "Other"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .balanced: return "fork.knife"
        case .vegetarian: return "leaf.fill"
        case .vegan: return "carrot.fill"
        case .keto: return "flame.fill"
        case .highProtein: return "fish.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

public enum MeasurementUnits: String, CaseIterable, Codable, Identifiable, Sendable {
    case metric = "Metric"
    case imperial = "Imperial"

    public var id: String { rawValue }

    public var heightUnit: String { self == .metric ? "cm" : "in" }
    public var weightUnit: String { self == .metric ? "kg" : "lb" }
}

/// Everything gathered during onboarding. Heights are stored in centimetres
/// and weights in kilograms, whatever the display units.
public struct UserProfile: Codable, Sendable, Equatable {
    public var age: Int
    public var heightCm: Double
    public var currentWeightKg: Double
    public var targetWeightKg: Double
    public var sex: BiologicalSex
    public var goal: FitnessGoal
    public var exerciseDaysPerWeek: Int
    public var smokes: Bool
    public var diet: DietType
    public var units: MeasurementUnits
    public var waterGoalGlasses: Int
    public var wakeTime: Date
    public var sleepTime: Date
    public var completedAt: Date

    public init(
        age: Int = 25,
        heightCm: Double = 170,
        currentWeightKg: Double = 72.5,
        targetWeightKg: Double = 68.0,
        sex: BiologicalSex = .male,
        goal: FitnessGoal = .maintain,
        exerciseDaysPerWeek: Int = 3,
        smokes: Bool = false,
        diet: DietType = .balanced,
        units: MeasurementUnits = .metric,
        waterGoalGlasses: Int = 8,
        wakeTime: Date = UserProfile.defaultTime(hour: 7),
        sleepTime: Date = UserProfile.defaultTime(hour: 23),
        completedAt: Date = Date()
    ) {
        self.age = age
        self.heightCm = heightCm
        self.currentWeightKg = currentWeightKg
        self.targetWeightKg = targetWeightKg
        self.sex = sex
        self.goal = goal
        self.exerciseDaysPerWeek = exerciseDaysPerWeek
        self.smokes = smokes
        self.diet = diet
        self.units = units
        self.waterGoalGlasses = waterGoalGlasses
        self.wakeTime = wakeTime
        self.sleepTime = sleepTime
        self.completedAt = completedAt
    }

    public static func defaultTime(hour: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    /// Mifflin-St Jeor activity multiplier from weekly training days.
    public var activityFactor: Double {
        switch exerciseDaysPerWeek {
        case 0: return 1.2
        case 1...2: return 1.375
        case 3...4: return 1.55
        case 5...6: return 1.725
        default: return 1.9
        }
    }
}
