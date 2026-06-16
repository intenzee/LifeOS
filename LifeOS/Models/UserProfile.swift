import Foundation

// MARK: - User Profile Enums

enum BiologicalSex: String, CaseIterable, Codable, Identifiable {
    case male = "Male"
    case female = "Female"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .male: return "figure.stand"
        case .female: return "figure.stand.dress"
        case .other: return "figure"
        }
    }
}

enum FitnessGoal: String, CaseIterable, Codable, Identifiable {
    case loseWeight = "Lose Weight"
    case maintain = "Maintain"
    case gainMuscle = "Gain Muscle"
    case improveFitness = "Improve Fitness"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .loseWeight: return "arrow.down.circle.fill"
        case .maintain: return "equal.circle.fill"
        case .gainMuscle: return "dumbbell.fill"
        case .improveFitness: return "bolt.heart.fill"
        }
    }

    /// Daily calorie adjustment applied on top of maintenance (TDEE).
    var calorieAdjustment: Double {
        switch self {
        case .loseWeight: return -500
        case .maintain: return 0
        case .gainMuscle: return 300
        case .improveFitness: return 0
        }
    }
}

enum DietType: String, CaseIterable, Codable, Identifiable {
    case balanced = "Balanced"
    case vegetarian = "Vegetarian"
    case vegan = "Vegan"
    case keto = "Keto"
    case highProtein = "High Protein"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
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

enum MeasurementUnits: String, CaseIterable, Codable, Identifiable {
    case metric = "Metric"
    case imperial = "Imperial"

    var id: String { rawValue }

    var heightUnit: String { self == .metric ? "cm" : "in" }
    var weightUnit: String { self == .metric ? "kg" : "lb" }
}

// MARK: - User Profile

/// Captures everything gathered during first-launch onboarding.
/// Heights are always stored in centimeters and weights in kilograms
/// (the app's internal unit), regardless of the user's display preference.
struct UserProfile: Codable {
    var age: Int
    var heightCm: Double
    var currentWeightKg: Double
    var targetWeightKg: Double
    var sex: BiologicalSex
    var goal: FitnessGoal
    var exerciseDaysPerWeek: Int
    var smokes: Bool
    var diet: DietType
    var units: MeasurementUnits
    var waterGoalGlasses: Int
    var wakeTime: Date
    var sleepTime: Date
    var completedAt: Date

    init(
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

    static func defaultTime(hour: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    /// Activity multiplier for the Mifflin-St Jeor TDEE based on weekly training days.
    var activityFactor: Double {
        switch exerciseDaysPerWeek {
        case 0: return 1.2
        case 1...2: return 1.375
        case 3...4: return 1.55
        case 5...6: return 1.725
        default: return 1.9
        }
    }
}
