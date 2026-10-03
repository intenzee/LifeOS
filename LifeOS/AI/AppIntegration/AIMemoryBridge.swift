import Foundation

/// Keeps the AI memory index (F06) in step with the Experience layer's
/// "What LifeOS knows" list, which stays the user-visible source of truth.
///
/// IntelligenceStore calls `didRemember` / `didForget` / `wipe`; the assistant
/// bridge reads `records` for retrieval, conflicts and portion hints.
@MainActor
final class AIMemoryBridge {
    static let shared = AIMemoryBridge()

    let index: MemoryIndexStore
    /// Latest snapshot of the index for synchronous readers (context building).
    private(set) var records: [MemoryRecord] = []
    /// Candidates the assistant extracted, keyed by the MemoryItem id it proposed,
    /// so the saved record keeps the typed facet and expiry.
    private var proposed: [String: MemoryCandidate] = [:]
    /// Superseded facts leave the visible list but stay in the index as history.
    private var keepAsHistory: Set<String> = []
    private let defaults = UserDefaults.standard
    private static let consolidatedKey = "ai.memory.consolidatedDay"

    private init() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AI", isDirectory: true).appendingPathComponent("memory-index.json")
        index = MemoryIndexStore(url: url)
        Task { await reload() }
    }

    func reload() async { records = await index.all() }

    // MARK: Proposals from chat

    /// A MemoryItem for a candidate the assistant found ("I don't eat oats").
    func item(for candidate: MemoryCandidate, now: Date = Date()) -> MemoryItem {
        let item = MemoryItem(id: "said.\(UUID().uuidString)", text: candidate.statement, category: Self.category(candidate),
                              source: .youSaid, createdAt: now)
        proposed[item.id] = candidate
        return item
    }

    static func category(_ c: MemoryCandidate) -> MemoryItem.Category {
        switch c.kind {
        case .preference: c.facet.map(\.isFood) == true ? .foodHabits : .preferences
        case .routine: .routines
        case .foodFact: .foodHabits
        case .episode: .insights
        case .goalContext: c.facet.map(\.isFood) == true ? .foodHabits : .aboutYou
        case .fact: c.facet.map(\.isFood) == true ? .foodHabits : .aboutYou
        }
    }

    // MARK: Hooks from IntelligenceStore

    func didRemember(_ item: MemoryItem) {
        let candidate = proposed.removeValue(forKey: item.id)
            ?? MemoryExtractor.extract(from: item.text, explicit: true).first
            ?? MemoryCandidate(kind: .fact, statement: item.text)
        var c = candidate
        c.statement = item.text            // the user may have edited the wording
        c.isUserStated = item.source == .youSaid || item.source == .correction
        if c.isUserStated { c.confidence = 1 }
        // Confirmed in the UI → no longer pending, even if sensitive.
        let confirmed = c.isSensitive
        Task {
            if let outcome = await index.add(c, id: item.id, evidence: "chat") {
                // A contradiction removes the old fact from the visible list too.
                if case .superseded(let old) = outcome.action {
                    let visible = old.filter { $0.hasPrefix("said.") }
                    keepAsHistory.formUnion(visible)
                    IntelligenceStore.shared.forget(visible)
                }
                if confirmed { await index.confirm(outcome.record.id) }
            }
            await reload()
            await AIAssistantBridge.shared.contextEngine.invalidate(.memoryChanged)
        }
    }

    func didForget(_ ids: [String]) {
        for id in ids { proposed[id] = nil }
        let history = ids.filter { keepAsHistory.contains($0) }
        keepAsHistory.subtract(history)
        let deleted = ids.filter { !history.contains($0) }
        guard !deleted.isEmpty else { return }
        Task {
            await index.delete(deleted)
            await reload()
            await AIAssistantBridge.shared.contextEngine.invalidate(.memoryChanged)
        }
    }

    func wipe() {
        proposed = [:]
        keepAsHistory = []
        AIAssistantBridge.shared.resetConversation()      // in-memory chat log goes too
        Task {
            await index.wipe()
            await reload()
            await AIAssistantBridge.shared.contextEngine.invalidate(.memoryChanged)
        }
    }

    /// Inferred memories and photo corrections from the Experience list, mirrored
    /// as records (no chat needed) so retrieval and portion hints see them.
    func sync(_ items: [MemoryItem]) async {
        let known = Set(records.map(\.id))
        for item in items where !known.contains(item.id) {
            let extracted = MemoryExtractor.extract(from: item.text, explicit: true).first
            let kind: MemoryRecord.Kind = item.category == .routines ? .routine
                : item.category == .photoCorrections ? .foodFact
                : item.category == .insights ? .episode : (extracted?.kind ?? .fact)
            let record = MemoryRecord(id: item.id, kind: kind, text: item.text, facet: extracted?.facet,
                                      importance: item.isPinned ? 0.9 : 0.5, confidence: item.isInferred ? 0.8 : 1,
                                      source: item.source == .correction ? .correction : item.isInferred ? .inferred : .userStated,
                                      createdAt: item.createdAt, lastObservedAt: item.isInferred ? Date() : nil, pinned: item.isPinned)
            await index.upsert(record)
        }
        // Inferred items the Experience layer no longer produces are gone here too.
        let visible = Set(items.map(\.id))
        let stale = records.filter { r in (r.id.hasPrefix("usual.") || r.id.hasPrefix("routine.") || r.id.hasPrefix("insight.")
                                           || r.id.hasPrefix("correction.")) && !visible.contains(r.id) }.map(\.id)
        if !stale.isEmpty { await index.delete(stale) }
        await reload()
    }

    /// Day episodes, roll-ups and decay, at most once a day (F06 §7). Runs on the
    /// first foreground of the day instead of a BGProcessingTask, so no
    /// project/entitlement change is needed; the work is < 10 ms.
    func consolidateIfNeeded(_ context: LifeContext) async {
        let day = MemoryConsolidator.dayKey(context.now, context.calendar)
        guard defaults.string(forKey: Self.consolidatedKey) != day else { return }
        let observed = Set(IntelligenceStore.shared.memories.filter(\.isInferred).map(\.id))
        _ = await index.consolidate(context: context, observedRoutineIDs: observed)
        defaults.set(day, forKey: Self.consolidatedKey)
        await reload()
    }

    /// "My katori is 120 ml" → resolver portion hints (F04).
    var portionHints: PortionHints { PortionHints(memories: records) }

    /// "Mom's rajma is 180 kcal per katori" → the user's own foods (F02 resolver).
    var dishFoods: [UserFood] {
        records.compactMap { r in
            guard r.isUsable(at: Date()), case .dishKcal(let dish, let kcal, let unit)? = r.facet else { return nil }
            return UserFood(name: dish, macros: Macros(kcal: kcal, protein: 0, carbs: 0, fat: 0), servingDescription: "1 \(unit)", kind: .learned)
        }
    }
}
