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

    /// Recommended daily calorie limit after applying the goal adjustment.
    /// Floored to a safe minimum to avoid unrealistic targets.
    static func dailyCalorieGoal(profile: UserProfile) -> Double {
        let adjusted = tdee(profile: profile) + profile.goal.calorieAdjustment
        let floor = profile.sex == .female ? 1200.0 : 1500.0
        return max(adjusted, floor).rounded()
    }
}
