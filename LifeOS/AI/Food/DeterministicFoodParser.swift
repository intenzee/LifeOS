import Foundation

/// Rule-based `foodTextParse` fallback (T0, F02 §5): the feature never disappears,
/// even on a phone with no Apple Intelligence, no key and no network.
///
/// Splits on `,` / `and` / `aur` / `with` / `+` / `&`, reads leading quantities
/// (digits, fractions, English and Hindi number words), units from a dictionary,
/// and meal type from time words. It does not resolve nutrition.
nonisolated enum DeterministicFoodParser {

    static func parse(_ text: String) -> ParsedMeal {
        var normalized = " " + text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "\n", with: " ") + " "

        let mealType = detectMealType(in: normalized)
        // Activity, reminders and chat are not food (F02 §6 "Non-food → no items").
        let words = Set(normalized.split(whereSeparator: { !$0.isLetter }).map(String.init))
        if !words.isDisjoint(with: nonFoodSignals) {
            return ParsedMeal(items: [], mealType: .unknown)
        }
        let preset = detectPreset(in: normalized)
        if let preset {
            return ParsedMeal(items: [], mealType: mealType, refersToPreset: true, presetPhrase: preset)
        }

        // Strip lead-in phrases and meal-time words so they don't become "foods".
        for phrase in leadIns { normalized = normalized.replacingOccurrences(of: phrase, with: " ") }
        for phrase in timePhrases { normalized = normalized.replacingOccurrences(of: " \(phrase) ", with: " , ") }

        let separators = #/\s*(?:,|;|\+|&|\band\b|\baur\b|\bwith\b|\balong with\b|\bplus\b|\bthen\b|\bon\b|\bin\b|\bafter\b|\bbefore\b)\s*/#
        let pieces = normalized.split(separator: separators)
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }

        let items = pieces.compactMap(parseItem)
        return ParsedMeal(items: items, mealType: mealType)
    }

    // MARK: - Item

    static func parseItem(_ raw: String) -> ParsedFoodItem? {
        var words = raw.split(separator: " ").map(String.init)
        while let first = words.first, fillerWords.contains(first) { words.removeFirst() }
        guard !words.isEmpty else { return nil }

        var quantity: Double?
        var unit: String?

        // Leading quantity: "2", "1.5", "1/2", "two", "do", "half", "a", "200g".
        if let first = words.first {
            if let (value, attachedUnit) = splitNumberUnit(first) {
                quantity = value
                words.removeFirst()
                if let attachedUnit, let canonical = units[attachedUnit] { unit = canonical }
            } else if let value = numberWords[first] {
                quantity = value
                words.removeFirst()
                // "one and a half" style handled loosely: "half" after a number adds 0.5
                if words.first == "half" { quantity! += 0.5; words.removeFirst() }
            }
        }
        while let first = words.first, ["of", "a", "an"].contains(first) { words.removeFirst() }

        // Trailing quantity: "dhokla 4 pieces", "paneer paratha do".
        if quantity == nil, words.count >= 2 {
            var tail = words
            var tailUnit: String?
            if let last = tail.last, let canonical = units[last], tail.count >= 3 {
                tailUnit = canonical
                tail.removeLast()
            }
            if let last = tail.last, let value = Double(last) ?? numberWords[last], !["a", "an"].contains(last) {
                quantity = value
                unit = tailUnit
                tail.removeLast()
                words = tail
            }
        }

        // Unit: "bowl of", "cups", "katori".
        if unit == nil, let first = words.first, let canonical = units[first] {
            unit = canonical
            words.removeFirst()
            if words.first == "of" { words.removeFirst() }
        }

        // Trailing preparation phrases: "without sugar", "no sugar", "fried".
        var preparation: [String] = []
        if let index = words.firstIndex(where: { ["without", "no", "less", "extra"].contains($0) }), index > 0 {
            preparation.append(words[index...].joined(separator: " "))
            words.removeSubrange(index...)
        }
        if let first = words.first, cookingStyles.contains(first), words.count > 1 {
            preparation.insert(first, at: 0)
            words.removeFirst()
        }

        let nameWords = words.filter { !trailingNoise.contains($0) }
        guard !nameWords.isEmpty else { return nil }
        let name = singular(nameWords.joined(separator: " "))
        guard name.count >= 2, !nonFoodWords.contains(name) else { return nil }

        let resolvedUnit = unit ?? (countableFoods.contains(where: { name.hasSuffix($0) }) ? "piece" : "serving")
        return ParsedFoodItem(name: name, originalText: raw, quantity: min(5_000, quantity ?? 1),
                              unit: resolvedUnit, preparation: preparation.joined(separator: ", "))
    }

    // MARK: - Helpers

    private static func splitNumberUnit(_ token: String) -> (Double, String?)? {
        if token.contains("/") {
            let parts = token.split(separator: "/")
            if parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d != 0 { return (n / d, nil) }
            return nil
        }
        guard let match = token.firstMatch(of: #/^(\d+(?:\.\d+)?)([a-z]*)$/#), let value = Double(match.1) else { return nil }
        let suffix = String(match.2)
        return (value, suffix.isEmpty ? nil : suffix)
    }

    static func singular(_ name: String) -> String {
        if let exact = irregularPlurals[name] { return exact }
        var words = name.split(separator: " ").map(String.init)
        guard var last = words.popLast() else { return name }
        if let irregular = irregularPlurals[last] {
            last = irregular
        } else if last.hasSuffix("ies"), last.count > 4 {
            last = String(last.dropLast(3)) + "y"
        } else if last.hasSuffix("oes"), last.count > 4 {
            last = String(last.dropLast(2))
        } else if last.hasSuffix("s"), !last.hasSuffix("ss"), !last.hasSuffix("us"), !last.hasSuffix("is"), last.count > 3 {
            last = String(last.dropLast())
        }
        words.append(last)
        return words.joined(separator: " ")
    }

    private static func detectMealType(in text: String) -> ParsedMeal.MealSlot {
        if text.contains("breakfast") || text.contains("this morning") || text.contains("in the morning") || text.contains("nashta") {
            return .breakfast
        }
        if text.contains("lunch") || text.contains("this afternoon") { return .lunch }
        if text.contains("dinner") || text.contains("supper") || text.contains("tonight") || text.contains("last night") {
            return .dinner
        }
        if text.contains("snack") || text.contains("evening tea") { return .snacks }
        return .unknown
    }

    private static func detectPreset(in text: String) -> String? {
        guard let match = text.firstMatch(of: #/\bmy (usual|regular|normal|same) ([a-z ]+?)(?=$|[,.]| again| today| please)/#) else {
            return nil
        }
        return "\(match.1) \(match.2)".trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Lexicon

    static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "half": 0.5, "quarter": 0.25,
        "couple": 2, "few": 3, "dozen": 12, "single": 1, "double": 2,
        // Hindi / Hinglish
        "ek": 1, "do": 2, "teen": 3, "char": 4, "chaar": 4, "paanch": 5, "panch": 5, "chhe": 6, "che": 6,
        "saat": 7, "aath": 8, "nau": 9, "das": 10, "aadha": 0.5, "adha": 0.5, "dedh": 1.5, "dhai": 2.5,
    ]

    static let units: [String: String] = [
        "bowl": "bowl", "bowls": "bowl", "katori": "bowl", "katoris": "bowl",
        "cup": "cup", "cups": "cup", "mug": "cup", "mugs": "cup",
        "glass": "glass", "glasses": "glass",
        "plate": "plate", "plates": "plate", "thali": "plate",
        "slice": "slice", "slices": "slice",
        "piece": "piece", "pieces": "piece", "pcs": "piece", "pc": "piece",
        "g": "g", "gm": "g", "gms": "g", "gram": "g", "grams": "g", "kg": "kg",
        "ml": "ml", "l": "l", "litre": "l", "liter": "l",
        "tbsp": "tbsp", "tablespoon": "tbsp", "tablespoons": "tbsp", "spoon": "tbsp", "spoons": "tbsp", "chammach": "tbsp",
        "tsp": "tsp", "teaspoon": "tsp", "teaspoons": "tsp",
        "scoop": "scoop", "scoops": "scoop", "serving": "serving", "servings": "serving",
        "handful": "handful", "handfuls": "handful", "can": "can", "cans": "can",
        "bottle": "bottle", "bottles": "bottle", "packet": "packet", "packets": "packet", "pack": "packet",
        "bar": "bar", "bars": "bar", "small": "small", "medium": "medium", "large": "large",
    ]

    static let countableFoods: [String] = [
        "roti", "chapati", "phulka", "paratha", "naan", "puri", "egg", "idli", "dosa", "vada", "samosa",
        "banana", "apple", "orange", "mango", "biscuit", "cookie", "muffin", "bagel", "toast", "sandwich",
        "burger", "momo", "ladoo", "laddu", "gulab jamun", "jalebi", "kachori", "pakora", "cutlet", "uttapam",
        "thepla", "bhatura", "kulcha", "date", "almond", "walnut", "donut", "croissant", "taco", "wrap",
    ]

    static let irregularPlurals: [String: String] = [
        "idlis": "idli", "rotis": "roti", "chapatis": "chapati", "chapatti": "chapati", "puris": "puri",
        "samosas": "samosa", "momos": "momo", "eggs": "egg", "potatoes": "potato", "tomatoes": "tomato",
        "mangoes": "mango", "dosas": "dosa", "vadas": "vada", "parathas": "paratha", "rajma": "rajma",
        "chana": "chana", "chole": "chole", "dates": "date", "cookies": "cookie", "biscuits": "biscuit",
        "fries": "fries", "oats": "oats", "noodles": "noodles", "chips": "chips", "nuts": "nuts",
        "greens": "greens", "sprouts": "sprouts", "rasgullas": "rasgulla", "ladoos": "ladoo", "laddus": "laddu",
        "dahi": "dahi", "lassi": "lassi", "chai": "chai", "pulses": "pulses", "peas": "peas", "hummus": "hummus",
        "couscous": "couscous", "asparagus": "asparagus", "tortillas": "tortilla", "berries": "berries",
    ]

    static let cookingStyles: Set<String> = [
        "fried", "boiled", "grilled", "roasted", "steamed", "baked", "scrambled", "poached", "tandoori",
        "masala", "plain", "butter", "ghee", "toasted", "sauteed", "raw",
    ]

    static let fillerWords: Set<String> = [
        "i", "had", "ate", "have", "eaten", "drank", "having", "just", "also", "some", "log", "add", "please",
        "for", "then", "maine", "khaya", "khayi", "piya", "liya", "today", "around", "about", "approx", "roughly",
    ]

    static let trailingNoise: Set<String> = ["please", "today", "too", "also", "only", "each", "total", "khaya", "khayi", "piya", "liya"]

    /// Words that mark a sentence as activity, reminders or chat rather than food.
    static let nonFoodSignals: Set<String> = [
        "run", "ran", "running", "walk", "walked", "jog", "jogged", "km", "steps", "workout", "gym", "exercise",
        "remind", "reminder", "call", "meeting", "email", "slept", "sleep", "weigh", "weighed",
    ]

    static let nonFoodWords: Set<String> = ["nothing", "it", "that", "this", "them", "something", "food", "meal", "the", "my"]

    static let leadIns: [String] = [
        " i had ", " i ate ", " i have had ", " i've had ", " ive had ", " i just had ", " i drank ",
        " had ", " ate ", " log ", " add ", " for breakfast ", " for lunch ", " for dinner ", " for snacks ",
        " as a snack ", " for snack ",
    ]

    static let timePhrases: [String] = [
        "for breakfast", "for lunch", "for dinner", "breakfast", "lunch", "dinner", "this morning",
        "in the morning", "this afternoon", "tonight", "last night", "as a snack", "snack", "snacks",
    ]
}
