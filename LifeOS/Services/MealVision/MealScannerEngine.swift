import UIKit

/// The single entry point the UI talks to. It delivers the product promise:
/// **free, and it never dead-ends.**
///
/// Since Phase 0 of the AI plan, every model call goes through the `AIGateway`
/// (F01). The engine keeps what is meal-specific — photo preparation,
/// fingerprinting, the learned-correction override and few-shot hints — and the
/// gateway owns routing, retries, model rotation, quotas, privacy and telemetry.
///
/// Routing for `mealPhotoAnalyze` (remote-config controlled):
///  • learned override (here, deterministic) → Groq with the user's key →
///    on-device Vision estimate. Apple Intelligence vision tiers sit in the
///    table behind the `photoAppleVision` flag (off until F04).
///  • Only hard, user-actionable Groq failures (bad key, rate limit) are
///    surfaced — and even then an on-device analysis is handed back if one exists.
///
/// The public API and outcomes are unchanged from the pre-gateway engine.
struct MealScannerEngine {

    private let gateway: any AIGatewaying
    private let learning: MealLearningEngine

    init(gateway: any AIGatewaying = AIServices.shared.gateway,
         learning: MealLearningEngine = .shared) {
        self.gateway = gateway
        self.learning = learning
    }

    /// Analyzes a meal photo.
    /// - Returns: an outcome whose `analysis` is ready to log.
    /// - Throws: only when there is genuinely nothing to log — i.e. no key or
    ///   Groq failed, AND on-device recognised no food. The thrown
    ///   `MealScanError` explains why so the UI can guide the user.
    func scan(image: UIImage, groqKey: String?) async throws -> MealScanOutcome {
        let typedKey = groqKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // 1. Normalise the photo once; the bitmap feeds both the models and fingerprinting.
        guard let prepared = MealImageProcessor.prepare(image) else {
            throw MealScanError.imageEncodingFailed
        }

        // 2. Fingerprint the meal so we can recall past corrections and file new ones.
        let signature = await Self.signature(for: image, prepared: prepared)

        // 3. Rank past corrections once; reuse for both the override and hints.
        let matches = signature.map { learning.matches(for: $0) } ?? []

        // Instant learned override: a photo the user already corrected is
        // answered from memory — free, offline, and exactly their ground truth.
        if let signature, let override = learning.instantOverride(from: matches) {
            return MealScanOutcome(analysis: learning.analysis(from: override),
                                   degradedFrom: nil,
                                   signature: signature)
        }

        // 4. Gateway: premium read (taught by similar past corrections) with
        //    automatic fallback to the on-device estimate.
        if !typedKey.isEmpty { AIServices.shared.recordKeyEntryConsent(for: .groqBYOK) }
        let request = AIRequest<MealPhotoEstimate>(
            task: .mealPhotoAnalyze,
            prompt: PromptRegistry.mealPhotoAnalyze(),
            input: .image(Self.aiImage(prepared)),
            context: Self.hintsContext(learning.learnedHints(from: matches)),
            privacy: .personal,
            latencyBudget: .seconds(90),
            credentialOverrides: typedKey.isEmpty ? [:] : [.groqBYOK: typedKey])

        do {
            let result = try await gateway.run(request)
            return MealScanOutcome(analysis: Self.analysis(from: result),
                                   degradedFrom: Self.groqFailure(in: result.degradedFrom),
                                   signature: signature)
        } catch let error as AIError {
            throw Self.scanError(for: error)
        }
    }

    /// Re-runs analysis on the same photo after a natural-language correction.
    /// Needs an engine that can see the photo again (today: Groq with a key).
    func refine(image: UIImage,
                previous: MealAnalysis,
                feedback: String,
                groqKey: String?) async throws -> MealScanOutcome {
        let typedKey = groqKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if typedKey.isEmpty, await gateway.availability(for: .mealPhotoRefine).primary == nil {
            throw MealScanError.missingKey
        }

        guard let prepared = MealImageProcessor.prepare(image) else {
            throw MealScanError.imageEncodingFailed
        }
        let signature = await Self.signature(for: image, prepared: prepared)
        let hints = signature.flatMap { learning.learnedHints(for: $0) }

        let note = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else {
            return MealScanOutcome(analysis: previous, degradedFrom: nil, signature: signature)
        }

        let request = AIRequest<MealPhotoEstimate>(
            task: .mealPhotoRefine,
            prompt: PromptRegistry.mealPhotoRefine(previousSummary: Self.summary(of: previous), feedback: note),
            input: .image(Self.aiImage(prepared)),
            context: Self.hintsContext(hints),
            privacy: .personal,
            latencyBudget: .seconds(90),
            credentialOverrides: typedKey.isEmpty ? [:] : [.groqBYOK: typedKey])

        do {
            let result = try await gateway.run(request)
            return MealScanOutcome(analysis: Self.analysis(from: result), degradedFrom: nil, signature: signature)
        } catch let error as AIError {
            throw Self.scanError(for: error)
        }
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

    // MARK: - Gateway mapping

    private static func signature(for image: UIImage, prepared: MealImageProcessor.Prepared) async -> ImageSignature? {
        if let cg = prepared.cgImage { return await ImageSignatureBuilder.make(from: cg) }
        if let cg = MealImageProcessor.uprightCGImage(image) { return await ImageSignatureBuilder.make(from: cg) }
        return nil
    }

    private static func aiImage(_ prepared: MealImageProcessor.Prepared) -> AIImage {
        AIImage(jpegData: prepared.jpegData,
                pixelWidth: prepared.cgImage?.width,
                pixelHeight: prepared.cgImage?.height)
    }

    /// Learned hints travel as a context section, rendered after the system
    /// prompt exactly where the legacy client appended them.
    private static func hintsContext(_ hints: String?) -> ContextPacket? {
        guard let hints, !hints.isEmpty else { return nil }
        return ContextPacket(sections: [.init(title: "learnedCorrections", body: hints, privacy: .personal)])
    }

    static func analysis(from result: AIResult<MealPhotoEstimate>) -> MealAnalysis {
        let estimate = result.output
        let totals = estimate.totals
        let source: MealAnalysis.Source
        switch result.provider {
        case .groqBYOK: source = .groq
        case .geminiBYOK: source = .gemini
        case .appleOnDevice: source = .appleOnDevice
        case .applePCC: source = .appleCloud
        case .visionLegacy, .deterministic: source = .onDevice
        }
        return MealAnalysis(
            name: estimate.displayName,
            calories: totals.calories,
            protein: totals.protein,
            carbs: totals.carbs,
            fat: totals.fat,
            servingSize: estimate.displayServing,
            // Cloud engines don't self-report; keep the legacy display default.
            confidence: estimate.confidence ?? 0.9,
            source: source,
            components: estimate.namedItems.map {
                MealAnalysis.Component(name: $0.name ?? "", calories: $0.calories ?? 0, protein: $0.protein ?? 0,
                                       carbs: $0.carbs ?? 0, fat: $0.fat ?? 0)
            })
    }

    /// The Groq failure the user should hear about, if Groq was actually tried.
    /// "No key" is not a degradation — it's the free on-device path.
    static func groqFailure(in attempts: [AIAttempt]) -> MealScanError? {
        attempts.first { attempt in
            guard attempt.provider == .groqBYOK else { return false }
            switch attempt.error {
            case .unavailable(.missingCredential), .consentRequired, .unavailable(.consentRequired),
                 .unavailable(.disabledByConfig):
                return false
            default:
                return true
            }
        }.map { scanError(for: $0.error) }
    }

    /// Maps the gateway taxonomy back onto the scanner's user-facing errors.
    static func scanError(for error: AIError) -> MealScanError {
        switch error {
        case .exhausted(let attempts):
            // Legacy rule: surface the Groq error if Groq was tried; otherwise
            // the on-device pass simply found no food.
            return groqFailure(in: attempts) ?? .badResponse
        case .unavailable(.missingCredential), .consentRequired, .unavailable(.consentRequired):
            return .missingKey
        case .authFailed:
            return .authFailed
        case .rateLimited, .quotaExhausted:
            return .rateLimited
        case .noModelAvailable, .modelRetired:
            return .noModelAvailable
        case .network(let detail):
            return .network(detail)
        case .unavailable(.offline):
            return .network("offline")
        case .timeout:
            return .network("timed out")
        case .server(let status):
            return .server(status)
        case .circuitOpen:
            return .server(503)
        case .cancelled:
            return .cancelled
        default:
            return .badResponse
        }
    }

    /// Compact one-line summary of a prior estimate, fed back into a refinement.
    static func summary(of analysis: MealAnalysis) -> String {
        let items = analysis.components.isEmpty
            ? ""
            : " Items: " + analysis.components.map { "\($0.name) (\(Int($0.calories))kcal)" }.joined(separator: ", ") + "."
        return "\(analysis.name) — \(analysis.servingSize), \(Int(analysis.calories)) kcal, " +
               "P\(Int(analysis.protein))/C\(Int(analysis.carbs))/F\(Int(analysis.fat)).\(items)"
    }
}
