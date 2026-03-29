import Foundation

final class BarcodeFoodLookup {
    static func lookup(barcode: String, completion: @escaping (FoodItem?) -> Void) {
        let urlString = "https://world.openfoodfacts.org/api/v0/product/\(barcode).json"

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? Int,
                   status == 1,
                   let product = json["product"] as? [String: Any] {

                    let name = product["product_name"] as? String ?? "Unknown Product"
                    let nutriments = product["nutriments"] as? [String: Any] ?? [:]

                    let calories = (nutriments["energy-kcal_100g"] as? Double) ?? 0
                    let protein = (nutriments["proteins_100g"] as? Double) ?? 0
                    let carbs = (nutriments["carbohydrates_100g"] as? Double) ?? 0
                    let fat = (nutriments["fat_100g"] as? Double) ?? 0

                    let food = FoodItem(
                        name: name,
                        calories: calories,
                        protein: protein,
                        carbs: carbs,
                        fat: fat,
                        servingSize: "100g",
                        barcode: barcode,
                        mealType: .snacks
                    )

                    DispatchQueue.main.async {
                        completion(food)
                    }
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }.resume()
    }
}