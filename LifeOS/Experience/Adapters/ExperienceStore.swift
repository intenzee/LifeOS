import Combine
import Foundation
import LifeOSCore
import SwiftUI

/// The single bridge between the Phase 3 screens and the app's existing managers.
///
/// Screens never talk to `FoodDatabaseManager`, `WorkoutDatabaseManager`,
/// `PersistenceManager` or `StreakManager` directly: they read the computed
/// values here and call the actions below. Every write ends in `afterWrite()`,
/// which does what `HomeViewModel.syncStreaks()` does (streak summary for today
/// plus a Watch snapshot), so the classic Home, the Watch and the new
/// experience never disagree.
@MainActor
final class ExperienceStore: ObservableObject {
    let dependencies: AppDependencies

    @Published private(set) var waterCount = 0
    @Published private(set) var currentWeight: Double = 0
    @Published private(set) var targetWeight: Double = 0
    @Published private(set) var todos: [TodoItem] = []
    /// Bumped by the Health `objectWillChange` so the activity tile refreshes.
    @Published private(set) var lastHealthUpdate: Date? = nil

    private var bag = Set<AnyCancellable>()
    private let sources = ExperienceSourceLog()

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        reload()

        // Forward the managers' changes so SwiftUI re-reads the computed values.
        Publishers.MergeMany(
            dependencies.foodDatabase.objectWillChange,
            dependencies.workoutDatabase.objectWillChange,
            dependencies.streakManager.objectWillChange
        )
        .sink { [weak self] in self?.objectWillChange.send() }
        .store(in: &bag)

        dependencies.healthManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.lastHealthUpdate = Date() }
            .store(in: &bag)

        // The calorie engine recomputes budgets on its own (Health sync, settings):
        // redraw and refresh the widgets with its numbers.
        HealthSync.shared.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.objectWillChange.send()
                WidgetBridge.publish(self)
            }
            .store(in: &bag)

        // The Watch and the classic Todo tab write behind our back.
        NotificationCenter.default.publisher(for: .weekTodoListDidChange)
            .merge(with: NotificationCenter.default.publisher(for: .watchDidMutateData))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &bag)
    }

    var food: FoodDatabaseManager { dependencies.foodDatabase }
    var workouts: WorkoutDatabaseManager { dependencies.workoutDatabase }
    var health: HealthManager { dependencies.healthManager }

    // MARK: - Day

    var day: Date { food.selectedDate }
    var isToday: Bool { Calendar.current.isDateInToday(day) }

    func select(day newDay: Date) {
        food.selectDate(newDay)
        workouts.selectDate(newDay) // the two managers keep separate selected dates
        reload()
    }

    func reload() {
        let metrics = dependencies.dailyMetricsRepository
        waterCount = metrics.loadWaterCount(for: day)
        currentWeight = metrics.loadCurrentWeight()
        targetWeight = metrics.loadTargetWeight()
        todos = PersistenceManager.shared.todos(on: day)
    }

    /// Mirrors `HomeViewModel.onAppear()` minus the legacy HealthKit energy write.
    func onAppear() {
        health.requestFullAuthorization()
        workouts.selectDate(food.selectedDate)
        reload()
        afterWrite()
    }

    // MARK: - Reads

    var log: DailyFoodLog { food.dailyLog }
    var profile: UserProfile? { PersistenceManager.shared.loadUserProfile() }
    var waterTarget: Int { profile?.waterGoalGlasses ?? 8 }

    /// Workout energy as the rest of the app computes it today (MET estimate from
    /// logged sets). Apple Health active energy is shown separately on the tile;
    /// switching the budget to it belongs to the Health spec (CAL-07).
    var workoutKcal: Double { workouts.getTotalCaloriesBurned(weight: currentWeight) }
    var dayWorkout: DayWorkout { workouts.dailyWorkout }

    /// The calorie engine's budget for the selected day (CAL-03), via `HealthSync`.
    var budget: ExperienceBudget { EngineBudget.budget(on: day, eaten: log.totalCalories()) }

    var budgetLines: [ExperienceBudget.Line] {
        let measured = HealthSync.shared.energyByDay[DayKey.make(for: day)]?.budgetMode == .measured
        let note: String? = budget.activeEnergy <= 0 ? nil
            : measured ? "Measured by your Apple Watch, through Apple Health."
            : "Estimated from your workouts and the sets you logged."
        return budget.lines(activeSourceNote: note, derivation: budgetDerivation)
    }

    /// Present only while the limit is the automatic, profile-based one.
    var budgetDerivation: ExperienceBudget.Derivation? {
        guard !CalorieLimitSettings.shared.isManual, let p = profile else { return nil }
        return .init(maintenance: CalorieGoalCalculator.tdee(profile: p),
                     adjustment: CalorieGoalCalculator.weightGoalAdjustment(profile: p),
                     weeklyChangeKg: CalorieGoalCalculator.targetWeeklyChangeKg(profile: p))
    }

    var calorieLimitIsManual: Bool { HealthSync.shared.settings.manualTarget != nil }

    var macroTargets: (protein: Double, carbs: Double, fat: Double) {
        // From the engine's budget, like the Watch's protein bar.
        CalorieGoalCalculator.macroTargets(forCalories: HealthSync.shared.budget(on: DayKey.make(for: day)))
    }

    var orbState: LifeOrbState {
        var s = LifeOrbState.budget(eaten: budget.eaten, budget: budget.budget, earned: budget.earned)
        s.isStale = !isToday
        return s
    }

    var items: [FoodItem] { MealType.allCases.flatMap { items(in: $0) } }

    func items(in meal: MealType) -> [FoodItem] {
        switch meal {
        case .breakfast: return log.breakfast
        case .lunch: return log.lunch
        case .dinner: return log.dinner
        case .snacks: return log.snacks
        }
    }

    func source(of item: FoodItem) -> ExperienceTimelineEntry.Source {
        sources.source(for: item.id) ?? (item.barcode != nil ? .barcode : .manual)
    }

    var timeline: [ExperienceTimelineEntry] {
        var rows: [ExperienceTimelineEntry] = items.map { item in
            ExperienceTimelineEntry(id: item.id.uuidString, kind: .meal, title: item.name,
                                    detail: "\(ExperienceMealSlot(item.mealType).title) · \(item.servingSize)",
                                    kcal: Int(item.calories.rounded()), time: item.timestamp, source: source(of: item))
        }
        let w = dayWorkout
        if w.totalSets > 0 || w.treadmillDone {
            let parts = Array(Set(w.exercises.filter { $0.setsCompleted > 0 }.map(\.bodyPart.rawValue))).sorted()
            let title = parts.isEmpty ? "Treadmill" : parts.joined(separator: ", ")
            var detail = "\(w.totalSets) sets"
            if w.treadmillDone { detail += " · treadmill \(Int(w.treadmillDuration)) min" }
            rows.append(.init(id: "workout", kind: .workout, title: title, detail: detail,
                              kcal: -Int(budget.earned), time: nil, source: .manual))
        }
        if waterCount > 0 {
            rows.append(.init(id: "water", kind: .water, title: "Water",
                              detail: "\(waterCount) of \(waterTarget) glasses", kcal: nil, time: nil, source: .manual))
        }
        if let point = PersistenceManager.shared.loadWeightHistory().last(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
            rows.append(.init(id: "weight", kind: .weight, title: "Weight", detail: Self.weightText(point.weightKg, units: profile?.units),
                              kcal: nil, time: nil, source: .manual))
        }
        return ExperienceTimelineEntry.ordered(rows)
    }

    var currentSlot: ExperienceMealSlot { ExperienceMealSlot.slot(for: Date()) }

    /// Foods the user has logged before, ranked for "now".
    func presets(for slot: ExperienceMealSlot? = nil, limit: Int = 8) -> [ExperiencePresetCandidate] {
        let pool = food.favoriteFoods + food.recentFoods + food.customFoods
        let candidates = pool.map { f in
            ExperiencePresetCandidate(id: f.id.uuidString, nutrient: f.nutrient, slot: ExperienceMealSlot(f.mealType),
                                      isFavorite: food.isFavorite(f), lastUsed: f.timestamp)
        }
        return ExperiencePresetCandidate.ranked(candidates, for: slot ?? currentSlot, limit: limit)
    }

    /// The user's own foods, used first when resolving a typed or spoken meal.
    var userNutrients: [ExperienceNutrient] { food.allFoods.map(\.nutrient) }

    var nextUp: ExperienceNextUp? {
        guard isToday else { return nil }
        let slot = currentSlot
        return ExperienceNextUp.make(hasLoggedToday: !items.isEmpty,
                                     slot: slot,
                                     slotIsLogged: !items(in: slot.mealType).isEmpty,
                                     topPreset: presets(for: slot, limit: 1).first,
                                     waterGlasses: waterCount, waterTarget: waterTarget,
                                     hour: Calendar.current.component(.hour, from: Date()))
    }

    var perfectDayStreak: Int { dependencies.streakManager.perfectDayStreak }
    var todayScore: Int { dependencies.streakManager.summaries[dependencies.streakManager.dateKey(for: Date())]?.score ?? 0 }
    var last30Days: [DailySummary?] { dependencies.streakManager.last30Days() }

    var weekWorkouts: [(date: Date, workout: DayWorkout)] {
        (0..<7).reversed().compactMap { offset in
            guard let d = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return (d, workouts.workout(on: DayKey.make(for: d)))
        }
    }

    func workoutKcal(for workout: DayWorkout) -> Double {
        CalorieCalculator.totalWorkoutCalories(workout: workout, weightKg: currentWeight)
    }

    // MARK: - Writes

    /// Logs foods into the viewed day (same rule as the classic Home). Returns ids for Undo.
    @discardableResult
    func log(_ foods: [FoodItem], slot: ExperienceMealSlot, source: ExperienceTimelineEntry.Source) -> [UUID] {
        let now = Date()
        let logged = foods.map { f in
            FoodItem(name: f.name, calories: f.calories, protein: f.protein, carbs: f.carbs, fat: f.fat,
                     servingSize: f.servingSize, barcode: f.barcode, mealType: slot.mealType, timestamp: now)
        }
        for item in logged {
            food.addFood(item)
            sources.record(source, for: item.id)
        }
        afterWrite()
        return logged.map(\.id)
    }

    func logPreset(id: String, scale: Double = 1) -> [UUID]? {
        let pool = food.favoriteFoods + food.recentFoods + food.customFoods
        guard let f = pool.first(where: { $0.id.uuidString == id }) else { return nil }
        return log([f.scaledBy(scale)], slot: currentSlot, source: .preset)
    }

    func remove(_ ids: [UUID]) {
        ids.forEach(food.removeFood)
        afterWrite()
    }

    func toggleFavorite(_ item: FoodItem) {
        food.toggleFavorite(item)
        objectWillChange.send()
    }

    func addWater(_ delta: Int) {
        guard isToday else { return }
        let next = min(max(waterCount + delta, 0), 12) // same cap as the classic Home
        guard next != waterCount else { return }
        waterCount = next
        dependencies.dailyMetricsRepository.saveWaterCount(next, for: Date())
        afterWrite()
    }

    /// Same sequence as `HomeViewModel.saveWeights()`: store, sync profile, recompute an auto target.
    /// It does not write to Apple Health (the classic picker asks first).
    func logWeight(kg: Double) {
        guard kg.isFinite, kg > 20, kg < 400 else { return }
        currentWeight = kg
        dependencies.dailyMetricsRepository.saveCurrentWeight(kg)
        if var p = profile {
            p.currentWeightKg = kg
            PersistenceManager.shared.saveUserProfile(p)
        }
        CalorieLimitSettings.shared.recomputeFromProfileIfAuto()
        afterWrite()
    }

    func toggleTodo(_ id: UUID) {
        PersistenceManager.shared.toggleTodo(id: id, on: DayKey.make(for: day))
        reload()
        // Same reminder handling as the classic Todo tab.
        if let item = todos.first(where: { $0.id == id }) {
            if item.isCompleted {
                NotificationService.shared.cancelReminder(for: id)
            } else if let date = item.reminderDate, date > Date() {
                NotificationService.shared.scheduleReminder(for: item, at: date)
            }
        }
        afterWrite()
    }

    /// Adds a todo on `due`'s day (or today), with the same reminder scheduling as
    /// the classic Todo tab. The todo list is per week, so only days in the
    /// current week can be written; returns nil otherwise.
    @discardableResult
    func addTodo(title: String, due: Date? = nil) -> UUID? {
        let key = DayKey.make(for: due ?? Date())
        guard let name = WeekDays.currentWeek().first(where: { $0.day == key })?.name else { return nil }
        var week = PersistenceManager.shared.loadWeekTodoList()
        let item = TodoItem(title: title, reminderDate: due.flatMap { $0 > Date() ? $0 : nil })
        week[name, default: []].append(item)
        PersistenceManager.shared.saveWeekTodoList(week)
        if let date = item.reminderDate { NotificationService.shared.scheduleReminder(for: item, at: date) }
        reload()
        afterWrite()
        return item.id
    }

    /// Removes a todo from this week (Undo for `addTodo`).
    func removeTodo(_ id: UUID) {
        var week = PersistenceManager.shared.loadWeekTodoList()
        for name in week.keys { week[name]?.removeAll { $0.id == id } }
        PersistenceManager.shared.saveWeekTodoList(week)
        NotificationService.shared.cancelReminder(for: id)
        reload()
        afterWrite()
    }

    /// Moves a todo's reminder to `date` (nil clears it), rescheduling the notification.
    func rescheduleTodo(_ id: UUID, to date: Date?) {
        var week = PersistenceManager.shared.loadWeekTodoList()
        guard let name = week.first(where: { $0.value.contains { $0.id == id } })?.key,
              let index = week[name]?.firstIndex(where: { $0.id == id }) else { return }
        week[name]?[index].reminderDate = date
        PersistenceManager.shared.saveWeekTodoList(week)
        NotificationService.shared.cancelReminder(for: id)
        if let date, date > Date(), let item = week[name]?[index], !item.isCompleted {
            NotificationService.shared.scheduleReminder(for: item, at: date)
        }
        reload()
        afterWrite()
    }

    /// The reminder time of a todo this week, if any.
    func todoReminder(_ id: UUID) -> Date? {
        PersistenceManager.shared.loadWeekTodoList().values.flatMap { $0 }.first { $0.id == id }?.reminderDate
    }

    /// Eat-back share for activity, as the calorie engine uses it (0…1, steps of 10%).
    var eatBackShare: Double { EngineBudget.eatBack }

    func setEatBack(_ share: Double) {
        EngineBudget.setEatBack(min(max(share, 0), 1))
        afterWrite()
    }

    /// `HomeViewModel.syncStreaks()`: Watch mirror always; today's streak summary only when viewing today.
    func afterWrite() {
        objectWillChange.send()
        dependencies.watchConnectivity.sendSnapshot()
        WidgetBridge.publish(self) // Phase 5 §3: widgets, Lock Screen, StandBy
        guard isToday else { return }
        let b = budget
        dependencies.streakManager.recordToday(
            caloriesConsumed: b.eaten,
            calorieLimit: b.budget,
            waterGlasses: waterCount,
            waterTarget: waterTarget,
            gymIntensity: dayWorkout.intensity(weightKg: currentWeight),
            todosCompleted: todos.filter(\.isCompleted).count,
            todosTotal: todos.count)
    }

    // MARK: - Formatting

    static func weightText(_ kg: Double, units: MeasurementUnits?) -> String {
        if units == .imperial { return "\(String(format: "%.1f", kg * 2.20462)) lb" }
        return "\(String(format: "%.1f", kg)) kg"
    }
}

// MARK: - Bridges between app models and the pure core

extension ExperienceMealSlot {
    init(_ meal: MealType) {
        switch meal {
        case .breakfast: self = .breakfast
        case .lunch: self = .lunch
        case .dinner: self = .dinner
        case .snacks: self = .snack
        }
    }

    var mealType: MealType {
        switch self {
        case .breakfast: return .breakfast
        case .lunch: return .lunch
        case .dinner: return .dinner
        case .snack: return .snacks
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .snack: return "carrot"
        case .dinner: return "moon.stars"
        }
    }
}

extension FoodItem {
    var nutrient: ExperienceNutrient {
        ExperienceNutrient(name: name, kcal: calories, protein: protein, carbs: carbs, fat: fat, serving: servingSize)
    }

    init(_ resolved: ExperienceResolvedItem, slot: ExperienceMealSlot) {
        self.init(name: resolved.nutrient.name, calories: resolved.nutrient.kcal,
                  protein: (resolved.nutrient.protein * 10).rounded() / 10,
                  carbs: (resolved.nutrient.carbs * 10).rounded() / 10,
                  fat: (resolved.nutrient.fat * 10).rounded() / 10,
                  servingSize: resolved.amountText, mealType: slot.mealType)
    }

    func scaledBy(_ factor: Double) -> FoodItem {
        guard factor != 1, factor.isFinite, factor > 0 else { return self }
        var copy = self
        copy.calories = (calories * factor).rounded()
        copy.protein = protein * factor
        copy.carbs = carbs * factor
        copy.fat = fat * factor
        copy.servingSize = "\(factor == 0.5 ? "½" : String(format: "%g", factor))× \(servingSize)"
        return copy
    }
}

extension ExperienceTimelineEntry.Source {
    var lxSource: LXSource {
        switch self {
        case .manual, .barcode: return .manual
        case .photo: return .photo
        case .voice: return .voice
        case .preset: return .preset
        case .watch, .health: return .watch
        }
    }
}

extension ExperienceConfidence {
    var lx: LXConfidence {
        switch self {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }
}

/// `FoodItem` has no source field and persistence records AI logs as `.manual`,
/// so the new experience remembers how it logged each item (voice, photo, preset)
/// for the timeline badges. Small, local, pruned.
final class ExperienceSourceLog {
    private let key = "lx.experience.sources.v1"
    private let defaults = UserDefaults.standard
    /// "uuid|source", oldest first; capped so it never grows without bound.
    private var rows: [String]
    private var map: [String: String] = [:]

    init() {
        rows = defaults.stringArray(forKey: key) ?? []
        for row in rows {
            let parts = row.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2 { map[parts[0]] = parts[1] }
        }
    }

    func source(for id: UUID) -> ExperienceTimelineEntry.Source? {
        map[id.uuidString].flatMap(ExperienceTimelineEntry.Source.init(rawValue:))
    }

    func record(_ source: ExperienceTimelineEntry.Source, for id: UUID) {
        guard source != .manual else { return }
        map[id.uuidString] = source.rawValue
        rows.append("\(id.uuidString)|\(source.rawValue)")
        if rows.count > 500 { rows.removeFirst(rows.count - 500) }
        defaults.set(rows, forKey: key)
    }
}
