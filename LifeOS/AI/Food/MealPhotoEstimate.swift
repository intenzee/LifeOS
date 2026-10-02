import Foundation

/// Structured result of `mealPhotoAnalyze` / `mealPhotoRefine`.
///
/// Schema v1 is exactly the JSON contract `GroqMealAnalyzer` has always asked
/// for, so routing the scanner through the gateway changes nothing for the
/// model or the user (Phase 0 exit criterion). F04 introduces schema v2 with
/// per-item portions and calibrated confidence.
nonisolated struct MealPhotoEstimate: AIOutput, Hashable {
    var name: String?
    var servingSize: String?
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var items: [Item]?
    /// Set only by local engines that know their own score (e.g. Vision); cloud
    /// estimates leave it nil and the app applies its legacy default.
    var confidence: Double?

    nonisolated struct Item: Codable, Sendable, Hashable {
        var name: String?
        var calories: Double?
        var protein: Double?
        var carbs: Double?
        var fat: Double?
    }

    static let schema: AISchema = .object(
        name: "MealPhotoEstimate",
        properties: [
            AISchemaProperty("name", .string(), description: "short descriptive name of the whole meal", optional: true),
            AISchemaProperty("servingSize", .string(), description: "the portion shown, e.g. 1 plate", optional: true),
            AISchemaProperty("calories", .number(minimum: 0, maximum: 10_000), description: "total kcal", optional: true),
            AISchemaProperty("protein", .number(minimum: 0, maximum: 1_000), description: "total grams", optional: true),
            AISchemaProperty("carbs", .number(minimum: 0, maximum: 1_000), description: "total grams", optional: true),
            AISchemaProperty("fat", .number(minimum: 0, maximum: 1_000), description: "total grams", optional: true),
            AISchemaProperty("items", .array(of: .object(name: "MealPhotoItem", properties: [
                AISchemaProperty("name", .string(), optional: true),
                AISchemaProperty("calories", .number(minimum: 0, maximum: 10_000), optional: true),
                AISchemaProperty("protein", .number(minimum: 0, maximum: 1_000), optional: true),
                AISchemaProperty("carbs", .number(minimum: 0, maximum: 1_000), optional: true),
                AISchemaProperty("fat", .number(minimum: 0, maximum: 1_000), optional: true),
            ]), maxItems: 20), description: "each distinct component", optional: true),
            AISchemaProperty("confidence", .number(minimum: 0, maximum: 1), optional: true),
        ]
    )

    /// Named components (unnamed items are dropped, negatives clamped) —
    /// identical to the legacy `decodeAnalysis` rules.
    var namedItems: [Item] {
        (items ?? []).compactMap { item in
            guard let name = item.name, !name.isEmpty else { return nil }
            return Item(name: name, calories: max(0, item.calories ?? 0), protein: max(0, item.protein ?? 0),
                        carbs: max(0, item.carbs ?? 0), fat: max(0, item.fat ?? 0))
        }
    }

    /// Explicit totals win; otherwise the items are summed.
    var totals: (calories: Double, protein: Double, carbs: Double, fat: Double) {
        let parts = namedItems
        return (max(0, calories ?? parts.reduce(0) { $0 + ($1.calories ?? 0) }),
                max(0, protein ?? parts.reduce(0) { $0 + ($1.protein ?? 0) }),
                max(0, carbs ?? parts.reduce(0) { $0 + ($1.carbs ?? 0) }),
                max(0, fat ?? parts.reduce(0) { $0 + ($1.fat ?? 0) }))
    }

    var displayName: String { (name?.isEmpty == false) ? name! : "Meal" }
    var displayServing: String { (servingSize?.isEmpty == false) ? servingSize! : "1 plate" }

    /// A meal with zero everything is not an answer — same rule as the legacy
    /// client's `badResponse`, so the chain falls through to the next engine.
    /// Exception: a local engine that recognised a named food it has no macros
    /// for still returns it so the user can fill numbers in (legacy behaviour).
    func semanticIssues() -> [String] {
        let t = totals
        let empty = t.calories <= 0 && t.protein <= 0 && t.carbs <= 0 && t.fat <= 0
        if empty && confidence == nil { return ["estimate has no calories or macros"] }
        return []
    }
}
