import Foundation

// MARK: - Snapshot received from the phone

/// A day snapshot pushed by the phone over WatchConnectivity. Parsed from the
/// `[String: Any]` application context (keys mirror the phone's
/// `WatchConnectivityManager.makeSnapshot()`).
struct WatchSnapshot: Equatable {
    var date: String
    var caloriesConsumed: Double
    var calorieLimit: Double
    var caloriesBurned: Double
    var waterCount: Int
    var waterTarget: Int
    var perfectStreak: Int
    var currentWeight: Double
    var targetWeight: Double
    var steps: Int
    var todos: [WatchTodo]
    var exercises: [WatchExercise]

    static let empty = WatchSnapshot(
        date: "", caloriesConsumed: 0, calorieLimit: 0, caloriesBurned: 0,
        waterCount: 0, waterTarget: 8, perfectStreak: 0, currentWeight: 0, targetWeight: 0,
        steps: 0, todos: [], exercises: []
    )

    init(date: String, caloriesConsumed: Double, calorieLimit: Double, caloriesBurned: Double,
         waterCount: Int, waterTarget: Int, perfectStreak: Int,
         currentWeight: Double, targetWeight: Double, steps: Int,
         todos: [WatchTodo], exercises: [WatchExercise]) {
        self.date = date
        self.caloriesConsumed = caloriesConsumed
        self.calorieLimit = calorieLimit
        self.caloriesBurned = caloriesBurned
        self.waterCount = waterCount
        self.waterTarget = waterTarget
        self.perfectStreak = perfectStreak
        self.currentWeight = currentWeight
        self.targetWeight = targetWeight
        self.steps = steps
        self.todos = todos
        self.exercises = exercises
    }

    init?(dictionary dict: [String: Any]) {
        guard (dict["type"] as? String) == "snapshot" else { return nil }
        self.date = dict["date"] as? String ?? ""
        self.caloriesConsumed = (dict["caloriesConsumed"] as? Double) ?? 0
        self.calorieLimit = (dict["calorieLimit"] as? Double) ?? 0
        self.caloriesBurned = (dict["caloriesBurned"] as? Double) ?? 0
        self.waterCount = (dict["waterCount"] as? Int) ?? 0
        self.waterTarget = (dict["waterTarget"] as? Int) ?? 8
        self.perfectStreak = (dict["perfectStreak"] as? Int) ?? 0
        self.currentWeight = (dict["currentWeight"] as? Double) ?? 0
        self.targetWeight = (dict["targetWeight"] as? Double) ?? 0
        self.steps = (dict["steps"] as? Int) ?? 0
        self.todos = (dict["todos"] as? [[String: Any]] ?? []).compactMap(WatchTodo.init(dictionary:))
        self.exercises = (dict["exercises"] as? [[String: Any]] ?? []).compactMap(WatchExercise.init(dictionary:))
    }

    var caloriesRemaining: Double { max(calorieLimit - caloriesConsumed, 0) }
    var calorieProgress: Double { calorieLimit > 0 ? min(caloriesConsumed / calorieLimit, 1) : 0 }
    var waterProgress: Double { waterTarget > 0 ? min(Double(waterCount) / Double(waterTarget), 1) : 0 }
    var todosCompleted: Int { todos.filter { $0.done }.count }
}

struct WatchTodo: Identifiable, Equatable {
    let id: UUID
    var title: String
    var done: Bool

    init?(dictionary dict: [String: Any]) {
        guard let idString = dict["id"] as? String, let id = UUID(uuidString: idString) else { return nil }
        self.id = id
        self.title = dict["title"] as? String ?? ""
        self.done = dict["done"] as? Bool ?? false
    }
}

struct WatchExercise: Identifiable, Equatable {
    let id: UUID
    var bodyPart: String
    var name: String
    var setsCompleted: Int
    var maxSets: Int

    init(id: UUID, bodyPart: String, name: String, setsCompleted: Int, maxSets: Int) {
        self.id = id
        self.bodyPart = bodyPart
        self.name = name
        self.setsCompleted = setsCompleted
        self.maxSets = maxSets
    }

    init?(dictionary dict: [String: Any]) {
        guard let idString = dict["id"] as? String, let id = UUID(uuidString: idString) else { return nil }
        self.id = id
        self.bodyPart = dict["bodyPart"] as? String ?? ""
        self.name = dict["name"] as? String ?? ""
        self.setsCompleted = dict["setsCompleted"] as? Int ?? 0
        self.maxSets = dict["maxSets"] as? Int ?? 3
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? bodyPart : name
    }
}

// MARK: - Exercise catalog (watch-local copy)

/// Mirror of the phone's `ExerciseCatalog`; kept independent so the watch target
/// stays self-contained.
enum WatchExerciseCatalog {
    static let bodyParts = ["Chest", "Back", "Shoulders", "Arms", "Legs", "Abs", "Cardio"]

    static let movements: [String: [String]] = [
        "Chest": ["Bench Press", "Incline Press", "Chest Fly", "Push-Up", "Cable Crossover"],
        "Back": ["Deadlift", "Lat Pulldown", "Bent-Over Row", "Pull-Up", "Seated Row"],
        "Shoulders": ["Overhead Press", "Lateral Raise", "Front Raise", "Rear Delt Fly", "Shrug"],
        "Arms": ["Bicep Curl", "Tricep Pushdown", "Hammer Curl", "Skull Crusher", "Preacher Curl"],
        "Legs": ["Squat", "Leg Press", "Lunge", "Leg Curl", "Leg Extension", "Calf Raise"],
        "Abs": ["Crunch", "Plank", "Leg Raise", "Russian Twist", "Cable Crunch"],
        "Cardio": ["Treadmill", "Cycling", "Rowing", "Elliptical", "Jump Rope"]
    ]

    static func movements(for bodyPart: String) -> [String] { movements[bodyPart] ?? [] }
}
