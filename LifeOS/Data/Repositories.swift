import Foundation

protocol DailyMetricsRepository {
    func loadWaterCount(for date: Date) -> Int
    func saveWaterCount(_ count: Int, for date: Date)
    func loadCurrentWeight() -> Double
    func saveCurrentWeight(_ weight: Double)
    func loadTargetWeight() -> Double
    func saveTargetWeight(_ weight: Double)
}

protocol WeeklyLogRepository {
    func loadWeekFoodLog() -> [String: DayMeals]
    func saveWeekFoodLog(_ log: [String: DayMeals])
    func loadWeekTodoList() -> [String: [TodoItem]]
    func saveWeekTodoList(_ list: [String: [TodoItem]])
    func loadWeekGymLog() -> [String: DayWorkout]
    func saveWeekGymLog(_ log: [String: DayWorkout])
}

final class LocalDailyMetricsRepository: DailyMetricsRepository {
    private let persistence: PersistenceManager

    init(persistence: PersistenceManager) {
        self.persistence = persistence
    }

    func loadWaterCount(for date: Date) -> Int {
        persistence.loadWaterCount(for: date)
    }

    func saveWaterCount(_ count: Int, for date: Date) {
        persistence.saveWaterCount(count, for: date)
    }

    func loadCurrentWeight() -> Double {
        persistence.loadCurrentWeight()
    }

    func saveCurrentWeight(_ weight: Double) {
        persistence.saveCurrentWeight(weight)
    }

    func loadTargetWeight() -> Double {
        persistence.loadTargetWeight()
    }

    func saveTargetWeight(_ weight: Double) {
        persistence.saveTargetWeight(weight)
    }
}

final class LocalWeeklyLogRepository: WeeklyLogRepository {
    private let persistence: PersistenceManager

    init(persistence: PersistenceManager) {
        self.persistence = persistence
    }

    func loadWeekFoodLog() -> [String: DayMeals] {
        persistence.loadWeekFoodLog()
    }

    func saveWeekFoodLog(_ log: [String: DayMeals]) {
        persistence.saveWeekFoodLog(log)
    }

    func loadWeekTodoList() -> [String: [TodoItem]] {
        persistence.loadWeekTodoList()
    }

    func saveWeekTodoList(_ list: [String: [TodoItem]]) {
        persistence.saveWeekTodoList(list)
    }

    func loadWeekGymLog() -> [String: DayWorkout] {
        persistence.loadWeekGymLog()
    }

    func saveWeekGymLog(_ log: [String: DayWorkout]) {
        persistence.saveWeekGymLog(log)
    }
}
