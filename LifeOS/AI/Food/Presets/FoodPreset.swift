import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// A named, reusable meal ("Usual breakfast", "Gym shake") — F03 §3.
nonisolated struct FoodPreset: Codable, Sendable, Identifiable, Hashable {
    nonisolated enum Source: String, Codable, Sendable { case user, aiSuggested, imported }
    /// F03 §4.6. Only `.off` is reachable in Phase 1 (reminders/auto-log ship with F09).
    nonisolated enum AutoLogPolicy: String, Codable, Sendable { case off, remind, autoLogWithUndo }

    var id: UUID
    var name: String
    var aliases: [String]
    /// Frozen nutrition: deleting a custom food later never breaks the preset (F03 §6).
    var items: [ResolvedFoodItem]
    var defaultMeal: ParsedMeal.MealSlot?
    var source: Source
    var usageCount: Int
    var lastUsedAt: Date?
    /// Recent use times (most recent last, capped) — the typical window is learned from these.
    var usageHistory: [Date]
    var autoLogPolicy: AutoLogPolicy
    var archived: Bool
    var createdAt: Date

    init(id: UUID = UUID(), name: String, aliases: [String] = [], items: [ResolvedFoodItem],
         defaultMeal: ParsedMeal.MealSlot? = nil, source: Source = .user, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.items = items
        self.defaultMeal = defaultMeal
        self.source = source
        self.usageCount = 0
        self.lastUsedAt = nil
        self.usageHistory = []
        self.autoLogPolicy = .off
        self.archived = false
        self.createdAt = createdAt
    }

    var totals: Macros { items.reduce(.zero) { $0 + $1.macros } }
    var containsEstimates: Bool { items.contains { $0.isEstimate } }
    var itemKeys: Set<String> { Set(items.map { FoodNameNormalizer.normalise($0.displayName) }) }

    /// Learned eating window: median hour ± spread, from usage (F03 §4.4 "window learning").
    func typicalHourRange(calendar: Calendar = .current) -> ClosedRange<Double>? {
        let hours = usageHistory.map { date -> Double in
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        }.sorted()
        guard hours.count >= 3 else { return nil }
        let median = hours[hours.count / 2]
        let q1 = hours[hours.count / 4], q3 = hours[(hours.count * 3) / 4]
        let spread = max(0.75, (q3 - q1))
        return (median - spread)...(median + spread)
    }

    mutating func recordUse(at date: Date) {
        usageCount += 1
        lastUsedAt = date
        usageHistory.append(date)
        if usageHistory.count > 30 { usageHistory.removeFirst(usageHistory.count - 30) }
    }
}

/// Persistence for presets. The AI team owns this until `FoodPreset` moves into
/// LifeOSData (contract C1); swapping the implementation is the only change.
nonisolated protocol PresetRepository: Sendable {
    func all() async -> [FoodPreset]
    func save(_ preset: FoodPreset) async
    func delete(_ id: UUID) async
    func recordUse(_ id: UUID, at date: Date) async
}

/// JSON file store with complete-until-first-unlock protection.
actor FilePresetRepository: PresetRepository {
    private let url: URL?
    private var presets: [UUID: FoodPreset] = [:]
    private var loaded = false

    init(url: URL?) { self.url = url }

    func all() -> [FoodPreset] {
        loadIfNeeded()
        return presets.values.sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    func save(_ preset: FoodPreset) {
        loadIfNeeded()
        presets[preset.id] = preset
        persist()
    }

    func delete(_ id: UUID) {
        loadIfNeeded()
        presets[id] = nil
        persist()
    }

    func recordUse(_ id: UUID, at date: Date) {
        loadIfNeeded()
        presets[id]?.recordUse(at: date)
        persist()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([FoodPreset].self, from: data) else { return }
        presets = Dictionary(decoded.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func persist() {
        guard let url, let data = try? JSONEncoder().encode(Array(presets.values)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: url, options: [.atomic])
        #endif
    }
}

// MARK: - Resolution (F03 §4.2)

nonisolated enum PresetResolution: Sendable, Equatable {
    case match(FoodPreset)
    case ambiguous([FoodPreset])
    case none
}

nonisolated struct PresetResolver: Sendable {
    var presets: [FoodPreset]
    var calendar: Calendar = .current

    /// Words that mean "my usual" without naming a preset.
    static let usualWords: Set<String> = ["usual", "regular", "normal", "same", "roz", "rozana", "daily", "always"]

    func resolve(_ phrase: String, now: Date = Date(), meal: ParsedMeal.MealSlot? = nil) -> PresetResolution {
        decide(scored(phrase, now: now, meal: meal))
    }

    func scored(_ phrase: String, now: Date, meal: ParsedMeal.MealSlot?) -> [(preset: FoodPreset, score: Double)] {
        let active = presets.filter { !$0.archived }
        guard !active.isEmpty else { return [] }
        let query = Self.clean(phrase)
        let queryTokens = Set(query.split(separator: " ").map(String.init))
        let mealHint = meal.flatMap { $0 == .unknown ? nil : $0 } ?? Self.mealWord(in: queryTokens)
        // "my usual" with no real name: rank by meal slot and time window.
        let unnamed = queryTokens.subtracting(Self.usualWords).subtracting(Self.mealWords).isEmpty

        return active.map { preset -> (preset: FoodPreset, score: Double) in
            var score = nameScore(query: query, tokens: queryTokens, preset: preset)
            if unnamed {
                score = max(score, 0.6)
                if let mealHint {
                    if preset.defaultMeal == mealHint || Self.clean(preset.name).contains(mealHint.rawValue) { score += 0.3 }
                } else if preset.defaultMeal == SmartFoodLogger.inferMeal(at: now, calendar: calendar) {
                    score += 0.2
                }
            }
            if let range = preset.typicalHourRange(calendar: calendar) {
                let c = calendar.dateComponents([.hour, .minute], from: now)
                let hour = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
                if range.contains(hour) { score += 0.1 }
            }
            score += min(0.05, Double(preset.usageCount) * 0.005)   // tiny habit prior
            return (preset, score)
        }
        .filter { $0.score >= 0.55 }
        .sorted { $0.score > $1.score }
    }

    private func nameScore(query: String, tokens: Set<String>, preset: FoodPreset) -> Double {
        let names = ([preset.name] + preset.aliases).map(Self.clean)
        if names.contains(query) { return 1.0 }
        var best = 0.0
        for name in names {
            let nameTokens = Set(name.split(separator: " ").map(String.init))
            guard !nameTokens.isEmpty, !tokens.isEmpty else { continue }
            // Exact token overlap ignoring "my/usual" glue words.
            let a = tokens.subtracting(Self.usualWords), b = nameTokens.subtracting(Self.usualWords)
            if !a.isEmpty, a == b { best = max(best, 0.95) }
            // Fuzzy tokens: each query token within 2 edits of a name token.
            let matched = a.filter { q in b.contains { FoodNameNormalizer.editDistance($0, q, limit: 2) <= (q.count > 4 ? 2 : 1) } }
            if !a.isEmpty, !b.isEmpty {
                let jaccard = Double(matched.count) / Double(a.count + b.count - matched.count)
                best = max(best, 0.85 * jaccard)
            }
            if let semantic = Self.semanticSimilarity(query, name), semantic >= 0.8 { best = max(best, 0.75) }
        }
        return best
    }

    static let mealWords: Set<String> = ["breakfast", "lunch", "dinner", "snack", "nashta"]

    static func mealWord(in tokens: Set<String>) -> ParsedMeal.MealSlot? {
        if tokens.contains("breakfast") || tokens.contains("nashta") { return .breakfast }
        if tokens.contains("lunch") { return .lunch }
        if tokens.contains("dinner") { return .dinner }
        if tokens.contains("snack") { return .snacks }
        return nil
    }

    static func clean(_ text: String) -> String {
        FoodNameNormalizer.normalise(text)
            .split(separator: " ")
            .filter { !["my", "log", "add", "had", "the", "ate", "today", "please", "again"].contains($0) }
            .joined(separator: " ")
    }

    /// On-device sentence embeddings (NaturalLanguage, works on every iPhone —
    /// no Apple Intelligence needed). nil when the asset is unavailable.
    static func semanticSimilarity(_ a: String, _ b: String) -> Double? {
        #if canImport(NaturalLanguage)
        guard a.count > 3, b.count > 3, let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        let distance = embedding.distance(between: a, and: b, distanceType: .cosine)
        guard distance.isFinite else { return nil }
        return 1 - distance
        #else
        return nil
        #endif
    }
}

// MARK: - Naming (T0 fallback for `presetSuggestName`)

nonisolated enum PresetNamer {
    static func suggest(items: [String], meal: ParsedMeal.MealSlot?, weekdaysOnly: Bool = false) -> String {
        let names = items.map { $0.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ") }
        if names.count == 1 { return names[0] }
        if names.count == 2 { return "\(names[0]) & \(names[1])" }
        let slot = meal.flatMap { $0 == .unknown ? nil : $0.rawValue } ?? "meal"
        return weekdaysOnly ? "Weekday \(slot)" : "Usual \(slot)"
    }
}
