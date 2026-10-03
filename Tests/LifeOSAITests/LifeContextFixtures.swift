import Foundation
@testable import LifeOSAI

/// Synthetic users for Phase 2–3 tests. Fixed clock (Fri 2 Oct 2026, 19:40 IST)
/// and calendar, so every number is reproducible.
nonisolated enum LifeFixtures {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        c.locale = Locale(identifier: "en_IN")
        c.firstWeekday = 2
        return c
    }()

    static func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    static let now = date(2, 19, 40)

    static func meal(_ name: String, _ slot: ParsedMeal.MealSlot, _ kcal: Double, protein: Double = 10, at time: Date) -> LifeContext.Meal {
        LifeContext.Meal(name: name, slot: slot, kcal: kcal, protein: protein, time: time)
    }

    /// 28 days of a steady Indian vegetarian logger, today in progress.
    static func steadyUser(memories: [MemoryRecord] = [], now: Date = now) -> LifeContext {
        let today = calendar.startOfDay(for: now)
        var days: [LifeContext.Day] = []
        for offset in (0..<28).reversed() {
            let d = calendar.date(byAdding: .day, value: -offset, to: today)!
            func at(_ h: Int, _ m: Int = 0) -> Date { calendar.date(bySettingHour: h, minute: m, second: 0, of: d)! }
            var meals = [
                meal("Poha", .breakfast, 270, protein: 6, at: at(9, 10)),
                meal("Chai", .breakfast, 90, protein: 3, at: at(9, 15)),
                meal("Roti", .lunch, 240, protein: 8, at: at(13, 40)),
                meal("Dal makhani", .lunch, 330, protein: 12, at: at(13, 45)),
                meal("Paneer bhurji", .dinner, 420, protein: 24, at: at(21, 15)),
            ]
            if offset % 7 == 1 { meals.append(meal("Gulab jamun", .snacks, 300, protein: 4, at: at(17))) }
            var workouts: [LifeContext.Workout] = []
            if [2, 4, 6].contains(calendar.component(.weekday, from: d)) {      // Mon, Wed, Fri
                workouts = [.init(name: "Strength", minutes: 48, kcal: 310, source: "Apple Watch", start: at(18))]
            }
            if offset == 0 {
                meals = Array(meals.prefix(4))     // dinner not logged yet
                workouts = [.init(name: "Evening run", minutes: 42, kcal: 290, source: "Apple Watch", start: at(18, 10))]
            }
            days.append(LifeContext.Day(date: d, meals: meals, carbs: 160, fat: 38, budget: 2_050 + (workouts.isEmpty ? 0 : 145),
                                        water: offset == 0 ? 5 : 7, waterTarget: 8, workouts: workouts,
                                        steps: 6_120 + offset * 10, sleepHours: 6.4, weightKg: offset % 3 == 0 ? 72.0 + Double(offset) * 0.05 : nil))
        }
        let budget = LifeContext.Budget(total: 2_195, lines: [
            .init(.bmr, 1_650), .init(.everydayActivity, 330), .init(.goal, -500), .init(.floorTopUp, 70), .init(.exerciseCredit, 145),
        ], mode: "measured", eatBack: 0.5, rawActive: 620, allowance: 330, floor: 1_500)
        let presets = [
            LifeContext.PresetSummary(id: "p1", name: "Usual lunch", kcal: 570, meal: .lunch, uses: 12),
            LifeContext.PresetSummary(id: "p2", name: "Gym shake", kcal: 410, meal: .snacks, uses: 6),
            LifeContext.PresetSummary(id: "p3", name: "Chicken wrap", kcal: 520, meal: .dinner, uses: 1),
            LifeContext.PresetSummary(id: "p4", name: "Poha & Chai", kcal: 360, meal: .breakfast, uses: 20),
        ]
        let todos = [
            LifeContext.Todo(id: "t1", title: "Gym", due: date(2, 18), done: true),
            LifeContext.Todo(id: "t2", title: "Call Priya about the trip", due: date(2, 21)),
            LifeContext.Todo(id: "t3", title: "Buy protein powder"),
        ]
        return LifeContext(now: now, calendar: calendar, localeIdentifier: "en_IN",
                           profile: .init(goal: "lose weight", dietType: "vegetarian", units: "metric", age: 31, sex: "m", weightKg: 72.4, heightCm: 176),
                           days: days, budget: budget, macroTargets: .init(protein: 120, carbs: 230, fat: 60),
                           presets: presets, todos: todos, memories: memories)
    }

    static func memory(_ statement: String, now: Date = now) -> MemoryRecord? {
        guard let c = MemoryExtractor.extract(from: statement, now: now, calendar: calendar, explicit: true).first else { return nil }
        return MemoryReconciler.apply(c, to: [], embedder: HashingEmbedder(), now: now).record
    }
}
