import SwiftUI
import Combine
import LifeOSData

// DailySummary lives in LifeOSCore.

// MARK: - Streak Manager
class StreakManager: ObservableObject {
    static let shared = StreakManager()

    @Published var summaries: [String: DailySummary] = [:]

    private let calendar = Calendar.current
    private weak var store: LocalStore?
    private var pendingWrite: Task<Void, Never>?

    private init() {}

    func load(from snapshot: DataSnapshot, store: LocalStore) {
        self.store = store
        summaries = Dictionary(snapshot.summaries.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
    }

    // Call this every time HomeView appears or data changes
    func recordToday(
        caloriesConsumed: Double,
        calorieLimit: Double,
        waterGlasses: Int,
        waterTarget: Int,
        gymIntensity: String,
        todosCompleted: Int,
        todosTotal: Int
    ) {
        let key = dateKey(for: Date())
        let summary = DailySummary(
            date: key,
            caloriesConsumed: caloriesConsumed,
            calorieLimit: calorieLimit,
            waterGlasses: waterGlasses,
            waterTarget: waterTarget,
            gymIntensity: gymIntensity,
            todosCompleted: todosCompleted,
            todosTotal: todosTotal
        )
        // HomeView calls this from several .onChange handlers. Identical values
        // are dropped, and real changes are coalesced into one write (FND-08).
        guard summaries[key] != summary else { return }
        summaries[key] = summary
        scheduleWrite(summary)
    }

    // MARK: - Streak Calculators

    func streak(for condition: (DailySummary) -> Bool) -> Int {
        var count = 0
        var checkDate = Date()

        // Don't penalise today if it's not done yet — start from yesterday
        // unless today already qualifies
        let todayKey = dateKey(for: checkDate)
        if let todaySummary = summaries[todayKey], condition(todaySummary) {
            count = 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        } else {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }

        while true {
            let key = dateKey(for: checkDate)
            guard let summary = summaries[key], condition(summary) else { break }
            count += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }
        return count
    }

    var calorieStreak: Int   { streak { $0.hitCalorieGoal } }
    var waterStreak: Int     { streak { $0.hitWaterGoal } }
    var gymStreak: Int       { streak { $0.hitGymGoal } }
    var todoStreak: Int      { streak { $0.hitTodoGoal } }
    var perfectDayStreak: Int { streak { $0.isPerfectDay } }

    // Last 30 days for the heatmap grid
    func last30Days() -> [DailySummary?] {
        (0..<30).reversed().map { offset -> DailySummary? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return summaries[dateKey(for: date)]
        }
    }

    // MARK: - Persistence

    /// Writes the latest summary 500 ms after the last change in a burst.
    private func scheduleWrite(_ summary: DailySummary) {
        pendingWrite?.cancel()
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let store = self?.store else { return }
            let db = store.database
            store.enqueue { try await db.summaries.save(summary) }
        }
    }

    func dateKey(for date: Date) -> String {
        DayKey.make(for: date).rawValue
    }
}
