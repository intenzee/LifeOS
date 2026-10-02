import Foundation

/// The unified result contract for meal photo analysis.
///
/// Every analyzer in the `MealVision` stack — on-device Vision or the Groq
/// vision model — produces one of these, so the UI and the orchestrator never
/// have to care which engine ran. Macros are totals for the whole plate.
struct MealAnalysis: Equatable {

    /// Which engine produced the estimate. Surfaced in the UI so the user knows
    /// whether they're looking at a full-macro AI read or a free on-device guess.
    enum Source: String, Equatable {
        case groq          // Cloud vision model (full macros, best accuracy)
        case onDevice      // Apple Vision + local nutrition table (offline, free)
        case learned       // Served from the user's own past corrections (offline)
    }

    /// A single recognised component of the plate (e.g. "Grilled chicken").
    /// Optional detail; totals are always the source of truth for logging.
    struct Component: Equatable {
        var name: String
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
    }

    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var servingSize: String
    /// 0…1 self-reported confidence. On-device uses the Vision score; Groq uses
    /// a coarse heuristic (full read = high). Used only for display.
    var confidence: Double
    var source: Source
    var components: [Component]

    init(name: String,
         calories: Double,
         protein: Double = 0,
         carbs: Double = 0,
         fat: Double = 0,
         servingSize: String = "1 serving",
         confidence: Double = 0.5,
         source: Source,
         components: [Component] = []) {
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.servingSize = servingSize
        self.confidence = confidence
        self.source = source
        self.components = components
    }

    /// Bridges into the app's persisted `FoodItem` for a given meal slot.
    func foodItem(mealType: MealType) -> FoodItem {
        FoodItem(
            name: name.isEmpty ? "Meal" : name,
            calories: max(0, calories),
            protein: max(0, protein),
            carbs: max(0, carbs),
            fat: max(0, fat),
            servingSize: servingSize.isEmpty ? "1 serving" : servingSize,
            mealType: mealType
        )
    }

    /// True when the numbers are too empty to be worth logging on their own.
    var isEmpty: Bool {
        calories <= 0 && protein <= 0 && carbs <= 0 && fat <= 0
    }
}

/// Precise, user-actionable failure taxonomy for the meal scanner.
///
/// The distinction matters: `.authFailed` should prompt the user to fix their
/// key, `.rateLimited` should ask them to wait, and everything else should
/// quietly fall back to the on-device estimate rather than dead-end.
enum MealScanError: Error, Equatable {
    case missingKey                 // No Groq key supplied
    case imageEncodingFailed        // Could not turn the photo into bytes
    case authFailed                 // 401/403 — key rejected
    case rateLimited                // 429 — free-tier limit hit
    case noModelAvailable           // Every candidate model was decommissioned/unavailable
    case network(String)            // Transport error (offline, timeout)
    case server(Int)                // 5xx from Groq
    case badResponse                // Empty or unparseable model output
    case cancelled

    /// A friendly, specific message for surfacing directly in the UI.
    var userMessage: String {
        switch self {
        case .missingKey:
            return "Add your free Groq key to use AI macros."
        case .imageEncodingFailed:
            return "Couldn't process that photo. Try another shot."
        case .authFailed:
            return "Your Groq key was rejected. Tap \"Change\" and paste a valid key from console.groq.com/keys."
        case .rateLimited:
            return "Groq's free limit was hit. Wait a moment and try again."
        case .noModelAvailable:
            return "AI vision is temporarily unavailable. We logged an on-device estimate instead."
        case .network:
            return "Network issue reaching Groq. Check your connection and try again."
        case .server:
            return "Groq had a hiccup. We logged an on-device estimate instead."
        case .badResponse:
            return "Couldn't read the AI estimate. We logged an on-device estimate instead."
        case .cancelled:
            return "Scan cancelled."
        }
    }
}

/// What the orchestrator returns: always a usable analysis, plus context on
/// whether the premium (Groq) path had to degrade to the on-device fallback.
struct MealScanOutcome {
    let analysis: MealAnalysis
    /// Set when Groq was attempted but we served the on-device result instead.
    let degradedFrom: MealScanError?
    /// Fingerprint of the analysed photo, so a later user correction can be
    /// filed against this exact image for the learning loop.
    let signature: ImageSignature?

    var didDegrade: Bool { degradedFrom != nil }

    init(analysis: MealAnalysis, degradedFrom: MealScanError? = nil, signature: ImageSignature? = nil) {
        self.analysis = analysis
        self.degradedFrom = degradedFrom
        self.signature = signature
    }
}
