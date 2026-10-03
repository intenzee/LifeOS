import Foundation

/// How the day's calorie budget is derived (doc 03 §3.1).
public enum BudgetMode: Codable, Sendable, Equatable {
    /// Apple Watch active energy above the everyday allowance is credited (P1 default with a Watch).
    case measured
    /// No Watch data: the MET estimate of logged sessions is credited.
    case estimated
    /// No exercise credit. Uses the manual target, or TDEE + goal adjustment.
    case fixed
    /// Today's app formula, kept so the UI can explain current numbers before P1:
    /// the stored limit (activity-factor TDEE + goal, or manual) plus eat-back × the
    /// MET estimate. It double counts (C4) and has no cap, and is replaced by
    /// `.measured`/`.estimated` when CAL-02/03 land.
    case classic
}

public struct EnergyInputs: Sendable, Equatable {
    public var profile: UserProfile
    public var mode: BudgetMode
    /// HealthKit active energy for the day (all sources merged). Used by `.measured`.
    public var activeKcal: Double?
    /// MET estimate of LifeOS-logged sessions (`CalorieCalculator`).
    public var estimatedSessionKcal: Double
    /// Personalised non-workout active energy (CAL-04). Clamped to `[BMR×0.1, BMR×0.35]`.
    public var allowanceOverride: Double?
    /// Share of exercise credited back, 0…1 (`CalorieSettings`, default 0.5).
    public var eatBack: Double
    /// Max credit before eat-back, kcal.
    public var cap: Double
    /// A user-set target (`.fixed`) or the stored limit (`.classic`).
    public var manualTarget: Double?

    public init(profile: UserProfile, mode: BudgetMode, activeKcal: Double? = nil, estimatedSessionKcal: Double = 0,
                allowanceOverride: Double? = nil, eatBack: Double = 0.5, cap: Double = 1000, manualTarget: Double? = nil) {
        self.profile = profile
        self.mode = mode
        self.activeKcal = activeKcal
        self.estimatedSessionKcal = estimatedSessionKcal
        self.allowanceOverride = allowanceOverride
        self.eatBack = eatBack
        self.cap = cap
        self.manualTarget = manualTarget
    }
}

/// Every number behind the day's budget (CAL-07). It drives the "Why this number?"
/// waterfall (UI-14). `lines` add up to `budget` (within rounding).
public struct BudgetBreakdown: Sendable, Equatable {
    /// v2: floor before exercise credit (P1-D1, 3 Oct 2026).
    public static let formulaVersion = 2

    public var mode: BudgetMode
    public var bmr: Double
    /// Multiplier applied to BMR for the baseline (1.2 for measured/estimated).
    public var activityMultiplier: Double
    public var goalAdjustment: Double
    /// Baseline before exercise credit (including the manual target, if any).
    public var baseline: Double
    /// Active energy already covered by the baseline (measured mode only).
    public var allowance: Double
    /// Active energy considered for credit: Watch kcal (measured) or the MET estimate.
    public var rawActive: Double
    public var eatBack: Double
    public var credit: Double
    public var floor: Double
    public var budget: Double
    public var formulaVersion: Int
    public var lines: [Line]

    public var floorApplied: Bool { lines.contains { $0.kind == .floorTopUp } }

    public struct Line: Sendable, Equatable {
        public enum Kind: String, Sendable, CaseIterable {
            case bmr, everydayActivity, goal, manualTarget, exerciseCredit, floorTopUp
        }

        public var kind: Kind
        public var kcal: Double

        public init(_ kind: Kind, _ kcal: Double) {
            self.kind = kind
            self.kcal = kcal
        }
    }
}

/// The calorie budget formula (CAL-01). Pure and deterministic. The only place
/// budget maths may live once CAL-03 removes the copies in the app.
public enum CalorieEngine {
    public static let sedentaryMultiplier = 1.2
    public static let defaultAllowanceShare = 0.2
    public static let allowanceRange = 0.1...0.35

    public static func floor(for profile: UserProfile) -> Double {
        profile.sex == .female ? 1200 : 1500
    }

    public static func budget(for input: EnergyInputs) -> BudgetBreakdown {
        let profile = input.profile
        let bmr = CalorieGoalCalculator.bmr(profile: profile)
        let goal = CalorieGoalCalculator.weightGoalAdjustment(profile: profile)
        let floor = floor(for: profile)
        let eatBack = min(max(input.eatBack, 0), 1)
        let cap = max(input.cap, 0)

        var multiplier = sedentaryMultiplier
        var allowance = 0.0
        var rawActive = 0.0
        var credit = 0.0
        var lines: [BudgetBreakdown.Line] = []
        let baseline: Double

        switch input.mode {
        case .measured, .estimated:
            baseline = bmr * multiplier + goal
            lines = [.init(.bmr, bmr), .init(.everydayActivity, bmr * (multiplier - 1)), .init(.goal, goal)]
            if input.mode == .measured {
                let lower = bmr * allowanceRange.lowerBound, upper = bmr * allowanceRange.upperBound
                allowance = input.allowanceOverride.map { min(max($0, lower), upper) } ?? bmr * defaultAllowanceShare
                rawActive = max(input.activeKcal ?? 0, 0)
                credit = eatBack * min(max(rawActive - allowance, 0), cap)
            } else {
                rawActive = max(input.estimatedSessionKcal, 0)
                credit = eatBack * min(rawActive, cap)
            }

        case .fixed, .classic:
            multiplier = profile.activityFactor
            if let manual = input.manualTarget {
                baseline = manual
                lines = [.init(.manualTarget, manual)]
            } else {
                let auto = CalorieGoalCalculator.dailyCalorieGoal(profile: profile) // floored + rounded
                baseline = auto
                lines = [.init(.bmr, bmr), .init(.everydayActivity, bmr * (multiplier - 1)), .init(.goal, goal)]
            }
            if input.mode == .classic {
                rawActive = max(input.estimatedSessionKcal, 0)
                credit = eatBack * rawActive // uncapped, as the app does today
            }
        }

        // The floor applies to the baseline, *then* exercise credit is added
        // (P1-D1, formula v2). Floor-after-credit swallowed the credit whenever an
        // aggressive goal put the baseline under the floor, so workouts never moved
        // the budget. .classic and a manual target keep their own behaviour.
        let appliesFloor = !(input.mode == .classic || (input.mode == .fixed && input.manualTarget != nil))
        let flooredBaseline = appliesFloor ? max(floor, baseline) : baseline
        let budget = flooredBaseline + credit

        // A remainder comes from the floor, or from rounding inside the auto target.
        let remainder = flooredBaseline - lines.reduce(0) { $0 + $1.kcal }
        if remainder > 0.5 { lines.append(.init(.floorTopUp, remainder)) }
        if credit > 0 { lines.append(.init(.exerciseCredit, credit)) }

        return BudgetBreakdown(mode: input.mode, bmr: bmr, activityMultiplier: multiplier, goalAdjustment: goal,
                               baseline: baseline, allowance: allowance, rawActive: rawActive, eatBack: eatBack,
                               credit: credit, floor: floor, budget: budget,
                               formulaVersion: BudgetBreakdown.formulaVersion, lines: lines)
    }
}
