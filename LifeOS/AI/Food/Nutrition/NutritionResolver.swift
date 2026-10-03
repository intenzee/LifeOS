import Foundation

/// Canonical form for food names: lower case, ASCII-ish, singular, single-spaced.
nonisolated enum FoodNameNormalizer {
    static func normalise(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "'s", with: "")
            .replacingOccurrences(of: "&", with: " and ")
        let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == " " ? Character($0) : " " }
        let words = String(cleaned).split(separator: " ").map(String.init).filter { !fillers.contains($0) }
        return DeterministicFoodParser.singular(words.joined(separator: " "))
    }

    static func tokens(_ name: String) -> [String] {
        normalise(name).split(separator: " ").map(String.init)
    }

    private static let fillers: Set<String> = ["a", "an", "the", "of", "some", "homemade", "home", "made", "fresh", "plain"]

    /// Levenshtein distance, early-exit above `limit`.
    static func editDistance(_ a: String, _ b: String, limit: Int = 3) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        if abs(a.count - b.count) > limit { return limit + 1 }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [Int](repeating: 0, count: b.count + 1)
            current[0] = i
            var rowMin = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                rowMin = min(rowMin, current[j])
            }
            if rowMin > limit { return limit + 1 }
            previous = current
        }
        return previous[b.count]
    }
}

/// A food the user owns (custom, favourite or recent), per serving.
nonisolated struct UserFood: Sendable, Hashable, Codable {
    nonisolated enum Kind: String, Sendable, Codable { case custom, favorite, recent, learned }
    var name: String
    var macros: Macros
    var servingDescription: String
    var kind: Kind
    var id: String

    init(name: String, macros: Macros, servingDescription: String = "1 serving", kind: Kind, id: String? = nil) {
        self.name = name
        self.macros = macros
        self.servingDescription = servingDescription
        self.kind = kind
        self.id = id ?? FoodNameNormalizer.normalise(name)
    }
}

/// How an item's nutrition was found — drives the source chip and confidence.
nonisolated enum MatchKind: String, Sendable, Codable, Hashable {
    case userFood, userFoodFuzzy, catalog, catalogFuzzy, headNoun, modelEstimate, label, unresolved

    var matchConfidence: Double {
        switch self {
        case .userFood: 1.0
        case .userFoodFuzzy: 0.85
        case .label: 0.95
        case .catalog: 0.9
        case .catalogFuzzy: 0.7
        case .headNoun: 0.6
        case .modelEstimate: 0.4
        case .unresolved: 0.15
        }
    }
}

nonisolated enum ConfidenceBand: String, Sendable, Codable {
    case high, medium, low

    init(_ value: Double) {
        self = value >= 0.75 ? .high : value >= 0.55 ? .medium : .low
    }
}

/// One item ready for the confirmation card and the log (F02 §4.3–4.4).
nonisolated struct ResolvedFoodItem: Sendable, Hashable, Codable, Identifiable {
    var id: UUID = UUID()
    var displayName: String
    var quantity: Double
    var unit: String
    var grams: Double?
    var macros: Macros
    /// Provenance tag, e.g. `db:lifeos-curated-v1:roti`, `user:custom:<id>`, `llm-estimate`.
    var sourceRef: String
    var matchKind: MatchKind
    var parseConfidence: Double
    var unitConfidence: Double
    var preparation: String
    /// Per-unit nutrition so quantity edits rescale without re-resolving.
    var macrosPerUnit: Macros
    var originalText: String

    var confidence: Double { parseConfidence * matchKind.matchConfidence * unitConfidence }
    var band: ConfidenceBand { ConfidenceBand(confidence) }
    /// F02 §4.4: anything under 0.6 is highlighted "Check this".
    var needsReview: Bool { confidence < 0.6 }
    var isEstimate: Bool { matchKind == .modelEstimate || matchKind == .unresolved || matchKind == .headNoun }

    /// "2 roti (80 g)"
    var servingDescription: String {
        let qty = quantity.formatted(.number.precision(.fractionLength(0...2)))
        let base = unit == "serving" ? "\(qty) serving" : "\(qty) \(unit)"
        guard let grams, !NutritionUnits.exactUnits.contains(unit) else { return base }
        return "\(base) (\(Int(grams.rounded())) \(unit == "ml" || unit == "l" ? "ml" : "g"))"
    }

    mutating func setQuantity(_ newQuantity: Double) {
        let q = max(0, newQuantity)
        if let grams, quantity > 0 { self.grams = grams / quantity * q }
        quantity = q
        macros = macrosPerUnit.scaled(q)
        parseConfidence = 1.0   // the user set it explicitly
    }
}

/// Deterministic nutrition resolution (T0) — the part that makes logging work on
/// any phone. The model (or rule parser) only says *what* was eaten; this says
/// how much energy that is, with provenance (principle 1: the model understands,
/// code computes).
nonisolated struct NutritionResolver: Sendable {
    var userFoods: [UserFood]
    var catalog: [String: FoodRecord]
    /// The user's own portion sizes from memory ("my katori is 120 ml").
    var portionHints: PortionHints

    init(userFoods: [UserFood] = [], catalog: [String: FoodRecord] = FoodCatalog.index, portionHints: PortionHints = .none) {
        self.userFoods = userFoods
        self.catalog = catalog
        self.portionHints = portionHints
    }

    func resolve(_ meal: ParsedMeal) -> [ResolvedFoodItem] {
        meal.items.map(resolve)
    }

    func resolve(_ item: ParsedFoodItem) -> ResolvedFoodItem {
        let name = FoodNameNormalizer.normalise(item.brand.isEmpty ? item.name : "\(item.brand) \(item.name)")
        let plainName = FoodNameNormalizer.normalise(item.name)
        let unit = Self.canonicalUnit(item.unit)
        let parseConfidence = Self.parseConfidence(item)

        // 1. The user's own foods win (their numbers, their portions).
        if let food = matchUserFood(name) ?? matchUserFood(plainName) {
            let perUnit = food.food.macros
            return ResolvedFoodItem(displayName: food.food.name, quantity: item.quantity, unit: unit == "serving" ? "serving" : unit,
                                    grams: nil, macros: perUnit.scaled(item.quantity),
                                    sourceRef: "user:\(food.food.kind.rawValue):\(food.food.id)",
                                    matchKind: food.exact ? .userFood : .userFoodFuzzy, parseConfidence: parseConfidence,
                                    unitConfidence: unit == "serving" || unit == "piece" ? 1.0 : 0.8,
                                    preparation: item.preparation, macrosPerUnit: perUnit, originalText: item.originalText)
        }

        // 2. Catalog: preparation-specific dish first ("fried egg"), then name, brand, fuzzy, head noun.
        let prepared = item.preparation.isEmpty ? nil : FoodNameNormalizer.normalise("\(item.preparation) \(item.name)")
        if let (record, kind) = (prepared.flatMap { catalog[$0] }.map { ($0, MatchKind.catalog) })
            ?? matchCatalog(name) ?? matchCatalog(plainName) {
            return build(record: record, kind: kind, item: item, unit: unit, parseConfidence: parseConfidence)
        }

        // 3. Unknown: keep the item so the user can fill it in (or a model estimates it).
        return ResolvedFoodItem(displayName: item.name, quantity: item.quantity, unit: unit, grams: nil, macros: .zero,
                                sourceRef: "unresolved", matchKind: .unresolved, parseConfidence: parseConfidence,
                                unitConfidence: 0.6, preparation: item.preparation, macrosPerUnit: .zero,
                                originalText: item.originalText)
    }

    /// Applies a model nutrition estimate to an unresolved item (F02 resolution step 5).
    static func applyingEstimate(_ estimate: NutritionEstimate, to item: ResolvedFoodItem) -> ResolvedFoodItem {
        var updated = item
        let total = Macros(kcal: estimate.kcal, protein: estimate.protein, carbs: estimate.carbs, fat: estimate.fat)
        updated.macros = total
        updated.macrosPerUnit = item.quantity > 0 ? total.scaled(1 / item.quantity) : total
        updated.grams = estimate.grams
        updated.matchKind = .modelEstimate
        updated.sourceRef = "llm-estimate"
        return updated
    }

    // MARK: - Matching

    private func matchUserFood(_ name: String) -> (food: UserFood, exact: Bool)? {
        guard !name.isEmpty else { return nil }
        if let exact = userFoods.first(where: { FoodNameNormalizer.normalise($0.name) == name }) { return (exact, true) }
        let tokens = Set(name.split(separator: " "))
        let scored = userFoods.compactMap { food -> (UserFood, Double)? in
            let other = Set(FoodNameNormalizer.normalise(food.name).split(separator: " "))
            guard !other.isEmpty else { return nil }
            let jaccard = Double(tokens.intersection(other).count) / Double(tokens.union(other).count)
            return jaccard >= 0.75 ? (food, jaccard) : nil
        }
        return scored.max { $0.1 < $1.1 }.map { ($0.0, false) }
    }

    func matchCatalog(_ name: String) -> (FoodRecord, MatchKind)? {
        guard !name.isEmpty else { return nil }
        if let record = catalog[name] { return (record, .catalog) }

        // Typos: one edit for short names, two for longer ones ("chappati", "biriyani").
        let limit = name.count >= 7 ? 2 : 1
        if name.count >= 4,
           let (key, _) = catalog.keys.lazy.map({ ($0, FoodNameNormalizer.editDistance($0, name, limit: limit)) })
            .filter({ $0.1 <= limit }).min(by: { $0.1 < $1.1 }) {
            return (catalog[key]!, .catalogFuzzy)
        }

        // Token overlap: "veg hakka noodles" ~ "hakka noodles".
        let tokens = Set(name.split(separator: " ").map(String.init))
        var best: (key: String, score: Double)?
        for key in catalog.keys {
            let keyTokens = Set(key.split(separator: " ").map(String.init))
            let shared = tokens.intersection(keyTokens).count
            guard shared > 0 else { continue }
            let score = Double(shared) / Double(tokens.union(keyTokens).count)
            // Prefer the longer key on ties ("chicken tikka" over "chicken").
            if score > (best?.score ?? 0) || (score == best?.score && key.count > (best?.key.count ?? 0)) {
                best = (key, score)
            }
        }
        if let best, best.score >= 0.6 { return (catalog[best.key]!, .catalogFuzzy) }

        // Head noun: "mushroom paratha" → paratha; "chicken masala dosa" → masala dosa.
        let words = name.split(separator: " ").map(String.init)
        for length in stride(from: min(3, words.count - 1), through: 1, by: -1) where words.count > length {
            let tail = words.suffix(length).joined(separator: " ")
            if let record = catalog[tail] { return (record, .headNoun) }
        }
        return nil
    }

    // MARK: - Portions

    private func build(record: FoodRecord, kind: MatchKind, item: ParsedFoodItem, unit: String,
                       parseConfidence: Double) -> ResolvedFoodItem {
        let (gramsPerUnit, unitConfidence, displayUnit) = portionHints.gramsPerUnit(record: record, unit: unit)
            ?? Self.gramsPerUnit(record: record, unit: unit)
        var perUnit = record.macros(grams: gramsPerUnit)
        perUnit = Self.applyPreparation(item.preparation, to: perUnit, record: record, gramsPerUnit: gramsPerUnit)
        return ResolvedFoodItem(displayName: record.name, quantity: item.quantity, unit: displayUnit,
                                grams: gramsPerUnit * item.quantity, macros: perUnit.scaled(item.quantity),
                                sourceRef: "db:\(FoodCatalog.version):\(record.id)", matchKind: kind,
                                parseConfidence: parseConfidence, unitConfidence: unitConfidence,
                                preparation: item.preparation, macrosPerUnit: perUnit, originalText: item.originalText)
    }

    /// Grams for one unit of this food, the unit confidence, and the unit to show.
    static func gramsPerUnit(record: FoodRecord, unit: String) -> (Double, Double, String) {
        switch unit {
        case "g", "ml": return (1, 1.0, unit)
        case "kg", "l": return (1000, 1.0, unit)
        default: break
        }
        if let grams = record.units[unit] { return (grams, 1.0, unit) }
        if unit == "serving" || unit.isEmpty {
            // The rule parser says "serving" when no unit was spoken: use the food's natural unit.
            // The food's own household unit is a known mapping; the defaulted *amount* is
            // already discounted by parseConfidence (0.8).
            return (record.servingGrams, record.defaultUnit == "piece" ? 0.9 : 0.85, record.defaultUnit)
        }
        if let factor = NutritionUnits.sizeFactors[unit] {
            return (record.servingGrams * factor, 0.75, unit)
        }
        if unit == "katori", let bowl = record.units["bowl"] { return (bowl, 1.0, "katori") }
        if unit == "bowl", let katori = record.units["katori"] { return (katori, 1.0, "bowl") }
        if let generic = NutritionUnits.genericGrams[unit] { return (generic, 0.7, unit) }
        return (record.servingGrams, 0.6, record.defaultUnit)
    }

    static func applyPreparation(_ preparation: String, to macros: Macros, record: FoodRecord, gramsPerUnit: Double) -> Macros {
        let prep = preparation.lowercased()
        guard !prep.isEmpty else { return macros }
        var result = macros
        let perUnitFatAdd: Double = record.category == .bread || record.defaultUnit == "piece" ? 5 : 7
        if prep.contains("ghee") || prep.contains("butter") || prep.contains("makhan") {
            let fat = perUnitFatAdd
            result = result + Macros(kcal: fat * 9, protein: 0, carbs: 0, fat: fat)
        } else if prep.contains("extra oil") || prep.contains("oily") {
            result = result + Macros(kcal: 45, protein: 0, carbs: 0, fat: 5)
        }
        if prep.contains("no sugar") || prep.contains("without sugar") || prep.contains("sugar free") || prep.contains("sugarless") {
            // Typical recipe sugar: ~5 g per 100 ml of chai/coffee/lassi, ~10 g per 100 g of kheer.
            let sugarPer100: Double = record.category == .sweet ? 10 : 5
            let sugar = min(result.carbs, sugarPer100 * gramsPerUnit / 100)
            result = Macros(kcal: max(0, result.kcal - sugar * 4), protein: result.protein,
                            carbs: max(0, result.carbs - sugar), fat: result.fat)
        }
        if prep.contains("less oil") || prep.contains("no oil") || prep.contains("air fried") {
            let fat = min(result.fat, result.fat * 0.3)
            result = Macros(kcal: max(0, result.kcal - fat * 9), protein: result.protein, carbs: result.carbs, fat: result.fat - fat)
        }
        return result
    }

    static func canonicalUnit(_ unit: String) -> String {
        let u = unit.lowercased().trimmingCharacters(in: .whitespaces)
        if u.isEmpty { return "serving" }
        return DeterministicFoodParser.units[u] ?? (u.hasSuffix("s") ? DeterministicFoodParser.units[String(u.dropLast())] : nil) ?? u
    }

    /// 1.0 when the user stated an amount, 0.8 when it was defaulted (F02 §4.4).
    static func parseConfidence(_ item: ParsedFoodItem) -> Double {
        let text = item.originalText.lowercased()
        guard !text.isEmpty else { return 0.9 }
        let words = Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let stated = text.contains(where: \.isNumber) || !words.isDisjoint(with: DeterministicFoodParser.numberWords.keys)
            || !words.isDisjoint(with: DeterministicFoodParser.units.keys)
        return stated ? 1.0 : 0.8
    }
}

/// Model estimate for a food the catalog can't resolve (task `nutritionEstimate`).
nonisolated struct NutritionEstimate: AIOutput, Hashable {
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let schema: AISchema = .object(name: "NutritionEstimate", properties: [
        AISchemaProperty("grams", .number(minimum: 0, maximum: 3_000), description: "estimated weight of the whole amount eaten"),
        AISchemaProperty("kcal", .number(minimum: 0, maximum: 5_000), description: "total kcal for the whole amount"),
        AISchemaProperty("protein", .number(minimum: 0, maximum: 500), description: "grams"),
        AISchemaProperty("carbs", .number(minimum: 0, maximum: 500), description: "grams"),
        AISchemaProperty("fat", .number(minimum: 0, maximum: 500), description: "grams"),
    ])

    func semanticIssues() -> [String] { kcal <= 0 ? ["kcal must be above 0"] : [] }
}

/// The user's own household sizes (F04 portion hints from F06 `unitSize` memories).
nonisolated struct PortionHints: Sendable, Hashable {
    /// Container → ml/g it holds ("katori": 120).
    var containers: [String: Double]
    /// Normalised food name → grams per piece ("roti": 30).
    var pieces: [String: Double]

    static let none = PortionHints(containers: [:], pieces: [:])
    static let containerUnits: Set<String> = ["katori", "bowl", "cup", "glass", "mug", "plate", "tumbler", "scoop", "spoon"]

    init(containers: [String: Double] = [:], pieces: [String: Double] = [:]) {
        self.containers = containers
        self.pieces = pieces
    }

    /// Built from active `unitSize` memories.
    init(memories: [MemoryRecord], now: Date = Date()) {
        var containers: [String: Double] = [:], pieces: [String: Double] = [:]
        for record in memories where record.isUsable(at: now) {
            guard case .unitSize(let unit, let grams)? = record.facet, grams > 0 else { continue }
            let u = unit == "tumbler" ? "glass" : unit
            if Self.containerUnits.contains(u) { containers[u] = grams } else { pieces[FoodNameNormalizer.normalise(u)] = grams }
        }
        self.init(containers: containers, pieces: pieces)
    }

    var isEmpty: Bool { containers.isEmpty && pieces.isEmpty }

    func gramsPerUnit(record: FoodRecord, unit: String) -> (Double, Double, String)? {
        guard !isEmpty else { return nil }
        let defaulted = unit == "serving" || unit.isEmpty
        let names = [record.name] + record.aliases
        if unit == "piece" || (defaulted && record.defaultUnit == "piece"),
           let grams = names.lazy.compactMap({ self.pieces[FoodNameNormalizer.normalise($0)] }).first {
            return (grams, 1.0, "piece")
        }
        let u = defaulted ? record.defaultUnit : unit
        guard let size = containers[u] ?? (u == "bowl" ? containers["katori"] : u == "katori" ? containers["bowl"] : nil),
              let generic = NutritionUnits.genericGrams[u], generic > 0 else { return nil }
        // The food's usual fill for that container, scaled to the user's container.
        let base = record.units[u] ?? generic
        return (base * size / generic, 1.0, u)
    }
}
