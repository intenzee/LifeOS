import Foundation
import LifeOSCore

/// Builds a day's summary from the store. Provided by the app, because the
/// calorie limit and water target come from settings and (from P1) the calorie engine.
public typealias SummaryBuilder = @Sendable (DayKey) async throws -> DailySummary?

/// Keeps `DailySummary` up to date (FND-08). It replaces the seven `.onChange`
/// handlers in HomeView that each re-encoded every summary.
///
/// It listens to store changes and collects the affected days. Once the store
/// has been quiet for `debounce`, it rebuilds each affected day once.
/// A burst of edits (logging a meal updates food, library and streak inputs)
/// produces a single recompute.
public actor SummaryService {
    /// Collections whose changes affect summaries. Summary writes themselves are
    /// excluded, so recomputing never triggers another recompute.
    public static let inputCollections: Set<String> = [
        FoodEntry.collection, WorkoutDay.collection, WaterDay.collection,
        WeightEntry.collection, TaskItem.collection
    ]

    private let database: LifeOSDatabase
    private let build: SummaryBuilder
    private let debounce: Duration
    private var pending = Set<DayKey>()
    private var flushTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    /// Number of completed recompute passes (diagnostics and tests).
    public private(set) var passes = 0

    public init(database: LifeOSDatabase, debounce: Duration = .milliseconds(500), build: @escaping SummaryBuilder) {
        self.database = database
        self.debounce = debounce
        self.build = build
    }

    /// Starts listening for store changes. Safe to call more than once.
    public func start() {
        guard listenTask == nil else { return }
        let stream = database.changes.changes()
        listenTask = Task { [weak self] in
            for await change in stream {
                guard let self else { return }
                await self.receive(change)
            }
        }
    }

    public func stop() {
        listenTask?.cancel()
        listenTask = nil
        flushTask?.cancel()
        flushTask = nil
    }

    /// Marks days dirty directly, e.g. at midnight or when settings change the calorie limit.
    public func invalidate(_ days: Set<DayKey>) {
        guard !days.isEmpty else { return }
        pending.formUnion(days)
        scheduleFlush()
    }

    /// Recomputes pending days now, skipping the debounce (app backgrounding, tests).
    public func flush() async {
        flushTask?.cancel()
        flushTask = nil
        await recomputePending()
    }

    private func receive(_ change: StoreChange) {
        guard Self.inputCollections.contains(change.collection) else { return }
        invalidate(change.days)
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        let delay = debounce
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.recomputePending()
        }
    }

    private func recomputePending() async {
        let days = pending.sorted()
        pending.removeAll()
        guard !days.isEmpty else { return }
        for day in days {
            do {
                if let summary = try await build(day) {
                    try await database.summaries.save(summary)
                }
            } catch {
                Log.data.error("Summary recompute failed for \(day.rawValue, privacy: .public): \(String(describing: error), privacy: .private)")
            }
        }
        passes += 1
    }
}
