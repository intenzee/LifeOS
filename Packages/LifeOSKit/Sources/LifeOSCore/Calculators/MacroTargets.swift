import Foundation

/// Daily macro targets (CAL-06, doc 03 §3.4). Protein is anchored to body weight
/// and stays constant. The remaining energy is split by diet type and scales
/// with the day's budget.
public struct MacroTargets: Sendable, Equatable {
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var fiberG: Double
}

/// Macro configuration. The defaults are **engineering placeholders pending
/// nutrition-advisor sign-off** (doc 03 §7 Q2). Product changes them here or via
/// remote config, not in calling code.
public struct MacroConfig: Codable, Sendable, Equatable {
    /// Protein, grams per kg of current body weight, by goal.
    public var proteinGPerKg: [FitnessGoal: Double]
    /// Extra g/kg for the High Protein diet type.
    public var highProteinBonusGPerKg: Double
    /// Share of the **non-protein** energy that comes from carbs (the rest is fat).
    public var carbShareOfRemainder: [DietType: Double]
    /// Protein never takes more than this share of the budget (low budgets).
    public var maxProteinShare: Double
    public var fiberGPer1000Kcal: Double

    public static let kcalPerGramProtein = 4.0
    public static let kcalPerGramCarb = 4.0
    public static let kcalPerGramFat = 9.0

    public static let `default` = MacroConfig(
        proteinGPerKg: [.loseWeight: 1.8, .maintain: 1.4, .gainMuscle: 1.8, .improveFitness: 1.6],
        highProteinBonusGPerKg: 0.4,
        // Balanced ≈ today's 40% carbs / 30% fat of the total (4:3 of the remainder).
        carbShareOfRemainder: [.balanced: 0.57, .vegetarian: 0.6, .vegan: 0.62, .keto: 0.08,
                               .highProtein: 0.55, .other: 0.57],
        maxProteinShare: 0.4,
        fiberGPer1000Kcal: 14
    )

    public init(proteinGPerKg: [FitnessGoal: Double], highProteinBonusGPerKg: Double,
                carbShareOfRemainder: [DietType: Double], maxProteinShare: Double, fiberGPer1000Kcal: Double) {
        self.proteinGPerKg = proteinGPerKg
        self.highProteinBonusGPerKg = highProteinBonusGPerKg
        self.carbShareOfRemainder = carbShareOfRemainder
        self.maxProteinShare = maxProteinShare
        self.fiberGPer1000Kcal = fiberGPer1000Kcal
    }

    public func targets(budget: Double, profile: UserProfile) -> MacroTargets {
        let budget = max(budget.isFinite ? budget : 0, 0)
        var perKg = proteinGPerKg[profile.goal] ?? 1.6
        if profile.diet == .highProtein { perKg += highProteinBonusGPerKg }
        let byWeight = perKg * max(profile.currentWeightKg, 0)
        let protein = min(byWeight, budget * maxProteinShare / Self.kcalPerGramProtein)
        let remainder = max(budget - protein * Self.kcalPerGramProtein, 0)
        let carbShare = min(max(carbShareOfRemainder[profile.diet] ?? 0.57, 0), 1)
        return MacroTargets(proteinG: protein.rounded(),
                            carbsG: (remainder * carbShare / Self.kcalPerGramCarb).rounded(),
                            fatG: (remainder * (1 - carbShare) / Self.kcalPerGramFat).rounded(),
                            fiberG: (budget / 1000 * fiberGPer1000Kcal).rounded())
    }
}
