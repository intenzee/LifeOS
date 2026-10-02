import Foundation
import Testing
@testable import LifeOSCore

private func summary(_ date: String, calories: Double = 1800, limit: Double = 2000, water: Int = 8,
                     gym: String = "High", done: Int = 3, total: Int = 3) -> DailySummary {
    DailySummary(date: date, caloriesConsumed: calories, calorieLimit: limit, waterGlasses: water,
                 waterTarget: 8, gymIntensity: gym, todosCompleted: done, todosTotal: total)
}

@Suite("Streaks")
struct StreakCalculatorTests {
    let today = DayKey("2026-10-03")!

    @Test func goalFlags() {
        #expect(summary("2026-10-03").isPerfectDay)
        #expect(summary("2026-10-03").score == 4)
        #expect(!summary("2026-10-03", calories: 0).hitCalorieGoal) // nothing logged isn't a win
        #expect(!summary("2026-10-03", calories: 2001).hitCalorieGoal)
        #expect(summary("2026-10-03", gym: "Medium").hitGymGoal)
        #expect(!summary("2026-10-03", gym: "Low").hitGymGoal)
        #expect(!summary("2026-10-03", done: 0, total: 0).hitTodoGoal)
    }

    @Test func countsBackFromTodayWhenTodayQualifies() {
        let calc = StreakCalculator(summaries: [
            summary("2026-10-03"), summary("2026-10-02"), summary("2026-10-01"),
            summary("2026-09-29") // gap on 09-30
        ], today: today)
        #expect(calc.perfectDayStreak == 3)
    }

    @Test func unfinishedTodayDoesNotBreakStreak() {
        let calc = StreakCalculator(summaries: [
            summary("2026-10-03", water: 2), summary("2026-10-02"), summary("2026-10-01")
        ], today: today)
        #expect(calc.waterStreak == 2)
        #expect(calc.calorieStreak == 3)
    }

    @Test func missingYesterdayEndsStreak() {
        let calc = StreakCalculator(summaries: [summary("2026-10-01")], today: today)
        #expect(calc.perfectDayStreak == 0)
    }

    @Test func streakCrossesMonthAndYear() {
        let summaries = DayKey.range(from: DayKey("2025-12-20")!, through: DayKey("2026-01-02")!)
            .map { summary($0.rawValue) }
        let calc = StreakCalculator(summaries: summaries, today: DayKey("2026-01-02")!)
        #expect(calc.gymStreak == 14)
    }

    @Test func heatmapIsOldestFirst() {
        let calc = StreakCalculator(summaries: [summary("2026-10-03"), summary("2026-09-04")], today: today)
        let days = calc.lastDays(30)
        #expect(days.count == 30)
        #expect(days.first??.date == "2026-09-04")
        #expect(days.last??.date == "2026-10-03")
        #expect(days.compactMap { $0 }.count == 2)
    }

    @Test func legacySummaryJSONDecodes() throws {
        let json = """
        {"date":"2026-10-01","caloriesConsumed":1500,"calorieLimit":2000,"waterGlasses":8,"waterTarget":8,
         "gymIntensity":"High","todosCompleted":1,"todosTotal":1}
        """
        let decoded = try JSONDecoder().decode(DailySummary.self, from: Data(json.utf8))
        #expect(decoded.isPerfectDay)
        #expect(decoded.dayKey.rawValue == "2026-10-01")
    }
}

@Suite("Support")
struct SupportTests {
    @Test func featureFlagResolutionOrder() {
        let flags = FeatureFlags()
        #expect(!flags.isEnabled(.healthKitIngestion))
        flags.applyRemote(["healthkit_ingestion": true, "unknown_future_flag": true])
        #expect(flags.isEnabled(.healthKitIngestion))
        flags.setLocalOverride(.healthKitIngestion, false)
        #expect(!flags.isEnabled(.healthKitIngestion))
        flags.setLocalOverride(.healthKitIngestion, nil)
        #expect(flags.isEnabled(.healthKitIngestion))
    }

    @Test func typedWatchContractIsOnByDefault() {
        #expect(FeatureFlags().isEnabled(.typedWatchContract))
    }

    @Test func estimatedEnergyWriteIsOffByDefault() {
        // FND-07: writing MET estimates to Apple Health double-counts Activity rings.
        #expect(!FeatureFlags().isEnabled(.healthKitEstimatedEnergyWrite))
    }

    @Test func appErrorCarriesUserMessage() {
        let error = AppError.storageWrite(StringError("disk full"))
        #expect(error.code == .storageWrite)
        #expect(error.category == .data)
        #expect(error.errorDescription == "Your change couldn't be saved.")
        #expect(error.underlying == "disk full")
    }

    @Test func foodLibraryRules() {
        var library = FoodLibrary()
        for index in 0..<25 {
            library.noteRecent(FoodTemplate(name: "Food \(index)", calories: 100, defaultMeal: .lunch))
        }
        #expect(library.recent.count == FoodLibrary.recentLimit)
        #expect(library.recent.first?.name == "Food 24")
        library.noteRecent(FoodTemplate(name: "Food 10", calories: 90, defaultMeal: .lunch))
        #expect(library.recent.first?.calories == 90)
        #expect(library.recent.filter { $0.name == "Food 10" }.count == 1)

        library.upsertCustom(FoodTemplate(name: "Bar", calories: 200, barcode: "123", defaultMeal: .snacks))
        library.upsertCustom(FoodTemplate(name: "Protein bar", calories: 210, barcode: "123", defaultMeal: .snacks))
        #expect(library.custom.map(\.name) == ["Protein bar"])

        let apple = FoodTemplate(name: "Apple", calories: 95, defaultMeal: .snacks)
        library.toggleFavorite(apple)
        #expect(library.favorites == [apple])
        library.toggleFavorite(apple)
        #expect(library.favorites.isEmpty)
    }

    @Test func nutritionTotals() {
        let day = DayKey("2026-10-03")!
        let totals = NutritionTotals([
            FoodEntry(dayKey: day, loggedAt: Date(), meal: .lunch, name: "A", calories: 100, proteinG: 10, carbsG: 5, fatG: 1, source: .manual),
            FoodEntry(dayKey: day, loggedAt: Date(), meal: .dinner, name: "B", calories: 250, proteinG: 5, carbsG: 30, fatG: 9, source: .manual)
        ])
        #expect(totals.calories == 350 && totals.proteinG == 15 && totals.carbsG == 35 && totals.fatG == 10)
    }
}
