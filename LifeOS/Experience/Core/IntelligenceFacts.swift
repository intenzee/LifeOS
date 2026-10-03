import Foundation

/// One day of the user's data, flattened for the intelligence layer (Phase 4).
/// Built by `ExperienceStore` from the managers; pure so every answer, memory,
/// insight and automation preview can be unit-tested.
nonisolated struct DayFacts: Equatable, Sendable, Identifiable {
    nonisolated struct Meal: Equatable, Sendable {
        var name: String
        var slot: ExperienceMealSlot
        var kcal: Double
        var protein: Double
        var time: Date
    }

    var date: Date            // start of day
    var meals: [Meal]
    var budget: Double        // that day's budget (limit + earned), 0 if unknown
    var water: Int
    var waterTarget: Int
    var workoutKcal: Double   // MET estimate from logged sets
    var gymSets: Int
    var weightKg: Double?

    var id: Date { date }
    var kcal: Double { meals.reduce(0) { $0 + $1.kcal } }
    var protein: Double { meals.reduce(0) { $0 + $1.protein } }
    var hasFood: Bool { !meals.isEmpty }
    var trained: Bool { gymSets > 0 || workoutKcal > 0 }
    var onBudget: Bool { hasFood && budget > 0 && kcal <= budget }

    init(date: Date, meals: [Meal] = [], budget: Double = 0, water: Int = 0, waterTarget: Int = 8,
         workoutKcal: Double = 0, gymSets: Int = 0, weightKg: Double? = nil) {
        self.date = date
        self.meals = meals
        self.budget = budget
        self.water = water
        self.waterTarget = waterTarget
        self.workoutKcal = workoutKcal
        self.gymSets = gymSets
        self.weightKg = weightKg
    }
}

/// Everything the assistant may look at, newest day last.
nonisolated struct IntelligenceSnapshot: Equatable, Sendable {
    var days: [DayFacts]
    var now: Date
    var proteinTarget: Double
    var budgetToday: ExperienceBudget
    var memories: [MemoryItem]
    var calendar: Calendar = .current

    var today: DayFacts? { days.last { calendar.isDate($0.date, inSameDayAs: now) } }

    /// The last `n` days ending today (inclusive), oldest first.
    func lastDays(_ n: Int) -> [DayFacts] {
        guard let start = calendar.date(byAdding: .day, value: -(n - 1), to: calendar.startOfDay(for: now)) else { return [] }
        return days.filter { $0.date >= start && $0.date <= now }
    }

    /// The `n` days before the last `n`.
    func previousDays(_ n: Int) -> [DayFacts] {
        let sod = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: -n, to: sod),
              let start = calendar.date(byAdding: .day, value: -(2 * n - 1), to: sod) else { return [] }
        return days.filter { $0.date >= start && $0.date <= end }
    }
}

nonisolated enum Fmt {
    static func kcal(_ v: Double) -> String { Int(v.rounded()).formatted() }
    static func grams(_ v: Double) -> String { "\(Int(v.rounded())) g" }
    static func avg(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
    static func weekday(_ d: Date, _ cal: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEE"
        return f.string(from: d)
    }
    static func shortDay(_ d: Date, _ cal: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }
}
