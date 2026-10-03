import Foundation

// MARK: - Write path: dedupe, merge, conflict, policy (F06 §5, AI-223)

nonisolated enum MemoryReconciler {
    /// Embedding similarity at which a new statement is "the same memory".
    static let duplicateThreshold = 0.88
    /// Inferred items below this are stored as pending (never used until confirmed).
    static let pendingBelow = 0.7

    nonisolated struct Outcome: Sendable, Equatable {
        nonisolated enum Action: Sendable, Equatable {
            case inserted
            case reinforced
            case superseded(oldIDs: [String])
            case pendingConfirmation
        }
        var record: MemoryRecord
        var action: Action
        /// Every record whose stored state changed (the new one included).
        var changed: [MemoryRecord]
    }

    /// Applies one candidate to the store's records. Pure: returns what changed.
    static func apply(_ candidate: MemoryCandidate, to records: [MemoryRecord], embedder: any TextEmbedding,
                      now: Date = Date(), id: String? = nil, evidence: String? = nil) -> Outcome {
        let vector = embedder.vector(for: candidate.statement)
        let live = records.filter { $0.status == .active || $0.status == .pending }

        // 1. Same subject with the same meaning, or a near-identical sentence → reinforce.
        if let match = live.first(where: { existing in
            if let a = existing.facet, let b = candidate.facet { return a == b }
            guard existing.facet == nil || candidate.facet == nil,
                  let v = vector, let e = existing.embedding, existing.embeddingVersion == embedder.version else {
                return existing.text.caseInsensitiveCompare(candidate.statement) == .orderedSame
            }
            return VectorMath.cosine(v, e) >= duplicateThreshold
        }) {
            var updated = match
            updated.confidence = max(match.confidence, candidate.confidence)
            updated.importance = max(match.importance, candidate.importance)
            updated.updatedAt = now
            updated.lastObservedAt = now
            if candidate.isUserStated { updated.source = .userStated }
            if updated.status == .pending, candidate.isUserStated, !candidate.isSensitive { updated.status = .active }
            if let expires = candidate.expiresAt { updated.expiresAt = expires }
            if let evidence, !updated.evidence.contains(evidence) { updated.evidence.append(evidence) }
            return Outcome(record: updated, action: .reinforced, changed: [updated])
        }

        // 2. New record.
        var record = MemoryRecord(id: id ?? "mem.\(UUID().uuidString)", kind: candidate.kind, text: candidate.statement,
                                  facet: candidate.facet, importance: candidate.importance, confidence: candidate.confidence,
                                  sensitive: candidate.isSensitive,
                                  source: candidate.isUserStated ? .userStated : .inferred, status: .active,
                                  evidence: evidence.map { [$0] } ?? [], createdAt: now, lastObservedAt: now,
                                  expiresAt: candidate.expiresAt, embedding: vector, embeddingVersion: vector == nil ? nil : embedder.version)
        if candidate.isSensitive || (!candidate.isUserStated && candidate.confidence < pendingBelow) {
            record.status = .pending
            return Outcome(record: record, action: .pendingConfirmation, changed: [record])
        }

        // 3. Contradiction → the new statement wins; the old stays as history.
        var changed = [record]
        var superseded: [String] = []
        if let facet = candidate.facet {
            for old in live where old.facet.map({ facet.contradicts($0) }) ?? false {
                // An inferred guess never overrides what the user said.
                if old.source == .userStated && !candidate.isUserStated { continue }
                var replaced = old
                replaced.status = .superseded
                replaced.supersededBy = record.id
                replaced.updatedAt = now
                changed.append(replaced)
                superseded.append(old.id)
            }
        }
        return Outcome(record: record, action: superseded.isEmpty ? .inserted : .superseded(oldIDs: superseded), changed: changed)
    }

    /// "Forget that I'm vegetarian" → the active records it refers to (F06 §5.1).
    static func matches(forget query: String, in records: [MemoryRecord], embedder: any TextEmbedding) -> [MemoryRecord] {
        let q = query.lowercased()
        let words = Set(HashingEmbedder.words(q).filter { $0.count > 2 && !["that", "about", "what", "said", "told"].contains($0) })
        guard !words.isEmpty else { return [] }
        let qv = embedder.vector(for: query)
        return records.filter { $0.status == .active || $0.status == .pending }.filter { record in
            let recordWords = Set(HashingEmbedder.words(record.text))
            if !words.isDisjoint(with: recordWords) { return true }
            if case .diet(let diet, _, _)? = record.facet, q.contains(diet) || (q.contains("veg") && diet.contains("veg")) { return true }
            if let qv, let e = record.embedding, record.embeddingVersion == embedder.version { return VectorMath.cosine(qv, e) >= 0.8 }
            return false
        }
    }
}

// MARK: - Read path: retrieval (F06 §6, AI-224)

/// Who the memories are for — decides k and what may be included.
nonisolated enum ContextDestination: String, Sendable, Hashable, CaseIterable {
    case onDevice, pcc, thirdParty

    init(provider: ProviderID?) {
        switch provider {
        case .applePCC?: self = .pcc
        case .geminiBYOK?, .groqBYOK?: self = .thirdParty
        default: self = .onDevice
        }
    }

    /// Context token budget per destination (F05 §5).
    var tokenBudget: Int {
        switch self {
        case .onDevice: 600
        case .pcc: 3_000
        case .thirdParty: 2_000
        }
    }

    var memoryK: Int { self == .pcc ? 15 : 6 }
}

nonisolated enum MemoryRetriever {
    nonisolated struct Scored: Sendable, Equatable {
        var record: MemoryRecord
        var score: Double
    }

    /// `0.55·cosine + 0.20·importance + 0.15·recency + 0.10·kindPrior(intent)`;
    /// pinned items and hard food constraints for food intents are always in.
    static func retrieve(query: String, intent: AIIntent, records: [MemoryRecord], destination: ContextDestination,
                         embedder: any TextEmbedding, now: Date = Date(), k: Int? = nil) -> [Scored] {
        let limit = k ?? destination.memoryK
        let eligible = records.filter { record in
            guard record.isUsable(at: now) else { return false }
            if destination == .thirdParty { return record.isThirdPartySafe }
            return true
        }
        guard !eligible.isEmpty else { return [] }
        let qv = embedder.vector(for: query)
        let qWords = Set(HashingEmbedder.words(query))

        let scored = eligible.map { record -> Scored in
            var similarity = 0.0
            if let qv, let e = record.embedding, record.embeddingVersion == embedder.version {
                similarity = max(0, VectorMath.cosine(qv, e))
            } else if !qWords.isEmpty {
                // Lexical overlap when vectors aren't comparable.
                let rWords = Set(HashingEmbedder.words(record.text))
                similarity = Double(qWords.intersection(rWords).count) / Double(max(1, min(qWords.count, rWords.count)))
            }
            let reference = record.lastUsedAt.map { max($0, record.updatedAt) } ?? record.updatedAt
            let ageDays = max(0, now.timeIntervalSince(reference) / 86_400)
            let recency = exp(-ageDays / 30)
            var score = 0.55 * similarity + 0.20 * record.importance + 0.15 * recency + 0.10 * kindPrior(record, intent: intent)
            if record.pinned { score += 1 }
            if intent.isFood, record.isHardFoodConstraint { score += 1 }
            return Scored(record: record, score: score)
        }
        return Array(scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.record.id < $1.record.id }.prefix(limit))
    }

    static func kindPrior(_ record: MemoryRecord, intent: AIIntent) -> Double {
        switch intent {
        case .logFood, .photoMeal, .whatShouldIEat:
            switch record.kind {
            case .foodFact: 1
            case .fact, .preference: record.facet.map(\.isFood) == true ? 1 : 0.4
            case .routine: 0.5
            case .goalContext: 0.6
            case .episode: 0.1
            }
        case .askProgress, .weeklyReview, .briefing:
            switch record.kind {
            case .episode: 1
            case .goalContext: 0.9
            case .routine: 0.7
            case .fact: 0.4
            case .preference: 0.3
            case .foodFact: 0.1
            }
        case .nudge:
            switch record.kind {
            case .preference: 1
            case .routine: 0.9
            case .goalContext: 0.6
            default: 0.1
            }
        case .explainBudget:
            switch record.kind {
            case .goalContext: 0.6
            case .routine: 0.5
            default: 0.1
            }
        case .generalChat:
            0.5
        }
    }
}

nonisolated extension MemoryFacet {
    var isFood: Bool {
        switch self {
        case .avoidsFood, .likesFood, .diet, .allergy, .unitSize, .dishKcal, .avoidsIngredient: true
        default: false
        }
    }
}

nonisolated extension MemoryRecord {
    /// Allergies, diets and "I don't eat …" — never left to a model to honour.
    var isHardFoodConstraint: Bool {
        switch facet {
        case .allergy?, .diet?, .avoidsFood?, .avoidsIngredient?: kind != .preference
        default: false
        }
    }
}

// MARK: - Consolidation & decay (F06 §7, AI-226)

nonisolated enum MemoryConsolidator {
    nonisolated struct Result: Sendable, Equatable {
        var changed: [MemoryRecord]
        var added: [MemoryRecord]
        var removedIDs: [String]
    }

    /// Nightly (or first foreground of the day): one episode per finished day,
    /// weekly roll-ups, routine decay, expiry. Deterministic; < 1 ms per day.
    static func run(records: [MemoryRecord], context: LifeContext, embedder: any TextEmbedding,
                    observedRoutineIDs: Set<String> = []) -> Result {
        let now = context.now
        let cal = context.calendar
        var changed: [MemoryRecord] = []
        var added: [MemoryRecord] = []
        var removed: [String] = []
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // 1. Day episodes for the last 7 finished days that have data.
        for day in context.completedDays(7) where day.hasFood || !day.workouts.isEmpty {
            let id = "episode.day.\(dayKey(day.date, cal))"
            guard byID[id] == nil else { continue }
            added.append(episode(id: id, text: dayEpisodeText(day, cal), date: day.date, now: now, embedder: embedder))
        }

        // 2. Week roll-up: every finished Monday–Sunday week with ≥ 3 day episodes.
        let dayEpisodes = (records + added).filter { $0.id.hasPrefix("episode.day.") && $0.status == .active }
        let weeks = Dictionary(grouping: dayEpisodes) { record -> String in
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: record.createdAt)
            return "\(comps.yearForWeekOfYear ?? 0)-W\(comps.weekOfYear ?? 0)"
        }
        let currentWeek = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        for (key, episodes) in weeks where key != "\(currentWeek.yearForWeekOfYear ?? 0)-W\(currentWeek.weekOfYear ?? 0)" && episodes.count >= 3 {
            let id = "episode.week.\(key)"
            guard byID[id] == nil else { continue }
            let days = episodes.sorted { $0.createdAt < $1.createdAt }
            let weekDays = context.days.filter { d in days.contains { cal.isDate($0.createdAt, inSameDayAs: d.date) } }
            added.append(episode(id: id, text: weekEpisodeText(weekDays, cal), date: days.first?.createdAt ?? now, now: now, embedder: embedder))
            // Day episodes of a rolled-up week are archived (the week keeps the summary).
            for var d in days where byID[d.id] != nil {
                d.status = .archived
                d.updatedAt = now
                changed.append(d)
            }
        }

        for var record in records where record.status == .active || record.status == .pending {
            var dirty = false
            // 3. Expiry.
            if let expires = record.expiresAt, expires <= now {
                record.status = .archived
                dirty = true
            }
            // 4. Routine decay: −0.2 per 30 unobserved days; below 0.3 → archived.
            if record.kind == .routine, record.source != .userStated, record.status == .active {
                if observedRoutineIDs.contains(record.id) {
                    record.lastObservedAt = now
                    dirty = true
                } else if let seen = record.lastObservedAt, now.timeIntervalSince(seen) >= 30 * 86_400 {
                    record.confidence = max(0, record.confidence - 0.2)
                    record.lastObservedAt = now      // one step per 30 days
                    if record.confidence < 0.3 { record.status = .archived }
                    dirty = true
                }
            }
            // 5. Episodes older than 180 days are dropped (the weeks summarise them).
            if record.kind == .episode, now.timeIntervalSince(record.createdAt) > 180 * 86_400 {
                removed.append(record.id)
                continue
            }
            // 6. Re-embed after an embedding model change.
            if record.embeddingVersion != embedder.version, let v = embedder.vector(for: record.text) {
                record.embedding = v
                record.embeddingVersion = embedder.version
                dirty = true
            }
            if dirty {
                record.updatedAt = now
                changed.append(record)
            }
        }
        return Result(changed: changed, added: added, removedIDs: removed)
    }

    static func dayKey(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func dayEpisodeText(_ day: LifeContext.Day, _ cal: Calendar) -> String {
        var parts: [String] = []
        if day.hasFood {
            parts.append(day.budget > 0 ? "\(Num.kcal(day.kcal))/\(Num.kcal(day.budget)) kcal" : "\(Num.kcal(day.kcal)) kcal")
            parts.append("protein \(Int(day.protein.rounded())) g")
        } else {
            parts.append("no meals logged")
        }
        if !day.workouts.isEmpty {
            parts.append(day.workouts.map { "\($0.name.lowercased()) \($0.minutes) min" }.joined(separator: ", "))
        }
        if day.water > 0 { parts.append("water \(day.water)/\(day.waterTarget)") }
        return "\(Num.shortDay(day.date, cal)): " + parts.joined(separator: "; ")
    }

    static func weekEpisodeText(_ days: [LifeContext.Day], _ cal: Calendar) -> String {
        let logged = days.filter(\.hasFood)
        let first = days.map(\.date).min() ?? Date()
        var parts = ["\(logged.count) logged days"]
        if !logged.isEmpty {
            parts.append("avg \(Num.kcal(logged.map(\.kcal).reduce(0, +) / Double(logged.count))) kcal")
            parts.append("protein \(Int((logged.map(\.protein).reduce(0, +) / Double(logged.count)).rounded())) g")
            let budgeted = logged.filter { $0.budget > 0 }
            if !budgeted.isEmpty {
                parts.append("on budget \(budgeted.filter { $0.kcal <= $0.budget }.count)/\(budgeted.count)")
            }
        }
        let trained = days.filter { !$0.workouts.isEmpty }.count
        parts.append("\(trained) workout day\(trained == 1 ? "" : "s")")
        return "Week of \(Num.shortDay(first, cal)): " + parts.joined(separator: ", ")
    }

    private static func episode(id: String, text: String, date: Date, now: Date, embedder: any TextEmbedding) -> MemoryRecord {
        let v = embedder.vector(for: text)
        return MemoryRecord(id: id, kind: .episode, text: text, importance: 0.3, confidence: 1, source: .consolidation,
                            createdAt: date, updatedAt: now, embedding: v, embeddingVersion: v == nil ? nil : embedder.version)
    }
}

// MARK: - Store (AI-220)

/// The AI's memory index: richer metadata for every memory the user can see,
/// plus episodes. JSON in Application Support, `.completeUnlessOpen` file
/// protection, excluded from iCloud backup. `pause` stops writes; `wipe`
/// removes every record, vector and the file itself.
actor MemoryIndexStore {
    private let url: URL?
    private let embedder: any TextEmbedding
    private var records: [String: MemoryRecord] = [:]
    private(set) var isPaused = false
    private var loaded = false

    init(url: URL?, embedder: any TextEmbedding = DefaultEmbedder()) {
        self.url = url
        self.embedder = embedder
    }

    var embeddingVersion: String { embedder.version }

    private struct File: Codable {
        var version = 1
        var paused: Bool
        var records: [MemoryRecord]
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let url, let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return }
        isPaused = file.paused
        records = Dictionary(file.records.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
    }

    private func persist() {
        guard let url else { return }
        let file = File(paused: isPaused, records: records.values.sorted { $0.createdAt < $1.createdAt })
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try? data.write(to: url, options: [.atomic])
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
    }

    func all() -> [MemoryRecord] {
        loadIfNeeded()
        return records.values.sorted { $0.createdAt < $1.createdAt }
    }

    func record(_ id: String) -> MemoryRecord? {
        loadIfNeeded()
        return records[id]
    }

    /// Runs a candidate through dedupe/conflict/policy and saves the result.
    @discardableResult
    func add(_ candidate: MemoryCandidate, id: String? = nil, evidence: String? = nil, now: Date = Date()) -> MemoryReconciler.Outcome? {
        loadIfNeeded()
        guard !isPaused else { return nil }
        let outcome = MemoryReconciler.apply(candidate, to: Array(records.values), embedder: embedder, now: now, id: id, evidence: evidence)
        for record in outcome.changed { records[record.id] = record }
        persist()
        return outcome
    }

    /// Insert or replace a record as given (bridge sync from the visible list).
    func upsert(_ record: MemoryRecord) {
        loadIfNeeded()
        var r = record
        if r.embedding == nil || r.embeddingVersion != embedder.version, let v = embedder.vector(for: r.text) {
            r.embedding = v
            r.embeddingVersion = embedder.version
        }
        records[r.id] = r
        persist()
    }

    func confirm(_ id: String, now: Date = Date()) {
        loadIfNeeded()
        guard var r = records[id] else { return }
        r.status = .active
        r.confidence = 1
        r.updatedAt = now
        records[id] = r
        persist()
    }

    func delete(_ ids: [String]) {
        loadIfNeeded()
        for id in ids { records[id] = nil }
        // History of deleted items goes too: "forget" means forget.
        for (id, r) in records where r.supersededBy.map(ids.contains) == true { records[id] = nil }
        persist()
    }

    func markUsed(_ ids: [String], at date: Date = Date()) {
        loadIfNeeded()
        for id in ids { records[id]?.lastUsedAt = date }
        persist()
    }

    func setPaused(_ paused: Bool) {
        loadIfNeeded()
        isPaused = paused
        persist()
    }

    func paused() -> Bool {
        loadIfNeeded()
        return isPaused
    }

    /// "Forget everything": every record and vector, and the file itself.
    func wipe() {
        records = [:]
        loaded = true
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    func consolidate(context: LifeContext, observedRoutineIDs: Set<String> = []) -> MemoryConsolidator.Result {
        loadIfNeeded()
        let result = MemoryConsolidator.run(records: Array(records.values), context: context, embedder: embedder,
                                            observedRoutineIDs: observedRoutineIDs)
        for r in result.changed + result.added { records[r.id] = r }
        for id in result.removedIDs { records[id] = nil }
        if !(result.changed.isEmpty && result.added.isEmpty && result.removedIDs.isEmpty) { persist() }
        return result
    }

    func retrieve(query: String, intent: AIIntent, destination: ContextDestination, now: Date = Date(), k: Int? = nil) -> [MemoryRetriever.Scored] {
        loadIfNeeded()
        return MemoryRetriever.retrieve(query: query, intent: intent, records: Array(records.values), destination: destination,
                                        embedder: embedder, now: now, k: k)
    }

    /// Export for the user (F06 §8): JSON, without vectors.
    func exportJSON() -> Data {
        loadIfNeeded()
        let clean = records.values.sorted { $0.createdAt < $1.createdAt }.map { r -> MemoryRecord in
            var c = r
            c.embedding = nil
            return c
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(clean)) ?? Data()
    }

    func exportMarkdown() -> String {
        loadIfNeeded()
        let active = records.values.filter { $0.status == .active }
        var out = "# What LifeOS knows\n"
        for kind in MemoryRecord.Kind.allCases {
            let items = active.filter { $0.kind == kind }.sorted { $0.createdAt < $1.createdAt }
            guard !items.isEmpty else { continue }
            out += "\n## \(kind.rawValue)\n" + items.map { "- \($0.text)" }.joined(separator: "\n") + "\n"
        }
        return out
    }
}

// MARK: - Formatting

nonisolated enum Num {
    /// "1,240" — grouped by hand: a NumberFormatter per number made context
    /// building ~10× slower.
    static func kcal(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        let n = Int(v.rounded())
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + out
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var dayFormatters: [String: DateFormatter] = [:]

    /// "Fri 2 Oct". Formatters are cached per time zone (formatting is thread-safe;
    /// creation and the cache are guarded).
    static func shortDay(_ d: Date, _ cal: Calendar) -> String {
        let formatter: DateFormatter = lock.withLock {
            let key = cal.timeZone.identifier + cal.identifier.debugDescription
            if let f = dayFormatters[key] { return f }
            let f = DateFormatter()
            f.calendar = cal
            f.timeZone = cal.timeZone
            f.locale = Locale(identifier: "en_GB")
            f.dateFormat = "EEE d MMM"
            dayFormatters[key] = f
            return f
        }
        return formatter.string(from: d)
    }
}
