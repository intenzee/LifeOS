import Foundation

/// Snapshot of one day's performance, used for streaks and the 30-day heatmap.
///
/// It is **derived** data: `SummaryService` (LifeOSData) recomputes it, and views
/// never write it. The JSON shape matches the legacy `DailySummary` stored under
/// the `dailySummaries` key, so migrated history decodes unchanged.
public struct DailySummary: Codable, Sendable, Equatable {
    /// `yyyy-MM-dd`.
    public var date: String
    public var caloriesConsumed: Double
    public var calorieLimit: Double
    public var waterGlasses: Int
    public var waterTarget: Int
    /// "High", "Medium", "Low" or "Rest" (see `WorkoutIntensity`).
    public var gymIntensity: String
    public var todosCompleted: Int
    public var todosTotal: Int

    public init(date: String, caloriesConsumed: Double, calorieLimit: Double, waterGlasses: Int,
                waterTarget: Int, gymIntensity: String, todosCompleted: Int, todosTotal: Int) {
        self.date = date
        self.caloriesConsumed = caloriesConsumed
        self.calorieLimit = calorieLimit
        self.waterGlasses = waterGlasses
        self.waterTarget = waterTarget
        self.gymIntensity = gymIntensity
        self.todosCompleted = todosCompleted
        self.todosTotal = todosTotal
    }

    public var hitCalorieGoal: Bool { caloriesConsumed > 0 && caloriesConsumed <= calorieLimit }
    public var hitWaterGoal: Bool { waterGlasses >= waterTarget }
    public var hitGymGoal: Bool { gymIntensity == WorkoutIntensity.high.rawValue || gymIntensity == WorkoutIntensity.medium.rawValue }
    public var hitTodoGoal: Bool { todosTotal > 0 && todosCompleted >= todosTotal }
    public var isPerfectDay: Bool { hitCalorieGoal && hitWaterGoal && hitGymGoal && hitTodoGoal }
    public var score: Int {
        [hitCalorieGoal, hitWaterGoal, hitGymGoal, hitTodoGoal].filter { $0 }.count
    }
}

extension DailySummary: DayRecord {
    public static let collection = "dailySummaries"

    public var id: String { date }

    /// Falls back to a far-past key for a malformed legacy date, so one bad
    /// record can't crash the store. The migrator drops such records first.
    public var dayKey: DayKey { DayKey(date) ?? .epoch }
}
