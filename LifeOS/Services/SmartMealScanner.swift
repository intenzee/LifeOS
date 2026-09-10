import Foundation
import UIKit
import Vision

/// Free, on-device meal recognition.
///
/// Uses Apple's `VNClassifyImageRequest` — a built-in image classifier that runs
/// entirely on device, needs no model download, no network, and no API key. It
/// returns a ranked list of labels; we surface the food-related ones as candidates
/// for the user to confirm, which is far more reliable than blindly auto-picking a
/// single guess. Nutrition is then resolved for free from a bundled table of common
/// foods, falling back to the free OpenFoodFacts name search.
enum SmartMealScanner {

    struct Candidate: Identifiable, Hashable {
        var id: String { label }
        let label: String        // human-readable, e.g. "Banana"
        let rawIdentifier: String // Vision identifier, e.g. "banana"
        let confidence: Double   // 0...1
    }

    // MARK: - Classification

    /// Classifies a meal photo and returns up to `limit` food candidates, ranked by
    /// confidence. Runs on a background queue; completion is called on the main actor.
    static func classify(_ image: UIImage, limit: Int = 6) async -> [Candidate] {
        guard let cgImage = normalizedCGImage(image) else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
                return
            }

            let observations = (request.results ?? [])
                .filter { $0.confidence >= 0.05 }

            var seen = Set<String>()
            var candidates: [Candidate] = []
            for obs in observations {
                let raw = obs.identifier.lowercased()
                guard isFoodLabel(raw) else { continue }
                let label = prettify(raw)
                guard !seen.contains(label) else { continue }
                seen.insert(label)
                candidates.append(Candidate(label: label,
                                            rawIdentifier: raw,
                                            confidence: Double(obs.confidence)))
                if candidates.count >= limit { break }
            }
            continuation.resume(returning: candidates)
        }
    }

    // MARK: - Nutrition resolution

    /// Resolves nutrition for a candidate: bundled table first (instant, offline),
    /// then the free OpenFoodFacts name search. Always returns something usable.
    static func resolveNutrition(for candidate: Candidate,
                                 mealType: MealType,
                                 apiClient: any APIClient) async -> FoodItem {
        if let local = localFood(for: candidate.rawIdentifier, mealType: mealType) {
            return local
        }
        if let remote = try? await openFoodFactsSearch(term: candidate.label,
                                                       mealType: mealType,
                                                       apiClient: apiClient) {
            return remote
        }
        // Last resort: log the name with unknown macros so nothing is lost.
        return FoodItem(name: candidate.label, calories: 0, servingSize: "1 serving", mealType: mealType)
    }

    // MARK: - Helpers

    private static func normalizedCGImage(_ image: UIImage) -> CGImage? {
        if let cg = image.cgImage { return cg }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let redrawn = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return redrawn?.cgImage
    }

    private static func prettify(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// A label is food-worthy if it's in our nutrition table or matches a broad
    /// food-term list. Vision emits thousands of identifiers; this keeps meals in
    /// and scenery/objects out.
    private static func isFoodLabel(_ raw: String) -> Bool {
        if nutritionTable[raw] != nil { return true }
        return foodKeywords.contains(where: { raw.contains($0) })
    }

    // MARK: - OpenFoodFacts free name search

    private struct OFFSearchResponse: Decodable {
        let products: [OFFProduct]
    }
    private struct OFFProduct: Decodable {
        let product_name: String?
        let nutriments: OFFNutriments?
    }
    private struct OFFNutriments: Decodable {
        let energyKcal100g: Double?
        let proteins100g: Double?
        let carbohydrates100g: Double?
        let fat100g: Double?
        enum CodingKeys: String, CodingKey {
            case energyKcal100g = "energy-kcal_100g"
            case proteins100g = "proteins_100g"
            case carbohydrates100g = "carbohydrates_100g"
            case fat100g = "fat_100g"
        }
    }

    private static func openFoodFactsSearch(term: String,
                                            mealType: MealType,
                                            apiClient: any APIClient) async throws -> FoodItem? {
        let query = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
        let urlString = "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(query)&search_simple=1&action=process&json=1&page_size=1&fields=product_name,nutriments"
        guard let url = URL(string: urlString) else { return nil }
        let request = APIRequest<OFFSearchResponse>(
            url: url,
            headers: ["User-Agent": "LifeOS/1.0 (support@lifeos.app)", "Accept": "application/json"]
        )
        let response = try await apiClient.send(request)
        guard let product = response.products.first,
              let n = product.nutriments,
              let kcal = n.energyKcal100g, kcal > 0 else { return nil }
        return FoodItem(
            name: product.product_name?.isEmpty == false ? product.product_name! : term,
            calories: kcal,
            protein: n.proteins100g ?? 0,
            carbs: n.carbohydrates100g ?? 0,
            fat: n.fat100g ?? 0,
            servingSize: "100g",
            mealType: mealType
        )
    }

    /// Bundled nutrition for common foods, values for a typical single serving.
    private static func localFood(for rawIdentifier: String, mealType: MealType) -> FoodItem? {
        guard let e = nutritionTable[rawIdentifier] else { return nil }
        return FoodItem(name: e.name, calories: e.cal, protein: e.p, carbs: e.c, fat: e.f,
                        servingSize: e.serving, mealType: mealType)
    }

    private typealias Nutrition = (name: String, cal: Double, p: Double, c: Double, f: Double, serving: String)

    /// Common Vision food identifiers → typical-serving nutrition.
    private static let nutritionTable: [String: Nutrition] = [
        "banana": ("Banana", 105, 1.3, 27, 0.4, "1 medium"),
        "apple": ("Apple", 95, 0.5, 25, 0.3, "1 medium"),
        "orange": ("Orange", 62, 1.2, 15, 0.2, "1 medium"),
        "strawberry": ("Strawberries", 49, 1, 12, 0.5, "1 cup"),
        "grape": ("Grapes", 104, 1.1, 27, 0.2, "1 cup"),
        "watermelon": ("Watermelon", 46, 0.9, 12, 0.2, "1 cup"),
        "pineapple": ("Pineapple", 82, 0.9, 22, 0.2, "1 cup"),
        "mango": ("Mango", 99, 1.4, 25, 0.6, "1 cup"),
        "pizza": ("Pizza", 285, 12, 36, 10, "1 slice"),
        "hamburger": ("Hamburger", 354, 20, 29, 17, "1 burger"),
        "cheeseburger": ("Cheeseburger", 403, 22, 30, 22, "1 burger"),
        "hotdog": ("Hot Dog", 290, 11, 24, 17, "1 hot dog"),
        "sandwich": ("Sandwich", 300, 15, 34, 11, "1 sandwich"),
        "sushi": ("Sushi", 200, 9, 38, 1, "6 pieces"),
        "salad": ("Salad", 150, 5, 12, 9, "1 bowl"),
        "rice": ("Rice", 206, 4.3, 45, 0.4, "1 cup cooked"),
        "fried_rice": ("Fried Rice", 333, 12, 42, 12, "1 cup"),
        "bread": ("Bread", 79, 3, 14, 1, "1 slice"),
        "bagel": ("Bagel", 245, 10, 48, 1.5, "1 bagel"),
        "pancake": ("Pancakes", 175, 5, 22, 7, "2 pancakes"),
        "waffle": ("Waffle", 218, 6, 25, 11, "1 waffle"),
        "egg": ("Eggs", 78, 6, 0.6, 5, "1 large"),
        "omelette": ("Omelette", 154, 11, 1, 12, "1 omelette"),
        "bacon": ("Bacon", 92, 6, 0.2, 7, "2 slices"),
        "steak": ("Steak", 271, 25, 0, 19, "6 oz"),
        "chicken": ("Chicken Breast", 165, 31, 0, 3.6, "100g"),
        "fried_chicken": ("Fried Chicken", 320, 22, 12, 20, "1 piece"),
        "fish": ("Fish", 206, 22, 0, 12, "1 fillet"),
        "shrimp": ("Shrimp", 99, 24, 0.2, 0.3, "100g"),
        "pasta": ("Pasta", 221, 8, 43, 1.3, "1 cup"),
        "spaghetti": ("Spaghetti", 221, 8, 43, 1.3, "1 cup"),
        "noodle": ("Noodles", 219, 7, 40, 3, "1 cup"),
        "soup": ("Soup", 120, 6, 15, 4, "1 bowl"),
        "taco": ("Taco", 170, 8, 13, 9, "1 taco"),
        "burrito": ("Burrito", 445, 18, 55, 17, "1 burrito"),
        "french_fries": ("French Fries", 312, 3.4, 41, 15, "1 medium"),
        "potato": ("Potato", 161, 4.3, 37, 0.2, "1 medium"),
        "mashed_potato": ("Mashed Potato", 214, 4, 35, 9, "1 cup"),
        "ice_cream": ("Ice Cream", 273, 4.6, 31, 15, "1 cup"),
        "cake": ("Cake", 350, 5, 51, 15, "1 slice"),
        "cupcake": ("Cupcake", 305, 3, 47, 12, "1 cupcake"),
        "cookie": ("Cookie", 148, 1.5, 20, 7, "1 cookie"),
        "donut": ("Donut", 253, 4, 31, 14, "1 donut"),
        "chocolate": ("Chocolate", 155, 2, 17, 9, "1 bar (30g)"),
        "coffee": ("Coffee", 2, 0.3, 0, 0, "1 cup"),
        "smoothie": ("Smoothie", 200, 4, 40, 2, "1 cup"),
        "yogurt": ("Yogurt", 149, 8.5, 11, 8, "1 cup"),
        "cereal": ("Cereal", 200, 5, 43, 2, "1 cup"),
        "oatmeal": ("Oatmeal", 150, 5, 27, 3, "1 cup"),
        "avocado": ("Avocado", 240, 3, 12, 22, "1 medium"),
        "broccoli": ("Broccoli", 55, 3.7, 11, 0.6, "1 cup"),
        "carrot": ("Carrot", 25, 0.6, 6, 0.1, "1 medium"),
        "corn": ("Corn", 132, 5, 29, 2, "1 ear"),
        "cheese": ("Cheese", 113, 7, 0.4, 9, "1 slice (28g)"),
        "nuts": ("Mixed Nuts", 173, 5, 6, 15, "28g"),
        "peanut": ("Peanuts", 166, 7, 6, 14, "28g")
    ]

    /// Broad food terms that qualify a Vision label as food even without a table entry.
    private static let foodKeywords: Set<String> = [
        "food", "fruit", "vegetable", "meat", "bread", "cake", "pie", "pasta", "rice",
        "salad", "soup", "sauce", "cheese", "egg", "fish", "chicken", "beef", "pork",
        "seafood", "dessert", "snack", "sandwich", "burger", "pizza", "taco", "burrito",
        "sushi", "noodle", "curry", "stew", "drink", "juice", "coffee", "tea", "smoothie",
        "berry", "melon", "citrus", "bean", "nut", "potato", "tomato", "pepper", "mushroom",
        "dish", "meal", "breakfast", "lunch", "dinner", "pastry", "chocolate", "candy",
        "cereal", "yogurt", "milk", "cream", "grain", "wrap", "roll", "dumpling"
    ]
}
