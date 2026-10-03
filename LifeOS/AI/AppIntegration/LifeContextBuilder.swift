import Foundation
import LifeOSCore

/// Builds the AI's `LifeContext` from the app's live stores (iOS-only glue).
///
/// Read-only: days come from the Experience snapshot (the same facts the rule
/// brain answers from), today's workouts and budget from the calorie engine via
/// `HealthSync` (CAL-07, never recomputed here), presets from the AI preset
/// store and memories from the AI memory index.
@MainActor
enum LifeContextBuilder {

    static func make(_ snap: IntelligenceSnapshot, store: ExperienceStore? = nil, presets: [FoodPreset] = [],
                     memories: [MemoryRecord] = [], conversationSummary: String? = nil) -> LifeContext {
        let cal = snap.calendar
        let health = HealthSync.shared
        let profile = PersistenceManager.shared.loadUserProfile()

        let days: [LifeContext.Day] = snap.days.map { d in
            let isToday = cal.isDate(d.date, inSameDayAs: snap.now)
            var workouts: [LifeContext.Workout] = []
            if isToday {
                workouts = health.todaySessions.map(workout)
                if d.gymSets > 0, !health.todaySessions.contains(where: { $0.kind.mergesWithGymLog }) {
                    workouts.append(.init(name: "Gym sets", minutes: Int(Double(d.gymSets) * 2.5), kcal: d.workoutKcal, source: "LifeOS sets"))
                }
            } else if d.trained {
                workouts = [.init(name: "Gym sets", minutes: Int(Double(d.gymSets) * 2.5), kcal: d.workoutKcal, source: "LifeOS sets")]
            }
            return LifeContext.Day(date: d.date,
                                   meals: d.meals.map { .init(name: $0.name, slot: slot($0.slot), kcal: $0.kcal, protein: $0.protein, time: $0.time) },
                                   budget: d.budget, water: d.water, waterTarget: d.waterTarget, workouts: workouts,
                                   steps: nil, sleepHours: nil, weightKg: d.weightKg)
        }

        var records = memories
        // The profile's diet is a user-stated fact even before they mention it in chat.
        if let profile, !records.contains(where: { if case .diet? = $0.facet { $0.isUsable(at: snap.now) } else { false } }) {
            let diet: String? = profile.diet == .vegetarian ? "vegetarian" : profile.diet == .vegan ? "vegan" : nil
            if let diet {
                records.append(MemoryRecord(id: "profile.diet", kind: .fact, text: "You're \(diet) (from your profile)",
                                            facet: .diet(diet, exceptions: [], days: []), importance: 0.9, createdAt: snap.now))
            }
        }

        let targets = store?.macroTargets
        return LifeContext(
            now: snap.now, calendar: cal, localeIdentifier: Locale.current.identifier,
            profile: profile.map { p in
                LifeContext.Profile(goal: goal(p.goal), dietType: p.diet == .balanced ? nil : p.diet.rawValue.lowercased(),
                                    units: p.units == .metric ? "metric" : "imperial", age: p.age,
                                    sex: p.sex == .male ? "m" : p.sex == .female ? "f" : nil,
                                    weightKg: p.currentWeightKg > 0 ? p.currentWeightKg : nil, heightCm: p.heightCm)
            },
            days: days,
            budget: budget(snap),
            macroTargets: targets.map { .init(protein: $0.protein, carbs: $0.carbs, fat: $0.fat) }
                ?? (snap.proteinTarget > 0 ? .init(protein: snap.proteinTarget) : nil),
            presets: presets.filter { !$0.archived }.map {
                .init(id: $0.id.uuidString, name: $0.name, kcal: $0.items.reduce(0) { $0 + $1.macros.kcal },
                      meal: $0.defaultMeal, uses: $0.usageCount)
            },
            todos: (store?.todos ?? []).map {
                .init(id: $0.id.uuidString, title: $0.title, due: $0.reminderDate, done: $0.isCompleted)
            },
            memories: records,
            conversationSummary: conversationSummary)
    }

    static func workout(_ s: WorkoutSession) -> LifeContext.Workout {
        let minutes = max(1, Int((s.end.timeIntervalSince(s.start) / 60).rounded()))
        let source = s.sourceName ?? (s.source == .watch ? "Apple Watch" : s.source == .healthKit ? "Apple Health" : "LifeOS")
        return LifeContext.Workout(name: s.kind.displayName, minutes: minutes, kcal: s.activeEnergyKcal ?? 0, source: source, start: s.start)
    }

    static func budget(_ snap: IntelligenceSnapshot) -> LifeContext.Budget? {
        let total = HealthSync.shared.budget(on: .today())
        guard total > 0 else { return nil }
        guard let b = EngineBudget.breakdown(on: .today()) else { return LifeContext.Budget(total: total) }
        let mode: String
        switch b.mode {
        case .measured: mode = "measured"
        case .estimated: mode = "estimated"
        case .fixed: mode = "fixed"
        case .classic: mode = "classic"
        }
        let lines = b.lines.compactMap { line in
            LifeContext.BudgetLine.Kind(rawValue: line.kind.rawValue).map { LifeContext.BudgetLine($0, line.kcal) }
        }
        // `total` is the stored, possibly frozen, figure every screen shows.
        return LifeContext.Budget(total: total, lines: lines, mode: mode, eatBack: b.eatBack, rawActive: b.rawActive,
                                  allowance: b.allowance, floor: b.floor)
    }

    static func slot(_ s: ExperienceMealSlot) -> ParsedMeal.MealSlot {
        switch s {
        case .breakfast: .breakfast
        case .lunch: .lunch
        case .snack: .snacks
        case .dinner: .dinner
        }
    }

    static func goal(_ g: FitnessGoal) -> String {
        switch g {
        case .loseWeight: "lose weight"
        case .maintain: "maintain"
        case .gainMuscle: "gain muscle"
        case .improveFitness: "improve fitness"
        }
    }
}
