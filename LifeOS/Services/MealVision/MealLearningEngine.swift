import UIKit

/// The self-improving layer of the meal scanner.
///
/// It turns user edits into a growing, on-device knowledge base and feeds that
/// knowledge back into every future scan — a practical, cost-free stand-in for
/// model fine-tuning:
///
///  1. **Record** — when the user corrects a result, we store the correction
///     keyed to the photo's `ImageSignature`.
///  2. **Retrieve** — on a new scan we find the most similar past corrections
///     (semantic embedding distance, with a perceptual-hash fast path).
///  3. **Apply** —
///       • a *near-identical* photo the user already fixed is answered directly
///         from memory (instant, offline, exactly their correction);
///       • otherwise the top matches are injected into the model prompt as
///         few-shot guidance, so the model stops repeating the same mistakes.
///
/// Over time this measurably shifts predictions toward the user's ground truth.
final class MealLearningEngine {

    static let shared = MealLearningEngine()

    private let store: CorrectionStore

    // MARK: Tuning

    /// Hamming distance (of 64 pHash bits) below which two photos are treated as
    /// the same shot → eligible for an instant learned override.
    private let nearDuplicateHamming = 8

    /// Feature-print distance below which a past correction is considered the
    /// *same dish* (different photo). Conservative to avoid false overrides.
    private let sameDishFeatureDistance: Float = 0.42

    /// How many past corrections to surface as few-shot hints.
    private let hintLimit = 4

    init(store: CorrectionStore = CorrectionStore()) {
        self.store = store
    }

    var correctionCount: Int { store.count }

    /// All learned corrections, most recently updated first — for the
    /// "Learned Corrections" management screen.
    var allCorrections: [MealCorrection] {
        store.all.sorted { $0.updatedAt > $1.updatedAt }
    }

    func delete(id: UUID) { store.remove(id: id) }

    // MARK: - Retrieve

    struct Match {
        let correction: MealCorrection
        let hamming: Int
        let featureDistance: Float?
    }

    /// Ranks stored corrections by similarity to `signature`, closest first.
    /// The query embedding is decoded once and reused across all candidates.
    func matches(for signature: ImageSignature) -> [Match] {
        let queryObservation = ImageSignatureBuilder.observation(from: signature.featurePrintData)
        return store.all
            .map { correction in
                let featureDistance = queryObservation.flatMap {
                    ImageSignatureBuilder.distance(from: $0, to: correction.signature.featurePrintData)
                }
                return Match(
                    correction: correction,
                    hamming: ImageSignatureBuilder.hammingDistance(signature.pHash, correction.signature.pHash),
                    featureDistance: featureDistance
                )
            }
            .sorted { lhs, rhs in
                // Prefer semantic distance when available; fall back to pHash.
                switch (lhs.featureDistance, rhs.featureDistance) {
                case let (l?, r?): return l < r
                case (nil, _?):    return false
                case (_?, nil):    return true
                default:           return lhs.hamming < rhs.hamming
                }
            }
    }

    /// A correction confident enough to serve *instead of* calling the model:
    /// either the same photo (tiny Hamming) or an unambiguous same-dish embedding.
    func instantOverride(for signature: ImageSignature) -> MealCorrection? {
        instantOverride(from: matches(for: signature))
    }

    /// Same, from a precomputed ranking (avoids a second similarity pass).
    func instantOverride(from ranked: [Match]) -> MealCorrection? {
        guard let best = ranked.first else { return nil }
        if best.hamming <= nearDuplicateHamming { return best.correction }
        if let d = best.featureDistance, d <= sameDishFeatureDistance { return best.correction }
        return nil
    }

    /// Few-shot guidance block for the model prompt, or `nil` if we've learned
    /// nothing relevant yet. Only reasonably-similar corrections are included so
    /// we never mislead the model with unrelated dishes.
    func learnedHints(for signature: ImageSignature) -> String? {
        learnedHints(from: matches(for: signature))
    }

    /// Same, from a precomputed ranking.
    func learnedHints(from ranked: [Match]) -> String? {
        let relevant = ranked
            .filter { match in
                if match.hamming <= nearDuplicateHamming { return true }
                if let d = match.featureDistance { return d <= sameDishFeatureDistance + 0.25 }
                return false
            }
            .prefix(hintLimit)

        guard !relevant.isEmpty else { return nil }

        let lines = relevant.map { match -> String in
            let c = match.correction
            let noteText = (c.note?.isEmpty == false) ? " User's note: \"\(c.note!)\"." : ""
            return "- A visually similar meal was corrected from \"\(c.originalName)\" to " +
                   "\"\(c.correctedName)\" (~\(Int(c.calories)) kcal, " +
                   "P\(Int(c.protein))/C\(Int(c.carbs))/F\(Int(c.fat)), \(c.servingSize)).\(noteText)"
        }

        return """
        The user has previously corrected your estimates on visually similar meals. \
        Treat these as strong ground-truth guidance and prefer consistency with them \
        when the dish looks alike (e.g. don't call it plain "fried rice" if a similar \
        plate was corrected to "egg fried rice"):
        \(lines.joined(separator: "\n"))
        """
    }

    /// Builds an analysis straight from a learned correction (no network).
    func analysis(from correction: MealCorrection) -> MealAnalysis {
        MealAnalysis(
            name: correction.correctedName,
            calories: correction.calories,
            protein: correction.protein,
            carbs: correction.carbs,
            fat: correction.fat,
            servingSize: correction.servingSize,
            confidence: 0.97,
            source: .learned
        )
    }

    // MARK: - Record

    /// Persists (or reinforces) a correction. Call this when the user edits a
    /// result — `original` is what the scanner produced, `corrected` is the
    /// ground truth they saved.
    func record(signature: ImageSignature,
                original: MealAnalysis,
                corrected: FoodItem,
                note: String? = nil) {
        let cleanedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let correction = MealCorrection(
            signature: signature,
            originalName: original.name,
            correctedName: corrected.name,
            calories: corrected.calories,
            protein: corrected.protein,
            carbs: corrected.carbs,
            fat: corrected.fat,
            servingSize: corrected.servingSize,
            note: (cleanedNote?.isEmpty == false) ? cleanedNote : nil
        )

        store.upsert(correction) { existing, incoming in
            // Same lesson if it's clearly the same photo, or the same dish label
            // on a visually close image — reinforce rather than duplicate.
            let hamming = ImageSignatureBuilder.hammingDistance(existing.signature.pHash,
                                                                incoming.signature.pHash)
            if hamming <= self.nearDuplicateHamming { return true }

            let sameLabel = existing.correctedName.caseInsensitiveCompare(incoming.correctedName) == .orderedSame
            if sameLabel,
               let d = ImageSignatureBuilder.featureDistance(existing.signature.featurePrintData,
                                                             incoming.signature.featurePrintData),
               d <= self.sameDishFeatureDistance {
                return true
            }
            return false
        }
    }

    func reset() { store.removeAll() }
}
