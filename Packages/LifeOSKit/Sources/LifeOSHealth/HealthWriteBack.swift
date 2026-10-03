import Foundation
import LifeOSCore
import LifeOSData

// Food and water write-back to Apple Health (WCH-08, doc 02 §3.4).
//
// LifeOS mirrors its own log into Health: each food entry becomes a food
// correlation (dietary energy + macros), and each day's water becomes one or
// more `.dietaryWater` samples. Every sample carries a write id. The ledger
// (`HealthWriteState`) remembers which write id each entry has, so an edit
// deletes the old samples and writes new ones, and a delete removes them.
//
// Write ids are derived from the content, so a retry after a failed or
// interrupted pass deletes whatever the earlier attempt wrote before saving
// again. Nothing is ever written twice.

/// What can be written. Each kind has its own Health permission.
public enum HealthWriteKind: String, Sendable, CaseIterable {
    case food, water
}

/// One food entry as a Health food correlation.
public struct NutritionSample: Sendable, Equatable {
    /// The write id stamped on the correlation and every sample in it.
    public var id: UUID
    public var date: Date
    public var name: String
    public var kcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double

    public init(id: UUID, date: Date, name: String, kcal: Double, proteinG: Double, carbsG: Double, fatG: Double) {
        self.id = id
        self.date = date
        self.name = name
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }
}

/// One `.dietaryWater` sample.
public struct WaterSample: Sendable, Equatable {
    public var id: UUID
    public var date: Date
    public var ml: Double

    public init(id: UUID, date: Date, ml: Double) {
        self.id = id
        self.date = date
        self.ml = ml
    }
}

/// The write side of the HealthKit seam. `HKHealthStoreClient` is the live one.
public protocol HealthWriteClient: Sendable {
    var isAvailable: Bool { get }
    /// Shows the Health sheet for the write types.
    func requestWriteAuthorization() async throws
    /// Whether the user allowed LifeOS to write this kind. Health tells apps
    /// their write status (unlike read status).
    func canWrite(_ kind: HealthWriteKind) -> Bool
    func save(food: [NutritionSample], water: [WaterSample]) async throws
    /// Deletes LifeOS's samples (and correlations) carrying these write ids.
    /// Ids with nothing behind them are fine.
    func deleteSamples(writeIDs: [UUID]) async throws
}

// MARK: - Planning (pure)

/// The Health changes that bring one day in line with the log.
public struct HealthWritePlan: Sendable, Equatable {
    /// Write ids to delete first. Includes the ids about to be written, so a
    /// retried write never duplicates.
    public var deletes: [UUID] = []
    public var food: [NutritionSample] = []
    public var water: [WaterSample] = []
    /// The day's ledger once the plan has run.
    public var ledger: HealthWriteDay

    public var isEmpty: Bool { deletes.isEmpty && food.isEmpty && water.isEmpty }
}

public enum HealthWritePlanner {
    /// Typical meal times, used when an entry was logged on another day
    /// (yesterday's dinner added this morning).
    static let mealHour: [MealType: Double] = [.breakfast: 8, .lunch: 13, .snacks: 16, .dinner: 19]

    /// - Parameters:
    ///   - kinds: what the user allowed. A kind that's missing keeps its ledger as is.
    public static func plan(day: DayKey, entries: [FoodEntry], water: WaterDay?, ledger: HealthWriteDay,
                            kinds: Set<HealthWriteKind>, now: Date, timeZone: TimeZone) -> HealthWritePlan {
        var plan = HealthWritePlan(ledger: ledger)
        if kinds.contains(.food) { planFood(day: day, entries: entries, timeZone: timeZone, into: &plan) }
        if kinds.contains(.water) { planWater(day: day, water: water, now: now, timeZone: timeZone, into: &plan) }
        return plan
    }

    private static func planFood(day: DayKey, entries: [FoodEntry], timeZone: TimeZone, into plan: inout HealthWritePlan) {
        let previous = plan.ledger.food
        var next: [UUID: UUID] = [:]
        for entry in entries.sorted(by: { $0.loggedAt < $1.loggedAt }) where shouldWrite(entry) {
            let sample = nutrition(for: entry, on: day, timeZone: timeZone)
            next[entry.id] = sample.id
            if previous[entry.id] != sample.id {
                plan.deletes.append(sample.id)
                plan.food.append(sample)
            }
        }
        for (entryID, writeID) in previous.sorted(by: { $0.value.uuidString < $1.value.uuidString })
        where next[entryID] != writeID {
            plan.deletes.append(writeID)
        }
        plan.ledger.food = next
    }

    /// Water is written as increments, so Health shows when it was drunk.
    /// Fewer glasses removes the newest samples, then tops up the difference.
    private static func planWater(day: DayKey, water: WaterDay?, now: Date, timeZone: TimeZone,
                                  into plan: inout HealthWritePlan) {
        let target = water?.milliliters ?? 0
        var kept = plan.ledger.water
        var total = kept.reduce(0) { $0 + $1.ml }
        while total > target + 0.5, let last = kept.popLast() {
            plan.deletes.append(last.id)
            total -= last.ml
        }
        let missing = target - total
        if missing > 0.5 {
            let id = StableID.make("hk-water", day.rawValue, String(kept.count))
            let date = date(on: day, preferring: [now, water?.updatedAt].compactMap { $0 }, timeZone: timeZone)
            kept.append(.init(id: id, ml: missing))
            plan.deletes.append(id)
            plan.water.append(WaterSample(id: id, date: date, ml: missing))
        }
        plan.ledger.water = kept
    }

    /// Entries imported from Health aren't written back. Empty entries carry nothing.
    static func shouldWrite(_ entry: FoodEntry) -> Bool {
        entry.source != .healthKit && (entry.calories > 0 || entry.proteinG > 0 || entry.carbsG > 0 || entry.fatG > 0)
    }

    static func nutrition(for entry: FoodEntry, on day: DayKey, timeZone: TimeZone) -> NutritionSample {
        let fallback = day.startDate(timeZone: timeZone).addingTimeInterval((mealHour[entry.meal] ?? 12) * 3600)
        let date = date(on: day, preferring: [entry.loggedAt], fallback: fallback, timeZone: timeZone)
        // Everything Health shows is in the id, so any edit gets new samples.
        // The day is too: an entry moved to another day must not share an id
        // with its old self, or the old day's delete could remove the new write.
        let fingerprint = [entry.name, number(entry.calories), number(entry.proteinG), number(entry.carbsG),
                           number(entry.fatG), String(Int(date.timeIntervalSince1970))]
        let id = StableID.make("hk-food", day.rawValue, entry.id.uuidString, fingerprint.joined(separator: "|"))
        return NutritionSample(id: id, date: date, name: entry.name, kcal: entry.calories, proteinG: entry.proteinG,
                               carbsG: entry.carbsG, fatG: entry.fatG)
    }

    /// The first candidate inside `day`, otherwise `fallback` (noon by default).
    static func date(on day: DayKey, preferring candidates: [Date], fallback: Date? = nil,
                     timeZone: TimeZone) -> Date {
        let start = day.startDate(timeZone: timeZone), end = day.endDate(timeZone: timeZone)
        return candidates.first { $0 >= start && $0 < end } ?? fallback ?? start.addingTimeInterval(12 * 3600)
    }

    private static func number(_ value: Double) -> String { String(format: "%.2f", value) }
}

// MARK: - Service

/// Mirrors the food and water log into Apple Health while "Save to Apple Health"
/// is on (WCH-08). It listens to store changes, so every way of logging is
/// covered (phone, Watch, Siri, the assistant) without callers knowing about Health.
///
/// Only days from `enabledFrom` on are written (turning it on doesn't backfill
/// history), and only the last `editableDays`: edits to older entries aren't mirrored.
public actor HealthWriteBackService {
    public static let watchedCollections: Set<String> = [FoodEntry.collection, WaterDay.collection]
    /// How far back edits are mirrored. The ledger is pruned past it.
    public static let editableDays = 30

    private let client: any HealthWriteClient
    private let database: LifeOSDatabase
    private let debounce: Duration
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private var pending = Set<DayKey>()
    private var flushTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    private var tail: Task<Void, Never>?

    public init(client: any HealthWriteClient, database: LifeOSDatabase, debounce: Duration = .seconds(1),
                timeZone: TimeZone = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.database = database
        self.debounce = debounce
        self.timeZone = timeZone
        self.now = now
    }

    // MARK: Lifecycle

    public func start() {
        guard listenTask == nil else { return }
        let stream = database.changes.changes()
        listenTask = Task { [weak self] in
            for await change in stream where Self.watchedCollections.contains(change.collection) {
                guard let self else { return }
                await self.invalidate(change.days)
            }
        }
    }

    public func stop() {
        listenTask?.cancel()
        listenTask = nil
        flushTask?.cancel()
        flushTask = nil
    }

    // MARK: Setting

    public func isEnabled() async throws -> Bool {
        try await database.healthWrites.load().enabledFrom != nil
    }

    /// Turns mirroring on (from today) or off. Turning it on asks for permission
    /// first. Turning it off leaves what's already in Health: the user can
    /// delete it there.
    public func setEnabled(_ enabled: Bool) async throws {
        if enabled { try await client.requestWriteAuthorization() }
        try await serially { [self] in
            try await self.applyEnabled(enabled)
        }
    }

    private func applyEnabled(_ enabled: Bool) async throws {
        var state = try await database.healthWrites.load()
        state.enabledFrom = enabled ? (state.enabledFrom ?? today) : nil
        try await database.healthWrites.save(state)
        if enabled { await reconcileLogged(today) }
    }

    /// Kinds the user allowed in Health.
    public func writableKinds() -> Set<HealthWriteKind> {
        guard client.isAvailable else { return [] }
        return Set(HealthWriteKind.allCases.filter { client.canWrite($0) })
    }

    // MARK: Reconcile

    public func invalidate(_ days: Set<DayKey>) {
        guard !days.isEmpty else { return }
        pending.formUnion(days)
        scheduleFlush()
    }

    /// Today and yesterday. Run at launch and on foreground, to catch changes
    /// made while the app wasn't listening.
    public func invalidateOpenDays() {
        invalidate([today, today.adding(days: -1)])
    }

    /// Writes pending days now, skipping the debounce.
    public func flush() async {
        flushTask?.cancel()
        flushTask = nil
        _ = try? await serially { [self] in
            await self.drain()
        }
    }

    private func drain() async {
        let days = pending.sorted()
        pending.removeAll()
        for day in days { await reconcileLogged(day) }
    }

    private func reconcileLogged(_ day: DayKey) async {
        do {
            try await reconcile(day)
        } catch {
            // The ledger only moves after Health accepted the change, so the
            // next change or launch retries this day.
            let key = day.rawValue
            Log.health.error("Health write for \(key, privacy: .public) failed: \(String(describing: error), privacy: .private)")
        }
    }

    /// Runs `work` after everything queued before it. A day's delete-then-save
    /// must never interleave with another pass over the same day, or both
    /// passes could save the same samples.
    private func serially<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task { () async throws -> T in
            await previous?.value
            return try await work()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }

    func reconcile(_ day: DayKey) async throws {
        var state = try await database.healthWrites.load()
        let today = self.today
        guard let from = state.enabledFrom, day >= from, day >= today.adding(days: -Self.editableDays) else { return }
        let kinds = writableKinds()
        guard !kinds.isEmpty else { return }

        let entries = try await database.food.entries(on: day)
        let water = try await database.water.days(from: day, through: day).first
        let ledger = state.days[day] ?? HealthWriteDay()
        let plan = HealthWritePlanner.plan(day: day, entries: entries, water: water, ledger: ledger, kinds: kinds,
                                           now: now(), timeZone: timeZone)
        guard !plan.isEmpty else { return }

        if !plan.deletes.isEmpty { try await client.deleteSamples(writeIDs: plan.deletes) }
        if !plan.food.isEmpty || !plan.water.isEmpty { try await client.save(food: plan.food, water: plan.water) }

        state.days[day] = plan.ledger.isEmpty ? nil : plan.ledger
        state.days = state.days.filter { $0.key >= today.adding(days: -Self.editableDays) }
        try await database.healthWrites.save(state)
        let key = day.rawValue, stale = plan.deletes.count - plan.food.count - plan.water.count
        Log.health.notice("Health write \(key, privacy: .public): \(plan.food.count) food, \(plan.water.count) water, \(stale) removed")
    }

    // MARK: Private

    private var today: DayKey { DayKey.today(now: now(), timeZone: timeZone) }

    private func scheduleFlush() {
        flushTask?.cancel()
        let delay = debounce
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.flush()
        }
    }
}
