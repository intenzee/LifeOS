import Foundation

/// Everything the AI layer may know about the user right now, flattened into
/// plain values (F05 §3). The app builds one from its stores
/// (`AppIntegration/LifeContextBuilder`); tests and evals build them by hand.
///
/// Read-only by design: the context engine, memory retrieval, the assistant
/// tools and the narratives all compute from this, so every answer is
/// reproducible from one value.
nonisolated struct LifeContext: Sendable, Equatable {

    nonisolated struct Profile: Sendable, Equatable {
        var goal: String            // "lose weight", "maintain", "gain muscle"
        var dietType: String?       // "vegetarian", "eggetarian", "vegan", "non-vegetarian"
        var units: String           // "metric" / "imperial"
        var age: Int?
        var sex: String?            // "m" / "f"
        var weightKg: Double?
        var heightCm: Double?

        init(goal: String = "maintain", dietType: String? = nil, units: String = "metric", age: Int? = nil,
             sex: String? = nil, weightKg: Double? = nil, heightCm: Double? = nil) {
            self.goal = goal
            self.dietType = dietType
            self.units = units
            self.age = age
            self.sex = sex
            self.weightKg = weightKg
            self.heightCm = heightCm
        }
    }

    nonisolated struct Meal: Sendable, Equatable {
        var name: String
        var slot: ParsedMeal.MealSlot
        var kcal: Double
        var protein: Double
        var time: Date

        init(name: String, slot: ParsedMeal.MealSlot, kcal: Double, protein: Double = 0, time: Date) {
            self.name = name
            self.slot = slot
            self.kcal = kcal
            self.protein = protein
            self.time = time
        }
    }

    nonisolated struct Workout: Sendable, Equatable {
        var name: String        // "Evening run", "Strength"
        var minutes: Int
        var kcal: Double
        var source: String      // "Apple Watch", "LifeOS sets", app name
        var start: Date?

        init(name: String, minutes: Int, kcal: Double, source: String, start: Date? = nil) {
            self.name = name
            self.minutes = minutes
            self.kcal = kcal
            self.source = source
            self.start = start
        }
    }

    nonisolated struct Day: Sendable, Equatable {
        var date: Date                  // start of day
        var meals: [Meal]
        var carbs: Double
        var fat: Double
        /// That day's budget from the calorie engine; 0 when unknown.
        var budget: Double
        var water: Int
        var waterTarget: Int
        var workouts: [Workout]
        var steps: Int?
        var sleepHours: Double?
        var weightKg: Double?

        init(date: Date, meals: [Meal] = [], carbs: Double = 0, fat: Double = 0, budget: Double = 0, water: Int = 0,
             waterTarget: Int = 8, workouts: [Workout] = [], steps: Int? = nil, sleepHours: Double? = nil,
             weightKg: Double? = nil) {
            self.date = date
            self.meals = meals
            self.carbs = carbs
            self.fat = fat
            self.budget = budget
            self.water = water
            self.waterTarget = waterTarget
            self.workouts = workouts
            self.steps = steps
            self.sleepHours = sleepHours
            self.weightKg = weightKg
        }

        var kcal: Double { meals.reduce(0) { $0 + $1.kcal } }
        var protein: Double { meals.reduce(0) { $0 + $1.protein } }
        var hasFood: Bool { !meals.isEmpty }
        var workoutKcal: Double { workouts.reduce(0) { $0 + $1.kcal } }
    }

    /// One line of the engine's budget breakdown (`BudgetBreakdown.Line`), in order.
    nonisolated struct BudgetLine: Sendable, Equatable {
        nonisolated enum Kind: String, Sendable, CaseIterable {
            case bmr, everydayActivity, goal, manualTarget, exerciseCredit, floorTopUp
        }
        var kind: Kind
        var kcal: Double

        init(_ kind: Kind, _ kcal: Double) {
            self.kind = kind
            self.kcal = kcal
        }
    }

    /// Today's budget as the calorie engine computed it (read-only; CAL-07).
    nonisolated struct Budget: Sendable, Equatable {
        var total: Double
        var lines: [BudgetLine]
        var mode: String            // "measured", "estimated", "fixed", "classic"
        var eatBack: Double         // 0…1
        var rawActive: Double       // Watch active kcal (measured) or MET estimate
        var allowance: Double       // active energy already in the baseline (measured)
        var floor: Double

        init(total: Double, lines: [BudgetLine] = [], mode: String = "estimated", eatBack: Double = 0.5,
             rawActive: Double = 0, allowance: Double = 0, floor: Double = 1200) {
            self.total = total
            self.lines = lines
            self.mode = mode
            self.eatBack = eatBack
            self.rawActive = rawActive
            self.allowance = allowance
            self.floor = floor
        }

        var credit: Double { lines.filter { $0.kind == .exerciseCredit }.reduce(0) { $0 + $1.kcal } }
        var baseline: Double { total - credit }
    }

    nonisolated struct MacroTargets: Sendable, Equatable {
        var protein: Double
        var carbs: Double
        var fat: Double

        init(protein: Double, carbs: Double = 0, fat: Double = 0) {
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
        }
    }

    nonisolated struct PresetSummary: Sendable, Equatable {
        var id: String
        var name: String
        var kcal: Double
        var meal: ParsedMeal.MealSlot?
        var uses: Int

        init(id: String, name: String, kcal: Double, meal: ParsedMeal.MealSlot? = nil, uses: Int = 0) {
            self.id = id
            self.name = name
            self.kcal = kcal
            self.meal = meal
            self.uses = uses
        }
    }

    nonisolated struct Todo: Sendable, Equatable {
        var id: String
        var title: String
        var due: Date?
        var done: Bool

        init(id: String, title: String, due: Date? = nil, done: Bool = false) {
            self.id = id
            self.title = title
            self.due = due
            self.done = done
        }
    }

    var now: Date
    var calendar: Calendar
    var localeIdentifier: String
    var profile: Profile?
    /// Oldest first; the last one may be today (in progress).
    var days: [Day]
    var budget: Budget?
    var macroTargets: MacroTargets?
    var presets: [PresetSummary]
    var todos: [Todo]
    var memories: [MemoryRecord]
    /// Rolling summary of the current assistant conversation (F07 §4).
    var conversationSummary: String?

    init(now: Date = Date(), calendar: Calendar = .current, localeIdentifier: String = "en_IN",
         profile: Profile? = nil, days: [Day] = [], budget: Budget? = nil, macroTargets: MacroTargets? = nil,
         presets: [PresetSummary] = [], todos: [Todo] = [], memories: [MemoryRecord] = [],
         conversationSummary: String? = nil) {
        self.now = now
        self.calendar = calendar
        self.localeIdentifier = localeIdentifier
        self.profile = profile
        self.days = days
        self.budget = budget
        self.macroTargets = macroTargets
        self.presets = presets
        self.todos = todos
        self.memories = memories
        self.conversationSummary = conversationSummary
    }

    var today: Day? { days.last { calendar.isDate($0.date, inSameDayAs: now) } }

    /// The last `n` days ending today (inclusive), oldest first.
    func lastDays(_ n: Int) -> [Day] {
        guard n > 0, let start = calendar.date(byAdding: .day, value: -(n - 1), to: calendar.startOfDay(for: now)) else { return [] }
        return days.filter { $0.date >= start && $0.date <= now }
    }

    /// Days in `[from, to]` (by start of day), oldest first.
    func days(from: Date, to: Date) -> [Day] {
        let a = calendar.startOfDay(for: from), b = calendar.startOfDay(for: to)
        return days.filter { $0.date >= a && $0.date <= b }
    }

    /// Completed days only — today is still in progress and never counts toward a pattern.
    func completedDays(_ n: Int) -> [Day] {
        lastDays(n + 1).filter { !calendar.isDate($0.date, inSameDayAs: now) }.suffix(n)
    }

    /// Every meal in the window with its day, oldest first.
    func meals(lastDays n: Int) -> [Meal] { lastDays(n).flatMap(\.meals) }
}
