import Foundation
import Testing
@testable import LifeOSCore

/// Doc 03 §3.1 golden values. Male, 25 y, 170 cm, 72.5 → 68 kg, 3 training days:
/// BMR 1667.5, goal −495, TDEE 2584.625, auto target 2090.
@Suite("CalorieEngine")
struct CalorieEngineTests {
    let male = UserProfile(age: 25, heightCm: 170, currentWeightKg: 72.5, targetWeightKg: 68, sex: .male,
                           exerciseDaysPerWeek: 3)

    private func run(_ mode: BudgetMode, active: Double? = nil, estimated: Double = 0, eatBack: Double = 0.5,
                     allowance: Double? = nil, cap: Double = 1000, manual: Double? = nil,
                     profile: UserProfile? = nil) -> BudgetBreakdown {
        CalorieEngine.budget(for: EnergyInputs(profile: profile ?? male, mode: mode, activeKcal: active,
                                               estimatedSessionKcal: estimated, allowanceOverride: allowance,
                                               eatBack: eatBack, cap: cap, manualTarget: manual))
    }

    @Test func measuredCreditsActiveAboveAllowance() {
        let b = run(.measured, active: 800)
        #expect(b.baseline == 1506)            // 1667.5 × 1.2 − 495
        #expect(b.allowance == 333.5)          // BMR × 0.2
        #expect(b.credit == 233.25)            // (800 − 333.5) × 50%
        #expect(b.budget == 1739.25)
        #expect(!b.floorApplied)
        #expect(b.lines.map(\.kind) == [.bmr, .everydayActivity, .goal, .exerciseCredit])
    }

    @Test func measuredIsCappedAndClampsAllowance() {
        #expect(run(.measured, active: 2000).credit == 500)                     // min(1666.5, 1000) × 50%
        #expect(run(.measured, active: 900, allowance: 1000).allowance == 583.625) // ≤ BMR × 0.35
        #expect(run(.measured, active: 900, allowance: 10).allowance == 166.75)    // ≥ BMR × 0.10
        #expect(run(.measured, active: 200).credit == 0)                         // below allowance
        #expect(run(.measured, active: nil).credit == 0)                         // no Watch data today
    }

    @Test(arguments: [(0.0, 0.0), (0.5, 150.0), (1.0, 300.0), (1.7, 300.0), (-1, 0.0)])
    func estimatedEatBack(eatBack: Double, credit: Double) {
        #expect(run(.estimated, estimated: 300, eatBack: eatBack).credit == credit)
    }

    @Test func floorTopsUpAndIsExplained() {
        let small = UserProfile(age: 60, heightCm: 150, currentWeightKg: 45, targetWeightKg: 40, sex: .female,
                                exerciseDaysPerWeek: 0)
        let b = run(.estimated, profile: small)
        #expect(b.budget == 1200)
        #expect(b.floorApplied)
        #expect(abs(b.lines.reduce(0) { $0 + $1.kcal } - b.budget) < 1e-9)
    }

    /// P1-D1: exercise credit is added on top of the floor, so workouts still
    /// raise the budget when an aggressive goal puts the baseline under it.
    @Test func creditStacksOnTopOfTheFloor() {
        let cutting = UserProfile(age: 22, heightCm: 167, currentWeightKg: 69.5, targetWeightKg: 58.5, sex: .male)
        let rest = run(.measured, active: 77, profile: cutting)
        #expect(rest.budget == 1500)
        let workout = run(.measured, active: 876, profile: cutting)
        #expect(workout.credit == (876 - 326.75) * 0.5)
        #expect(workout.budget == 1500 + workout.credit)
        #expect(workout.lines.map(\.kind) == [.bmr, .everydayActivity, .goal, .floorTopUp, .exerciseCredit])
        #expect(abs(workout.lines.reduce(0) { $0 + $1.kcal } - workout.budget) < 1e-9)
    }

    @Test func fixedUsesActivityFactorTDEEOrManual() {
        let auto = run(.fixed, estimated: 500)
        #expect(auto.budget == 2090)
        #expect(auto.credit == 0)
        #expect(auto.activityMultiplier == 1.55)
        #expect(run(.fixed, manual: 1000).budget == 1000) // a manual target is respected as-is
    }

    @Test func classicMatchesTodaysAppFormula() {
        // HomeViewModel.adjustedCalorieLimit = CalorieLimitSettings.loadLimit() + burned × eat-back
        let b = run(.classic, estimated: 300, eatBack: 0.5, manual: 2090)
        #expect(b.budget == 2090 + 300 * 0.5)
        #expect(run(.classic, estimated: 3000, manual: 2200).budget == 3700) // uncapped, as today
        #expect(run(.classic, estimated: 300).budget == 2240)                // auto target when no stored limit
    }

    @Test(arguments: [BudgetMode.measured, .estimated, .fixed, .classic])
    func waterfallAddsUpToBudget(mode: BudgetMode) {
        for active in [0.0, 450, 1600] {
            let b = run(mode, active: active, estimated: active)
            #expect(abs(b.lines.reduce(0) { $0 + $1.kcal } - b.budget) <= 0.5)
            #expect(b.formulaVersion == 2)
        }
    }
}
