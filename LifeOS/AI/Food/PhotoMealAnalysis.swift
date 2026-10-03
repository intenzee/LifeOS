import Foundation

/// Photo schema v2 (F04 §4.1): every item with an estimated weight, so nutrition
/// comes from the resolver (catalog / user foods) and the model's own macros
/// are only a fallback for foods we can't resolve.
nonisolated struct PhotoMealAnalysis: AIOutput, Hashable {
    nonisolated struct Item: Codable, Sendable, Hashable {
        var name: String
        var estimatedGrams: Double
        var householdMeasure: String
        var identificationConfidence: Double
        var cookingMethod: String
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double

        init(name: String, estimatedGrams: Double, householdMeasure: String = "", identificationConfidence: Double = 0.7,
             cookingMethod: String = "", kcal: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0) {
            self.name = name
            self.estimatedGrams = estimatedGrams
            self.householdMeasure = householdMeasure
            self.identificationConfidence = identificationConfidence
            self.cookingMethod = cookingMethod
            self.kcal = kcal
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            estimatedGrams = try c.decodeIfPresent(Double.self, forKey: .estimatedGrams) ?? 0
            householdMeasure = try c.decodeIfPresent(String.self, forKey: .householdMeasure) ?? ""
            identificationConfidence = try c.decodeIfPresent(Double.self, forKey: .identificationConfidence) ?? 0.6
            cookingMethod = try c.decodeIfPresent(String.self, forKey: .cookingMethod) ?? ""
            kcal = try c.decodeIfPresent(Double.self, forKey: .kcal) ?? 0
            protein = try c.decodeIfPresent(Double.self, forKey: .protein) ?? 0
            carbs = try c.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
            fat = try c.decodeIfPresent(Double.self, forKey: .fat) ?? 0
        }
    }

    var mealName: String
    var items: [Item]
    var notFood: Bool
    var notes: String

    init(mealName: String, items: [Item], notFood: Bool = false, notes: String = "") {
        self.mealName = mealName
        self.items = items
        self.notFood = notFood
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mealName = try c.decodeIfPresent(String.self, forKey: .mealName) ?? "Meal"
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        notFood = try c.decodeIfPresent(Bool.self, forKey: .notFood) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    static let schema: AISchema = .object(name: "PhotoMealAnalysis", properties: [
        AISchemaProperty("mealName", .string(), description: "short name of the whole meal, e.g. Veg thali"),
        AISchemaProperty("items", .array(of: .object(name: "PhotoItem", properties: [
            AISchemaProperty("name", .string(), description: "canonical dish name, singular, lower case; keep regional names"),
            AISchemaProperty("estimatedGrams", .number(minimum: 0, maximum: 2_000), description: "estimated weight of the visible portion in grams"),
            AISchemaProperty("householdMeasure", .string(), description: "e.g. 1 katori, 2 pieces, 1 cup", optional: true),
            AISchemaProperty("identificationConfidence", .number(minimum: 0, maximum: 1), description: "how sure you are what this item is"),
            AISchemaProperty("cookingMethod", .string(), description: "fried, grilled, curry, raw…; empty if unclear", optional: true),
            AISchemaProperty("kcal", .number(minimum: 0, maximum: 5_000), description: "estimated kcal of the visible portion"),
            AISchemaProperty("protein", .number(minimum: 0, maximum: 500), optional: true),
            AISchemaProperty("carbs", .number(minimum: 0, maximum: 500), optional: true),
            AISchemaProperty("fat", .number(minimum: 0, maximum: 500), optional: true),
        ]), maxItems: 15), description: "every distinct food or drink, including chutneys, sauces and visible oil or ghee"),
        AISchemaProperty("notFood", .boolean(), description: "true if the image shows no food or drink"),
        AISchemaProperty("notes", .string(), description: "caveats, e.g. sauce may hide oil", optional: true),
    ])

    func semanticIssues() -> [String] {
        if notFood { return [] }
        if items.isEmpty { return ["no items listed although notFood is false"] }
        if items.allSatisfy({ $0.estimatedGrams <= 0 && $0.kcal <= 0 }) { return ["items have no weight or calories"] }
        return []
    }
}

/// Turns a photo analysis into resolved items (F04 §4 pipeline steps 3–4).
nonisolated enum PhotoMealResolver {
    /// Portion uncertainty for a single top-down photo (F04 §4.3).
    static let singleViewPortionFactor = 0.75

    static func resolve(_ analysis: PhotoMealAnalysis, catalog: [String: FoodRecord] = FoodCatalog.index) -> [ResolvedFoodItem] {
        // Grams from the photo only make sense against per-100 g data, so user
        // foods (per serving) are not used here.
        let resolver = NutritionResolver(userFoods: [], catalog: catalog)
        return analysis.items.compactMap { item -> ResolvedFoodItem? in
            let grams = max(0, item.estimatedGrams)
            let modelMacros = Macros(kcal: item.kcal, protein: item.protein, carbs: item.carbs, fat: item.fat)
            guard grams > 0 || modelMacros.kcal > 0 else { return nil }
            let identification = min(1, max(0.1, item.identificationConfidence))

            if grams > 0 {
                let parsed = ParsedFoodItem(name: item.name, originalText: item.householdMeasure, quantity: grams, unit: "g",
                                            preparation: item.cookingMethod)
                var resolved = resolver.resolve(parsed)
                if resolved.matchKind == .catalog || resolved.matchKind == .catalogFuzzy {
                    resolved.displayName = item.name
                    resolved.parseConfidence = identification
                    resolved.unitConfidence = singleViewPortionFactor
                    resolved.originalText = item.householdMeasure
                    return resolved
                }
            }
            // Fallback: the model's own estimate, clearly badged.
            return ResolvedFoodItem(displayName: item.name, quantity: grams > 0 ? grams : 1, unit: grams > 0 ? "g" : "serving",
                                    grams: grams > 0 ? grams : nil, macros: modelMacros, sourceRef: "llm-estimate",
                                    matchKind: modelMacros.kcal > 0 ? .modelEstimate : .unresolved,
                                    parseConfidence: identification, unitConfidence: singleViewPortionFactor,
                                    preparation: item.cookingMethod,
                                    macrosPerUnit: grams > 0 ? modelMacros.scaled(1 / grams) : modelMacros,
                                    originalText: item.householdMeasure)
        }
    }

    /// Calibrated meal confidence: mean item confidence (F04 §4.3).
    static func confidence(_ items: [ResolvedFoodItem]) -> Double {
        guard !items.isEmpty else { return 0 }
        return items.map(\.confidence).reduce(0, +) / Double(items.count)
    }
}

nonisolated extension PromptRegistry {
    static let mealPhotoV2Instructions = """
    You identify every food and drink in a meal photo and estimate portions. Rules:
    - List every distinct item, including drinks, chutneys, raita, sauces, pickles, and visible oil or ghee.
    - Keep regional dish names (dal makhani, poha, rajma, sambar); singular, lower case.
    - Estimate the weight in grams of each visible portion using references: a dinner plate is about 26 cm, \
    a katori/small bowl holds about 150 ml, a roti weighs about 40 g, a tablespoon about 15 g.
    - Never return 0 grams for a visible item. Give one best estimate, not a range.
    - identificationConfidence: 0.9+ only when the item is unmistakable; lower for hidden or ambiguous items.
    - Also give your kcal and macro estimate for each visible portion (used only as a fallback).
    - If the image shows no food or drink, set notFood to true and return no items.
    """

    static func mealPhotoAnalyzeV2() -> AIPrompt {
        AIPrompt(id: "mealPhoto.analyze.v2", version: version, instructions: mealPhotoV2Instructions,
                 user: "Analyse this meal photo.")
    }

    static func mealPhotoRefineV2(previous: String, feedback: String) -> AIPrompt {
        AIPrompt(id: "mealPhoto.refine.v2", version: version, instructions: mealPhotoV2Instructions,
                 user: """
                 Your previous analysis of this photo: \(previous)
                 The user corrects you (quoted data): "\(feedback)"
                 Re-examine the same photo and return a corrected analysis. Apply the correction faithfully \
                 (dish names, added or removed items, quantities like "I added 4 eggs"); keep everything else consistent.
                 """)
    }
}
