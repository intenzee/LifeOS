import Foundation

/// A small, bundled nutrition table for common foods — the offline backbone of
/// the on-device analyzer. Values are for one typical serving.
///
/// This is intentionally a single shared source of truth so both the quick
/// on-device path and any future feature can resolve a recognised label to
/// macros without a network call, a key, or a cost.
enum NutritionDatabase {

    struct Entry: Equatable {
        let name: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let serving: String
    }

    /// Look up by a Vision identifier or a loose food word. Tries the exact
    /// identifier first, then a contains-match against the keys, so "banana"
    /// and "cavendish_banana" both resolve.
    static func entry(for rawIdentifier: String) -> Entry? {
        let key = rawIdentifier.lowercased()
        if let exact = table[key] { return exact }
        if let fuzzy = table.first(where: { key.contains($0.key) || $0.key.contains(key) })?.value {
            return fuzzy
        }
        return nil
    }

    /// Whether a Vision label is food-worthy — either it's in the table or it
    /// matches a broad food term. Keeps meals in and scenery out.
    static func isFoodLabel(_ rawIdentifier: String) -> Bool {
        let key = rawIdentifier.lowercased()
        if table[key] != nil { return true }
        return keywords.contains { key.contains($0) }
    }

    // MARK: - Data

    static let table: [String: Entry] = [
        "banana": .init(name: "Banana", calories: 105, protein: 1.3, carbs: 27, fat: 0.4, serving: "1 medium"),
        "apple": .init(name: "Apple", calories: 95, protein: 0.5, carbs: 25, fat: 0.3, serving: "1 medium"),
        "orange": .init(name: "Orange", calories: 62, protein: 1.2, carbs: 15, fat: 0.2, serving: "1 medium"),
        "strawberry": .init(name: "Strawberries", calories: 49, protein: 1, carbs: 12, fat: 0.5, serving: "1 cup"),
        "grape": .init(name: "Grapes", calories: 104, protein: 1.1, carbs: 27, fat: 0.2, serving: "1 cup"),
        "watermelon": .init(name: "Watermelon", calories: 46, protein: 0.9, carbs: 12, fat: 0.2, serving: "1 cup"),
        "pineapple": .init(name: "Pineapple", calories: 82, protein: 0.9, carbs: 22, fat: 0.2, serving: "1 cup"),
        "mango": .init(name: "Mango", calories: 99, protein: 1.4, carbs: 25, fat: 0.6, serving: "1 cup"),
        "pizza": .init(name: "Pizza", calories: 285, protein: 12, carbs: 36, fat: 10, serving: "1 slice"),
        "hamburger": .init(name: "Hamburger", calories: 354, protein: 20, carbs: 29, fat: 17, serving: "1 burger"),
        "cheeseburger": .init(name: "Cheeseburger", calories: 403, protein: 22, carbs: 30, fat: 22, serving: "1 burger"),
        "hotdog": .init(name: "Hot Dog", calories: 290, protein: 11, carbs: 24, fat: 17, serving: "1 hot dog"),
        "sandwich": .init(name: "Sandwich", calories: 300, protein: 15, carbs: 34, fat: 11, serving: "1 sandwich"),
        "sushi": .init(name: "Sushi", calories: 200, protein: 9, carbs: 38, fat: 1, serving: "6 pieces"),
        "salad": .init(name: "Salad", calories: 150, protein: 5, carbs: 12, fat: 9, serving: "1 bowl"),
        "rice": .init(name: "Rice", calories: 206, protein: 4.3, carbs: 45, fat: 0.4, serving: "1 cup cooked"),
        "fried_rice": .init(name: "Fried Rice", calories: 333, protein: 12, carbs: 42, fat: 12, serving: "1 cup"),
        "bread": .init(name: "Bread", calories: 79, protein: 3, carbs: 14, fat: 1, serving: "1 slice"),
        "bagel": .init(name: "Bagel", calories: 245, protein: 10, carbs: 48, fat: 1.5, serving: "1 bagel"),
        "pancake": .init(name: "Pancakes", calories: 175, protein: 5, carbs: 22, fat: 7, serving: "2 pancakes"),
        "waffle": .init(name: "Waffle", calories: 218, protein: 6, carbs: 25, fat: 11, serving: "1 waffle"),
        "egg": .init(name: "Eggs", calories: 78, protein: 6, carbs: 0.6, fat: 5, serving: "1 large"),
        "omelette": .init(name: "Omelette", calories: 154, protein: 11, carbs: 1, fat: 12, serving: "1 omelette"),
        "bacon": .init(name: "Bacon", calories: 92, protein: 6, carbs: 0.2, fat: 7, serving: "2 slices"),
        "steak": .init(name: "Steak", calories: 271, protein: 25, carbs: 0, fat: 19, serving: "6 oz"),
        "chicken": .init(name: "Chicken Breast", calories: 165, protein: 31, carbs: 0, fat: 3.6, serving: "100g"),
        "fried_chicken": .init(name: "Fried Chicken", calories: 320, protein: 22, carbs: 12, fat: 20, serving: "1 piece"),
        "fish": .init(name: "Fish", calories: 206, protein: 22, carbs: 0, fat: 12, serving: "1 fillet"),
        "shrimp": .init(name: "Shrimp", calories: 99, protein: 24, carbs: 0.2, fat: 0.3, serving: "100g"),
        "pasta": .init(name: "Pasta", calories: 221, protein: 8, carbs: 43, fat: 1.3, serving: "1 cup"),
        "spaghetti": .init(name: "Spaghetti", calories: 221, protein: 8, carbs: 43, fat: 1.3, serving: "1 cup"),
        "noodle": .init(name: "Noodles", calories: 219, protein: 7, carbs: 40, fat: 3, serving: "1 cup"),
        "soup": .init(name: "Soup", calories: 120, protein: 6, carbs: 15, fat: 4, serving: "1 bowl"),
        "taco": .init(name: "Taco", calories: 170, protein: 8, carbs: 13, fat: 9, serving: "1 taco"),
        "burrito": .init(name: "Burrito", calories: 445, protein: 18, carbs: 55, fat: 17, serving: "1 burrito"),
        "french_fries": .init(name: "French Fries", calories: 312, protein: 3.4, carbs: 41, fat: 15, serving: "1 medium"),
        "potato": .init(name: "Potato", calories: 161, protein: 4.3, carbs: 37, fat: 0.2, serving: "1 medium"),
        "mashed_potato": .init(name: "Mashed Potato", calories: 214, protein: 4, carbs: 35, fat: 9, serving: "1 cup"),
        "ice_cream": .init(name: "Ice Cream", calories: 273, protein: 4.6, carbs: 31, fat: 15, serving: "1 cup"),
        "cake": .init(name: "Cake", calories: 350, protein: 5, carbs: 51, fat: 15, serving: "1 slice"),
        "cupcake": .init(name: "Cupcake", calories: 305, protein: 3, carbs: 47, fat: 12, serving: "1 cupcake"),
        "cookie": .init(name: "Cookie", calories: 148, protein: 1.5, carbs: 20, fat: 7, serving: "1 cookie"),
        "donut": .init(name: "Donut", calories: 253, protein: 4, carbs: 31, fat: 14, serving: "1 donut"),
        "chocolate": .init(name: "Chocolate", calories: 155, protein: 2, carbs: 17, fat: 9, serving: "1 bar (30g)"),
        "coffee": .init(name: "Coffee", calories: 2, protein: 0.3, carbs: 0, fat: 0, serving: "1 cup"),
        "smoothie": .init(name: "Smoothie", calories: 200, protein: 4, carbs: 40, fat: 2, serving: "1 cup"),
        "yogurt": .init(name: "Yogurt", calories: 149, protein: 8.5, carbs: 11, fat: 8, serving: "1 cup"),
        "cereal": .init(name: "Cereal", calories: 200, protein: 5, carbs: 43, fat: 2, serving: "1 cup"),
        "oatmeal": .init(name: "Oatmeal", calories: 150, protein: 5, carbs: 27, fat: 3, serving: "1 cup"),
        "avocado": .init(name: "Avocado", calories: 240, protein: 3, carbs: 12, fat: 22, serving: "1 medium"),
        "broccoli": .init(name: "Broccoli", calories: 55, protein: 3.7, carbs: 11, fat: 0.6, serving: "1 cup"),
        "carrot": .init(name: "Carrot", calories: 25, protein: 0.6, carbs: 6, fat: 0.1, serving: "1 medium"),
        "corn": .init(name: "Corn", calories: 132, protein: 5, carbs: 29, fat: 2, serving: "1 ear"),
        "cheese": .init(name: "Cheese", calories: 113, protein: 7, carbs: 0.4, fat: 9, serving: "1 slice (28g)"),
        "nuts": .init(name: "Mixed Nuts", calories: 173, protein: 5, carbs: 6, fat: 15, serving: "28g"),
        "peanut": .init(name: "Peanuts", calories: 166, protein: 7, carbs: 6, fat: 14, serving: "28g")
    ]

    static let keywords: Set<String> = [
        "food", "fruit", "vegetable", "meat", "bread", "cake", "pie", "pasta", "rice",
        "salad", "soup", "sauce", "cheese", "egg", "fish", "chicken", "beef", "pork",
        "seafood", "dessert", "snack", "sandwich", "burger", "pizza", "taco", "burrito",
        "sushi", "noodle", "curry", "stew", "drink", "juice", "coffee", "tea", "smoothie",
        "berry", "melon", "citrus", "bean", "nut", "potato", "tomato", "pepper", "mushroom",
        "dish", "meal", "breakfast", "lunch", "dinner", "pastry", "chocolate", "candy",
        "cereal", "yogurt", "milk", "cream", "grain", "wrap", "roll", "dumpling"
    ]
}
