import Foundation

/// One edit to a meal draft or preset variant (F03 §4.5, F02 refine-by-text).
nonisolated enum MealOperation: Sendable, Hashable {
    case remove(target: String)
    case setQuantity(target: String, quantity: Double, unit: String?)
    case replace(target: String, with: ParsedFoodItem)
    case add(ParsedFoodItem)
    /// "no sugar", "with ghee": applies to the items it makes sense for.
    case prepare(modifier: String, target: String?)
}

/// Parses corrections like "no curd", "3 rotis instead of 2", "add a banana",
/// "paneer instead of chicken", "without sugar" — deterministically, so it works
/// on phones without Apple Intelligence and costs nothing.
nonisolated enum MealModificationParser {

    /// Splits "<preset phrase> but <mods>" into its parts.
    static func splitVariant(_ text: String) -> (base: String, modifications: String?) {
        let lower = " " + text.lowercased() + " "
        for marker in [" but ", " except ", " without ", " minus ", " lekin ", " par "] {
            if let range = lower.range(of: marker) {
                let base = String(lower[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                var mods = String(lower[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if marker == " without " || marker == " minus " { mods = "no " + mods }
                return (base, mods.isEmpty ? nil : mods)
            }
        }
        return (text.trimmingCharacters(in: .whitespaces), nil)
    }

    static func parse(_ text: String, current: [ResolvedFoodItem]) -> [MealOperation] {
        let clauses = text.lowercased()
            .replacingOccurrences(of: " and ", with: ",")
            .replacingOccurrences(of: " aur ", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }
        return clauses.flatMap { parseClause($0, current: current) }
    }

    private static let modifierTargets: Set<String> = ["sugar", "ghee", "butter", "oil", "salt", "cheese", "cream", "mayo"]

    static func parseClause(_ clause: String, current: [ResolvedFoodItem]) -> [MealOperation] {
        var words = clause.split(separator: " ").map(String.init)
        while let first = words.first, ["please", "actually", "also", "then", "make", "it"].contains(first) { words.removeFirst() }
        guard !words.isEmpty else { return [] }
        let rest = words.joined(separator: " ")

        // "no X" / "without X" / "remove X" / "skip X" / "nahi X" / "X nahi"
        if let first = words.first, ["no", "without", "remove", "skip", "minus", "drop", "delete", "nahi", "bina"].contains(first) {
            let target = words.dropFirst().filter { !["the", "a", "an", "any"].contains($0) }.joined(separator: " ")
            return [removal(target, current: current)]
        }
        if words.last == "nahi" || words.last == "nahin" {
            return [removal(words.dropLast().joined(separator: " "), current: current)]
        }

        // "with ghee", "extra butter", "less oil"
        if let first = words.first, ["with", "extra", "less", "more"].contains(first), words.count >= 2 {
            let target = words.dropFirst().joined(separator: " ")
            if modifierTargets.contains(DeterministicFoodParser.singular(target)) {
                return [.prepare(modifier: "\(first) \(target)", target: nil)]
            }
            if first == "extra" || first == "more" {
                return DeterministicFoodParser.parseItem(target).map { [.add($0)] } ?? []
            }
        }

        // "add X", "plus X", "also X"
        if let first = words.first, ["add", "plus", "include"].contains(first) {
            let text = words.dropFirst().joined(separator: " ")
            return DeterministicFoodParser.parse(text).items.map { .add($0) }
        }

        // "A instead of B" / "B ki jagah A"
        for marker in [" instead of ", " in place of ", " not ", " ki jagah "] {
            guard let range = (" " + rest + " ").range(of: marker) else { continue }
            let padded = " " + rest + " "
            var newPart = String(padded[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            var oldPart = String(padded[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if marker == " ki jagah " { swap(&newPart, &oldPart) }
            guard let newItem = DeterministicFoodParser.parseItem(newPart) else { continue }
            // "2 eggs instead of 1" → same food, new quantity.
            let oldItem = DeterministicFoodParser.parseItem(oldPart)
            let oldName = oldItem?.name ?? ""
            let sameFood = oldItem == nil || Double(oldPart) != nil
                || FoodNameNormalizer.normalise(oldName) == FoodNameNormalizer.normalise(newItem.name)
            if sameFood, let target = bestMatch(newItem.name, in: current) {
                return [.setQuantity(target: target, quantity: newItem.quantity, unit: unitIfStated(newItem))]
            }
            if let target = bestMatch(oldName.isEmpty ? oldPart : oldName, in: current) {
                return [.replace(target: target, with: newItem)]
            }
            return [.add(newItem)]
        }

        // "half the rice" / "only 1 roti" / "3 rotis" → quantity change for an existing item.
        if let item = DeterministicFoodParser.parseItem(rest) {
            if let target = bestMatch(item.name, in: current) {
                let stated = item.originalText.split(separator: " ").contains { Double($0) != nil || DeterministicFoodParser.numberWords[String($0)] != nil }
                if stated { return [.setQuantity(target: target, quantity: item.quantity, unit: unitIfStated(item))] }
                return []
            }
            if modifierTargets.contains(item.name) { return [.prepare(modifier: "with \(item.name)", target: nil)] }
            return [.add(item)]
        }
        return []
    }

    private static func removal(_ target: String, current: [ResolvedFoodItem]) -> MealOperation {
        let singular = DeterministicFoodParser.singular(target)
        if let match = bestMatch(target, in: current) { return .remove(target: match) }
        if modifierTargets.contains(singular) { return .prepare(modifier: "no \(singular)", target: nil) }
        return .remove(target: target)
    }

    private static func unitIfStated(_ item: ParsedFoodItem) -> String? {
        item.unit == "serving" || item.unit == "piece" ? nil : item.unit
    }

    /// The display name in `current` that `name` refers to, if any.
    static func bestMatch(_ name: String, in current: [ResolvedFoodItem]) -> String? {
        let query = FoodNameNormalizer.normalise(name)
        guard !query.isEmpty else { return nil }
        let queryTokens = Set(query.split(separator: " "))
        var best: (String, Double)?
        for item in current {
            let candidates = [item.displayName, item.originalText].map(FoodNameNormalizer.normalise)
            for candidate in candidates where !candidate.isEmpty {
                let tokens = Set(candidate.split(separator: " "))
                let score: Double
                if candidate == query { score = 1 }
                else if !queryTokens.isDisjoint(with: tokens) {
                    score = Double(queryTokens.intersection(tokens).count) / Double(queryTokens.union(tokens).count) + 0.2
                } else if FoodNameNormalizer.editDistance(candidate, query, limit: 2) <= 2, query.count >= 4 {
                    score = 0.6
                } else { continue }
                if score > (best?.1 ?? 0) { best = (item.displayName, score) }
            }
        }
        return best?.0
    }

    /// Applies operations deterministically; new items go through the resolver.
    static func apply(_ operations: [MealOperation], to items: [ResolvedFoodItem],
                      resolver: NutritionResolver) -> [ResolvedFoodItem] {
        var result = items
        for operation in operations {
            switch operation {
            case .remove(let target):
                result.removeAll { $0.displayName == target }
            case .setQuantity(let target, let quantity, let unit):
                guard let index = result.firstIndex(where: { $0.displayName == target }) else { continue }
                if let unit, unit != result[index].unit {
                    var parsed = ParsedFoodItem(name: result[index].displayName, originalText: "\(quantity) \(unit)",
                                                quantity: quantity, unit: unit, preparation: result[index].preparation)
                    parsed.originalText = "\(quantity) \(unit) \(result[index].displayName)"
                    var resolved = resolver.resolve(parsed)
                    resolved.id = result[index].id
                    result[index] = resolved
                } else {
                    result[index].setQuantity(quantity)
                }
            case .replace(let target, let newItem):
                guard let index = result.firstIndex(where: { $0.displayName == target }) else {
                    result.append(resolver.resolve(newItem)); continue
                }
                result[index] = resolver.resolve(newItem)
            case .add(let item):
                result.append(resolver.resolve(item))
            case .prepare(let modifier, let target):
                for index in result.indices {
                    if let target, result[index].displayName != target { continue }
                    guard applies(modifier, to: result[index]) else { continue }
                    var parsed = ParsedFoodItem(name: result[index].displayName, originalText: result[index].originalText,
                                                quantity: result[index].quantity, unit: result[index].unit,
                                                preparation: [result[index].preparation, modifier].filter { !$0.isEmpty }.joined(separator: ", "))
                    if parsed.originalText.isEmpty { parsed.originalText = "\(parsed.quantity) \(parsed.name)" }
                    let resolved = resolver.resolve(parsed)
                    guard resolved.matchKind != .unresolved else { continue }
                    var updated = resolved
                    updated.id = result[index].id
                    updated.parseConfidence = result[index].parseConfidence
                    result[index] = updated
                }
            }
        }
        return result
    }

    /// "no sugar" only touches drinks and sweets; "with ghee" only breads, rice and dals.
    private static func applies(_ modifier: String, to item: ResolvedFoodItem) -> Bool {
        guard item.sourceRef.hasPrefix("db:"), let id = item.sourceRef.split(separator: ":").last,
              let record = FoodCatalog.record(id: String(id)) else { return false }
        if modifier.contains("sugar") { return [.beverage, .sweet, .dairy].contains(record.category) }
        if modifier.contains("ghee") || modifier.contains("butter") {
            return [.bread, .rice, .dal, .southIndian].contains(record.category)
        }
        return true
    }
}
