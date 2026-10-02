import Foundation

/// Computes a daily calorie target from a `UserProfile` using the
/// Mifflin-St Jeor equation for BMR, scaled by activity level (TDEE) and
/// adjusted for the user's fitness goal.
enum CalorieGoalCalculator {
    /// Basal Metabolic Rate (kcal/day) via Mifflin-St Jeor.
    static func bmr(profile: UserProfile) -> Double {
        let base = (10.0 * profile.currentWeightKg)
            + (6.25 * profile.heightCm)
            - (5.0 * Double(profile.age))

        switch profile.sex {
        case .male:
            return base + 5.0
        case .female:
            return base - 161.0
        case .other:
            // Average of the male/female offsets when unspecified.
            return base - 78.0
        }
    }

    /// Total Daily Energy Expenditure (kcal/day).
    static func tdee(profile: UserProfile) -> Double {
        bmr(profile: profile) * profile.activityFactor
    }

    // MARK: - Weight-goal driven adjustment

    /// Energy in 1 kg of body mass (≈7,700 kcal), used to translate a desired
    /// weekly weight change into a daily calorie deficit/surplus.
    private static let kcalPerKg = 7700.0
    /// Horizon (weeks) over which the current→target gap is spread. A longer
    /// horizon means gentler daily adjustments.
    private static let horizonWeeks = 10.0
    /// Safety caps on weekly change: never advise faster than 0.75 kg/week loss
    /// or 0.35 kg/week gain (evidence-based sustainable rates).
    private static let maxWeeklyLoss = 0.75
    private static let maxWeeklyGain = 0.35
    /// Gaps under this (kg) are treated as maintenance.
    private static let maintenanceBand = 0.3

    /// Desired weekly weight change (kg, negative = loss) derived from the gap
    /// between current and target weight, clamped to safe rates.
    static func targetWeeklyChangeKg(profile: UserProfile) -> Double {
        let gap = profile.targetWeightKg - profile.currentWeightKg // negative = need to lose
        guard abs(gap) >= maintenanceBand else { return 0 }
        let weekly = gap / horizonWeeks
        return min(max(weekly, -maxWeeklyLoss), maxWeeklyGain)
    }

    /// Daily calorie adjustment (kcal) applied on top of TDEE so the user tracks
    /// toward their target weight at a safe rate. Negative = deficit.
    static func weightGoalAdjustment(profile: UserProfile) -> Double {
        (targetWeeklyChangeKg(profile: profile) * kcalPerKg / 7.0).rounded()
    }

    /// Recommended daily calorie limit.
    ///
    /// Built from TDEE plus an adjustment derived from the current→target weight
    /// gap (so *changing either weight* moves the target predictably), floored to
    /// a safe minimum to avoid unrealistic goals.
    static func dailyCalorieGoal(profile: UserProfile) -> Double {
        let adjusted = tdee(profile: profile) + weightGoalAdjustment(profile: profile)
        let floor = profile.sex == .female ? 1200.0 : 1500.0
        return max(adjusted, floor).rounded()
    }

    /// Macro targets (grams/day) for a calorie goal using a 30% protein /
    /// 40% carbohydrate / 30% fat split (4 kcal/g protein & carbs, 9 kcal/g fat).
    static func macroTargets(forCalories calories: Double) -> (protein: Double, carbs: Double, fat: Double) {
        let protein = (calories * 0.30) / 4.0
        let carbs = (calories * 0.40) / 4.0
        let fat = (calories * 0.30) / 9.0
        return (protein.rounded(), carbs.rounded(), fat.rounded())
    }

    /// Human-readable explanation of how the daily target was derived, for display
    /// in the UI so the number never looks arbitrary.
    static func explanation(profile: UserProfile) -> String {
        let tdeeValue = Int(tdee(profile: profile).rounded())
        let adjustment = Int(weightGoalAdjustment(profile: profile))
        let weekly = targetWeeklyChangeKg(profile: profile)
        let target = String(format: "%.1f", profile.targetWeightKg)

        if adjustment == 0 {
            return "Maintenance: \(tdeeValue) kcal to hold \(String(format: "%.1f", profile.currentWeightKg)) kg."
        }
        let rate = String(format: "%.2f", abs(weekly))
        if adjustment < 0 {
            return "TDEE \(tdeeValue) − \(abs(adjustment)) for ~\(rate) kg/week loss toward \(target) kg."
        }
        return "TDEE \(tdeeValue) + \(adjustment) for ~\(rate) kg/week gain toward \(target) kg."
    }
}
