import Foundation

extension ExperienceMealSlot: Codable {}

/// A "When … if … then …" rule (Phase 4 §4.4).
nonisolated struct AutomationRule: Identifiable, Codable, Equatable, Sendable {
    nonisolated enum Trigger: Codable, Equatable, Sendable {
        /// Weekdays use Calendar numbering (1 = Sunday … 7 = Saturday); empty = every day.
        case time(hour: Int, minute: Int, weekdays: [Int])
        case everyHours(Int, fromHour: Int, toHour: Int)
        case mealLogged
        case workoutLogged
        case weightLogged

        var isScheduled: Bool {
            switch self {
            case .time, .everyHours: return true
            default: return false
            }
        }
    }

    nonisolated enum Condition: Codable, Equatable, Sendable {
        case none
        case waterBelow(Int)
        case proteinBelowShare(Double)
        case overBudget
        case slotNotLogged(ExperienceMealSlot)
        case notWeighedToday
    }

    nonisolated enum Action: Codable, Equatable, Sendable {
        case notify(String)
        case suggestUsual(ExperienceMealSlot)
        case morningBrief
        case eveningRecap
        case weeklyReview
        case budgetEffect
        case suggestHighProtein
    }

    var id: String
    var name: String
    var trigger: Trigger
    var condition: Condition = .none
    var action: Action
    var isOn: Bool = true
    var templateID: String? = nil
    var runs: [Date] = []

    func runsThisWeek(now: Date, calendar: Calendar = .current) -> Int {
        runs.filter { calendar.isDate($0, equalTo: now, toGranularity: .weekOfYear) }.count
    }
}

// MARK: - Sentences

nonisolated enum AutomationText {
    static func sentence(_ r: AutomationRule, calendar: Calendar = .current) -> String {
        var parts = [whenText(r.trigger, calendar: calendar)]
        if let c = conditionText(r.condition) { parts.append("if \(c)") }
        parts.append(actionText(r.action))
        let s = parts.joined(separator: ", ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    static func whenText(_ t: AutomationRule.Trigger, calendar: Calendar = .current) -> String {
        switch t {
        case let .time(h, m, days):
            return "\(daysText(days, calendar: calendar)) at \(clock(h, m))"
        case let .everyHours(n, from, to):
            return "every \(n == 1 ? "hour" : "\(n) hours") from \(clock(from, 0)) to \(clock(to, 0))"
        case .mealLogged: return "when I log a meal"
        case .workoutLogged: return "when I log a workout"
        case .weightLogged: return "when I log my weight"
        }
    }

    static func daysText(_ days: [Int], calendar: Calendar = .current) -> String {
        let set = Set(days)
        if set.isEmpty || set.count == 7 { return "every day" }
        if set == [2, 3, 4, 5, 6] { return "on weekdays" }
        if set == [1, 7] { return "at weekends" }
        let names = days.sorted { MemoryInference.mondayIndex($0) < MemoryInference.mondayIndex($1) }
            .map { calendar.weekdaySymbols[$0 - 1] }
        return "every " + (names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!)
    }

    static func conditionText(_ c: AutomationRule.Condition) -> String? {
        switch c {
        case .none: return nil
        case .waterBelow(let n): return "I've had under \(n) glasses"
        case .proteinBelowShare(let s): return "protein is under \(Int((s * 100).rounded()))% of target"
        case .overBudget: return "I'm over budget"
        case .slotNotLogged(let slot): return "\(slot.title.lowercased()) isn't logged"
        case .notWeighedToday: return "I haven't weighed in"
        }
    }

    static func actionText(_ a: AutomationRule.Action) -> String {
        switch a {
        case .notify(let text): return "remind me: \(text)"
        case .suggestUsual(let slot): return "suggest my usual \(slot.title.lowercased())"
        case .morningBrief: return "show my morning brief"
        case .eveningRecap: return "summarise my day"
        case .weeklyReview: return "prepare my weekly review"
        case .budgetEffect: return "show what it added to my budget"
        case .suggestHighProtein: return "suggest a high-protein dinner"
        }
    }

    static func clock(_ h: Int, _ m: Int) -> String {
        let h12 = h % 12 == 0 ? 12 : h % 12
        let suffix = h < 12 ? "am" : "pm"
        return m == 0 ? "\(h12) \(suffix)" : String(format: "%d:%02d %@", h12, m, suffix)
    }
}

// MARK: - Templates

nonisolated enum AutomationTemplates {
    nonisolated enum Category: String, CaseIterable, Sendable { case food = "Food", training = "Training", water = "Water", weight = "Weight", focus = "Focus" }

    static let all: [(rule: AutomationRule, category: Category)] = [
        (AutomationRule(id: "t.morningBrief", name: "Morning brief", trigger: .time(hour: 7, minute: 30, weekdays: []), action: .morningBrief, templateID: "t.morningBrief"), .focus),
        (AutomationRule(id: "t.usualBreakfast", name: "Usual breakfast", trigger: .time(hour: 8, minute: 0, weekdays: [2, 3, 4, 5, 6]),
                        condition: .slotNotLogged(.breakfast), action: .suggestUsual(.breakfast), templateID: "t.usualBreakfast"), .food),
        (AutomationRule(id: "t.water", name: "Water nudge", trigger: .time(hour: 14, minute: 0, weekdays: []), condition: .waterBelow(4),
                        action: .notify("Have a glass of water"), templateID: "t.water"), .water),
        (AutomationRule(id: "t.afterWorkout", name: "After a workout", trigger: .workoutLogged, action: .budgetEffect, templateID: "t.afterWorkout"), .training),
        (AutomationRule(id: "t.protein", name: "Protein check", trigger: .time(hour: 19, minute: 0, weekdays: []), condition: .proteinBelowShare(0.8),
                        action: .suggestHighProtein, templateID: "t.protein"), .food),
        (AutomationRule(id: "t.weighIn", name: "Weigh-in", trigger: .time(hour: 7, minute: 0, weekdays: [2]), condition: .notWeighedToday,
                        action: .notify("Time to weigh in"), templateID: "t.weighIn"), .weight),
        (AutomationRule(id: "t.recap", name: "Evening recap", trigger: .time(hour: 21, minute: 30, weekdays: []), action: .eveningRecap, templateID: "t.recap"), .focus),
        (AutomationRule(id: "t.weekly", name: "Weekly review", trigger: .time(hour: 18, minute: 0, weekdays: [1]), action: .weeklyReview, templateID: "t.weekly"), .focus),
    ]
}

// MARK: - Conditions and planning

nonisolated struct QuietHours: Equatable, Sendable, Codable {
    var startHour = 22
    var endHour = 7

    func contains(hour: Int) -> Bool {
        startHour > endHour ? (hour >= startHour || hour < endHour) : (hour >= startHour && hour < endHour)
    }
}

nonisolated struct PlannedNotification: Equatable, Sendable, Identifiable {
    var id: String
    var ruleID: String
    var fireDate: Date
}

nonisolated enum AutomationPlanner {
    /// Whether a rule is still worth firing given what is logged so far.
    static func conditionHolds(_ c: AutomationRule.Condition, day: DayFacts?, proteinTarget: Double) -> Bool {
        guard let day else { return true }
        switch c {
        case .none: return true
        case .waterBelow(let n): return day.water < n
        case .proteinBelowShare(let s): return proteinTarget <= 0 || day.protein < proteinTarget * s
        case .overBudget: return day.budget > 0 && day.kcal > day.budget
        case .slotNotLogged(let slot): return !day.meals.contains { $0.slot == slot }
        case .notWeighedToday: return day.weightKg == nil
        }
    }

    /// Fire times for one rule on one day.
    static func times(for t: AutomationRule.Trigger, on day: Date, calendar: Calendar) -> [Date] {
        let weekday = calendar.component(.weekday, from: day)
        switch t {
        case let .time(h, m, days):
            guard days.isEmpty || days.contains(weekday) else { return [] }
            return [calendar.date(bySettingHour: h, minute: m, second: 0, of: day)].compactMap { $0 }
        case let .everyHours(n, from, to):
            guard n > 0 else { return [] }
            return stride(from: from, through: to, by: n).compactMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: day) }
        default:
            return []
        }
    }

    /// Notifications for the next `days` days. Today's conditional rules are
    /// dropped when the condition no longer holds (re-planned after every log);
    /// quiet hours and the per-day cap always apply, earliest first.
    static func plan(_ rules: [AutomationRule], now: Date, today: DayFacts?, proteinTarget: Double,
                     days: Int = 7, quiet: QuietHours = QuietHours(), maxPerDay: Int = 4,
                     calendar: Calendar = .current) -> [PlannedNotification] {
        var out: [PlannedNotification] = []
        let start = calendar.startOfDay(for: now)
        for offset in 0..<max(days, 0) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            var dayPlan: [PlannedNotification] = []
            for rule in rules where rule.isOn && rule.trigger.isScheduled {
                if offset == 0 && !conditionHolds(rule.condition, day: today, proteinTarget: proteinTarget) { continue }
                for t in times(for: rule.trigger, on: day, calendar: calendar) where t > now {
                    guard !quiet.contains(hour: calendar.component(.hour, from: t)) else { continue }
                    let stamp = Int(t.timeIntervalSince1970)
                    dayPlan.append(PlannedNotification(id: "lx.auto.\(rule.id).\(stamp)", ruleID: rule.id, fireDate: t))
                }
            }
            out += dayPlan.sorted { $0.fireDate < $1.fireDate }.prefix(maxPerDay)
        }
        return out
    }

    /// "Here's how this would have run last week: 3 times." Uses each day's end-of-day facts.
    static func backtest(_ rule: AutomationRule, days: [DayFacts], proteinTarget: Double, quiet: QuietHours = QuietHours(),
                         calendar: Calendar = .current) -> Int {
        days.reduce(0) { total, day in
            switch rule.trigger {
            case .time, .everyHours:
                let fires = times(for: rule.trigger, on: day.date, calendar: calendar)
                    .filter { !quiet.contains(hour: calendar.component(.hour, from: $0)) }.count
                return total + (conditionHolds(rule.condition, day: day, proteinTarget: proteinTarget) ? fires : 0)
            case .mealLogged:
                return total + (conditionHolds(rule.condition, day: day, proteinTarget: proteinTarget) ? day.meals.count : 0)
            case .workoutLogged:
                return total + (day.trained && conditionHolds(rule.condition, day: day, proteinTarget: proteinTarget) ? 1 : 0)
            case .weightLogged:
                return total + (day.weightKg != nil ? 1 : 0)
            }
        }
    }
}

// MARK: - "Remind me to…" parsing (assistant → rule preview card)

nonisolated enum AutomationParser {
    static func parse(_ sentence: String, idSeed: String = UUID().uuidString) -> AutomationRule? {
        let s = " " + sentence.lowercased().replacingOccurrences(of: "’", with: "'") + " "
        guard s.contains("remind me") || s.contains("notify me") || s.contains("nudge me") else { return nil }

        var trigger: AutomationRule.Trigger?
        if let n = match(#"every (\d+) hours?"#, in: s).flatMap(Int.init) {
            trigger = .everyHours(min(max(n, 1), 12), fromHour: 9, toHour: 21)
        } else if s.contains("every hour") {
            trigger = .everyHours(1, fromHour: 9, toHour: 21)
        } else if let (h, m) = clock(in: s) {
            trigger = .time(hour: h, minute: m, weekdays: weekdays(in: s))
        } else if !weekdays(in: s).isEmpty {
            trigger = .time(hour: 9, minute: 0, weekdays: weekdays(in: s))
        }
        guard let trigger else { return nil }

        // What to be reminded of: after "to", before the time/day words.
        var what = "Reminder"
        if let r = s.range(of: #"(?:remind|notify|nudge) me (?:to |about )?"#, options: .regularExpression) {
            var tail = String(s[r.upperBound...])
            for stop in [" every ", " at ", " on ", " each ", " daily", " in the ", " tomorrow", " tonight", " weekdays", " weekends"] {
                if let x = tail.range(of: stop) { tail = String(tail[..<x.lowerBound]) }
            }
            let cleaned = MemoryPhrases.secondPerson(tail.trimmingCharacters(in: .whitespacesAndNewlines))
            if !cleaned.isEmpty { what = cleaned.prefix(1).uppercased() + cleaned.dropFirst() }
        }
        return AutomationRule(id: "u.\(idSeed)", name: what, trigger: trigger, action: .notify(what))
    }

    static func match(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    /// "at 7", "at 7pm", "at 7:30 am", "at 19:00".
    static func clock(in s: String) -> (Int, Int)? {
        guard let re = try? NSRegularExpression(pattern: #"at (\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?"#),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let hr = Range(m.range(at: 1), in: s), var h = Int(s[hr]) else {
            if s.contains("tonight") { return (20, 0) }
            if s.contains("morning") { return (8, 0) }
            if s.contains("evening") { return (19, 0) }
            return nil
        }
        let minute = Range(m.range(at: 2), in: s).flatMap { Int(s[$0]) } ?? 0
        let suffix = Range(m.range(at: 3), in: s).map { String(s[$0]) }
        if let suffix, suffix.hasPrefix("p"), h < 12 { h += 12 }
        if let suffix, suffix.hasPrefix("a"), h == 12 { h = 0 }
        if suffix == nil, h >= 1, h <= 6 { h += 12 } // "at 6" means evening, not dawn
        guard (0...23).contains(h), (0...59).contains(minute) else { return nil }
        return (h, minute)
    }

    static func weekdays(in s: String) -> [Int] {
        if s.contains("weekday") { return [2, 3, 4, 5, 6] }
        if s.contains("weekend") { return [1, 7] }
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        return names.enumerated().filter { s.contains($0.element) }.map { $0.offset + 1 }
    }
}
