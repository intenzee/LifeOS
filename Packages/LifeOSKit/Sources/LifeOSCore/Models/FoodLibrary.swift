import Foundation

/// A reusable food (recent, favourite or custom). Not tied to a day.
/// Field names match the legacy `FoodItem` minus the per-log fields.
public struct FoodTemplate: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var servingSize: String
    public var barcode: String?
    public var defaultMeal: MealType

    public init(id: UUID = UUID(), name: String, calories: Double, protein: Double = 0, carbs: Double = 0,
                fat: Double = 0, servingSize: String = "1 serving", barcode: String? = nil,
                defaultMeal: MealType) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.servingSize = servingSize
        self.barcode = barcode
        self.defaultMeal = defaultMeal
    }
}

/// The user's recent, favourite and custom foods, stored as one document.
public struct FoodLibrary: Codable, Sendable, Equatable {
    public static let recentLimit = 20
    public static let customLimit = 50

    public var recent: [FoodTemplate]
    public var favorites: [FoodTemplate]
    public var custom: [FoodTemplate]

    public init(recent: [FoodTemplate] = [], favorites: [FoodTemplate] = [], custom: [FoodTemplate] = []) {
        self.recent = recent
        self.favorites = favorites
        self.custom = custom
    }

    /// Moves `food` to the front of `recent`, de-duplicating by name. Matches
    /// the legacy `FoodDatabaseManager.addFood` behaviour.
    public mutating func noteRecent(_ food: FoodTemplate) {
        recent.removeAll { $0.name == food.name }
        recent.insert(food, at: 0)
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
    }

    /// Adds or replaces a custom food, matching by name (case-insensitive) or barcode.
    public mutating func upsertCustom(_ food: FoodTemplate) {
        custom.removeAll {
            $0.name.caseInsensitiveCompare(food.name) == .orderedSame
                || ($0.barcode != nil && $0.barcode == food.barcode)
        }
        custom.insert(food, at: 0)
        if custom.count > Self.customLimit { custom = Array(custom.prefix(Self.customLimit)) }
    }

    public mutating func toggleFavorite(_ food: FoodTemplate) {
        if let index = favorites.firstIndex(where: { $0.id == food.id }) {
            favorites.remove(at: index)
        } else {
            favorites.append(food)
        }
    }
}
