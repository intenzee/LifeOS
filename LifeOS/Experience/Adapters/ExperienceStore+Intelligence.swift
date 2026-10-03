import Foundation

extension ExperienceStore {
    /// The last 28 days as pure facts for the assistant, memory inference,
    /// insights and automation previews (Phase 4). Reads only; never writes.
    func intelligenceSnapshot(memories: [MemoryItem], days: Int = 28, now: Date = Date()) -> IntelligenceSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let streaks = dependencies.streakManager
        let metrics = dependencies.dailyMetricsRepository
        let share = CalorieSettings.shared.loadPercentage()
        let base = CalorieLimitSettings.shared.loadLimit()
        let weights = PersistenceManager.shared.loadWeightHistory()

        let facts: [DayFacts] = (0..<days).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let log = food.dailyLog(for: d)
            let meals: [DayFacts.Meal] = MealType.allCases.flatMap { type -> [DayFacts.Meal] in
                let list: [FoodItem]
                switch type {
                case .breakfast: list = log.breakfast
                case .lunch: list = log.lunch
                case .dinner: list = log.dinner
                case .snacks: list = log.snacks
                }
                return list.map { DayFacts.Meal(name: $0.name, slot: ExperienceMealSlot(type), kcal: $0.calories, protein: $0.protein, time: $0.timestamp) }
            }
            let workout = workouts.workout(on: DayKey.make(for: d))
            let wk = CalorieCalculator.totalWorkoutCalories(workout: workout, weightKg: currentWeight)
            // A recorded streak summary has that day's real budget; otherwise use today's settings.
            let budget = streaks.summaries[streaks.dateKey(for: d)]?.calorieLimit ?? (base + (wk * share).rounded())
            let weight = weights.last { cal.isDate($0.date, inSameDayAs: d) }?.weightKg
            return DayFacts(date: d, meals: meals, budget: budget, water: metrics.loadWaterCount(for: d), waterTarget: waterTarget,
                            workoutKcal: wk, gymSets: workout.totalSets, weightKg: weight)
        }
        // Today's budget and eaten always come from today, whatever day the UI is showing.
        let todayBudget = ExperienceBudget(baseLimit: base,
                                           activeEnergy: CalorieCalculator.totalWorkoutCalories(workout: workouts.workout(on: DayKey.make(for: now)), weightKg: currentWeight),
                                           eatBackShare: share,
                                           eaten: food.dailyLog(for: now).totalCalories())
        return IntelligenceSnapshot(days: facts, now: now, proteinTarget: macroTargets.protein, budgetToday: todayBudget, memories: memories)
    }
}
