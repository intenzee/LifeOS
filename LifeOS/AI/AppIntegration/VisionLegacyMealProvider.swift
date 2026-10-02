import Foundation
import UIKit

/// T4 — the existing `OnDeviceMealAnalyzer` (Apple Vision classification +
/// bundled `NutritionDatabase`) exposed to the gateway as the last link of the
/// photo chain, so a scan still "never dead-ends".
enum VisionLegacyMealProvider {

    static func make() -> LocalHandlerProvider {
        LocalHandlerProvider(id: .visionLegacy, capabilities: [.text, .vision], handlers: [
            .mealPhotoAnalyze: { call in
                guard let data = call.input.images.first?.data,
                      let estimate = await analyze(data) else {
                    // Legacy contract: nil means "no recognisable food".
                    throw AIError.invalidOutput("no recognisable food")
                }
                return String(decoding: try JSONEncoder().encode(estimate), as: UTF8.self)
            },
        ])
    }

    @MainActor
    private static func analyze(_ jpegData: Data) async -> MealPhotoEstimate? {
        guard let image = UIImage(data: jpegData),
              let analysis = await OnDeviceMealAnalyzer().analyze(image) else { return nil }
        return MealPhotoEstimate(name: analysis.name, servingSize: analysis.servingSize,
                                 calories: analysis.calories, protein: analysis.protein,
                                 carbs: analysis.carbs, fat: analysis.fat, items: [],
                                 confidence: analysis.confidence)
    }
}
