import Foundation

enum BarcodeFoodLookupError: Error {
    case invalidURL
}

struct OpenFoodFactsResponse: Decodable {
    let status: Int
    let product: OpenFoodFactsProduct?
}

struct OpenFoodFactsProduct: Decodable {
    let productName: String?
    let servingSize: String?
    let nutriments: OpenFoodFactsNutriments

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case servingSize = "serving_size"
        case nutriments
    }
}

struct OpenFoodFactsNutriments: Decodable {
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

final class BarcodeFoodLookup {
    static func lookup(barcode: String, apiClient: any APIClient) async throws -> FoodItem? {
        let urlString = "https://world.openfoodfacts.org/api/v2/product/\(barcode).json"
        guard let url = URL(string: urlString) else {
            throw BarcodeFoodLookupError.invalidURL
        }

        let headers = [
            "User-Agent": "LifeOS/1.0 (support@lifeos.app)",
            "Accept": "application/json"
        ]

        let request = APIRequest<OpenFoodFactsResponse>(
            url: url,
            method: .get,
            headers: headers
        )

        let response = try await apiClient.send(request)
        guard response.status == 1, let product = response.product else {
            return nil
        }

        let nutriments = product.nutriments
        return FoodItem(
            name: product.productName ?? "Unknown Product",
            calories: nutriments.energyKcal100g ?? 0,
            protein: nutriments.proteins100g ?? 0,
            carbs: nutriments.carbohydrates100g ?? 0,
            fat: nutriments.fat100g ?? 0,
            servingSize: product.servingSize ?? "100g",
            barcode: barcode,
            mealType: .snacks
        )
    }
}