import Foundation

/// Structured result of `foodTextParse` (F02 §4.2): *structure only, no calories*.
/// Nutrition is resolved deterministically afterwards (F02 §4.3) — the model
/// understands, code computes.
nonisolated struct ParsedMeal: AIOutput, Hashable {
    var items: [ParsedFoodItem]
    var mealType: MealSlot
    /// ISO-8601 time if the user stated one, else empty.
    var statedTime: String
    /// True if the user referred to a saved preset or "usual" meal.
    var refersToPreset: Bool
    /// e.g. "usual breakfast"; empty when `refersToPreset` is false.
    var presetPhrase: String

    nonisolated enum MealSlot: String, Codable, Sendable, CaseIterable {
        case breakfast, lunch, dinner, snacks, unknown
    }

    init(items: [ParsedFoodItem], mealType: MealSlot = .unknown, statedTime: String = "",
         refersToPreset: Bool = false, presetPhrase: String = "") {
        self.items = items
        self.mealType = mealType
        self.statedTime = statedTime
        self.refersToPreset = refersToPreset
        self.presetPhrase = presetPhrase
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([ParsedFoodItem].self, forKey: .items) ?? []
        mealType = (try? c.decode(MealSlot.self, forKey: .mealType)) ?? .unknown
        statedTime = try c.decodeIfPresent(String.self, forKey: .statedTime) ?? ""
        refersToPreset = try c.decodeIfPresent(Bool.self, forKey: .refersToPreset) ?? false
        presetPhrase = try c.decodeIfPresent(String.self, forKey: .presetPhrase) ?? ""
    }

    static let schema: AISchema = .object(
        name: "ParsedMeal",
        description: "Foods and drinks the person said they consumed.",
        properties: [
            AISchemaProperty("items", .array(of: ParsedFoodItem.schema, maxItems: 20),
                             description: "Each distinct food or drink mentioned; empty if the text is not about food"),
            AISchemaProperty("mealType", .string(choices: MealSlot.allCases.map(\.rawValue)),
                             description: "breakfast, lunch, dinner, snacks, or unknown"),
            AISchemaProperty("statedTime", .string(), description: "ISO-8601 time if the user stated one, else empty",
                             optional: true),
            AISchemaProperty("refersToPreset", .boolean(),
                             description: "true if the user referred to a saved or 'usual' meal", optional: true),
            AISchemaProperty("presetPhrase", .string(), description: "the phrase naming the usual meal, else empty",
                             optional: true),
        ]
    )
}

nonisolated struct ParsedFoodItem: Codable, Sendable, Hashable {
    /// Canonical English (or regional) dish name, singular, lower-case: "roti", "dal makhani".
    var name: String
    /// The user's own words for this item.
    var originalText: String
    var quantity: Double
    /// piece, bowl, cup, g, ml, slice, plate, tbsp, scoop, glass, serving…
    var unit: String
    /// fried, with ghee, no sugar… ("" if none)
    var preparation: String
    /// "" if none
    var brand: String

    init(name: String, originalText: String = "", quantity: Double = 1, unit: String = "serving",
         preparation: String = "", brand: String = "") {
        self.name = name
        self.originalText = originalText
        self.quantity = quantity
        self.unit = unit
        self.preparation = preparation
        self.brand = brand
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        originalText = try c.decodeIfPresent(String.self, forKey: .originalText) ?? ""
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity) ?? 1
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? "serving"
        preparation = try c.decodeIfPresent(String.self, forKey: .preparation) ?? ""
        brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
    }

    static let schema: AISchema = .object(
        name: "ParsedFoodItem",
        properties: [
            AISchemaProperty("name", .string(), description: "canonical singular dish name in lower case, e.g. roti, dal makhani"),
            AISchemaProperty("originalText", .string(), description: "the user's words for this item", optional: true),
            AISchemaProperty("quantity", .number(minimum: 0, maximum: 5_000), description: "how many units (grams/ml count as units); 1 if not stated"),
            AISchemaProperty("unit", .string(), description: "piece, bowl, cup, g, ml, slice, plate, tbsp, scoop, glass or serving"),
            AISchemaProperty("preparation", .string(), description: "e.g. fried, with ghee, no sugar; empty if none", optional: true),
            AISchemaProperty("brand", .string(), description: "brand name, empty if none", optional: true),
        ]
    )
}
