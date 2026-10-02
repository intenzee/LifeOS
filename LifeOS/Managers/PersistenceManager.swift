import Foundation
import LifeOSData

extension Notification.Name {
    static let weekTodoListDidChange = Notification.Name("weekTodoListDidChange")
}

/// Profile, water, weight, todos and the protein checklist.
///
/// Since FND-04 the data lives in LifeOSData. `LocalStore` preloads it at
/// launch, reads here are synchronous from memory, and every save is queued
/// to the store. The weekday-name methods keep the week-picker UI working:
/// "Monday" always means the Monday of the *current* week, resolved to a real
/// date before saving, so nothing is overwritten or deleted when the week
/// rolls over (fixes C1).
final class PersistenceManager {
    static let shared = PersistenceManager()

    private let targetWeightKey = "targetWeight"
    private let currentWeightKey = "currentWeight"

    private weak var store: LocalStore?
    private var profile: UserProfile?
    private var water: [DayKey: Int] = [:]
    private var weights: [WeightEntry] = []
    private var tasks: [DayKey: [TaskItem]] = [:]
    private var protein: [DayKey: ProteinChecklist] = [:]

    func load(from snapshot: DataSnapshot, store: LocalStore) {
        self.store = store
        profile = snapshot.profile
        water = Dictionary(snapshot.water.map { ($0.dayKey, $0.glasses) }, uniquingKeysWith: { _, last in last })
        weights = snapshot.weight
        tasks = Dictionary(grouping: snapshot.tasks, by: \.dayKey)
        protein = Dictionary(snapshot.proteinChecklist.map { ($0.dayKey, $0) }, uniquingKeysWith: { _, last in last })
    }

    private var database: LifeOSDatabase? { store?.database }

    // MARK: - User Profile (onboarding)

    func saveUserProfile(_ profile: UserProfile) {
        self.profile = profile
        guard let store else { return }
        let db = store.database
        store.enqueue { try await db.profile.save(profile) }
    }

    func loadUserProfile() -> UserProfile? {
        profile
    }

    // MARK: - Water (date-keyed)

    func saveWaterCount(_ count: Int, for date: Date = Date()) {
        let day = DayKey.make(for: date)
        water[day] = max(0, count)
        guard let store else { return }
        let db = store.database
        store.enqueue { try await db.water.setGlasses(count, on: day, source: .manual) }
    }

    func loadWaterCount(for date: Date = Date()) -> Int {
        water[DayKey.make(for: date)] ?? 0
    }

    // MARK: - Weight goals (preferences, stay in UserDefaults)

    func saveTargetWeight(_ weight: Double) {
        UserDefaults.standard.set(weight, forKey: targetWeightKey)
    }

    func loadTargetWeight() -> Double {
        let saved = UserDefaults.standard.double(forKey: targetWeightKey)
        return saved > 0 ? saved : (profile?.targetWeightKg ?? 68.0)
    }

    func saveCurrentWeight(_ weight: Double) {
        UserDefaults.standard.set(weight, forKey: currentWeightKey)
        recordWeightPoint(weight)
    }

    func loadCurrentWeight() -> Double {
        let saved = UserDefaults.standard.double(forKey: currentWeightKey)
        return saved > 0 ? saved : (profile?.currentWeightKg ?? 72.5)
    }

    // MARK: - Weight history (one point per day)

    /// Records the day's weight, replacing any earlier manual entry for that day.
    func recordWeightPoint(_ weight: Double, on date: Date = Date()) {
        guard weight > 0 else { return }
        let day = DayKey.make(for: date)
        weights.removeAll { $0.dayKey == day && $0.source == .manual && $0.healthKitUUID == nil }
        weights.append(WeightEntry(id: StableID.make("weight", day.rawValue, EntrySource.manual.rawValue),
                                   dayKey: day, measuredAt: date, kg: weight, source: .manual))
        guard let store else { return }
        let db = store.database
        store.enqueue { try await db.weight.setDailyWeight(weight, on: day, measuredAt: date, source: .manual) }
    }

    /// Weight history as dated points (latest reading per day), oldest first.
    func loadWeightHistory() -> [(date: Date, weightKg: Double)] {
        let latestPerDay = Dictionary(grouping: weights, by: \.dayKey)
            .compactMapValues { $0.max { $0.measuredAt < $1.measuredAt } }
        return latestPerDay.keys.sorted().compactMap { day in
            latestPerDay[day].map { (day.startDate(), $0.kg) }
        }
    }

    // MARK: - Protein checklist (week picker)

    func saveWeekFoodLog(_ log: [String: DayMeals]) {
        for (name, meals) in log {
            guard let day = WeekDays.dayKey(for: name) else { continue }
            let checklist = ProteinChecklist(dayKey: day, breakfast: meals.breakfast, lunch: meals.lunch,
                                             dinner: meals.dinner, snacks: meals.snacks)
            guard protein[day] != checklist else { continue }
            protein[day] = checklist.isEmpty ? nil : checklist
            if let store {
                let db = store.database
                store.enqueue { try await db.proteinChecklist.save(checklist) }
            }
        }
    }

    func loadWeekFoodLog() -> [String: DayMeals] {
        Dictionary(uniqueKeysWithValues: WeekDays.currentWeek().map { name, day in
            let checklist = protein[day] ?? ProteinChecklist(dayKey: day)
            return (name, DayMeals(breakfast: checklist.breakfast, lunch: checklist.lunch,
                                   dinner: checklist.dinner, snacks: checklist.snacks))
        })
    }

    // MARK: - Todos (week picker)

    func saveWeekTodoList(_ list: [String: [TodoItem]]) {
        let now = Date()
        for (name, todos) in list {
            guard let day = WeekDays.dayKey(for: name) else { continue }
            let existing = Dictionary((tasks[day] ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let updated = todos.map { todo -> TaskItem in
                let previous = existing[todo.id]
                let completedAt = todo.isCompleted ? (previous?.completedAt ?? now) : nil
                return TaskItem(id: todo.id, dayKey: day, title: todo.title, isCompleted: todo.isCompleted,
                                completedAt: completedAt, reminderAt: todo.reminderDate,
                                createdAt: previous?.createdAt ?? now, source: previous?.source ?? .manual)
            }
            let removed = Set(existing.keys).subtracting(updated.map(\.id))
            let changed = updated.filter { existing[$0.id] != $0 }
            tasks[day] = updated.isEmpty ? nil : updated

            guard let store, !(removed.isEmpty && changed.isEmpty) else { continue }
            let db = store.database
            store.enqueue {
                for id in removed { try await db.tasks.delete(id: id, on: day) }
                for task in changed { try await db.tasks.save(task) }
            }
        }
        NotificationCenter.default.post(name: .weekTodoListDidChange, object: nil)
    }

    func loadWeekTodoList() -> [String: [TodoItem]] {
        Dictionary(uniqueKeysWithValues: WeekDays.currentWeek().map { name, day in
            (name, (tasks[day] ?? []).map {
                TodoItem(id: $0.id, title: $0.title, isCompleted: $0.isCompleted, reminderDate: $0.reminderAt)
            })
        })
    }

    /// Toggles one todo on a specific date (any week). Used by the Watch.
    func toggleTodo(id: UUID, on day: DayKey, at now: Date = Date()) {
        guard var dayTasks = tasks[day], let index = dayTasks.firstIndex(where: { $0.id == id }) else { return }
        dayTasks[index].isCompleted.toggle()
        dayTasks[index].completedAt = dayTasks[index].isCompleted ? now : nil
        tasks[day] = dayTasks
        let task = dayTasks[index]
        if let store {
            let db = store.database
            store.enqueue { try await db.tasks.save(task) }
        }
        NotificationCenter.default.post(name: .weekTodoListDidChange, object: nil)
    }

    /// Todos for a specific date (any week).
    func todos(on date: Date) -> [TodoItem] {
        (tasks[DayKey.make(for: date)] ?? []).map {
            TodoItem(id: $0.id, title: $0.title, isCompleted: $0.isCompleted, reminderDate: $0.reminderAt)
        }
    }

    // MARK: - Gym log (week picker)

    func saveWeekGymLog(_ log: [String: DayWorkout]) {
        for (name, workout) in log {
            guard let day = WeekDays.dayKey(for: name) else { continue }
            WorkoutDatabaseManager.shared.replaceWorkout(workout, on: day)
        }
    }

    func loadWeekGymLog() -> [String: DayWorkout] {
        Dictionary(uniqueKeysWithValues: WeekDays.currentWeek().map { name, day in
            (name, WorkoutDatabaseManager.shared.workout(on: day))
        })
    }
}
