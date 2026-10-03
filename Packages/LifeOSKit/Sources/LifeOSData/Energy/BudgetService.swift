import Foundation
import LifeOSCore

public extension EnergySettings {
    static let documentName = "energySettings"
    /// The `StoreChange.collection` published when settings are saved.
    static let changeCollection = "documents/\(documentName)"
}

/// The single source of truth for the daily calorie budget (CAL-02, doc 03 §3.3).
///
/// For every affected day it:
/// 1. re-merges the manual gym log into the matching Watch workout (WCH-06),
/// 2. derives the day's exercise estimate and workout flag,
/// 3. runs `CalorieEngine` and stores `budgetKcal`, mode and formula version in `EnergyDay`.
///
/// Every consumer (Home, Watch snapshot, widgets, streaks, the assistant) reads
/// `EnergyDay.budgetKcal`. Past days freeze once they are 36 h old and a sync has
/// completed since, so a profile edit never rewrites history.
///
/// Its own writes come back as change events, but a recompute that changes
/// nothing writes nothing, so it settles after one extra pass.
public actor BudgetService {
    /// Collections whose changes affect a day's budget.
    public static let dayInputs: Set<String> = [EnergyDay.collection, WorkoutSession.collection, WorkoutDay.collection]
    /// Documents whose changes affect every unfrozen day.
    public static let globalInputs: Set<String> = ["documents/profile", EnergySettings.changeCollection]
    /// How long after its start a day may freeze (doc 03 §3.3).
    public static let freezeAfter: TimeInterval = 36 * 3600
    /// Unfrozen days recomputed when the profile or settings change.
    public static let openDaysWindow = 2

    private let database: LifeOSDatabase
    private let debounce: Duration
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone
    private var pending = Set<DayKey>()
    private var flushTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    public private(set) var passes = 0

    public init(database: LifeOSDatabase, debounce: Duration = .milliseconds(300), timeZone: TimeZone = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
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

    /// Marks days dirty (day rollover, foreground, tests).
    public func invalidate(_ days: Set<DayKey>) {
        guard !days.isEmpty else { return }
        pending.formUnion(days)
        scheduleFlush()
    }

    /// Today and the previous `openDaysWindow` days.
    public func invalidateOpenDays() {
        let today = DayKey.today(now: now(), timeZone: timeZone)
        invalidate(Set((0...Self.openDaysWindow).map { today.adding(days: -$0) }))
    }

    /// Recomputes pending days now, skipping the debounce.
    public func flush() async {
        flushTask?.cancel()
        flushTask = nil
        await recomputePending()
    }

    // MARK: Reads

    /// The stored budget for `day`, computing it first if it was never stored.
    public func budget(on day: DayKey) async throws -> Double? {
        if let stored = try await database.energy.day(day)?.budgetKcal { return stored }
        try await recompute(day)
        return try await database.energy.day(day)?.budgetKcal
    }

    /// The full breakdown for `day` from its stored inputs (the "Why this number?" sheet).
    /// A frozen day is explained with today's settings but its stored budget wins.
    public func breakdown(on day: DayKey) async throws -> BudgetBreakdown? {
        guard let profile = try await database.profile.load() else { return nil }
        let settings = try await database.energySettings.load()
        let energy = try await database.energy.day(day) ?? EnergyDay(dayKey: day)
        let recent = try await database.energy.days(from: day.adding(days: -(BudgetPlanner.measuredWindow - 1)),
                                                    through: day)
        return BudgetPlanner.budget(for: energy, recent: recent, profile: profile, settings: settings)
    }

    // MARK: Allowance (CAL-04)

    /// Recomputes the personalised allowance from the last 28 days. Returns the
    /// new value (or `nil` while there isn't enough history). Saves only on change.
    @discardableResult
    public func refreshAllowance() async throws -> Double? {
        guard let profile = try await database.profile.load() else { return nil }
        let today = DayKey.today(now: now(), timeZone: timeZone)
        let days = try await database.energy.days(from: today.adding(days: -AllowanceEstimator.window), through: today)
        let value = AllowanceEstimator.allowance(today: today, days: days, profile: profile)
        var settings = try await database.energySettings.load()
        guard settings.allowanceKcal != value else { return value }
        settings.allowanceKcal = value
        settings.allowanceComputedAt = now()
        try await database.energySettings.save(settings)
        Log.health.notice("Allowance personalised: \(value.map { Int($0) } ?? -1, privacy: .private) kcal")
        return value
    }

    // MARK: Private

    private func receive(_ change: StoreChange) {
        if Self.dayInputs.contains(change.collection) {
            invalidate(change.days)
        } else if Self.globalInputs.contains(change.collection) {
            invalidateOpenDays()
        }
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
                try await recompute(day)
            } catch {
                let key = day.rawValue
                Log.data.error("Budget recompute failed for \(key, privacy: .public): \(String(describing: error), privacy: .private)")
            }
        }
        passes += 1
    }

    /// Reconciles and budgets one day.
    func recompute(_ day: DayKey) async throws {
        let profile = try await database.profile.load()
        let settings = try await database.energySettings.load()
        let manualDay = try await database.workouts.day(day)

        // 1. Merge (derived, recomputed from scratch).
        let manual = WorkoutMerge.ManualLog(dayKey: day, exerciseIDs: manualDay.exercises.filter { $0.setsCompleted > 0 }.map(\.id))
        let sessions = WorkoutMerge.attach(manual: manual, to: try await database.workoutSessions.sessions(on: day))
        try await database.workoutSessions.replaceSessions(on: day, with: sessions)

        // 2. Derived energy inputs.
        let weight = profile?.currentWeightKg ?? 70
        let metKcal = CalorieCalculator.totalWorkoutCalories(workout: manualDay, weightKg: weight)
        let estimated = WorkoutMerge.estimatedSessionKcal(sessions: sessions, manualMETKcal: metKcal)
        let hadWorkout = !sessions.isEmpty || manualDay.totalSets > 0 || manualDay.treadmillDone

        let recent = try await database.energy.days(from: day.adding(days: -(BudgetPlanner.measuredWindow - 1)),
                                                    through: day.adding(days: -1))
        let lastSync = try await database.healthSync.load().lastCompletedSync
        let freezeAt = day.startDate(timeZone: timeZone).addingTimeInterval(Self.freezeAfter)
        let nowDate = now()

        try await database.energy.update(day) { energy in
            energy.estimatedSessionKcal = estimated
            energy.hadWorkout = hadWorkout
            guard !energy.isFrozen else { return }
            // 3. Budget (needs a profile; without one, nothing to budget yet).
            if let profile {
                let breakdown = BudgetPlanner.budget(for: energy, recent: recent + [energy], profile: profile,
                                                     settings: settings)
                energy.budgetKcal = breakdown.budget.rounded()
                energy.budgetMode = breakdown.mode
                energy.formulaVersion = breakdown.formulaVersion
            }
            if nowDate >= freezeAt, let lastSync, lastSync >= freezeAt, energy.budgetKcal != nil {
                energy.frozenAt = nowDate
            }
        }
    }
}
