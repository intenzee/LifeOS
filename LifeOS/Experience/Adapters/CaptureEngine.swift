import Foundation

/// What the Capture sheet understood from one sentence (Phase 3 §3.2 / §3.3).
struct CaptureProposal: Equatable {
    var heard: String
    var items: [ExperienceResolvedItem]
    var slot: ExperienceMealSlot
    var source: ExperienceTimelineEntry.Source
    /// "On device", "Groq"…, or "Offline · on-device" for the rule-based parser.
    var engineNote: String
    /// Set when the sentence named a usual meal ("my usual breakfast").
    var presetPhrase: String?

    var totalKcal: Int { Int(items.reduce(0) { $0 + $1.nutrient.kcal }.rounded()) }
    var unresolvedCount: Int { items.filter { $0.confidence == .low }.count }
}

/// Sentence → structured items (AI gateway, falling back to the rule-based
/// parser) → nutrition (the user's own foods, then built-in tables).
enum CaptureEngine {
    static func propose(_ sentence: String,
                        source: ExperienceTimelineEntry.Source,
                        defaultSlot: ExperienceMealSlot,
                        userFoods: [ExperienceNutrient]) async -> CaptureProposal {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsed: ParsedMeal
        var note: String
        do {
            let result = try await AIServices.shared.gateway.run(AIRequest<ParsedMeal>(
                task: .foodTextParse,
                prompt: PromptRegistry.foodTextParse(text),
                input: .text(text),
                privacy: .personal,
                latencyBudget: .seconds(20),
                cachePolicy: .bypass))
            parsed = result.output
            note = engineName(result.provider)
            // An empty AI answer for clearly food-like text: try the rules before giving up.
            if parsed.items.isEmpty && !parsed.refersToPreset {
                let rules = DeterministicFoodParser.parse(text)
                if !rules.items.isEmpty || rules.refersToPreset { parsed = rules; note = "On device" }
            }
        } catch {
            parsed = DeterministicFoodParser.parse(text)
            note = "Offline · on-device"
        }

        let slot = slot(from: parsed.mealType) ?? defaultSlot
        let items = parsed.items.enumerated().map { index, item in
            ExperienceFoodResolver.resolve(name: item.name, quantity: item.quantity, unit: item.unit,
                                           id: "\(index)-\(item.name)", userFoods: userFoods,
                                           bundled: { NutritionDatabase.entry(for: $0).map(\.nutrient) })
        }
        return CaptureProposal(heard: text, items: items, slot: slot, source: source, engineNote: note,
                               presetPhrase: parsed.refersToPreset && !parsed.presetPhrase.isEmpty ? parsed.presetPhrase : nil)
    }

    static func slot(from meal: ParsedMeal.MealSlot) -> ExperienceMealSlot? {
        switch meal {
        case .breakfast: return .breakfast
        case .lunch: return .lunch
        case .dinner: return .dinner
        case .snacks: return .snack
        case .unknown: return nil
        }
    }

    static func engineName(_ provider: ProviderID) -> String {
        switch provider {
        case .appleOnDevice: return "On device"
        case .applePCC: return "Private Cloud Compute"
        case .geminiBYOK: return "Gemini"
        case .groqBYOK: return "Groq"
        case .visionLegacy, .deterministic: return "On device"
        }
    }
}

extension NutritionDatabase.Entry {
    var nutrient: ExperienceNutrient {
        ExperienceNutrient(name: name, kcal: calories, protein: protein, carbs: carbs, fat: fat, serving: serving)
    }
}
