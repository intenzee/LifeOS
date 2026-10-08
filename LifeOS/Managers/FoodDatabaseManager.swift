import Foundation
import Combine
import LifeOSData

/// Food log for the browsed date, plus recent, favourite and custom foods.
///
/// Since FND-04 the data lives in LifeOSData (`FoodEntry` records keyed by real
/// date, plus one `FoodLibrary` document). `LocalStore` preloads it at launch.
/// Each change saves just the affected record instead of re-encoding the
/// whole history (C6).
final class FoodDatabaseManager: ObservableObject {
    static let shared = FoodDatabaseManager()

    @Published var recentFoods: [FoodItem] = []
    @Published var favoriteFoods: [FoodItem] = []
    @Published var customFoods: [FoodItem] = []
    @Published var dailyLog: DailyFoodLog = DailyFoodLog()
    @Published var selectedDate: Date = Date()

    private weak var store: LocalStore?
    private var allDailyLogs: [DayKey: DailyFoodLog] = [:]
    /// Every logged entry ID, so re-logging a recent food never reuses an ID
    /// (the store upserts by ID).
    private var loggedIDs = Set<UUID>()

    init() {}

    func load(from snapshot: DataSnapshot, store: LocalStore) {
        self.store = store
        var logs: [DayKey: DailyFoodLog] = [:]
        for entry in snapshot.food {
            logs[entry.dayKey, default: DailyFoodLog()].addFood(FoodItem(entry))
        }
        allDailyLogs = logs
        loggedIDs = Set(snapshot.food.map(\.id))
        recentFoods = snapshot.foodLibrary.recent.map { FoodItem($0) }
        favoriteFoods = snapshot.foodLibrary.favorites.map { FoodItem($0) }
        customFoods = snapshot.foodLibrary.custom.map { FoodItem($0) }
        loadDailyLogForSelectedDate()
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        loadDailyLogForSelectedDate()
    }

    /// Read-only log for any date, without changing the selection. The Watch
    /// snapshot uses it to always report *today*.
    func dailyLog(for date: Date) -> DailyFoodLog {
        allDailyLogs[DayKey.make(for: date)] ?? DailyFoodLog()
    }

    private func loadDailyLogForSelectedDate() {
        dailyLog = allDailyLogs[DayKey.make(for: selectedDate)] ?? DailyFoodLog()
    }

    func addFood(_ food: FoodItem) {
        var food = food
        if loggedIDs.contains(food.id) {
            food = FoodItem(name: food.name, calories: food.calories, protein: food.protein, carbs: food.carbs,
                            fat: food.fat, servingSize: food.servingSize, barcode: food.barcode,
                            mealType: food.mealType, timestamp: food.timestamp,
                            source: food.source, aiConfidence: food.aiConfidence)
        }
        loggedIDs.insert(food.id)

        let day = DayKey.make(for: selectedDate)
        dailyLog.addFood(food)
        allDailyLogs[day] = dailyLog

        if let index = recentFoods.firstIndex(where: { $0.name == food.name }) {
            recentFoods.remove(at: index)
        }
        recentFoods.insert(food, at: 0)
        if recentFoods.count > 20 {
            recentFoods.removeLast()
        }

        let entry = food.entry(on: day)
        enqueue { db in try await db.food.save(entry) }
        saveLibrary()
    }

    func addCustomFood(_ food: FoodItem) {
        if let index = customFoods.firstIndex(where: { $0.name.caseInsensitiveCompare(food.name) == .orderedSame || ($0.barcode != nil && $0.barcode == food.barcode) }) {
            customFoods.remove(at: index)
        }

        customFoods.insert(food, at: 0)

        if customFoods.count > 50 {
            customFoods = Array(customFoods.prefix(50))
        }

        saveLibrary()
    }

    func removeFood(_ foodId: UUID) {
        let day = DayKey.make(for: selectedDate)
        dailyLog.removeFood(foodId)
        allDailyLogs[day] = dailyLog
        enqueue { db in try await db.food.delete(id: foodId, on: day) }
    }

    /// Saves an edited entry of the browsed date under the same id (the store
    /// upserts by id, and Health write-back reconciles the day from the store).
    /// `FoodItem` doesn't carry the v2 fields, so they're copied from the stored
    /// entry: amounts scale with `scale`, links (preset, photo, source) are kept.
    func updateFood(_ food: FoodItem, scale: Double = 1) {
        let day = DayKey.make(for: selectedDate)
        dailyLog.replaceFood(food)
        allDailyLogs[day] = dailyLog
        let edited = food.entry(on: day)
        enqueue { db in
            var entry = edited
            if let stored = try await db.food.entries(on: day).first(where: { $0.id == entry.id }) {
                entry.fiberG = stored.fiberG.map { $0 * scale }
                entry.sugarG = stored.sugarG.map { $0 * scale }
                entry.sodiumMg = stored.sodiumMg.map { $0 * scale }
                entry.grams = stored.grams.map { $0 * scale }
                entry.presetID = stored.presetID
                entry.photoAssetID = stored.photoAssetID
                entry.nutritionSourceRef = stored.nutritionSourceRef
            }
            try await db.food.save(entry)
        }
    }

    func toggleFavorite(_ food: FoodItem) {
        // Same rule as `isFavorite`: a recent or custom copy of a favourite has its
        // own id, so match by name too, or un-starring it would add a duplicate.
        let matching = favoriteFoods.indices.filter { favoriteFoods[$0].id == food.id || Self.sameName(favoriteFoods[$0], food) }
        if matching.isEmpty {
            favoriteFoods.append(food)
        } else {
            for index in matching.reversed() { favoriteFoods.remove(at: index) }
        }
        saveLibrary()
    }

    /// Drops recent foods matching `predicate` and saves the library.
    func removeRecents(where predicate: (FoodItem) -> Bool) {
        let before = recentFoods.count
        recentFoods.removeAll(where: predicate)
        if recentFoods.count != before { saveLibrary() }
    }

    func isFavorite(_ food: FoodItem) -> Bool {
        favoriteFoods.contains(where: { Self.sameName($0, food) })
    }

    private static func sameName(_ a: FoodItem, _ b: FoodItem) -> Bool {
        a.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(b.name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private func saveLibrary() {
        let library = FoodLibrary(recent: recentFoods.map(\.template), favorites: favoriteFoods.map(\.template),
                                  custom: customFoods.map(\.template))
        enqueue { db in try await db.foodLibrary.save(library) }
    }

    private func enqueue(_ write: @escaping @Sendable (LifeOSDatabase) async throws -> Void) {
        guard let store else {
            Log.food.fault("Food change before the store was ready was not saved")
            return
        }
        let db = store.database
        store.enqueue { try await write(db) }
    }

    var allFoods: [FoodItem] {
        let combined = recentFoods + customFoods + favoriteFoods + Self.commonFoods

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