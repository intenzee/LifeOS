import Foundation
import UIKit
import Vision

/// T4: Apple Vision classification exposed to the gateway as the last link of
/// the photo chain, so a scan still "never dead-ends". Runs on every iPhone.
///
/// - Schema v1 (`mealPhoto.analyze`): the legacy single best guess from
///   `OnDeviceMealAnalyzer`, unchanged.
/// - Schema v2 (`mealPhoto.analyze.v2`): up to four distinct foods Vision is
///   reasonably sure about, each sized by the nutrition catalog's typical
///   serving. The result card then asks the user to add anything missed.
enum VisionLegacyMealProvider {

    static func make() -> LocalHandlerProvider {
        LocalHandlerProvider(id: .visionLegacy, capabilities: [.text, .vision], handlers: [
            .mealPhotoAnalyze: { call in
                guard let data = call.input.images.first?.data else { throw AIError.unsupportedInput }
                if call.prompt.id.hasSuffix(".v2") {
                    let analysis = await analyzeV2(data)
                    guard !analysis.items.isEmpty else { throw AIError.invalidOutput("no recognisable food") }
                    return String(decoding: try JSONEncoder().encode(analysis), as: UTF8.self)
                }
                guard let estimate = await analyze(data) else {
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

    /// Multi-item on-device read for schema v2.
    private static func analyzeV2(_ jpegData: Data) async -> PhotoMealAnalysis {
        guard let cgImage = UIImage(data: jpegData)?.cgImage else { return PhotoMealAnalysis(mealName: "Meal", items: []) }
        let observations = await classify(cgImage)

        var seen = Set<String>()
        var items: [PhotoMealAnalysis.Item] = []
        let candidates = observations
            .filter { $0.confidence >= 0.12 && NutritionDatabase.isFoodLabel($0.identifier) }
            .sorted { $0.confidence > $1.confidence }
        for observation in candidates where items.count < 4 {
            let label = observation.identifier.replacingOccurrences(of: "_", with: " ")
            let key = FoodNameNormalizer.normalise(label)
            if let (record, _) = NutritionResolver().matchCatalog(key) {
                guard seen.insert(record.id).inserted else { continue }
                let grams = record.servingGrams
                let macros = record.macros(grams: grams)
                items.append(.init(name: record.name, estimatedGrams: grams, householdMeasure: "1 \(record.defaultUnit)",
                                   identificationConfidence: Double(observation.confidence),
                                   kcal: macros.kcal, protein: macros.protein, carbs: macros.carbs, fat: macros.fat))
            } else if let entry = NutritionDatabase.entry(for: observation.identifier.lowercased()) {
                guard seen.insert(entry.name.lowercased()).inserted else { continue }
                items.append(.init(name: entry.name.lowercased(), estimatedGrams: 0, householdMeasure: entry.serving,
                                   identificationConfidence: Double(observation.confidence),
                                   kcal: entry.calories, protein: entry.protein, carbs: entry.carbs, fat: entry.fat))
            }
        }
        let name = items.count == 1 ? items[0].name.capitalizedFirst
            : items.prefix(2).map { $0.name.capitalizedFirst }.joined(separator: " & ")
        return PhotoMealAnalysis(mealName: items.isEmpty ? "Meal" : name, items: items,
                                 notes: "On-device recognition — add anything it missed.")
    }

    private static func classify(_ cgImage: CGImage) async -> [VNClassificationObservation] {
        await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            try? handler.perform([request])
            return request.results ?? []
        }.value
    }
}
