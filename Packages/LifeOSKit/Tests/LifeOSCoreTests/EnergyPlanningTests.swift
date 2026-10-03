import Foundation
import Testing
@testable import LifeOSCore

private let oct3 = DayKey("2026-10-03")!
private let tz = TimeZone(identifier: "Asia/Kolkata")!

private func at(_ day: DayKey, _ hour: Double) -> Date {
    day.startDate(timeZone: tz).addingTimeInterval(hour * 3600)
}

private func session(_ kind: ActivityKind, _ from: Double, _ to: Double, kcal: Double? = nil,
                     day: DayKey = oct3) -> WorkoutSession {
    WorkoutSession(dayKey: day, start: at(day, from), end: at(day, to), kind: kind, activeEnergyKcal: kcal,
                   source: .watch, healthKitUUID: UUID())
}

private func energy(_ day: DayKey, active: Double? = nil, watch: Double? = nil, workout: Bool = false) -> EnergyDay {
    EnergyDay(dayKey: day, activeKcal: active, watchActiveKcal: watch, hadWorkout: workout)
}

/// Doc 03 §6. These vectors must pass as written.
@Suite("Doc 03 test vectors")
struct Doc03VectorTests {
    let a = UserProfile(age: 30, heightCm: 180, currentWeightKg: 80, targetWeightKg: 75, sex: .male)

    private func budget(_ profile: UserProfile, _ mode: BudgetMode, active: Double? = nil, manual: Double? = nil) -> Double {
        CalorieEngine.budget(for: EnergyInputs(profile: profile, mode: mode, activeKcal: active, eatBack: 0.5,
                                               manualTarget: manual)).budget
    }

    @Test func personaA_measuredWorkoutDay() {
        let b = CalorieEngine.budget(for: EnergyInputs(profile: a, mode: .measured, activeKcal: 780))
        #expect(b.bmr == 1780)
        #expect(b.baseline == 2136 - 550)
        #expect(b.allowance == 356)
        #expect(b.credit == 212)
        #expect(b.budget == 1798)
    }

    @Test func personaB_restDay() { #expect(budget(a, .measured, active: 300) == 1586) }
    @Test func personaC_marathonIsCapped() { #expect(budget(a, .measured, active: 2600) == 2086) }

    @Test func personaD_femaleFloor() {
        let d = UserProfile(age: 60, heightCm: 150, currentWeightKg: 50, targetWeightKg: 45, sex: .female)
        #expect(budget(d, .measured, active: 100) == 1200)
    }

    @Test func personaE_fixedManual() {
        let b = CalorieEngine.budget(for: EnergyInputs(profile: a, mode: .fixed, activeKcal: 900, manualTarget: 2000))
        #expect(b.budget == 2000)
        #expect(b.credit == 0)
    }
}

@Suite("WorkoutMerge (WCH-06)")
struct WorkoutMergeTests {
    let ids = [UUID(), UUID()]

    @Test func overlapFractionUsesShorterInterval() {
        let long = DateInterval(start: at(oct3, 18), end: at(oct3, 20))
        let short = DateInterval(start: at(oct3, 19.5), end: at(oct3, 20.5))
        #expect(WorkoutMerge.overlapFraction(long, short) == 0.5)
        #expect(WorkoutMerge.overlapFraction(long, DateInterval(start: at(oct3, 21), end: at(oct3, 22))) == 0)
    }

    @Test func mergesIntoTheOnlyStrengthSessionWithoutSetTimes() {
        let sessions = [session(.strength, 18, 19, kcal: 300), session(.walk, 8, 8.5, kcal: 90)]
        let merged = WorkoutMerge.attach(manual: .init(dayKey: oct3, exerciseIDs: ids), to: sessions)
        #expect(merged[0].mergedExerciseIDs == ids)
        #expect(merged[1].mergedExerciseIDs.isEmpty)
    }

    @Test func twoCandidatesWithoutTimesMeansNoMerge() {
        let sessions = [session(.strength, 7, 8), session(.hiit, 18, 19)]
        let merged = WorkoutMerge.attach(manual: .init(dayKey: oct3, exerciseIDs: ids), to: sessions)
        #expect(merged.allSatisfy { $0.mergedExerciseIDs.isEmpty })
    }

    @Test func setTimesPickTheOverlappingSession() {
        let sessions = [session(.strength, 7, 8), session(.strength, 18, 19)]
        let window = DateInterval(start: at(oct3, 18.2), end: at(oct3, 18.9))
        let merged = WorkoutMerge.attach(manual: .init(dayKey: oct3, exerciseIDs: ids, window: window), to: sessions)
        #expect(merged[0].mergedExerciseIDs.isEmpty)
        #expect(merged[1].mergedExerciseIDs == ids)
    }

    @Test func setTimesWithNoOverlapMeansNoMerge() {
        let window = DateInterval(start: at(oct3, 12), end: at(oct3, 12.5))
        let merged = WorkoutMerge.attach(manual: .init(dayKey: oct3, exerciseIDs: ids, window: window),
                                         to: [session(.strength, 18, 19)])
        #expect(merged[0].mergedExerciseIDs.isEmpty)
    }

    @Test func runsNeverAbsorbAGymLog() {
        let merged = WorkoutMerge.attach(manual: .init(dayKey: oct3, exerciseIDs: ids), to: [session(.run, 6, 7)])
        #expect(merged[0].mergedExerciseIDs.isEmpty)
    }

    @Test func deletionUnmergesBecauseMergeIsRecomputed() {
        var sessions = WorkoutMerge.attach(manual: .init(dayKey: oct3, exerciseIDs: ids),
                                           to: [session(.strength, 18, 19)])
        #expect(!sessions[0].mergedExerciseIDs.isEmpty)
        sessions = WorkoutMerge.attach(manual: .init(dayKey: oct3, exerciseIDs: []), to: sessions)
        #expect(sessions[0].mergedExerciseIDs.isEmpty)
        #expect(WorkoutMerge.attach(manual: .init(dayKey: oct3, exerciseIDs: ids), to: []).isEmpty)
    }

    @Test func duplicateRecordingsCountOnce() {
        // The same run from Strava and the Workout app, plus a separate walk.
        let sessions = [session(.run, 7, 8, kcal: 400), session(.run, 7.05, 8, kcal: 380), session(.walk, 18, 19, kcal: 120)]
        #expect(WorkoutMerge.dedupedWorkoutEnergy(sessions) == 520)
    }

    @Test func measuredBeatsMETEstimate() {
        let merged = WorkoutMerge.attach(manual: .init(dayKey: oct3, exerciseIDs: ids), to: [session(.strength, 18, 19, kcal: 250)])
        #expect(WorkoutMerge.estimatedSessionKcal(sessions: merged, manualMETKcal: 180) == 250)
        #expect(WorkoutMerge.estimatedSessionKcal(sessions: [], manualMETKcal: 180) == 180)
        #expect(WorkoutMerge.estimatedSessionKcal(sessions: [session(.run, 6, 7, kcal: 300)], manualMETKcal: 180) == 480)
    }
}

@Suite("BudgetPlanner (CAL-02)")
struct BudgetPlannerTests {
    let profile = UserProfile(age: 30, heightCm: 180, currentWeightKg: 80, targetWeightKg: 75, sex: .male)

    @Test func measuredNeedsThreeWatchDaysInTheLastSeven() {
        let two = [energy(oct3, watch: 500), energy(oct3.adding(days: -3), watch: 300)]
        #expect(BudgetPlanner.mode(for: oct3, recent: two, settings: .init()) == .estimated)
        let three = two + [energy(oct3.adding(days: -6), watch: 200)]
        #expect(BudgetPlanner.mode(for: oct3, recent: three, settings: .init()) == .measured)
        // Outside the window doesn't count; iPhone-only energy doesn't count.
        let stale = two + [energy(oct3.adding(days: -7), watch: 200), energy(oct3.adding(days: -1), active: 400)]
        #expect(BudgetPlanner.mode(for: oct3, recent: stale, settings: .init()) == .estimated)
    }

    @Test func fixedPreferenceOrManualTargetWins() {
        let watchDays = (0..<7).map { energy(oct3.adding(days: -$0), watch: 400) }
        #expect(BudgetPlanner.mode(for: oct3, recent: watchDays, settings: .init(modePreference: .fixed)) == .fixed)
        #expect(BudgetPlanner.mode(for: oct3, recent: watchDays, settings: .init(manualTarget: 1900)) == .fixed)
    }

    @Test func plannerFeedsTheEngine() {
        let days = (0..<3).map { energy(oct3.adding(days: -$0), active: 780, watch: 700) }
        let b = BudgetPlanner.budget(for: days[0], recent: days, profile: profile, settings: .init())
        #expect(b.mode == .measured)
        #expect(b.budget == 1798)
        let estimated = EnergyDay(dayKey: oct3, estimatedSessionKcal: 300)
        #expect(BudgetPlanner.budget(for: estimated, recent: [], profile: profile, settings: .init()).budget == 1736)
    }

    @Test(arguments: [(0.04, 0.0), (0.46, 0.5), (0.55, 0.6), (1.4, 1.0), (-.infinity, 0.5)])
    func eatBackSnapsToTenPercentSteps(raw: Double, snapped: Double) {
        #expect(EnergySettings.snapEatBack(raw) == snapped)
    }
}

@Suite("AllowanceEstimator (CAL-04)")
struct AllowanceEstimatorTests {
    let profile = UserProfile(age: 30, heightCm: 180, currentWeightKg: 80, targetWeightKg: 75, sex: .male) // BMR 1780

    private func history(_ count: Int, restActive: [Double], workoutActive: Double = 900) -> [EnergyDay] {
        (1...count).map { offset in
            let day = oct3.adding(days: -offset)
            let restIndex = offset - 1
            if restIndex < restActive.count { return energy(day, active: restActive[restIndex]) }
            return energy(day, active: workoutActive, workout: true)
        }
    }

    @Test func needsFourteenDaysAndFiveRestDays() {
        #expect(AllowanceEstimator.allowance(today: oct3, days: history(13, restActive: [300, 300, 300, 300, 300]),
                                             profile: profile) == nil)
        #expect(AllowanceEstimator.allowance(today: oct3, days: history(20, restActive: [300, 300, 300, 300]),
                                             profile: profile) == nil)
    }

    @Test func medianOfRestDaysIgnoresWorkoutDaysAndToday() {
        var days = history(20, restActive: [250, 400, 300, 350, 500, 280])
        days.append(energy(oct3, active: 2000)) // today, excluded
        #expect(AllowanceEstimator.allowance(today: oct3, days: days, profile: profile) == 325) // (300 + 350) / 2
    }

    @Test func clampedToBMRRange() {
        #expect(AllowanceEstimator.allowance(today: oct3, days: history(20, restActive: Array(repeating: 50, count: 6)),
                                             profile: profile) == 178)  // BMR × 0.10
        #expect(AllowanceEstimator.allowance(today: oct3, days: history(20, restActive: Array(repeating: 900, count: 6)),
                                             profile: profile) == 623)  // BMR × 0.35
    }
}

@Suite("MacroTargets (CAL-06)")
struct MacroTargetTests {
    let profile = UserProfile(age: 30, heightCm: 180, currentWeightKg: 80, targetWeightKg: 75, sex: .male,
                              goal: .loseWeight)

    @Test func proteinAnchoredToBodyWeightAndConstant() {
        let low = MacroConfig.default.targets(budget: 1800, profile: profile)
        let high = MacroConfig.default.targets(budget: 2400, profile: profile)
        #expect(low.proteinG == 144)  // 1.8 g/kg × 80
        #expect(high.proteinG == 144)
        #expect(high.carbsG > low.carbsG)
        #expect(high.fatG > low.fatG)
    }

    @Test(arguments: DietType.allCases)
    func energyAddsUpForEveryDiet(diet: DietType) {
        var p = profile
        p.diet = diet
        let t = MacroConfig.default.targets(budget: 2000, profile: p)
        let kcal = t.proteinG * 4 + t.carbsG * 4 + t.fatG * 9
        #expect(abs(kcal - 2000) <= 10)
        #expect(t.fiberG == 28)
    }

    @Test func ketoIsLowCarbAndHighProteinAddsProtein() {
        var keto = profile
        keto.diet = .keto
        #expect(MacroConfig.default.targets(budget: 2000, profile: keto).carbsG < 30)
        var hp = profile
        hp.diet = .highProtein
        #expect(MacroConfig.default.targets(budget: 2000, profile: hp).proteinG == 176) // (1.8 + 0.4) × 80
    }

    @Test func proteinShareIsCappedOnLowBudgets() {
        let t = MacroConfig.default.targets(budget: 1200, profile: profile)
        #expect(t.proteinG == 120) // 40% of 1200 kcal / 4
        #expect(MacroConfig.default.targets(budget: .nan, profile: profile).proteinG == 0)
    }
}
