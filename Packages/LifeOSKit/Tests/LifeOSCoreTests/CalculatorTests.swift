import Foundation
import Testing
@testable import LifeOSCore

// Golden values worked out by hand from the formulas, so the move out of the
// app target is provably behaviour-neutral (QA-02).

@Suite("CalorieGoalCalculator")
struct CalorieGoalCalculatorTests {
    @Test func maleLosingWeight() {
        let profile = UserProfile(age: 25, heightCm: 170, currentWeightKg: 72.5, targetWeightKg: 68,
                                  sex: .male, exerciseDaysPerWeek: 3)
        #expect(CalorieGoalCalculator.bmr(profile: profile) == 1667.5)
        #expect(abs(CalorieGoalCalculator.tdee(profile: profile) - 2584.625) < 1e-9)
        #expect(abs(CalorieGoalCalculator.targetWeeklyChangeKg(profile: profile) - -0.45) < 1e-9)
        #expect(CalorieGoalCalculator.weightGoalAdjustment(profile: profile) == -495)
        #expect(CalorieGoalCalculator.dailyCalorieGoal(profile: profile) == 2090)
        #expect(CalorieGoalCalculator.explanation(profile: profile) == "TDEE 2585 − 495 for ~0.45 kg/week loss toward 68.0 kg.")
    }

    @Test func femaleMaintenanceSedentary() {
        let profile = UserProfile(age: 30, heightCm: 165, currentWeightKg: 60, targetWeightKg: 60.2,
                                  sex: .female, exerciseDaysPerWeek: 0)
        #expect(CalorieGoalCalculator.bmr(profile: profile) == 1320.25)
        #expect(CalorieGoalCalculator.weightGoalAdjustment(profile: profile) == 0) // inside the 0.3 kg band
        #expect(CalorieGoalCalculator.dailyCalorieGoal(profile: profile) == 1584)
        #expect(CalorieGoalCalculator.explanation(profile: profile).hasPrefix("Maintenance: 1584 kcal"))
    }

    @Test func safetyFloorsApply() {
        let female = UserProfile(age: 60, heightCm: 150, currentWeightKg: 40, targetWeightKg: 35,
                                 sex: .female, exerciseDaysPerWeek: 0)
        #expect(CalorieGoalCalculator.dailyCalorieGoal(profile: female) == 1200)
        var male = female
        male.sex = .male
        #expect(CalorieGoalCalculator.dailyCalorieGoal(profile: male) == 1500)
    }

    @Test func weeklyRateIsClamped() {
        let bigLoss = UserProfile(currentWeightKg: 120, targetWeightKg: 70)
        #expect(CalorieGoalCalculator.targetWeeklyChangeKg(profile: bigLoss) == -0.75)
        let bigGain = UserProfile(currentWeightKg: 50, targetWeightKg: 70)
        #expect(CalorieGoalCalculator.targetWeeklyChangeKg(profile: bigGain) == 0.35)
        #expect(CalorieGoalCalculator.weightGoalAdjustment(profile: bigGain) == 385)
    }

    @Test func otherSexUsesAverageOffset() {
        let profile = UserProfile(age: 25, heightCm: 170, currentWeightKg: 72.5, sex: .other)
        #expect(CalorieGoalCalculator.bmr(profile: profile) == 1662.5 - 78)
    }

    @Test(arguments: [(0, 1.2), (1, 1.375), (2, 1.375), (3, 1.55), (4, 1.55), (5, 1.725), (6, 1.725), (7, 1.9)])
    func activityFactor(days: Int, factor: Double) {
        #expect(UserProfile(exerciseDaysPerWeek: days).activityFactor == factor)
    }

    @Test func macroSplit() {
        let macros = CalorieGoalCalculator.macroTargets(forCalories: 2000)
        #expect(macros.protein == 150)
        #expect(macros.carbs == 200)
        #expect(macros.fat == 67)
    }

    @Test func profileJSONIsBackwardCompatible() throws {
        // Shape written by the pre-P0 app (Date = seconds since 2001).
        let json = """
        {"age":31,"heightCm":180,"currentWeightKg":80,"targetWeightKg":75,"sex":"Male","goal":"Lose Weight",
         "exerciseDaysPerWeek":4,"smokes":false,"diet":"High Protein","units":"Metric","waterGoalGlasses":10,
         "wakeTime":0,"sleepTime":0,"completedAt":0}
        """
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
        #expect(profile.goal == .loseWeight && profile.diet == .highProtein && profile.waterGoalGlasses == 10)
    }
}

@Suite("Workout energy estimate")
struct CalorieCalculatorTests {
    @Test func perSetAndTreadmill() {
        #expect(abs(CalorieCalculator.caloriesPerSet(bodyPart: .chest, weightKg: 70) - 18.375) < 1e-9)
        #expect(abs(CalorieCalculator.treadmillCalories(weightKg: 70, durationMinutes: 20) - 208.25) < 1e-9)
    }

    @Test func dayTotalAndIntensity() {
        let day = DayKey("2026-10-03")!
        var workout = WorkoutDay(dayKey: day, exercises: [
            Exercise(bodyPart: .chest, setsCompleted: 3),
            Exercise(bodyPart: .legs, setsCompleted: 4, maxSets: 4)
        ])
        // chest 3 × 18.375 + legs 4 × 19.90625
        #expect(abs(CalorieCalculator.totalWorkoutCalories(workout: workout, weightKg: 70) - 134.75) < 1e-9)
        #expect(WorkoutIntensity(workout: workout, weightKg: 70) == .low)
        workout.treadmillDone = true
        #expect(WorkoutIntensity(workout: workout, weightKg: 70) == .medium) // 343
    }

    @Test(arguments: [(0.0, WorkoutIntensity.rest), (119.9, .rest), (120, .low), (299.9, .low),
                      (300, .medium), (449.9, .medium), (450, .high), (1000, .high)])
    func intensityThresholds(calories: Double, expected: WorkoutIntensity) {
        #expect(WorkoutIntensity(estimatedCalories: calories) == expected)
    }

    @Test func exerciseDisplayName() {
        #expect(Exercise(bodyPart: .back).displayName == "Back")
        #expect(Exercise(bodyPart: .back, name: "  ").displayName == "Back")
        #expect(Exercise(bodyPart: .back, name: "Deadlift").displayName == "Deadlift")
        #expect(ExerciseCatalog.movements(for: .legs).contains("Squat"))
    }
}
