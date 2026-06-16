import Foundation

extension Notification.Name {
    static let weekTodoListDidChange = Notification.Name("weekTodoListDidChange")
}

final class PersistenceManager {
    static let shared = PersistenceManager()

    // Water is stored per-day: "waterCount_YYYY-MM-dd"

    private let targetWeightKey = "targetWeight"
    private let currentWeightKey = "currentWeight"
    private let weekFoodKey = "weekFoodLog"
    private let weekTodoKey = "weekTodoList"
    private let weekGymKey = "weekGymLog"
    private let userProfileKey = "userProfile"

    // MARK: - User Profile (onboarding)

    func saveUserProfile(_ profile: UserProfile) {
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: userProfileKey)
        }
    }

    func loadUserProfile() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: userProfileKey),
              let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return nil
        }
        return decoded
    }

    // MARK: - Water (date-keyed)

    private func waterKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        return "waterCount_\(formatter.string(from: date))"
    }

    func saveWaterCount(_ count: Int, for date: Date = Date()) {
        UserDefaults.standard.set(count, forKey: waterKey(for: date))
    }

    func loadWaterCount(for date: Date = Date()) -> Int {
        UserDefaults.standard.integer(forKey: waterKey(for: date))
    }

    func saveTargetWeight(_ weight: Double) {
        UserDefaults.standard.set(weight, forKey: targetWeightKey)
    }

    func loadTargetWeight() -> Double {
        let saved = UserDefaults.standard.double(forKey: targetWeightKey)
        return saved > 0 ? saved : 68.0
    }

    func saveCurrentWeight(_ weight: Double) {
        UserDefaults.standard.set(weight, forKey: currentWeightKey)
    }

    func loadCurrentWeight() -> Double {
        let saved = UserDefaults.standard.double(forKey: currentWeightKey)
        return saved > 0 ? saved : 72.5
    }

    func saveWeekFoodLog(_ log: [String: DayMeals]) {
        if let encoded = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(encoded, forKey: weekFoodKey)
        }
    }

    func loadWeekFoodLog() -> [String: DayMeals] {
        guard let data = UserDefaults.standard.data(forKey: weekFoodKey),
              let decoded = try? JSONDecoder().decode([String: DayMeals].self, from: data) else {
            return defaultWeekFoodLog()
        }
        return decoded
    }

    func saveWeekTodoList(_ list: [String: [TodoItem]]) {
        if let encoded = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(encoded, forKey: weekTodoKey)
            NotificationCenter.default.post(name: .weekTodoListDidChange, object: nil)
        }
    }

    func loadWeekTodoList() -> [String: [TodoItem]] {
        guard let data = UserDefaults.standard.data(forKey: weekTodoKey),
              let decoded = try? JSONDecoder().decode([String: [TodoItem]].self, from: data) else {
            return defaultWeekTodoList()
        }
        return decoded
    }

    func saveWeekGymLog(_ log: [String: DayWorkout]) {
        if let encoded = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(encoded, forKey: weekGymKey)
        }
    }

    func loadWeekGymLog() -> [String: DayWorkout] {
        guard let data = UserDefaults.standard.data(forKey: weekGymKey),
              let decoded = try? JSONDecoder().decode([String: DayWorkout].self, from: data) else {
            return defaultWeekGymLog()
        }
        return decoded
    }

    private func defaultWeekFoodLog() -> [String: DayMeals] {
        ["Monday": DayMeals(), "Tuesday": DayMeals(), "Wednesday": DayMeals(),
         "Thursday": DayMeals(), "Friday": DayMeals(), "Saturday": DayMeals(), "Sunday": DayMeals()]
    }

    private func defaultWeekTodoList() -> [String: [TodoItem]] {
        ["Monday": [], "Tuesday": [], "Wednesday": [], "Thursday": [],
         "Friday": [], "Saturday": [], "Sunday": []]
    }

    private func defaultWeekGymLog() -> [String: DayWorkout] {
        ["Monday": DayWorkout(), "Tuesday": DayWorkout(), "Wednesday": DayWorkout(),
         "Thursday": DayWorkout(), "Friday": DayWorkout(), "Saturday": DayWorkout(), "Sunday": DayWorkout()]
    }
}