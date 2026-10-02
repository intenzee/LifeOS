import Foundation

/// Where a record came from. Mandatory on every user-data record so automated
/// writes stay visible and attributable (master plan §6, principle 4).
public enum EntrySource: String, Codable, Sendable, CaseIterable {
    case manual
    case barcode
    case photoAI
    case nlAI
    case preset
    case assistant
    case automation
    case watch
    case healthKit
}

/// Meal slot. Raw values match the legacy app's `MealType`, so persisted data
/// and display strings are unchanged.
public enum MealType: String, CaseIterable, Codable, Sendable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snacks = "Snacks"
}

/// Raw values match the legacy app's `BodyPart`.
public enum BodyPart: String, CaseIterable, Codable, Sendable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case arms = "Arms"
    case legs = "Legs"
    case abs = "Abs"
    case cardio = "Cardio"
}

/// Built-in list of common movements per body part. Shared by the iPhone and
/// Watch apps, replacing the watch's duplicated `WatchExerciseCatalog`.
public enum ExerciseCatalog {
    public static let movements: [BodyPart: [String]] = [
        .chest: ["Bench Press", "Incline Press", "Chest Fly", "Push-Up", "Cable Crossover"],
        .back: ["Deadlift", "Lat Pulldown", "Bent-Over Row", "Pull-Up", "Seated Row"],
        .shoulders: ["Overhead Press", "Lateral Raise", "Front Raise", "Rear Delt Fly", "Shrug"],
        .arms: ["Bicep Curl", "Tricep Pushdown", "Hammer Curl", "Skull Crusher", "Preacher Curl"],
        .legs: ["Squat", "Leg Press", "Lunge", "Leg Curl", "Leg Extension", "Calf Raise"],
        .abs: ["Crunch", "Plank", "Leg Raise", "Russian Twist", "Cable Crunch"],
        .cardio: ["Treadmill", "Cycling", "Rowing", "Elliptical", "Jump Rope"]
    ]

    public static func movements(for bodyPart: BodyPart) -> [String] {
        movements[bodyPart] ?? []
    }
}
