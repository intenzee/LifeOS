import UIKit

/// The single entry point the UI talks to. It orchestrates the two analyzers to
/// deliver the product promise: **free, and it never dead-ends.**
///
/// Strategy:
///  • With a Groq key → try the cloud model for a full-plate macro read. If that
///    fails for any recoverable reason (model retired, network, bad response,
///    server hiccup), transparently fall back to the on-device estimate so the
///    user still gets a logged meal. Only hard, user-actionable failures
///    (bad key, rate limit) are surfaced without a silent fallback — but even
///    then we hand back an on-device analysis to log if one exists.
///  • Without a key → go straight to on-device.
///
/// The result is a `MealScanOutcome` that always carries a usable `MealAnalysis`
/// (unless the photo contains no recognisable food at all), plus a note about
/// whether the premium path degraded — which the UI can show as a gentle banner.
struct MealScannerEngine {

    private let groq: GroqMealAnalyzer
    private let onDevice: OnDeviceMealAnalyzer
    private let learning: MealLearningEngine

    init(groq: GroqMealAnalyzer = GroqMealAnalyzer(),
         onDevice: OnDeviceMealAnalyzer = OnDeviceMealAnalyzer(),
         learning: MealLearningEngine = .shared) {
        self.groq = groq
        self.onDevice = onDevice
        self.learning = learning
    }

    /// Analyzes a meal photo.
    /// - Returns: an outcome whose `analysis` is ready to log.
    /// - Throws: only when there is genuinely nothing to log — i.e. no key,
    ///   Groq failed, AND on-device recognised no food. In that single case the
    ///   thrown `MealScanError` explains why so the UI can guide the user.
    func scan(image: UIImage, groqKey: String?) async throws -> MealScanOutcome {
        let trimmedKey = groqKey?.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Normalise the photo once; the bitmap feeds both Groq and fingerprinting.
        guard let prepared = MealImageProcessor.prepare(image) else {
            throw MealScanError.imageEncodingFailed
        }

        // 2. Fingerprint the meal so we can recall past corrections and file new ones.
        let signature: ImageSignature?
        if let cg = prepared.cgImage {
            signature = await ImageSignatureBuilder.make(from: cg)
        } else if let cg = MealImageProcessor.uprightCGImage(image) {
            signature = await ImageSignatureBuilder.make(from: cg)
        } else {
            signature = nil
        }

        // 3. Rank past corrections once; reuse for both the override and hints.
        let matches = signature.map { learning.matches(for: $0) } ?? []

        // Instant learned override: a photo the user already corrected is
        // answered from memory — free, offline, and exactly their ground truth.
        if let signature, let override = learning.instantOverride(from: matches) {
            return MealScanOutcome(analysis: learning.analysis(from: override),
                                   degradedFrom: nil,
                                   signature: signature)
        }

        // 4. No key: on-device recognition is the whole story.
        guard let key = trimmedKey, !key.isEmpty else {
            if let local = await onDevice.analyze(image) {
                return MealScanOutcome(analysis: local, degradedFrom: nil, signature: signature)
            }
            throw MealScanError.badResponse
        }

        // 5. Key present: premium read, taught by the user's similar past corrections.
        let hints = learning.learnedHints(from: matches)
        do {
            let analysis = try await groq.analyze(image,
                                                  apiKey: key,
                                                  prepared: prepared,
                                                  learnedHints: hints)
            return MealScanOutcome(analysis: analysis, degradedFrom: nil, signature: signature)
        } catch let groqError as MealScanError {
            // Premium failed — degrade to on-device so the meal still logs.
            if let local = await onDevice.analyze(image) {
                return MealScanOutcome(analysis: local, degradedFrom: groqError, signature: signature)
            }
            throw groqError
        }
    }

    /// Re-runs analysis on the same photo after a natural-language correction.
    /// Requires a Groq key (the correction is applied by the vision model).
    func refine(image: UIImage,
                previous: MealAnalysis,
                feedback: String,
                groqKey: String?) async throws -> MealScanOutcome {
        let key = groqKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !key.isEmpty else { throw MealScanError.missingKey }

        guard let prepared = MealImageProcessor.prepare(image) else {
            throw MealScanError.imageEncodingFailed
        }

        let signature: ImageSignature?
        if let cg = prepared.cgImage {
            signature = await ImageSignatureBuilder.make(from: cg)
        } else if let cg = MealImageProcessor.uprightCGImage(image) {
            signature = await ImageSignatureBuilder.make(from: cg)
        } else {
            signature = nil
        }

        let hints = signature.flatMap { learning.learnedHints(for: $0) }
        let refined = try await groq.refine(image,
                                            apiKey: key,
                                            previous: previous,
                                            feedback: feedback,
                                            prepared: prepared,
                                            learnedHints: hints)
        return MealScanOutcome(analysis: refined, degradedFrom: nil, signature: signature)
    }

    /// Whether the Groq error was the user's to fix (vs. a transient/infra issue
    /// we handled silently). The UI uses this to decide if it should nudge the
    /// user to re-check their key rather than just log quietly.
    static func isUserActionable(_ error: MealScanError) -> Bool {
        switch error {
        case .authFailed, .rateLimited, .missingKey:
            return true
        default:
            return false
        }
    }
}
