import Foundation
import LifeOSCore

/// CAL-03 for the new experience: every budget the Phase 3–5 screens, widgets,
/// Siri and automations show comes from the calorie engine through `HealthSync`.
/// No budget maths here; this only converts `BudgetBreakdown` for the
/// Foundation-only `ExperienceBudget`.
@MainActor
enum EngineBudget {
    /// The engine's budget for `date` with `eaten` applied.
    /// Today uses the live breakdown. Other days use the stored total with the
    /// engine's lines for that day.
    static func budget(on date: Date, eaten: Double) -> ExperienceBudget {
        let health = HealthSync.shared
        let day = DayKey.make(for: date)
        let total = health.budget(on: day)
        guard let breakdown = breakdown(on: day) else {
            return .engine(budget: total, credit: 0, rawActive: health.exerciseKcal(on: day),
                           eatBack: health.settings.eatBack, eaten: eaten, lines: [])
        }
        // A frozen past day keeps its stored total even if settings changed since;
        // the credit then can't exceed it.
        return .engine(budget: total, credit: min(breakdown.credit, total), rawActive: breakdown.rawActive,
                       eatBack: breakdown.eatBack, eaten: eaten, lines: lines(breakdown))
    }

    static func breakdown(on day: DayKey) -> BudgetBreakdown? {
        let health = HealthSync.shared
        if day == .today(), let today = health.todayBreakdown { return today }
        guard let profile = PersistenceManager.shared.loadUserProfile() else { return nil }
        return BudgetPlanner.budget(for: health.energyByDay[day] ?? EnergyDay(dayKey: day),
                                    recent: Array(health.energyByDay.values), profile: profile,
                                    settings: health.settings)
    }

    private static func lines(_ b: BudgetBreakdown) -> [ExperienceBudget.EngineLine] {
        b.lines.compactMap { line in
            ExperienceBudget.EngineLine.Kind(rawValue: line.kind.rawValue).map { .init(kind: $0, kcal: line.kcal) }
        }
    }

    /// The eat-back share the engine uses (0…1, steps of 10%).
    static var eatBack: Double { HealthSync.shared.settings.eatBack }

    static func setEatBack(_ share: Double) {
        HealthSync.shared.updateSettings { $0.eatBack = share }
    }
}
