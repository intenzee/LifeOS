import Foundation

/// One meal from the user's food log, as the miner sees it.
nonisolated struct LoggedMeal: Sendable, Hashable {
    nonisolated struct Item: Sendable, Hashable {
        var name: String
        var macros: Macros
        var servingDescription: String
    }
    var date: Date
    var meal: ParsedMeal.MealSlot
    var items: [Item]
}

nonisolated struct PresetSuggestion: Sendable, Hashable, Identifiable {
    /// Stable key of the routine (sorted item names) so "Not now" can be remembered.
    var id: String
    var name: String
    var items: [ResolvedFoodItem]
    var meal: ParsedMeal.MealSlot
    var occurrences: Int
    var weekdaysOnly: Bool
    var message: String
}

/// Finds repeated meals and proposes them as presets (F03 §4.3, T0).
///
/// A routine is a set of foods (≥ 2) eaten together ≥ 3 times in 14 days or
/// ≥ 4 times in 30 days, with occurrences ≥ 0.8 Jaccard-similar. Routines a
/// preset already covers, or that the user dismissed, are skipped. At most one
/// suggestion per call; callers show it as an in-app card, never a notification.
nonisolated enum RoutineMiner {

    static func suggest(history: [LoggedMeal], existing: [FoodPreset], dismissed: Set<String> = [],
                        now: Date = Date(), calendar: Calendar = .current) -> PresetSuggestion? {
        let windowStart = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let recentStart = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let meals = history
            .filter { $0.date >= windowStart && $0.date <= now }
            .map { meal -> (LoggedMeal, Set<String>) in (meal, Set(meal.items.map { FoodNameNormalizer.normalise($0.name) })) }
            .filter { $0.1.count >= 2 }
            .sorted { $0.0.date < $1.0.date }

        // Greedy clustering on Jaccard similarity to each cluster's first set.
        var clusters: [(key: Set<String>, members: [LoggedMeal])] = []
        for (meal, set) in meals {
            if let index = clusters.firstIndex(where: { jaccard($0.key, set) >= 0.8 }) {
                clusters[index].members.append(meal)
            } else {
                clusters.append((set, [meal]))
            }
        }

        let covered = existing.filter { !$0.archived }.map(\.itemKeys)
        let candidates = clusters.compactMap { cluster -> (cluster: (key: Set<String>, members: [LoggedMeal]), score: Double)? in
            let inLast14 = cluster.members.filter { $0.date >= recentStart }.count
            let inLast30 = cluster.members.count
            guard inLast14 >= 3 || inLast30 >= 4 else { return nil }
            guard !dismissed.contains(key(cluster.key)) else { return nil }
            guard !covered.contains(where: { jaccard($0, cluster.key) >= 0.8 }) else { return nil }
            let last = cluster.members.map(\.date).max() ?? now
            let daysAgo = max(0, now.timeIntervalSince(last) / 86_400)
            return (cluster, Double(inLast30) / (1 + daysAgo / 7))
        }

        guard let best = candidates.max(by: { $0.score < $1.score }),
              let latest = best.cluster.members.max(by: { $0.date < $1.date }) else { return nil }

        let members = best.cluster.members
        let weekdaysOnly = members.count >= 3 && members.allSatisfy { !calendar.isDateInWeekend($0.date) }
        let meal = mostCommon(members.map(\.meal)) ?? latest.meal
        let items = latest.items.map { item -> ResolvedFoodItem in
            ResolvedFoodItem(displayName: item.name, quantity: 1, unit: "serving", grams: nil, macros: item.macros,
                             sourceRef: "user:history:\(FoodNameNormalizer.normalise(item.name))", matchKind: .userFood,
                             parseConfidence: 1, unitConfidence: 1, preparation: "", macrosPerUnit: item.macros,
                             originalText: item.servingDescription)
        }
        let name = PresetNamer.suggest(items: latest.items.map(\.name), meal: meal, weekdaysOnly: weekdaysOnly)
        let foods = latest.items.map { $0.name.lowercased() }
        let foodList = foods.count == 2 ? "\(foods[0]) and \(foods[1])" : foods.dropLast().joined(separator: ", ") + " and \(foods.last ?? "")"
        let when = weekdaysOnly ? "most weekdays" : "\(members.count) times"
        let message = "You've had \(foodList) \(when) lately. Save it as “\(name)” to log it in one tap?"
        return PresetSuggestion(id: key(best.cluster.key), name: name, items: items, meal: meal,
                                occurrences: members.count, weekdaysOnly: weekdaysOnly, message: message)
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }

    static func key(_ set: Set<String>) -> String { set.sorted().joined(separator: "+") }

    private static func mostCommon(_ slots: [ParsedMeal.MealSlot]) -> ParsedMeal.MealSlot? {
        Dictionary(grouping: slots, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }
}
