import Foundation

/// Nutrition for one serving of a food (Phase 3 §3.3: "the model understands, code computes").
nonisolated struct ExperienceNutrient: Equatable, Sendable {
    var name: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    /// Human serving, e.g. "1 piece", "100g", "1 cup".
    var serving: String

    init(name: String, kcal: Double, protein: Double = 0, carbs: Double = 0, fat: Double = 0, serving: String = "1 serving") {
        self.name = name
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.serving = serving
    }

    func scaled(_ factor: Double) -> ExperienceNutrient {
        let f = factor.isFinite ? max(factor, 0) : 1
        return ExperienceNutrient(name: name, kcal: (kcal * f).rounded(), protein: protein * f, carbs: carbs * f, fat: fat * f, serving: serving)
    }

    /// Grams in the serving string ("100g", "28 g"), if it states them.
    var servingGrams: Double? {
        let s = serving.lowercased()
        guard let r = s.range(of: #"(\d+(?:\.\d+)?)\s*(g|ml)\b"#, options: .regularExpression) else { return nil }
        let digits = s[r].prefix { $0.isNumber || $0 == "." }
        return Double(digits)
    }
}

/// How sure the resolver is about one item's calories.
nonisolated enum ExperienceConfidence: Sendable, Equatable {
    /// Matched one of the user's own foods (recent, custom, favourite).
    case high
    /// Matched a built-in table entry.
    case medium
    /// Nothing matched: calories are 0 until the user fills them in.
    case low
}

/// One parsed item with calories attached.
nonisolated struct ExperienceResolvedItem: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var quantity: Double
    var unit: String
    var nutrient: ExperienceNutrient
    var confidence: ExperienceConfidence

    var amountText: String {
        let q = quantity == quantity.rounded() ? String(Int(quantity)) : String(format: "%.1f", quantity)
        return "\(q) \(unit)"
    }
}

/// Resolves parsed food names to nutrition. Order: the user's own foods, then
/// the app's bundled table, then a small South Asian staples table (the bundled
/// table is mostly Western; this app's owner logs rotis and dal).
nonisolated enum ExperienceFoodResolver {

    static func resolve(name rawName: String,
                        quantity rawQuantity: Double,
                        unit rawUnit: String,
                        id: String,
                        userFoods: [ExperienceNutrient],
                        bundled: (String) -> ExperienceNutrient?) -> ExperienceResolvedItem {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let quantity = rawQuantity.isFinite && rawQuantity > 0 ? rawQuantity : 1
        let unit = rawUnit.trimmingCharacters(in: .whitespaces).isEmpty ? "serving" : rawUnit.lowercased()

        let match: (ExperienceNutrient, ExperienceConfidence)? =
            userMatch(name, in: userFoods).map { ($0, .high) }
            ?? staples(name).map { ($0, .medium) }
            ?? bundled(name).flatMap { sharesWord($0.name, name) ? ($0, .medium) : nil }

        guard let (base, confidence) = match else {
            return ExperienceResolvedItem(id: id, name: name.firstLetterCapitalized, quantity: quantity, unit: unit,
                                          nutrient: ExperienceNutrient(name: name.firstLetterCapitalized, kcal: 0), confidence: .low)
        }
        let nutrient = base.scaled(factor(quantity: quantity, unit: unit, base: base))
        return ExperienceResolvedItem(id: id, name: base.name, quantity: quantity, unit: unit, nutrient: nutrient, confidence: confidence)
    }

    /// "200 g" of a "100g" food is 2×; "2 pieces" of a "1 piece" food is 2×.
    static func factor(quantity: Double, unit: String, base: ExperienceNutrient) -> Double {
        if unit == "g" || unit == "ml", let grams = base.servingGrams, grams > 0 {
            return quantity / grams
        }
        if unit == "g" || unit == "ml" {
            // Grams against a non-gram serving: assume ~150 g per serving rather than 200×.
            return quantity / 150
        }
        if unit == "half" { return 0.5 }
        return quantity
    }

    static func userMatch(_ name: String, in foods: [ExperienceNutrient]) -> ExperienceNutrient? {
        let key = normalize(name)
        guard !key.isEmpty else { return nil }
        if let exact = foods.first(where: { normalize($0.name) == key }) { return exact }
        // "Eggs (2 large)" should match "eggs"; require whole-word containment to avoid "tea" ⊂ "steak".
        return foods.first { food in
            let words = Set(normalize(food.name).split(separator: " ").map(String.init))
            return words.contains(key) || words.contains(singular(key))
        }
    }

    /// Guards loose substring lookups ("tea" must not resolve to "Steak").
    static func sharesWord(_ a: String, _ b: String) -> Bool {
        let wa = Set(normalize(a).split(separator: " ").map { singular(String($0)) })
        let wb = Set(normalize(b).split(separator: " ").map { singular(String($0)) })
        return !wa.isDisjoint(with: wb)
    }

    static func staples(_ name: String) -> ExperienceNutrient? {
        let key = normalize(name)
        if let hit = stapleTable[key] ?? stapleTable[singular(key)] { return hit }
        for (alias, canonical) in stapleAliases where key == alias || key.hasSuffix(" " + alias) {
            return stapleTable[canonical]
        }
        return nil
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .components(separatedBy: CharacterSet.letters.union(.whitespaces).inverted).joined()
            .split(separator: " ").joined(separator: " ")
    }

    static func singular(_ s: String) -> String {
        if s.hasSuffix("ies") { return String(s.dropLast(3)) + "y" }
        if s.hasSuffix("es"), s.count > 4, ["ch", "sh", "ss", "to"].contains(where: { s.dropLast(2).hasSuffix($0) }) { return String(s.dropLast(2)) }
        if s.hasSuffix("s"), !s.hasSuffix("ss") { return String(s.dropLast()) }
        return s
    }

    /// Typical home-style servings (approximate; the proposal card shows them as "Likely").
    static let stapleTable: [String: ExperienceNutrient] = [
        "roti": .init(name: "Roti", kcal: 104, protein: 3, carbs: 18, fat: 2.4, serving: "1 piece"),
        "paratha": .init(name: "Paratha", kcal: 260, protein: 5, carbs: 36, fat: 10, serving: "1 piece"),
        "naan": .init(name: "Naan", kcal: 262, protein: 9, carbs: 45, fat: 5, serving: "1 piece"),
        "dal": .init(name: "Dal", kcal: 180, protein: 9, carbs: 24, fat: 5, serving: "1 bowl"),
        "dal makhani": .init(name: "Dal makhani", kcal: 300, protein: 11, carbs: 28, fat: 16, serving: "1 bowl"),
        "rajma": .init(name: "Rajma", kcal: 220, protein: 11, carbs: 32, fat: 5, serving: "1 bowl"),
        "chole": .init(name: "Chole", kcal: 260, protein: 11, carbs: 34, fat: 9, serving: "1 bowl"),
        "sabzi": .init(name: "Sabzi", kcal: 120, protein: 3, carbs: 12, fat: 7, serving: "1 bowl"),
        "paneer": .init(name: "Paneer curry", kcal: 320, protein: 16, carbs: 10, fat: 24, serving: "1 bowl"),
        "chai": .init(name: "Chai", kcal: 90, protein: 3, carbs: 12, fat: 3.5, serving: "1 cup"),
        "coffee": .init(name: "Coffee with milk", kcal: 70, protein: 3, carbs: 8, fat: 3, serving: "1 cup"),
        "idli": .init(name: "Idli", kcal: 58, protein: 2, carbs: 12, fat: 0.4, serving: "1 piece"),
        "dosa": .init(name: "Dosa", kcal: 170, protein: 4, carbs: 28, fat: 5, serving: "1 piece"),
        "masala dosa": .init(name: "Masala dosa", kcal: 390, protein: 8, carbs: 55, fat: 15, serving: "1 piece"),
        "sambar": .init(name: "Sambar", kcal: 130, protein: 6, carbs: 18, fat: 4, serving: "1 bowl"),
        "upma": .init(name: "Upma", kcal: 250, protein: 6, carbs: 38, fat: 8, serving: "1 bowl"),
        "poha": .init(name: "Poha", kcal: 250, protein: 5, carbs: 42, fat: 7, serving: "1 bowl"),
        "samosa": .init(name: "Samosa", kcal: 260, protein: 4, carbs: 28, fat: 15, serving: "1 piece"),
        "biryani": .init(name: "Biryani", kcal: 500, protein: 20, carbs: 60, fat: 18, serving: "1 plate"),
        "curd": .init(name: "Curd", kcal: 100, protein: 6, carbs: 7, fat: 5, serving: "1 bowl"),
        "raita": .init(name: "Raita", kcal: 90, protein: 4, carbs: 8, fat: 4, serving: "1 bowl"),
        "lassi": .init(name: "Lassi", kcal: 220, protein: 7, carbs: 32, fat: 7, serving: "1 glass"),
        "khichdi": .init(name: "Khichdi", kcal: 280, protein: 10, carbs: 45, fat: 6, serving: "1 bowl"),
        "milk": .init(name: "Milk", kcal: 150, protein: 8, carbs: 12, fat: 8, serving: "1 glass"),
        "chicken curry": .init(name: "Chicken curry", kcal: 350, protein: 28, carbs: 8, fat: 22, serving: "1 bowl"),
        "egg curry": .init(name: "Egg curry", kcal: 250, protein: 13, carbs: 8, fat: 18, serving: "1 bowl"),
    ]

    static let stapleAliases: [(String, String)] = [
        ("chapati", "roti"), ("chapatti", "roti"), ("phulka", "roti"),
        ("daal", "dal"), ("dhal", "dal"), ("tea", "chai"), ("masala chai", "chai"),
        ("dahi", "curd"), ("yogurt", "curd"), ("yoghurt", "curd"),
        ("chana masala", "chole"), ("sabji", "sabzi"), ("bhaji", "sabzi"),
        ("paneer butter masala", "paneer"), ("palak paneer", "paneer"), ("shahi paneer", "paneer"),
    ]
}

/// A food the user has logged before, ranked for the Capture sheet's preset row (Phase 3 §3.2:
/// "sorted by what is usual at this time of day; one tap logs").
nonisolated struct ExperiencePresetCandidate: Identifiable, Equatable, Sendable {
    var id: String
    var nutrient: ExperienceNutrient
    var slot: ExperienceMealSlot?
    var isFavorite: Bool
    var lastUsed: Date?

    /// Favourites matching the current slot, then other foods matching the slot, then favourites, then the most recent.
    static func ranked(_ candidates: [ExperiencePresetCandidate], for slot: ExperienceMealSlot, limit: Int = 8) -> [ExperiencePresetCandidate] {
        func score(_ c: ExperiencePresetCandidate) -> Int {
            (c.slot == slot ? 2 : 0) + (c.isFavorite ? 1 : 0)
        }
        var seen = Set<String>()
        return candidates
            .filter { seen.insert(ExperienceFoodResolver.normalize($0.nutrient.name)).inserted }
            .sorted { a, b in
                let sa = score(a), sb = score(b)
                if sa != sb { return sa > sb }
                return (a.lastUsed ?? .distantPast) > (b.lastUsed ?? .distantPast)
            }
            .prefix(limit)
            .map { $0 }
    }
}

private extension String {
    nonisolated var firstLetterCapitalized: String { prefix(1).uppercased() + dropFirst() }
}
