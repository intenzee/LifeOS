import Foundation

/// One atomic thing LifeOS knows about the user (F06 §3–4).
///
/// The Experience layer's `MemoryItem` list stays the user-visible source of
/// truth; a `MemoryRecord` is the AI's richer view of the same item (shared
/// `id`), carrying what retrieval, dedupe and conflict handling need: kind,
/// a typed facet, importance, confidence, sensitivity, expiry and history.
nonisolated struct MemoryRecord: Codable, Sendable, Hashable, Identifiable {

    nonisolated enum Kind: String, Codable, Sendable, CaseIterable {
        case fact, preference, routine, foodFact, episode, goalContext
    }

    nonisolated enum Source: String, Codable, Sendable {
        case userStated, inferred, correction, consolidation
    }

    nonisolated enum Status: String, Codable, Sendable {
        /// Used in answers.
        case active
        /// Inferred with confidence < 0.7, or sensitive and not yet confirmed — never used.
        case pending
        /// Replaced by a newer, contradicting statement; kept as history.
        case superseded
        /// Expired or decayed below 0.3.
        case archived
    }

    var id: String
    var kind: Kind
    /// One user-readable statement, second person ("You don't eat oats").
    var text: String
    var facet: MemoryFacet?
    var importance: Double
    var confidence: Double
    /// Health conditions, medications, pregnancy… Stored only after explicit
    /// confirmation; never sent to third-party clouds.
    var sensitive: Bool
    var source: Source
    var status: Status
    var evidence: [String]
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    /// Last time the routine was seen in the logs (decay, F06 §7).
    var lastObservedAt: Date?
    var expiresAt: Date?
    var supersededBy: String?
    var pinned: Bool
    var embedding: [Float]?
    var embeddingVersion: String?

    init(id: String = "mem.\(UUID().uuidString)", kind: Kind, text: String, facet: MemoryFacet? = nil,
         importance: Double = 0.5, confidence: Double = 1, sensitive: Bool = false, source: Source = .userStated,
         status: Status = .active, evidence: [String] = [], createdAt: Date = Date(), updatedAt: Date? = nil,
         lastUsedAt: Date? = nil, lastObservedAt: Date? = nil, expiresAt: Date? = nil, supersededBy: String? = nil,
         pinned: Bool = false, embedding: [Float]? = nil, embeddingVersion: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.facet = facet
        self.importance = importance
        self.confidence = confidence
        self.sensitive = sensitive
        self.source = source
        self.status = status
        self.evidence = evidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.lastUsedAt = lastUsedAt
        self.lastObservedAt = lastObservedAt
        self.expiresAt = expiresAt
        self.supersededBy = supersededBy
        self.pinned = pinned
        self.embedding = embedding
        self.embeddingVersion = embeddingVersion
    }

    func isUsable(at date: Date) -> Bool {
        status == .active && (expiresAt.map { $0 > date } ?? true)
    }

    /// Food preferences and diet facts are the only personal memories a
    /// third-party cloud may see (F05 §6), and never sensitive ones.
    var isThirdPartySafe: Bool {
        guard !sensitive else { return false }
        switch facet {
        case .avoidsFood?, .likesFood?, .diet?, .allergy?, .unitSize?, .dishKcal?, .avoidsIngredient?, .answerStyle?:
            return true
        default:
            return false
        }
    }
}

/// The typed meaning of a memory, so conflicts, suggestion filters and
/// portion hints are decided in code, not by a model.
nonisolated enum MemoryFacet: Codable, Sendable, Hashable {
    case avoidsFood(String)
    case likesFood(String)
    /// "vegetarian", "eggetarian", "vegan", "pescatarian", "non-vegetarian", "jain";
    /// `exceptions` like ["egg"]; `days` = weekdays (1 = Sunday) when it only applies some days.
    case diet(String, exceptions: [String], days: [Int])
    case allergy(String)
    /// "My katori is about 120 ml" → unit "katori", 120 g/ml.
    case unitSize(unit: String, grams: Double)
    /// "Mom's rajma is about 180 kcal per katori".
    case dishKcal(dish: String, kcal: Double, unit: String)
    /// Weekdays (1 = Sunday) and an optional focus ("legs").
    case trainingDays([Int], focus: String?)
    case mealTime(slot: ParsedMeal.MealSlot, minutes: Int)
    case quietBefore(hour: Int)
    case answerStyle(String)
    case goal(String)
    case avoidsIngredient(String)       // "off sugar", "no onion garlic"

    /// Two facets describe the same subject (so a new one reinforces or replaces the old).
    var subjectKey: String {
        switch self {
        case .avoidsFood(let f), .likesFood(let f): "food:\(f)"
        case .diet: "diet"
        case .allergy(let a): "allergy:\(a)"
        case .unitSize(let unit, _): "unit:\(unit)"
        case .dishKcal(let dish, _, _): "dish:\(dish)"
        case .trainingDays(_, let focus): "training:\(focus ?? "")"
        case .mealTime(let slot, _): "mealTime:\(slot.rawValue)"
        case .quietBefore: "quietBefore"
        case .answerStyle: "answerStyle"
        case .goal(let g): "goal:\(g)"
        case .avoidsIngredient(let i): "ingredient:\(i)"
        }
    }

    /// Whether `other` (about the same subject) states something different.
    func contradicts(_ other: MemoryFacet) -> Bool {
        guard subjectKey == other.subjectKey || isLikeDislikePair(other) else { return false }
        return self != other
    }

    private func isLikeDislikePair(_ other: MemoryFacet) -> Bool {
        switch (self, other) {
        case (.avoidsFood(let a), .likesFood(let b)), (.likesFood(let a), .avoidsFood(let b)): a == b
        default: false
        }
    }
}

extension MemoryFacet {
    /// Foods to keep out of suggestions (F07 "allergies are hard constraints").
    nonisolated static func excludedFoods(_ records: [MemoryRecord], on date: Date, calendar: Calendar = .current) -> Set<String> {
        var out = Set<String>()
        let weekday = calendar.component(.weekday, from: date)
        for record in records where record.isUsable(at: date) {
            switch record.facet {
            case .avoidsFood(let food)?, .allergy(let food)?, .avoidsIngredient(let food)?:
                out.insert(food)
            case .diet(let diet, let exceptions, let days)?:
                guard days.isEmpty || days.contains(weekday) else { continue }
                var foods = DietRules.excluded(for: diet)
                foods.subtract(exceptions.flatMap { DietRules.expand($0) })
                out.formUnion(foods)
            default:
                continue
            }
        }
        return out
    }
}

/// What each diet rules out, by food word (matched against dish names).
nonisolated enum DietRules {
    static let meat: Set<String> = ["chicken", "mutton", "lamb", "goat", "beef", "pork", "bacon", "ham", "sausage",
                                    "salami", "keema", "steak", "turkey", "duck", "pepperoni", "kebab", "tikka"]
    static let seafood: Set<String> = ["fish", "prawn", "prawns", "shrimp", "crab", "tuna", "salmon", "squid", "pomfret", "surmai"]
    static let egg: Set<String> = ["egg", "eggs", "omelette", "omelet", "anda", "bhurji"]
    static let dairy: Set<String> = ["milk", "curd", "dahi", "paneer", "ghee", "butter", "cheese", "lassi", "raita",
                                     "yogurt", "yoghurt", "kheer", "chaas", "buttermilk", "cream", "whey", "khoa", "rabri"]
    static let jain: Set<String> = ["onion", "garlic", "potato", "aloo", "carrot", "beetroot", "radish", "ginger"]

    static func excluded(for diet: String) -> Set<String> {
        switch diet {
        case "vegetarian": meat.union(seafood).union(egg)
        case "eggetarian": meat.union(seafood)
        case "vegan": meat.union(seafood).union(egg).union(dairy).union(["honey"])
        case "pescatarian": meat
        case "jain": meat.union(seafood).union(egg).union(jain)
        default: []
        }
    }

    /// "eggs" → the egg words; anything else → itself.
    static func expand(_ word: String) -> Set<String> {
        if egg.contains(word) { return egg }
        if word == "dairy" { return dairy }
        if word == "fish" || word == "seafood" { return seafood }
        return [word]
    }

    /// Whether a dish name hits any excluded word (whole words, plural-tolerant).
    static func dish(_ name: String, hits excluded: Set<String>) -> Bool {
        guard !excluded.isEmpty else { return false }
        let words = Set(FoodNameNormalizer.tokens(name).flatMap { w in [w, w.hasSuffix("s") ? String(w.dropLast()) : w] })
        return excluded.contains { e in e.contains(" ") ? name.lowercased().contains(e) : words.contains(e) }
    }
}
