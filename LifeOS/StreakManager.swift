import SwiftUI
import Combine

// MARK: - Daily Summary (snapshot of one day's performance)
struct DailySummary: Codable {
    var date: String                // "yyyy-MM-dd"
    var caloriesConsumed: Double
    var calorieLimit: Double
    var waterGlasses: Int
    var waterTarget: Int
    var gymIntensity: String        // "High", "Medium", "Low", "Rest"
    var todosCompleted: Int
    var todosTotal: Int

    var hitCalorieGoal: Bool {
        caloriesConsumed > 0 && caloriesConsumed <= calorieLimit
    }
    var hitWaterGoal: Bool {
        waterGlasses >= waterTarget
    }
    var hitGymGoal: Bool {
        gymIntensity == "High" || gymIntensity == "Medium"
    }
    var hitTodoGoal: Bool {
        todosTotal > 0 && todosCompleted >= todosTotal
    }
    var isPerfectDay: Bool {
        hitCalorieGoal && hitWaterGoal && hitGymGoal && hitTodoGoal
    }
    var score: Int {
        [hitCalorieGoal, hitWaterGoal, hitGymGoal, hitTodoGoal].filter { $0 }.count
    }
}

// MARK: - Streak Manager
class StreakManager: ObservableObject {
    static let shared = StreakManager()

    @Published var summaries: [String: DailySummary] = [:]

    private let summariesKey = "dailySummaries"
    private let calendar = Calendar.current

    private init() {
        load()
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
        summaries[key] = summary
        save()
        objectWillChange.send()
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
    private func save() {
        if let encoded = try? JSONEncoder().encode(summaries) {
            UserDefaults.standard.set(encoded, forKey: summariesKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: summariesKey),
              let decoded = try? JSONDecoder().decode([String: DailySummary].self, from: data)
        else { return }
        summaries = decoded
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func dateKey(for date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}

