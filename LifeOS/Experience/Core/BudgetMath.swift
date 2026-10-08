import Foundation

/// Today's calorie budget, explained (UI/UX Phase 3 §3.10 "every number explains itself").
///
/// Mirrors the formula the app already uses on Home: budget = daily limit +
/// active energy × the "eat back" share from Settings. Pure value type: no
/// managers, no UI, so it is unit-tested in `Packages/LifeOSDesign`.
nonisolated struct ExperienceBudget: Equatable, Sendable {
    /// The user's daily calorie limit (Settings or the recommended target).
    var baseLimit: Double
    /// Active energy today (Apple Health / Apple Watch), kcal.
    var activeEnergy: Double
    /// Share of active energy added back to the budget, 0…1 (Settings default 0.5).
    var eatBackShare: Double
    /// Calories logged today.
    var eaten: Double

    /// The calorie engine's exercise credit (CAL-03). When set, `earned` is this
    /// number, not a share of `activeEnergy`: the engine applies the cap, the
    /// measured-mode allowance and the floor.
    var credit: Double? = nil
    /// The engine's own lines (`BudgetBreakdown.lines`), shown by the explainer.
    var engineLines: [EngineLine]? = nil
    /// How the engine credits activity for this day (mirror of `LifeOSCore.BudgetMode`).
    var creditMode: CreditMode? = nil
    /// Everyday-movement allowance subtracted before measured-mode credit, kcal.
    var allowance: Double = 0

    /// Mirror of `LifeOSCore.BudgetMode` for this Foundation-only layer.
    nonisolated enum CreditMode: Sendable, Equatable {
        /// Apple Watch active energy above the everyday allowance is credited.
        case measured
        /// The estimate of sessions logged in the app is credited.
        case estimated
        /// A fixed target: activity is never credited.
        case off
    }

    init(baseLimit: Double, activeEnergy: Double, eatBackShare: Double, eaten: Double) {
        self.baseLimit = baseLimit
        self.activeEnergy = activeEnergy
        self.eatBackShare = eatBackShare
        self.eaten = eaten
    }

    /// The budget exactly as the calorie engine stored it: `budget` is the engine's
    /// total and `earned` its credit, so the orb, widgets, Watch and Siri agree.
    static func engine(budget: Double, credit: Double, rawActive: Double, eatBack: Double, eaten: Double,
                       lines: [EngineLine], mode: CreditMode? = nil, allowance: Double = 0) -> ExperienceBudget {
        let c = max(finite(credit), 0).rounded()
        var b = ExperienceBudget(baseLimit: max(finite(budget) - c, 0), activeEnergy: rawActive,
                                 eatBackShare: eatBack, eaten: eaten)
        b.credit = c
        b.engineLines = lines
        b.creditMode = mode
        b.allowance = max(finite(allowance), 0)
        return b
    }

    /// One sentence on how activity reaches this budget, matching the engine's mode,
    /// so the Training hero never promises credit the engine won't give.
    var activityNote: String {
        let pct = Int((min(max(Self.finite(eatBackShare), 0), 1) * 100).rounded())
        let active = Int(max(Self.finite(activeEnergy), 0).rounded())
        let everyday = Int(allowance.rounded())
        if creditMode == .off { return "Your budget is a fixed target, so activity isn't added to it." }
        if pct == 0 { return "Counting activity is off. Tap to choose how much is added back." }
        switch (creditMode, earned > 0) {
        case (.measured, true):
            return "\(pct)% of \(active) active kcal, above your everyday \(everyday), is added to your budget within your daily cap."
        case (.measured, false):
            return "Measured by your Apple Watch: \(pct)% of active energy above your everyday \(everyday) kcal is added as you move."
        case (_, true):
            return "\(pct)% of \(active) kcal from today's sessions is added to your budget, within your daily cap."
        case (_, false):
            return "Log sets or a treadmill session and part of it is added to your budget."
        }
    }

    /// Mirror of `LifeOSCore.BudgetBreakdown.Line` (this layer is Foundation-only).
    nonisolated struct EngineLine: Equatable, Sendable {
        enum Kind: String, Sendable { case bmr, everydayActivity, goal, manualTarget, exerciseCredit, floorTopUp }
        var kind: Kind
        var kcal: Double
    }

    private static func finite(_ v: Double) -> Double { v.isFinite ? v : 0 }

    var earned: Double {
        if let credit { return max(Self.finite(credit), 0).rounded() }
        let share = min(max(Self.finite(eatBackShare), 0), 1)
        return (max(Self.finite(activeEnergy), 0) * share).rounded()
    }

    var budget: Double { max(Self.finite(baseLimit), 0) + earned }
    /// Negative when over budget ("120 over").
    var remaining: Double { budget - max(Self.finite(eaten), 0) }
    var isOver: Bool { remaining < 0 }
    /// Eaten ÷ budget for the Life Orb; 0 when there is no budget (never NaN).
    var fill: Double { budget > 0 ? max(Self.finite(eaten), 0) / budget : 0 }

    /// How the automatic daily limit was derived from the profile (Phase 3 §3.10 top lines).
    nonisolated struct Derivation: Equatable, Sendable {
        var maintenance: Double      // TDEE
        var adjustment: Double       // negative = deficit
        var weeklyChangeKg: Double   // negative = loss
    }

    /// Lines for the explainer sheet, in reading order. With a `derivation` (auto target)
    /// the base line is preceded by maintenance and goal lines; a floor shows as its own note.
    func lines(activeSourceNote: String? = nil, derivation: Derivation? = nil) -> [Line] {
        if let engineLines { return lines(engine: engineLines, activeSourceNote: activeSourceNote) }
        var out: [Line] = []
        let base = Int(max(Self.finite(baseLimit), 0).rounded())
        if let d = derivation, d.maintenance.isFinite, d.maintenance > 0 {
            out.append(Line(id: "maintenance", label: "Maintenance", kcal: Int(d.maintenance.rounded()), kind: .component,
                            note: "What you burn on a typical day, from your age, height, weight, sex and activity level."))
            let adj = Int(Self.finite(d.adjustment).rounded())
            if adj != 0 {
                let rate = String(format: "%.2g", abs(d.weeklyChangeKg))
                out.append(Line(id: "goal", label: adj < 0 ? "Goal: lose \(rate) kg/week" : "Goal: gain \(rate) kg/week",
                                kcal: adj, kind: .component,
                                note: "Spreads the gap to your target weight over about 10 weeks, within safe rates."))
            }
            let raw = Int(d.maintenance.rounded()) + adj
            out.append(Line(id: "base", label: "Base budget", kcal: base, kind: .subtotal,
                            note: base > raw ? "Raised to a safe minimum of \(base.formatted()) kcal." : nil))
        } else {
            out.append(Line(id: "base", label: "Daily limit", kcal: base, kind: .component,
                            note: "Your own calorie target from Settings."))
        }
        let sharePct = Int((min(max(Self.finite(eatBackShare), 0), 1) * 100).rounded())
        out.append(Line(id: "earned", label: "Earned from activity", kcal: Int(earned), kind: .earned,
                        note: activeEnergy > 0
                            ? "\(sharePct)% of \(Int(max(activeEnergy, 0).rounded())) active kcal."
                            : (sharePct == 0 ? "Counting activity is off in Settings." : "No active energy recorded yet today."),
                        source: activeSourceNote))
        out.append(Line(id: "budget", label: "Today's budget", kcal: Int(budget.rounded()), kind: .subtotal))
        out.append(Line(id: "eaten", label: "Eaten so far", kcal: Int(max(Self.finite(eaten), 0).rounded()), kind: .eaten))
        out.append(Line(id: "remaining", label: isOver ? "Over today" : "Remaining",
                        kcal: Int(abs(remaining).rounded()), kind: .total))
        return out
    }

    /// The engine's lines in its order (floor top-up before exercise credit, formula v2),
    /// then the budget, eaten and remaining.
    private func lines(engine: [EngineLine], activeSourceNote: String?) -> [Line] {
        var out: [Line] = []
        let sharePct = Int((min(max(Self.finite(eatBackShare), 0), 1) * 100).rounded())
        for (i, l) in engine.enumerated() {
            let kcal = Int(Self.finite(l.kcal).rounded())
            switch l.kind {
            case .bmr:
                out.append(Line(id: "bmr\(i)", label: "Resting burn", kcal: kcal, kind: .component,
                                note: "What your body uses at rest, from Apple Health or your profile."))
            case .everydayActivity:
                out.append(Line(id: "everyday\(i)", label: "Everyday activity", kcal: kcal, kind: .component,
                                note: "Normal moving about, already counted before any workout."))
            case .goal where kcal != 0:
                out.append(Line(id: "goal\(i)", label: kcal < 0 ? "Goal: lose weight" : "Goal: gain weight", kcal: kcal,
                                kind: .component, note: "Spreads the gap to your target weight over safe weekly rates."))
            case .goal:
                break
            case .manualTarget:
                out.append(Line(id: "manual\(i)", label: "Your daily target", kcal: kcal, kind: .component,
                                note: "Your own calorie target from Settings."))
            case .floorTopUp:
                out.append(Line(id: "floor\(i)", label: "Safe minimum top-up", kcal: kcal, kind: .component,
                                note: "Raised so your budget never drops below a safe minimum."))
            case .exerciseCredit:
                out.append(Line(id: "earned", label: "Earned from activity", kcal: kcal, kind: .earned,
                                note: sharePct == 0 ? "Counting activity is off in Settings."
                                    : creditMode == .measured && allowance > 0
                                    ? "\(sharePct)% of \(Int(max(Self.finite(activeEnergy), 0).rounded())) active kcal above your everyday \(Int(allowance.rounded())), within your daily cap."
                                    : "\(sharePct)% of \(Int(max(Self.finite(activeEnergy), 0).rounded())) active kcal, within your daily cap.",
                                source: activeSourceNote))
            }
        }
        if !engine.contains(where: { $0.kind == .exerciseCredit }) {
            out.append(Line(id: "earned", label: "Earned from activity", kcal: Int(earned), kind: .earned,
                            note: sharePct == 0 ? "Counting activity is off in Settings." : "No activity counted yet today.",
                            source: activeSourceNote))
        }
        out.append(Line(id: "budget", label: "Today's budget", kcal: Int(budget.rounded()), kind: .subtotal))
        out.append(Line(id: "eaten", label: "Eaten so far", kcal: Int(max(Self.finite(eaten), 0).rounded()), kind: .eaten))
        out.append(Line(id: "remaining", label: isOver ? "Over today" : "Remaining",
                        kcal: Int(abs(remaining).rounded()), kind: .total))
        return out
    }

    nonisolated struct Line: Identifiable, Equatable, Sendable {
        enum Kind: Sendable { case component, earned, subtotal, eaten, total }
        let id: String
        let label: String
        let kcal: Int
        let kind: Kind
        var note: String? = nil
        var source: String? = nil
    }
}

/// Default meal slot from the time of day (Phase 3 §3.2: "Breakfast before 11 am by default").
nonisolated enum ExperienceMealSlot: String, CaseIterable, Sendable {
    case breakfast, lunch, snack, dinner

    static func slot(for date: Date, calendar: Calendar = .current) -> ExperienceMealSlot {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 4..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<19: return .snack
        default: return .dinner
        }
    }

    var title: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .snack: return "Snack"
        case .dinner: return "Dinner"
        }
    }
}

/// Copy rules (Phase 3 §4): short, calm, specific; never shaming.
nonisolated enum ExperienceCopy {
    static func logged(kcal: Int, proteinG: Int?) -> String {
        if let p = proteinG, p > 0 { return "Logged. \(kcal) kcal, \(p) g protein." }
        return "Logged. \(kcal) kcal."
    }

    static func remainingHeadline(_ budget: ExperienceBudget) -> (value: String, label: String) {
        let r = Int(abs(budget.remaining).rounded())
        return budget.isOver ? (r.formatted(), "over today") : (r.formatted(), "kcal left")
    }

    static func overNote(_ budget: ExperienceBudget) -> String? {
        budget.isOver ? "\(Int(abs(budget.remaining).rounded())) over today. Tomorrow resets." : nil
    }
}
