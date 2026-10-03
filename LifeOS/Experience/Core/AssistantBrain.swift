import Foundation

/// One assistant answer (Phase 4 §4.1 response types).
nonisolated struct AssistantReply: Equatable, Sendable {
    nonisolated struct Row: Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        var detail: String
        var kcal: Int
        /// What to send to Capture to log it ("2 rotis").
        var logText: String?
    }

    nonisolated enum Card: Equatable, Sendable {
        case none
        case chart(title: String, points: [ChartPoint], goal: Double?, unit: String)
        case list(title: String, rows: [Row])
        case logProposal(sentence: String)
        case rule(AutomationRule)
        case remembered(MemoryItem)
        case forgotten([MemoryItem])
    }

    nonisolated struct ChartPoint: Equatable, Sendable, Identifiable {
        var date: Date
        var value: Double
        var id: Date { date }
    }

    var text: String
    var basedOn: String? = nil
    var card: Card = .none
    var usedMemories: [MemoryItem] = []
    var isSafetyRedirect = false
    /// Nothing matched: the app may ask the AI model (with this as the fallback text).
    var needsModel = false
}

/// The on-device assistant: answers from the user's own data, with no model
/// needed. Anything it can't answer is flagged `needsModel` for the gateway.
nonisolated enum AssistantBrain {

    static func reply(to raw: String, _ s: IntelligenceSnapshot) -> AssistantReply {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = " " + text.lowercased().replacingOccurrences(of: "’", with: "'") + " "

        if let safety = safetyRedirect(t, s) { return safety }

        if let remembered = MemoryPhrases.rememberedText(from: text) {
            let item = MemoryItem(id: "said.\(UUID().uuidString)", text: remembered, category: MemoryPhrases.category(for: remembered),
                                  source: .youSaid, createdAt: s.now)
            return AssistantReply(text: "Got it.", card: .remembered(item))
        }
        if t.hasPrefix(" forget ") {
            let words = Set(t.split(separator: " ").map(String.init).filter { $0.count > 3 && !["forget", "that", "about"].contains($0) })
            let hits = s.memories.filter { m in words.contains { m.text.lowercased().contains($0) } }
            return hits.isEmpty
                ? AssistantReply(text: "I couldn't find that in what I know. You can see everything in You → What LifeOS knows.")
                : AssistantReply(text: "Forget \(hits.count == 1 ? "this" : "these \(hits.count)")?", card: .forgotten(hits))
        }
        if let rule = AutomationParser.parse(text) {
            return AssistantReply(text: "Here's the rule. Turn it on?", card: .rule(rule))
        }
        if let sentence = logSentence(t) {
            return AssistantReply(text: "Log this?", card: .logProposal(sentence: sentence))
        }

        let slot = slotMentioned(t)
        if t.contains("protein") { return protein(s) }
        if (t.contains("plan") || t.contains("suggest") || t.contains("what should i eat") || t.contains("ideas")) && !t.contains("week") {
            return plan(t, slot: slot ?? defaultSlot(s), s)
        }
        if t.contains("usual") || t.contains("frequent") || t.contains("often") || t.contains("favourite") || t.contains("favorite") {
            return frequent(slot: slot, s)
        }
        if t.contains("budget") || t.contains("left") || t.contains("remaining") || t.contains("how many calories") || t.contains("over ") {
            return budget(s)
        }
        if t.contains("week") || t.contains("how am i doing") || t.contains("how's it going") || t.contains("summary") { return week(s) }
        if t.contains("workout") || t.contains("gym") || t.contains("train") || t.contains("exercise") { return workouts(s) }
        if t.contains("water") || t.contains("drink") || t.contains("hydrat") { return water(s) }
        if t.contains("weigh") { return weight(s) }

        return AssistantReply(text: "I can answer questions about your budget, meals, protein, water, workouts and weight, log food, set reminders, and remember things about you.",
                              needsModel: true)
    }

    static func suggestions(_ s: IntelligenceSnapshot, screen: String? = nil) -> [String] {
        var out: [String] = []
        out.append(s.budgetToday.earned > 0 ? "Why is my budget higher today?" : "How many calories are left?")
        out.append("How's my protein this week?")
        let hour = s.calendar.component(.hour, from: s.now)
        let next = hour < 11 ? "breakfast" : hour < 16 ? "lunch" : "dinner"
        let cap = max(300, min(800, Int((s.budgetToday.remaining / 100).rounded() * 100)))
        out.append("Plan \(next) under \(cap) kcal")
        if screen == "Training" { out[1] = "How many workouts this week?" }
        return out
    }

    // MARK: Safety (stay in its lane)

    static func safetyRedirect(_ t: String, _ s: IntelligenceSnapshot) -> AssistantReply? {
        let medical = ["medication", "medicine", "pill", "dosage", " dose", "diagnos", "insulin", "metformin", "ozempic", "semaglutide",
                       "prescri", "diabetes", "thyroid", "blood pressure", "cholesterol", "disease", "symptom"]
        if medical.contains(where: t.contains) {
            return AssistantReply(text: "I can't advise on medication or diagnose anything. Your doctor is the right person for that. I can still help with meals and your budget.",
                                  isSafetyRedirect: true)
        }
        if let n = AutomationParser.match(#"(\d{3,4})\s*(?:kcal|cal|calories)"#, in: t).flatMap(Double.init), n < 1200,
           ["diet", "a day", "per day", "daily", "eat only", "only eat", "fast"].contains(where: t.contains) {
            return AssistantReply(text: "I won't plan below 1,200 kcal a day. Going that low makes it hard to get enough protein and nutrients. Your budget today is \(Fmt.kcal(s.budgetToday.budget)) kcal. A registered dietitian can help with a faster plan safely.",
                                  basedOn: "Safe minimum used for your budget", isSafetyRedirect: true)
        }
        return nil
    }

    // MARK: Logging

    static func logSentence(_ t: String) -> String? {
        let leads = [" log ", " i had ", " i ate ", " just had ", " add ", " i've had ", " i have had ", " had "]
        guard let lead = leads.first(where: { t.hasPrefix($0) }) else { return nil }
        let rest = t.dropFirst(lead.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard rest.count >= 2, !rest.hasPrefix("a reminder") else { return nil }
        return rest
    }

    static func slotMentioned(_ t: String) -> ExperienceMealSlot? {
        if t.contains("breakfast") { return .breakfast }
        if t.contains("lunch") { return .lunch }
        if t.contains("dinner") || t.contains("supper") { return .dinner }
        if t.contains("snack") { return .snack }
        return nil
    }

    static func defaultSlot(_ s: IntelligenceSnapshot) -> ExperienceMealSlot { ExperienceMealSlot.slot(for: s.now, calendar: s.calendar) }

    // MARK: Answers

    static func budget(_ s: IntelligenceSnapshot) -> AssistantReply {
        let b = s.budgetToday
        let base = Fmt.kcal(b.baseLimit), earned = Fmt.kcal(b.earned)
        var text: String
        if b.isOver {
            text = "You're \(Fmt.kcal(-b.remaining)) over today. Tomorrow resets."
        } else {
            text = "You're \(Fmt.kcal(b.remaining)) under."
            let hour = s.calendar.component(.hour, from: s.now)
            let dinnerLogged = s.today?.meals.contains { $0.slot == .dinner } ?? false
            if hour >= 16, !dinnerLogged, b.remaining >= 300 {
                text += " A \(Int((min(b.remaining, 700) / 50).rounded(.down) * 50)) kcal dinner keeps you on track."
            }
        }
        text += b.earned > 0
            ? " Budget \(Fmt.kcal(b.budget)) = \(base) base + \(earned) earned from activity."
            : " Budget \(Fmt.kcal(b.budget)), your daily limit with nothing earned from activity yet."
        return AssistantReply(text: text, basedOn: "Today's log and budget")
    }

    static func protein(_ s: IntelligenceSnapshot) -> AssistantReply {
        let week = s.lastDays(7).filter(\.hasFood)
        guard !week.isEmpty else { return AssistantReply(text: "No meals logged this week yet, so I can't work out your protein.", basedOn: "Last 7 days") }
        let avg = Fmt.avg(week.map(\.protein))
        let gap = s.proteinTarget - avg
        var text = "You've averaged \(Fmt.grams(avg)) protein this week"
        if s.proteinTarget > 0 {
            text += abs(gap) < 5 ? ", right on target." : gap > 0 ? ", \(Fmt.grams(gap)) under target." : ", \(Fmt.grams(-gap)) over target."
        } else { text += "." }
        let points = s.lastDays(14).map { AssistantReply.ChartPoint(date: $0.date, value: $0.protein) }
        return AssistantReply(text: text, basedOn: "Your last \(week.count) logged days",
                              card: .chart(title: "Protein, last 14 days", points: points, goal: s.proteinTarget > 0 ? s.proteinTarget : nil, unit: "g"))
    }

    static func week(_ s: IntelligenceSnapshot) -> AssistantReply {
        guard let review = WeeklyReview.make(s) else {
            return AssistantReply(text: "Log a couple more days and I'll have a week to summarise.", basedOn: "Last 7 days")
        }
        let points = s.lastDays(7).map { AssistantReply.ChartPoint(date: $0.date, value: $0.kcal) }
        return AssistantReply(text: "\(review.oneLine) Average \(Fmt.kcal(review.avgIntake)) kcal against \(Fmt.kcal(review.avgBudget)).",
                              basedOn: "Your last 7 days",
                              card: .chart(title: "Calories, last 7 days", points: points, goal: review.avgBudget > 0 ? review.avgBudget : nil, unit: "kcal"))
    }

    /// Foods eaten in a slot over 4 weeks, most frequent first.
    static func history(slot: ExperienceMealSlot?, _ s: IntelligenceSnapshot) -> [(name: String, count: Int, kcal: Double, protein: Double)] {
        var counts: [String: (name: String, count: Int, kcal: Double, protein: Double)] = [:]
        for day in s.lastDays(28) {
            for m in day.meals where slot == nil || m.slot == slot {
                let key = ExperienceFoodResolver.normalize(m.name)
                var e = counts[key] ?? (m.name, 0, m.kcal, m.protein)
                e.count += 1
                counts[key] = e
            }
        }
        return counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    static func frequent(slot: ExperienceMealSlot?, _ s: IntelligenceSnapshot) -> AssistantReply {
        let top = history(slot: slot, s).prefix(3)
        let what = slot.map { "\($0.title.lowercased())s" } ?? "foods"
        guard !top.isEmpty else { return AssistantReply(text: "I haven't seen enough \(what) yet. Log a few and ask again.", basedOn: "Last 4 weeks") }
        let rows = top.map { AssistantReply.Row(id: $0.name, title: $0.name, detail: "\($0.count) time\($0.count == 1 ? "" : "s")", kcal: Int($0.kcal), logText: $0.name) }
        return AssistantReply(text: "Your \(top.count == 1 ? "most frequent" : "\(top.count) most frequent") \(what):", basedOn: "Last 4 weeks of logs",
                              card: .list(title: "Most frequent \(what)", rows: Array(rows)))
    }

    static func plan(_ t: String, slot: ExperienceMealSlot, _ s: IntelligenceSnapshot) -> AssistantReply {
        let stated = AutomationParser.match(#"under (\d{2,4})"#, in: t).flatMap(Double.init)
        let cap = stated ?? max(250, s.budgetToday.remaining)
        let excluded = MemoryPhrases.excludedFoods(s.memories)
        let used = excluded.isEmpty ? [] : s.memories.filter { ["vegetarian", "vegan", "egg"].contains(where: $0.text.lowercased().contains) }
        let allowed: ((name: String, count: Int, kcal: Double, protein: Double)) -> Bool = { item in
            let n = item.name.lowercased()
            return item.kcal <= cap && !excluded.contains { n.contains($0) }
        }
        var pool = history(slot: slot, s).filter(allowed)
        if pool.count < 3 { pool += history(slot: nil, s).filter(allowed).filter { p in !pool.contains { $0.name == p.name } } }
        let picks = pool.sorted { $0.protein != $1.protein ? $0.protein > $1.protein : $0.kcal < $1.kcal }.prefix(3)
        guard !picks.isEmpty else {
            return AssistantReply(text: "I don't have a \(slot.title.lowercased()) under \(Fmt.kcal(cap)) kcal in your history yet. Something like dal with 2 rotis is about 390 kcal.",
                                  basedOn: "Your logs and built-in foods", usedMemories: used)
        }
        let rows = picks.map { AssistantReply.Row(id: $0.name, title: $0.name, detail: "\(Fmt.grams($0.protein)) protein", kcal: Int($0.kcal), logText: $0.name) }
        return AssistantReply(text: "\(picks.count == 1 ? "One" : picks.count == 2 ? "Two" : "Three") \(slot.title.lowercased()) idea\(picks.count == 1 ? "" : "s") under \(Fmt.kcal(cap)) kcal you've had before, most protein first:",
                              basedOn: "Your last 4 weeks of meals", card: .list(title: "\(slot.title) under \(Fmt.kcal(cap)) kcal", rows: Array(rows)),
                              usedMemories: used)
    }

    static func workouts(_ s: IntelligenceSnapshot) -> AssistantReply {
        let week = s.lastDays(7)
        let trained = week.filter(\.trained)
        let earned = trained.reduce(0) { $0 + $1.workoutKcal }
        let text = trained.isEmpty
            ? "No workouts logged in the last 7 days."
            : "\(trained.count) workout\(trained.count == 1 ? "" : "s") in the last 7 days, \(trained.reduce(0) { $0 + $1.gymSets }) sets, about \(Fmt.kcal(earned)) kcal burned."
        let rows = trained.reversed().map { AssistantReply.Row(id: "\($0.date)", title: Fmt.weekday($0.date, s.calendar), detail: "\($0.gymSets) sets", kcal: Int($0.workoutKcal), logText: nil) }
        return AssistantReply(text: text, basedOn: "Sets logged in LifeOS, last 7 days",
                              card: rows.isEmpty ? .none : .list(title: "Workouts", rows: Array(rows)))
    }

    static func water(_ s: IntelligenceSnapshot) -> AssistantReply {
        guard let d = s.today else { return AssistantReply(text: "No water logged today yet.", basedOn: "Today") }
        let left = d.waterTarget - d.water
        return AssistantReply(text: left > 0 ? "\(d.water) of \(d.waterTarget) glasses so far, \(left) to go." : "\(d.water) glasses today. Target reached.",
                              basedOn: "Today's water")
    }

    static func weight(_ s: IntelligenceSnapshot) -> AssistantReply {
        let points = s.lastDays(28).compactMap { d in d.weightKg.map { AssistantReply.ChartPoint(date: d.date, value: $0) } }
        guard let last = points.last else { return AssistantReply(text: "No weigh-ins in the last 4 weeks.", basedOn: "Last 4 weeks") }
        var text = String(format: "Latest weigh-in: %.1f kg on %@.", last.value, Fmt.shortDay(last.date, s.calendar))
        if let first = points.first, points.count >= 2 {
            let delta = last.value - first.value
            text += String(format: " %@ %.1f kg since %@.", delta <= 0 ? "Down" : "Up", abs(delta), Fmt.shortDay(first.date, s.calendar))
        }
        return AssistantReply(text: text, basedOn: "Your weigh-ins, last 4 weeks",
                              card: points.count >= 2 ? .chart(title: "Weight, last 4 weeks", points: points, goal: nil, unit: "kg") : .none)
    }
}
