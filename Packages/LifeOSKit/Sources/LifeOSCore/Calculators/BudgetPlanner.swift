import Foundation

/// The user's calorie-budget settings (CAL-05). Stored as one document by LifeOSData.
public struct EnergySettings: Codable, Sendable, Equatable {
    public enum ModePreference: String, Codable, Sendable, CaseIterable {
        /// Measured with enough Watch data, estimated otherwise (doc 03 §3.1).
        case automatic
        /// No exercise credit: the manual target, or TDEE + goal.
        case fixed
    }

    public var modePreference: ModePreference
    /// Share of exercise energy added back, 0…1 in 10% steps (default 50%).
    public var eatBack: Double
    /// Max exercise energy considered per day, before eat-back.
    public var cap: Double
    /// A user-typed daily target. Forces `.fixed`.
    public var manualTarget: Double?
    /// Personalised non-workout active energy (CAL-04). `nil` = default `BMR × 0.2`.
    public var allowanceKcal: Double?
    public var allowanceComputedAt: Date?

    public static let defaultEatBack = 0.5
    public static let defaultCap = 1000.0

    public init(modePreference: ModePreference = .automatic, eatBack: Double = defaultEatBack,
                cap: Double = defaultCap, manualTarget: Double? = nil, allowanceKcal: Double? = nil,
                allowanceComputedAt: Date? = nil) {
        self.modePreference = modePreference
        self.eatBack = eatBack
        self.cap = cap
        self.manualTarget = manualTarget
        self.allowanceKcal = allowanceKcal
        self.allowanceComputedAt = allowanceComputedAt
    }

    /// Snaps eat-back to 0…100% in 10% steps, as the settings slider does.
    public static func snapEatBack(_ value: Double) -> Double {
        guard value.isFinite else { return defaultEatBack }
        return (min(max(value, 0), 1) * 10).rounded() / 10
    }
}

/// Turns stored days and settings into `CalorieEngine` inputs (CAL-02).
/// Pure, so the whole budget pipeline is testable without a store.
public enum BudgetPlanner {
    /// Days with Watch energy, out of the last 7, needed for measured mode.
    public static let measuredMinimumDays = 3
    public static let measuredWindow = 7

    /// Picks the mode for `day` (doc 03 §3.1). `recent` may hold any days;
    /// only the 7 ending on `day` count.
    public static func mode(for day: DayKey, recent: [EnergyDay], settings: EnergySettings) -> BudgetMode {
        if settings.modePreference == .fixed || settings.manualTarget != nil { return .fixed }
        let start = day.adding(days: -(measuredWindow - 1))
        let watchDays = Set(recent.filter { $0.dayKey >= start && $0.dayKey <= day && $0.hasWatchEnergy }.map(\.dayKey))
        return watchDays.count >= measuredMinimumDays ? .measured : .estimated
    }

    public static func inputs(for energy: EnergyDay, recent: [EnergyDay], profile: UserProfile,
                              settings: EnergySettings) -> EnergyInputs {
        EnergyInputs(profile: profile,
                     mode: mode(for: energy.dayKey, recent: recent, settings: settings),
                     activeKcal: energy.activeKcal,
                     estimatedSessionKcal: energy.estimatedSessionKcal,
                     allowanceOverride: settings.allowanceKcal,
                     eatBack: EnergySettings.snapEatBack(settings.eatBack),
                     cap: settings.cap,
                     manualTarget: settings.manualTarget)
    }

    public static func budget(for energy: EnergyDay, recent: [EnergyDay], profile: UserProfile,
                              settings: EnergySettings) -> BudgetBreakdown {
        CalorieEngine.budget(for: inputs(for: energy, recent: recent, profile: profile, settings: settings))
    }
}

/// Personalised everyday-activity allowance (CAL-04, doc 03 §3.1): the median
/// active energy on days without a workout. Until there's enough history the
/// engine uses `BMR × 0.2`.
public enum AllowanceEstimator {
    /// Days of energy history required before personalising.
    public static let minimumHistoryDays = 14
    /// Workout-free days required inside the window.
    public static let minimumRestDays = 5
    public static let window = 28

    /// The allowance for `today`, or `nil` to keep the default. Today is excluded
    /// (it isn't over). Result is clamped to `[BMR×0.1, BMR×0.35]`.
    public static func allowance(today: DayKey, days: [EnergyDay], profile: UserProfile) -> Double? {
        let start = today.adding(days: -window)
        let history = days.filter { $0.dayKey >= start && $0.dayKey < today && $0.activeKcal != nil }
        guard Set(history.map(\.dayKey)).count >= minimumHistoryDays else { return nil }
        let rest = history.filter { !$0.hadWorkout }.compactMap(\.activeKcal).sorted()
        guard rest.count >= minimumRestDays else { return nil }
        let median = rest.count.isMultiple(of: 2)
            ? (rest[rest.count / 2 - 1] + rest[rest.count / 2]) / 2
            : rest[rest.count / 2]
        let bmr = CalorieGoalCalculator.bmr(profile: profile)
        let range = CalorieEngine.allowanceRange
        return min(max(median, bmr * range.lowerBound), bmr * range.upperBound).rounded()
    }
}
