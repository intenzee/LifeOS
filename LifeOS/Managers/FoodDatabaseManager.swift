import Foundation
import Combine

final class FoodDatabaseManager: ObservableObject {
    static let shared = FoodDatabaseManager()

    @Published var recentFoods: [FoodItem] = []
    @Published var favoriteFoods: [FoodItem] = []
    @Published var customFoods: [FoodItem] = []
    @Published var dailyLog: DailyFoodLog = DailyFoodLog()
    @Published var selectedDate: Date = Date()

    private let recentFoodsKey = "recentFoods"
    private let favoriteFoodsKey = "favoriteFoods"
    private let customFoodsKey = "customFoods"
    private let allDailyLogsKey = "allDailyFoodLogs"
    private var allDailyLogs: [String: DailyFoodLog] = [:]

    init() {
        loadData()
        loadDailyLogForSelectedDate()
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        loadDailyLogForSelectedDate()
    }

    private func loadDailyLogForSelectedDate() {
        let dateKey = dateToString(selectedDate)
        dailyLog = allDailyLogs[dateKey] ?? DailyFoodLog()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func dateToString(_ date: Date) -> String {
        return Self.dateFormatter.string(from: date)
    }

    func addFood(_ food: FoodItem) {
        dailyLog.addFood(food)

        let dateKey = dateToString(selectedDate)
        allDailyLogs[dateKey] = dailyLog

        if let index = recentFoods.firstIndex(where: { $0.name == food.name }) {
            recentFoods.remove(at: index)
        }
        recentFoods.insert(food, at: 0)
        if recentFoods.count > 20 {
            recentFoods.removeLast()
        }

        saveData()
    }

    func addCustomFood(_ food: FoodItem) {
        if let index = customFoods.firstIndex(where: { $0.name.caseInsensitiveCompare(food.name) == .orderedSame || ($0.barcode != nil && $0.barcode == food.barcode) }) {
            customFoods.remove(at: index)
        }

        customFoods.insert(food, at: 0)

        if customFoods.count > 50 {
            customFoods = Array(customFoods.prefix(50))
        }

        saveData()
    }

    func removeFood(_ foodId: UUID) {
        dailyLog.removeFood(foodId)

        let dateKey = dateToString(selectedDate)
        allDailyLogs[dateKey] = dailyLog

        saveData()
    }

    func toggleFavorite(_ food: FoodItem) {
        if let index = favoriteFoods.firstIndex(where: { $0.id == food.id }) {
            favoriteFoods.remove(at: index)
        } else {
            favoriteFoods.append(food)
        }
        saveData()
    }

    func isFavorite(_ food: FoodItem) -> Bool {
        favoriteFoods.contains(where: { $0.name == food.name })
    }

    private func saveData() {
        if let encoded = try? JSONEncoder().encode(recentFoods) {
            UserDefaults.standard.set(encoded, forKey: recentFoodsKey)
        }
        if let encoded = try? JSONEncoder().encode(favoriteFoods) {
            UserDefaults.standard.set(encoded, forKey: favoriteFoodsKey)
        }
        if let encoded = try? JSONEncoder().encode(customFoods) {
            UserDefaults.standard.set(encoded, forKey: customFoodsKey)
        }
        if let encoded = try? JSONEncoder().encode(allDailyLogs) {
            UserDefaults.standard.set(encoded, forKey: allDailyLogsKey)
        }
    }

    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: recentFoodsKey),
           let decoded = try? JSONDecoder().decode([FoodItem].self, from: data) {
            recentFoods = decoded
        }
        if let data = UserDefaults.standard.data(forKey: favoriteFoodsKey),
           let decoded = try? JSONDecoder().decode([FoodItem].self, from: data) {
            favoriteFoods = decoded
        }
        if let data = UserDefaults.standard.data(forKey: customFoodsKey),
           let decoded = try? JSONDecoder().decode([FoodItem].self, from: data) {
            customFoods = decoded
        }
        if let data = UserDefaults.standard.data(forKey: allDailyLogsKey),
           let decoded = try? JSONDecoder().decode([String: DailyFoodLog].self, from: data) {
            allDailyLogs = decoded
        }
    }

    var allFoods: [FoodItem] {
        var combined = recentFoods + customFoods + favoriteFoods + Self.commonFoods

        var uniqueFoods: [FoodItem] = []
        var seenNames = Set<String>()

        for food in combined {
            if !seenNames.contains(food.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                uniqueFoods.append(food)
                seenNames.insert(food.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }
        }
        return uniqueFoods
    }

    static let commonFoods: [FoodItem] = [
        FoodItem(name: "Chicken Breast (100g)", calories: 165, protein: 31, carbs: 0, fat: 3.6, servingSize: "100g", mealType: .lunch),
        FoodItem(name: "Brown Rice (1 cup)", calories: 216, protein: 5, carbs: 45, fat: 1.8, servingSize: "1 cup", mealType: .lunch),
        FoodItem(name: "Banana", calories: 105, protein: 1.3, carbs: 27, fat: 0.4, servingSize: "1 medium", mealType: .breakfast),
        FoodItem(name: "Eggs (2 large)", calories: 140, protein: 12, carbs: 1, fat: 10, servingSize: "2 eggs", mealType: .breakfast),
        FoodItem(name: "Oatmeal (1 cup)", calories: 150, protein: 5, carbs: 27, fat: 3, servingSize: "1 cup", mealType: .breakfast),
        FoodItem(name: "Protein Shake", calories: 120, protein: 24, carbs: 3, fat: 2, servingSize: "1 scoop", mealType: .breakfast),
        FoodItem(name: "Apple", calories: 95, protein: 0.5, carbs: 25, fat: 0.3, servingSize: "1 medium", mealType: .snacks),
        FoodItem(name: "Almonds (28g)", calories: 164, protein: 6, carbs: 6, fat: 14, servingSize: "28g", mealType: .snacks)
    ]
}