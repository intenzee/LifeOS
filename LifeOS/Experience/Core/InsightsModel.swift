import Foundation

/// An insight card (Phase 4 §4.3): claim, evidence with its time range, one action.
nonisolated struct InsightCard: Identifiable, Equatable, Sendable {
    nonisolated enum Action: Equatable, Sendable {
        case createReminder(AutomationRule)
        case openBudget
        case none
    }
    var id: String
    var claim: String
    var evidence: [(label: String, value: Double)]
    var evidenceRange: String
    var actionTitle: String?
    var action: Action
    var learnedFrom: String

    static func == (a: InsightCard, b: InsightCard) -> Bool {
        a.id == b.id && a.claim == b.claim && a.evidence.map(\.label) == b.evidence.map(\.label)
            && a.evidence.map(\.value) == b.evidence.map(\.value) && a.action == b.action
    }
}

nonisolated enum Briefs {
    /// Evening recap: "Today: 1,840 of 1,920 kcal, 118 g protein, 9 glasses. Perfect day kept."
    static func eveningRecap(_ day: DayFacts, perfectDay: Bool) -> String {
        var parts: [String] = []
        if day.budget > 0 { parts.append("\(Fmt.kcal(day.kcal)) of \(Fmt.kcal(day.budget)) kcal") } else { parts.append("\(Fmt.kcal(day.kcal)) kcal") }
        parts.append("\(Fmt.grams(day.protein)) protein")
        parts.append("\(day.water) glass\(day.water == 1 ? "" : "es")")
        var s = "Today: " + parts.joined(separator: ", ") + "."
        if perfectDay { s += " Perfect day kept." }
        else if day.budget > 0, day.kcal > day.budget { s += " \(Fmt.kcal(day.kcal - day.budget)) over. Tomorrow resets." }
        return s
    }

    /// Morning brief: one line about today, or nil when there is nothing useful.
    static func morning(_ snapshot: IntelligenceSnapshot) -> String? {
        let cal = snapshot.calendar
        let weekday = cal.component(.weekday, from: snapshot.now)
        let memories = snapshot.memories
        if let gym = memories.first(where: { $0.id == "routine.gym" }),
           let name = cal.shortWeekdaySymbols[safe: weekday - 1], gym.text.contains(name) {
            return "Gym day. Each logged set adds to today's budget."
        }
        let yesterday = snapshot.lastDays(2).first { !cal.isDate($0.date, inSameDayAs: snapshot.now) }
        if let y = yesterday, y.budget > 0, y.kcal > y.budget + 150 {
            return "Yesterday ran \(Fmt.kcal(y.kcal - y.budget)) over. Today is a fresh \(Fmt.kcal(snapshot.budgetToday.budget))."
        }
        if let y = yesterday, y.hasFood, snapshot.proteinTarget > 0, y.protein < snapshot.proteinTarget * 0.7 {
            return "Protein was \(Fmt.grams(y.protein)) yesterday. A protein-first breakfast helps today."
        }
        return nil
    }
}

/// The Sunday story (Phase 4 §4.3), 4–6 pages.
nonisolated struct WeeklyReview: Equatable, Sendable {
    var range: String
    var oneLine: String
    var averageFill: Double
    var avgIntake: Double
    var avgBudget: Double
    var avgProtein: Double
    var proteinTarget: Double
    var workouts: Int
    var loggedDays: Int
    var daily: [(date: Date, kcal: Double, budget: Double)]
    var bestDay: (date: Date, reason: String)?
    var pattern: InsightCard?
    var focus: InsightCard

    static func == (a: WeeklyReview, b: WeeklyReview) -> Bool {
        a.oneLine == b.oneLine && a.avgIntake == b.avgIntake && a.workouts == b.workouts && a.pattern == b.pattern && a.focus == b.focus
    }

    static func make(_ snapshot: IntelligenceSnapshot) -> WeeklyReview? {
        let week = snapshot.lastDays(7)
        let logged = week.filter(\.hasFood)
        guard logged.count >= 2 else { return nil }
        let cal = snapshot.calendar
        let avgIntake = Fmt.avg(logged.map(\.kcal))
        let budgets = logged.map(\.budget).filter { $0 > 0 }
        let avgBudget = Fmt.avg(budgets)
        let avgProtein = Fmt.avg(logged.map(\.protein))
        let onBudget = logged.filter(\.onBudget).count
        let workouts = week.filter(\.trained).count

        let oneLine: String
        if avgBudget > 0 && onBudget >= logged.count - 1 {
            oneLine = "A steady week: on budget \(onBudget) of \(logged.count) logged days."
        } else if avgBudget > 0 && avgIntake > avgBudget {
            oneLine = "A heavier week: about \(Fmt.kcal(avgIntake - avgBudget)) a day over budget."
        } else {
            oneLine = "You logged \(logged.count) of 7 days and trained \(workouts) time\(workouts == 1 ? "" : "s")."
        }

        // Best day: on budget with the most protein.
        let best = logged.filter(\.onBudget).max { $0.protein < $1.protein }
            .map { ($0.date, "On budget with \(Fmt.grams($0.protein)) protein\($0.trained ? " and a workout" : "").") }

        // One pattern: weekend vs weekday over 4 weeks, else protein gap.
        var pattern: InsightCard?
        let month = snapshot.lastDays(28).filter { $0.hasFood && !cal.isDate($0.date, inSameDayAs: snapshot.now) }
        let weekend = month.filter { cal.isDateInWeekend($0.date) }.map(\.kcal)
        let weekday = month.filter { !cal.isDateInWeekend($0.date) }.map(\.kcal)
        if weekend.count >= 2, weekday.count >= 4, abs(Fmt.avg(weekend) - Fmt.avg(weekday)) >= 200 {
            let diff = Fmt.avg(weekend) - Fmt.avg(weekday)
            pattern = InsightCard(id: "pattern.weekend",
                                  claim: "Weekends run about \(Int((abs(diff) / 50).rounded() * 50)) kcal \(diff > 0 ? "higher" : "lower") than weekdays.",
                                  evidence: [("Weekdays", Fmt.avg(weekday)), ("Weekends", Fmt.avg(weekend))],
                                  evidenceRange: "Last 4 weeks", actionTitle: nil, action: .none,
                                  learnedFrom: "Learned from \(max(1, month.count / 7)) weeks of data")
        } else if snapshot.proteinTarget > 0, avgProtein < snapshot.proteinTarget * 0.85 {
            pattern = InsightCard(id: "pattern.protein",
                                  claim: "Protein averaged \(Fmt.grams(avgProtein)), \(Fmt.grams(snapshot.proteinTarget - avgProtein)) under target.",
                                  evidence: [("Average", avgProtein), ("Target", snapshot.proteinTarget)],
                                  evidenceRange: "This week", actionTitle: nil, action: .none, learnedFrom: "From \(logged.count) logged days")
        }

        // Next week's focus: one suggestion with a reminder.
        let focus: InsightCard
        if snapshot.proteinTarget > 0, avgProtein < snapshot.proteinTarget * 0.85 {
            let rule = AutomationTemplates.all.first { $0.rule.id == "t.protein" }!.rule
            focus = InsightCard(id: "focus.protein", claim: "Next week: get protein closer to \(Fmt.grams(snapshot.proteinTarget)).",
                                evidence: [], evidenceRange: "", actionTitle: "Create reminder", action: .createReminder(rule), learnedFrom: "")
        } else if workouts < 3 {
            let rule = AutomationRule(id: "u.focus.train", name: "Training reminder", trigger: .time(hour: 18, minute: 0, weekdays: [2, 4, 6]),
                                      action: .notify("Training today. Log your sets so they count."))
            focus = InsightCard(id: "focus.train", claim: "Next week: aim for 3 training days.", evidence: [], evidenceRange: "",
                                actionTitle: "Create reminder", action: .createReminder(rule), learnedFrom: "")
        } else {
            let rule = AutomationTemplates.all.first { $0.rule.id == "t.water" }!.rule
            focus = InsightCard(id: "focus.water", claim: "Next week: keep the streak and hit water every day.", evidence: [], evidenceRange: "",
                                actionTitle: "Create reminder", action: .createReminder(rule), learnedFrom: "")
        }

        let first = week.first?.date ?? snapshot.now
        return WeeklyReview(range: "\(Fmt.shortDay(first, cal)) – \(Fmt.shortDay(snapshot.now, cal))",
                            oneLine: oneLine,
                            averageFill: avgBudget > 0 ? avgIntake / avgBudget : 0,
                            avgIntake: avgIntake, avgBudget: avgBudget, avgProtein: avgProtein, proteinTarget: snapshot.proteinTarget,
                            workouts: workouts, loggedDays: logged.count,
                            daily: week.map { ($0.date, $0.kcal, $0.budget) },
                            bestDay: best, pattern: pattern, focus: focus)
    }
}

extension Array {
    nonisolated subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
