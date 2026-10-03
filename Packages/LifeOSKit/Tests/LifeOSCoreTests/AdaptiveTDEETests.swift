import Foundation
import Testing
@testable import LifeOSCore

/// CAL-10/11: the trend and the three synthetic personas from doc 03 §5.
@Suite("Adaptive TDEE")
struct AdaptiveTDEETests {
    let today = DayKey(year: 2026, month: 10, day: 3)!

    private func entry(_ day: DayKey, _ kg: Double, hour: Int = 7) -> WeightEntry {
        WeightEntry(dayKey: day, measuredAt: day.startDate().addingTimeInterval(Double(hour) * 3600), kg: kg,
                    source: .manual)
    }

    /// `days` of history ending today. The true weight moves by
    /// `(trueTDEE − eaten) / 7700` a day; the user logs `logged` kcal and weighs
    /// on days where `weighs(offset)` is true, with `noise(offset)` kg of water.
    private func persona(trueTDEE: Double, eaten: Double, logged: Double, days: Int = 60,
                         weighs: (Int) -> Bool = { _ in true }, noise: (Int) -> Double = { _ in 0 })
        -> (intake: [DayKey: Double], weights: [WeightEntry]) {
        var intake: [DayKey: Double] = [:]
        var weights: [WeightEntry] = []
        var kg = 80.0
        for offset in 0..<days {
            let day = today.adding(days: offset - days + 1)
            intake[day] = logged
            if weighs(offset) { weights.append(entry(day, kg + noise(offset))) }
            kg -= (trueTDEE - eaten) / AdaptiveTDEE.kcalPerKg
        }
        return (intake, weights)
    }

    private func estimate(_ p: (intake: [DayKey: Double], weights: [WeightEntry]), formula: Double = 2200)
        -> TDEEEstimate {
        AdaptiveTDEE.estimate(intakeKcal: p.intake, budgetKcal: [:], weights: p.weights, formulaKcal: formula,
                              through: today)
    }

    // MARK: Trend weight

    @Test func trendSmoothsAndCarriesOverDaysWithoutAReading() {
        let d0 = today.adding(days: -2)
        let points = TrendWeight.series([entry(d0, 80), entry(today, 81)], from: d0, through: today)
        #expect(points.map(\.day) == [d0, d0.adding(days: 1), today])
        #expect(points[0].trendKg == 80)
        #expect(points[1].trendKg == 80)              // carried over
        #expect(points[1].rawKg == nil)
        // A 2-day gap applies 1 − 0.9² = 0.19 of the step.
        #expect(abs(points[2].trendKg - 80.19) < 1e-9)
    }

    @Test func trendUsesTheLatestReadingOfADayAndWarmsUpBeforeTheRange() {
        let d0 = today.adding(days: -10)
        let points = TrendWeight.series([entry(d0, 70), entry(today, 90, hour: 6), entry(today, 80, hour: 21)],
                                        from: today, through: today)
        #expect(points.count == 1)                    // only the requested range
        #expect(points[0].rawKg == 80)                // the evening reading wins
        #expect(abs(points[0].trendKg - (70 + (1 - pow(0.9, 10)) * 10)) < 1e-9)
    }

    @Test func trendIsEmptyWithoutReadings() {
        #expect(TrendWeight.series([], from: today, through: today).isEmpty)
        #expect(TrendWeight.series([entry(today.adding(days: 1), 80)], from: today, through: today).isEmpty)
    }

    // MARK: Personas

    @Test func accurateLoggerRecoversTheTrueExpenditure() {
        let result = estimate(persona(trueTDEE: 2400, eaten: 1900, logged: 1900))
        #expect(result.status == .ok)
        #expect(abs(result.observedKcal! - 2400) < 25)
        #expect(result.trendDeltaKg! < 0)
        #expect(result.weight == AdaptiveTDEE.maxWeight)   // every day logged and weighed
        #expect(abs(result.blendedKcal - (0.8 * result.observedKcal! + 0.2 * 2200)) < 1e-6)
        #expect(abs(result.differenceKcal! - 200) < 25)
    }

    /// Eats 1,900 but logs 1,500: the estimate reads ~400 low. That's the known
    /// limit of the method, and why CAL-12 rate-limits and announces changes.
    @Test func underLoggerReadsLowByTheUnloggedAmount() {
        let result = estimate(persona(trueTDEE: 2400, eaten: 1900, logged: 1500))
        #expect(result.status == .ok)
        #expect(abs(result.observedKcal! - 2000) < 25)
    }

    @Test func waterNoiseIsSmoothedAway() {
        let noisy = persona(trueTDEE: 2400, eaten: 1900, logged: 1900, noise: { $0 % 2 == 0 ? 1.0 : -1.0 })
        let result = estimate(noisy)
        #expect(result.status == .ok)
        #expect(abs(result.observedKcal! - 2400) < 100)
    }

    @Test func sparseWeighInsLowerTheBlendWeight() {
        let result = estimate(persona(trueTDEE: 2400, eaten: 1900, logged: 1900, weighs: { $0 % 3 == 0 }))
        #expect(result.status == .ok)
        #expect(result.weight < AdaptiveTDEE.maxWeight)
        #expect(result.weight > 0.5)
    }

    // MARK: Guardrails

    @Test func needsFourteenQualifyingDaysAndEightyPercentCoverage() {
        var p = persona(trueTDEE: 2400, eaten: 1900, logged: 1900)
        for offset in 0..<7 { p.intake[today.adding(days: -offset)] = nil }       // 21 of 28 = 75%
        let result = estimate(p)
        #expect(result.status == .notEnoughLoggedDays)
        #expect(result.observedKcal == nil)
        #expect(result.blendedKcal == 2200)
        #expect(result.weight == 0)
    }

    @Test func daysUnderSixtyPercentOfTheBudgetDontQualify() {
        let p = persona(trueTDEE: 2400, eaten: 1900, logged: 1000)                // 1,000 < 0.6 × 2,200
        #expect(estimate(p).status == .notEnoughLoggedDays)
        let budgets = Dictionary(uniqueKeysWithValues: p.intake.keys.map { ($0, 1500.0) })
        let withBudgets = AdaptiveTDEE.estimate(intakeKcal: p.intake, budgetKcal: budgets, weights: p.weights,
                                                formulaKcal: 2200, through: today)
        #expect(withBudgets.status != .notEnoughLoggedDays)                       // 1,000 ≥ 0.6 × 1,500
    }

    @Test func needsEightWeighInsOverTwoWeeks() {
        let few = persona(trueTDEE: 2400, eaten: 1900, logged: 1900, weighs: { $0 >= 53 })     // last 7 days
        #expect(estimate(few).status == .notEnoughWeighIns)
        let bunched = persona(trueTDEE: 2400, eaten: 1900, logged: 1900, weighs: { $0 >= 50 })  // 10 in 10 days
        #expect(estimate(bunched).status == .tooFewDays)
    }

    @Test func implausibleFiguresAreRejected() {
        // Logged 1,900 while weight climbs ~0.5 kg a day: observed ≈ −1,600 kcal.
        var p = persona(trueTDEE: 2400, eaten: 1900, logged: 1900)
        p.weights = p.weights.enumerated().map { i, e in entry(e.dayKey, 70 + Double(i) * 0.5) }
        let result = estimate(p)
        #expect(result.status == .implausible)
        #expect(result.observedKcal == nil)
        #expect(result.blendedKcal == 2200)
    }

    @Test func windowIsClampedToTwentyOneToTwentyEightDays() {
        let p = persona(trueTDEE: 2400, eaten: 1900, logged: 1900)
        #expect(AdaptiveTDEE.estimate(intakeKcal: p.intake, budgetKcal: [:], weights: p.weights, formulaKcal: 2200,
                                      through: today, windowDays: 90).windowDays == 28)
        #expect(AdaptiveTDEE.estimate(intakeKcal: p.intake, budgetKcal: [:], weights: p.weights, formulaKcal: 2200,
                                      through: today, windowDays: 7).windowDays == 21)
    }
}
