import Foundation

/// Daily calorie target from a `UserProfile`: Mifflin-St Jeor BMR, scaled by
/// activity level (TDEE), plus an adjustment toward the target weight.
///
/// Moved unchanged from the app target. Known issue C4 (activity factor *and*
/// exercise calories both count training) is fixed by the calorie engine in P1
/// (doc 03), not here. P0 is behaviour-neutral.
public enum CalorieGoalCalculator {
    /// Basal Metabolic Rate (kcal/day) via Mifflin-St Jeor.
    public static func bmr(profile: UserProfile) -> Double {
        let base = (10.0 * profile.currentWeightKg)
            + (6.25 * profile.heightCm)
            - (5.0 * Double(profile.age))

        switch profile.sex {
        case .male: return base + 5.0
        case .female: return base - 161.0
        case .other: return base - 78.0 // average of the male/female offsets
        }
    }

    /// Total Daily Energy Expenditure (kcal/day).
    public static func tdee(profile: UserProfile) -> Double {
        bmr(profile: profile) * profile.activityFactor
    }

    /// Energy in 1 kg of body mass.
    static let kcalPerKg = 7700.0
    /// Weeks over which the current→target gap is spread.
    static let horizonWeeks = 10.0
    /// Never advise faster than 0.75 kg/week loss or 0.35 kg/week gain.
    static let maxWeeklyLoss = 0.75
    static let maxWeeklyGain = 0.35
    /// Gaps under this (kg) count as maintenance.
    static let maintenanceBand = 0.3

    /// Desired weekly change (kg, negative = loss), clamped to safe rates.
    public static func targetWeeklyChangeKg(profile: UserProfile) -> Double {
        let gap = profile.targetWeightKg - profile.currentWeightKg
        guard abs(gap) >= maintenanceBand else { return 0 }
        let weekly = gap / horizonWeeks
        return min(max(weekly, -maxWeeklyLoss), maxWeeklyGain)
    }

    /// Daily adjustment (kcal) on top of TDEE. Negative = deficit.
    public static func weightGoalAdjustment(profile: UserProfile) -> Double {
        (targetWeeklyChangeKg(profile: profile) * kcalPerKg / 7.0).rounded()
    }

    /// Recommended daily limit, floored at 1,200 (female) / 1,500 kcal.
    public static func dailyCalorieGoal(profile: UserProfile) -> Double {
        let adjusted = tdee(profile: profile) + weightGoalAdjustment(profile: profile)
        let floor = profile.sex == .female ? 1200.0 : 1500.0
        return max(adjusted, floor).rounded()
    }

    /// Macro grams for a 30% protein / 40% carbs / 30% fat split.
    public static func macroTargets(forCalories calories: Double) -> (protein: Double, carbs: Double, fat: Double) {
        let protein = (calories * 0.30) / 4.0
        let carbs = (calories * 0.40) / 4.0
        let fat = (calories * 0.30) / 9.0
        return (protein.rounded(), carbs.rounded(), fat.rounded())
    }

    /// Human-readable derivation of the target, shown in the UI.
    public static func explanation(profile: UserProfile) -> String {
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
