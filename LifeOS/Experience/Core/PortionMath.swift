import Foundation

/// 3.7 portion maths: grams from a pack's serving text, the serving chips, the
/// plate-fill level and per-100 g scaling. Pure, so the portion screen's numbers
/// are unit-tested.
nonisolated enum PortionMath {
    struct Chip: Equatable, Sendable {
        let label: String
        let grams: Double
    }

    /// Grams in a serving text such as "30 g", "1 bar (45g)", "250 ml" or
    /// "2 biscuits (18.5 g)". The last weight wins, so "1 bar (45 g)" is 45.
    /// Millilitres count as grams (close enough for drinks). Nil when there's no weight.
    static func grams(inServing text: String) -> Double? {
        let pattern = #"(\d+(?:[.,]\d+)?)\s*(kg|gms|gm|grams|gram|g|ml|oz)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.matches(in: text, range: range).last,
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[numberRange].replacingOccurrences(of: ",", with: ".")),
              value > 0 else { return nil }
        switch text[unitRange].lowercased() {
        case "kg": return value * 1000
        case "oz": return (value * 28.35 * 10).rounded() / 10
        default: return value
        }
    }

    /// The starting amount: one serving when the pack says how much that is, else 100 g.
    static func defaultGrams(servingGrams: Double?) -> Double {
        guard let s = servingGrams, s.isFinite, s > 0 else { return 100 }
        return s
    }

    /// ½, 1, 1½ and 2 servings when the serving weight is known, else round gram steps.
    static func chips(servingGrams: Double?) -> [Chip] {
        guard let s = servingGrams, s.isFinite, s > 0 else {
            return [50, 100, 150, 200].map { Chip(label: "\(Int($0)) g", grams: $0) }
        }
        return [("½", 0.5), ("1", 1), ("1½", 1.5), ("2", 2)].map { Chip(label: $0.0, grams: (s * $0.1).rounded()) }
    }

    /// Slider bounds: at least 500 g, or four servings of something heavier.
    static func sliderRange(servingGrams: Double?) -> ClosedRange<Double> {
        5...max(500, defaultGrams(servingGrams: servingGrams) * 4)
    }

    /// 0…1 for the plate visual: two servings (or 200 g) fill the plate.
    static func plateFill(grams: Double, servingGrams: Double?) -> Double {
        let full = defaultGrams(servingGrams: servingGrams) * 2
        guard grams.isFinite, grams > 0, full > 0 else { return 0 }
        return min(grams / full, 1)
    }

    /// A per-100 g value for `grams`, never negative or NaN.
    static func scale(per100 value: Double, grams: Double) -> Double {
        guard value.isFinite, grams.isFinite else { return 0 }
        return max(value, 0) * max(grams, 0) / 100
    }

    /// Per-100 g from a per-serving value, when the serving weight is known.
    static func per100(_ value: Double, servingGrams: Double) -> Double? {
        guard value.isFinite, servingGrams.isFinite, servingGrams > 0 else { return nil }
        return max(value, 0) * 100 / servingGrams
    }

    // MARK: Meal amounts (3.5 photo result)

    /// Units offered for a photographed meal's amount.
    static let mealUnits = ["serving", "bowl", "cup", "plate", "piece", "glass", "slice", "handful", "gram", "oz", "tbsp"]

    /// A starting amount and unit from an estimate's serving text: "1 plate",
    /// "2 cups", "250 g". Unknown text is one serving.
    static func parseAmount(_ serving: String) -> (quantity: Double, unit: String) {
        let lower = serving.lowercased()
        let number = lower
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .first(where: { !$0.isEmpty })
            .flatMap(Double.init) ?? 1
        let unit = mealUnits.first(where: { lower.contains($0) })
            ?? (grams(inServing: lower) != nil ? "gram" : "serving")
        return (max(0.5, number.isFinite ? number : 1), unit)
    }

    /// Step for the amount buttons: 25 g, 1 oz, or half a unit.
    static func amountStep(unit: String) -> Double {
        unit == "gram" ? 25 : (unit == "oz" ? 1 : 0.5)
    }

    /// "1.5 bowls", "250 g", "1 plate".
    static func amountLabel(quantity: Double, unit: String) -> String {
        let q = quantity.formatted(.number.precision(.fractionLength(0...2)))
        if unit == "gram" { return "\(q) g" }
        let plural = quantity != 1 && unit != "oz" ? (unit.hasSuffix("h") ? "\(unit)es" : "\(unit)s") : unit
        return "\(q) \(plural)"
    }
}
