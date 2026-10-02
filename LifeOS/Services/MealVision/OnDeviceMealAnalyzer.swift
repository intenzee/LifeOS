import UIKit
import Vision

/// The always-available, zero-cost, offline fallback.
///
/// Uses Apple's built-in `VNClassifyImageRequest` (no model download, no key, no
/// network) to recognise the dominant food in a photo, then resolves macros from
/// the bundled `NutritionDatabase`. It can never be "unavailable" the way a cloud
/// model can, which is exactly why the engine leans on it to guarantee that a
/// scan always produces something loggable.
///
/// Its accuracy is deliberately modest — a single best-guess item, not a
/// full-plate macro breakdown — so it's the floor, not the ceiling.
struct OnDeviceMealAnalyzer {

    /// Classifies the image and returns a best-effort `MealAnalysis`.
    /// Returns `nil` only when nothing food-like is recognised at all.
    func analyze(_ image: UIImage) async -> MealAnalysis? {
        guard let cgImage = MealImageProcessor.uprightCGImage(image) else { return nil }

        let observations = await classify(cgImage)
        guard let best = firstFoodObservation(observations) else { return nil }

        let raw = best.identifier.lowercased()
        let confidence = Double(best.confidence)

        if let entry = NutritionDatabase.entry(for: raw) {
            return MealAnalysis(
                name: entry.name,
                calories: entry.calories,
                protein: entry.protein,
                carbs: entry.carbs,
                fat: entry.fat,
                servingSize: entry.serving,
                confidence: confidence,
                source: .onDevice
            )
        }

        // Recognised as food but not in the table: log the name so nothing is
        // lost. The user can adjust macros on the confirmation screen.
        return MealAnalysis(
            name: prettify(raw),
            calories: 0,
            servingSize: "1 serving",
            confidence: confidence,
            source: .onDevice
        )
    }

    // MARK: - Vision

    private func classify(_ cgImage: CGImage) async -> [VNClassificationObservation] {
        await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
                continuation.resume(returning: request.results ?? [])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    /// The highest-confidence observation that reads as food.
    private func firstFoodObservation(_ observations: [VNClassificationObservation]) -> VNClassificationObservation? {
        observations
            .filter { $0.confidence >= 0.05 && NutritionDatabase.isFoodLabel($0.identifier) }
            .max { $0.confidence < $1.confidence }
    }

    private func prettify(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
