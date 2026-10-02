import Foundation

/// Streak maths over daily summaries. Pure and deterministic: `today` is
/// injected, so tests don't depend on the clock.
public struct StreakCalculator: Sendable {
    public let summaries: [DayKey: DailySummary]
    public let today: DayKey

    public init(summaries: [DayKey: DailySummary], today: DayKey) {
        self.summaries = summaries
        self.today = today
    }

    public init(summaries: some Sequence<DailySummary>, today: DayKey) {
        var byDay: [DayKey: DailySummary] = [:]
        for summary in summaries {
            if let key = DayKey(summary.date) { byDay[key] = summary }
        }
        self.init(summaries: byDay, today: today)
    }

    /// Consecutive qualifying days ending today. An unfinished today doesn't
    /// break the streak: counting starts from yesterday unless today already
    /// qualifies. Same behaviour as the legacy `StreakManager.streak(for:)`.
    public func streak(where condition: (DailySummary) -> Bool) -> Int {
        var count = 0
        var cursor = today
        if let summary = summaries[today], condition(summary) {
            count = 1
        }
        cursor = cursor.adding(days: -1)
        while let summary = summaries[cursor], condition(summary) {
            count += 1
            cursor = cursor.adding(days: -1)
        }
        return count
    }

    public var calorieStreak: Int { streak { $0.hitCalorieGoal } }
    public var waterStreak: Int { streak { $0.hitWaterGoal } }
    public var gymStreak: Int { streak { $0.hitGymGoal } }
    public var todoStreak: Int { streak { $0.hitTodoGoal } }
    public var perfectDayStreak: Int { streak { $0.isPerfectDay } }

    /// The last `days` days, oldest first, for the heatmap. `nil` = no data.
    public func lastDays(_ days: Int = 30) -> [DailySummary?] {
        guard days > 0 else { return [] }
        return (0..<days).reversed().map { summaries[today.adding(days: -$0)] }
    }
}
