import Foundation

final class CalorieSettings {
    static let shared = CalorieSettings()

    private let percentageKey = "caloriePercentage"

    func savePercentage(_ percentage: Double) {
        UserDefaults.standard.set(percentage, forKey: percentageKey)
    }

    func loadPercentage() -> Double {
        let saved = UserDefaults.standard.double(forKey: percentageKey)
        return saved > 0 ? saved : 0.5
    }
}

final class CalorieLimitSettings {
    static let shared = CalorieLimitSettings()

    private let limitKey = "dailyCalorieLimit"
    private let defaultLimit = 2200.0

    func saveLimit(_ limit: Double) {
        UserDefaults.standard.set(limit, forKey: limitKey)
    }

    func loadLimit() -> Double {
        let saved = UserDefaults.standard.double(forKey: limitKey)
        return saved > 0 ? saved : defaultLimit
    }
}