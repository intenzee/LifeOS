import Foundation

/// One thing LifeOS knows about the user (Phase 4 §4.2 "What LifeOS knows").
nonisolated struct MemoryItem: Identifiable, Equatable, Sendable, Codable {
    nonisolated enum Category: String, CaseIterable, Sendable, Codable {
        case aboutYou, foodHabits, preferences, routines, insights, photoCorrections

        var title: String {
            switch self {
            case .aboutYou: return "About you"
            case .foodHabits: return "Food habits"
            case .preferences: return "Preferences"
            case .routines: return "Routines"
            case .insights: return "Insights"
            case .photoCorrections: return "Photo corrections"
            }
        }
    }

    nonisolated enum Source: String, Sendable, Codable {
        case youSaid, fromLogs, learned, correction

        var label: String {
            switch self {
            case .youSaid: return "You said"
            case .fromLogs: return "From your logs"
            case .learned: return "Learned from your data"
            case .correction: return "Your correction"
            }
        }
    }

    var id: String
    var text: String
    var category: Category
    var source: Source
    var createdAt: Date
    var isPinned: Bool = false
    /// "likely" for inferred items; nil for things the user said.
    var confidenceWord: String? = nil
    /// How many assistant answers used this memory.
    var usedCount: Int = 0
    /// Supporting detail, e.g. "Seen 9 of the last 14 days".
    var evidence: String? = nil

    var isInferred: Bool { source == .fromLogs || source == .learned }
}

nonisolated enum MemoryPhrases {
    /// "remember that I'm vegetarian" → "You're vegetarian". Returns nil when the
    /// sentence is not a remember request.
    static func rememberedText(from sentence: String) -> String? {
        let lower = sentence.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let leads = ["please remember that ", "please remember ", "remember that ", "remember ", "note that ", "keep in mind that ", "keep in mind "]
        guard let lead = leads.first(where: { lower.hasPrefix($0) }) else { return nil }
        let body = String(sentence.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(lead.count))
        let text = secondPerson(body).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".!")))
        return text.isEmpty ? nil : text.prefix(1).uppercased() + text.dropFirst()
    }

    /// First person → second person, word by word ("I'm" → "you're", "my" → "your").
    static func secondPerson(_ s: String) -> String {
        let map: [String: String] = [
            "i'm": "you're", "i’m": "you're", "i": "you", "my": "your", "me": "you", "mine": "yours",
            "myself": "yourself", "i've": "you've", "i'd": "you'd", "i'll": "you'll",
        ]
        var out: [String] = []
        var previous = ""
        for raw in s.split(separator: " ", omittingEmptySubsequences: true) {
            var word = String(raw)
            var trailing = ""
            while let last = word.last, last.isPunctuation, last != "'", last != "’" {
                trailing = String(last) + trailing
                word.removeLast()
            }
            let key = word.lowercased()
            var replacement = map[key] ?? word
            if key == "am" && previous == "i" { replacement = "are" } // "I am" → "you are"
            out.append(replacement + trailing)
            previous = key
        }
        return out.joined(separator: " ")
    }

    static func category(for text: String) -> MemoryItem.Category {
        let t = text.lowercased()
        if ["prefer", "don't like", "do not like", "no notifications", "short answers", "notify", "remind", "hate", "love"].contains(where: t.contains) {
            return .preferences
        }
        if ["gym", "train", "workout", "run ", "walk", "every ", "mondays", "weekdays", "wake", "sleep"].contains(where: t.contains) {
            return .routines
        }
        if ["eat", "breakfast", "lunch", "dinner", "snack", "vegetarian", "vegan", "allergic", "allergy", "lactose", "gluten", "egg", "chicken", "spicy"].contains(where: t.contains) {
            return .foodHabits
        }
        return .aboutYou
    }

    /// Health conditions, medicines, pregnancy: never saved without a "Remember" tap.
    static func isSensitive(_ text: String) -> Bool {
        let t = " " + text.lowercased() + " "
        let words = ["diabet", "pcos", "pcod", "thyroid", "blood pressure", "hypertension", "cholesterol", "pregnan", "breastfeed",
                     "medication", "medicine", "metformin", "insulin", "ozempic", "semaglutide", "mounjaro", "depress", "anxiety",
                     "celiac", "coeliac", " ibs ", "kidney", "heart disease", "asthma", "cancer", "fatty liver", "anaemi", "anemi",
                     "eating disorder", "anorex", "bulimi", "binge", "allerg"]
        return words.contains { t.contains($0) }
    }

    /// Food words a memory forbids ("vegetarian" rules out chicken etc.) — used to keep suggestions in lane.
    static func excludedFoods(_ memories: [MemoryItem]) -> Set<String> {
        let all = memories.map { $0.text.lowercased() }.joined(separator: " ")
        var out = Set<String>()
        if all.contains("vegetarian") || all.contains("vegan") {
            out.formUnion(["chicken", "fish", "mutton", "beef", "pork", "prawn", "shrimp", "bacon", "steak", "egg curry"])
        }
        if all.contains("vegan") { out.formUnion(["egg", "milk", "curd", "paneer", "lassi", "raita", "cheese", "yogurt"]) }
        if all.contains("no egg") || all.contains("don't eat egg") { out.insert("egg") }
        return out
    }
}

/// Memories inferred from the user's own logs (Phase 4 §4.2 "From your logs").
nonisolated enum MemoryInference {
    static func infer(from snapshot: IntelligenceSnapshot) -> [MemoryItem] {
        var out: [MemoryItem] = []
        let cal = snapshot.calendar
        let recent = snapshot.lastDays(14)

        // Usual meal per slot: the same food on at least 4 of the last 14 days.
        for slot in ExperienceMealSlot.allCases {
            var counts: [String: (name: String, days: Set<Date>, kcal: Double, hours: [Int])] = [:]
            for day in recent {
                for m in day.meals where m.slot == slot {
                    let key = ExperienceFoodResolver.normalize(m.name)
                    var e = counts[key] ?? (m.name, [], m.kcal, [])
                    e.days.insert(day.date)
                    e.hours.append(cal.component(.hour, from: m.time))
                    counts[key] = e
                }
            }
            if let top = counts.values.filter({ $0.days.count >= 4 }).max(by: { $0.days.count < $1.days.count }) {
                let hour = top.hours.sorted()[top.hours.count / 2]
                out.append(MemoryItem(id: "usual.\(slot.rawValue)", text: "Usual \(slot.title.lowercased()) is \(top.name) (\(Int(top.kcal)) kcal), usually around \(hourText(hour))",
                                      category: .foodHabits, source: .fromLogs, createdAt: snapshot.now, confidenceWord: "likely",
                                      evidence: "Logged on \(top.days.count) of the last 14 days"))
            }
        }

        // Training days: weekdays trained in at least 3 of the last 4 weeks.
        let month = snapshot.lastDays(28)
        var byWeekday: [Int: Int] = [:]
        for d in month where d.trained { byWeekday[cal.component(.weekday, from: d.date), default: 0] += 1 }
        let gymDays = byWeekday.filter { $0.value >= 3 }.keys.sorted { mondayIndex($0) < mondayIndex($1) }
        if !gymDays.isEmpty {
            let names = gymDays.map { cal.shortWeekdaySymbols[$0 - 1] }
            out.append(MemoryItem(id: "routine.gym", text: "Gym on \(names.joined(separator: ", "))", category: .routines, source: .fromLogs,
                                  createdAt: snapshot.now, confidenceWord: "likely", evidence: "Trained on these days in at least 3 of the last 4 weeks"))
        }

        // Weekend vs weekday intake, with at least 2 logged weekend days and 4 weekdays.
        // Today is still in progress, so it never counts towards a pattern.
        let logged = month.filter { $0.hasFood && !cal.isDate($0.date, inSameDayAs: snapshot.now) }
        let weekend = logged.filter { cal.isDateInWeekend($0.date) }.map(\.kcal)
        let weekday = logged.filter { !cal.isDateInWeekend($0.date) }.map(\.kcal)
        if weekend.count >= 2, weekday.count >= 4 {
            let diff = Fmt.avg(weekend) - Fmt.avg(weekday)
            if abs(diff) >= 200 {
                let rounded = Int((abs(diff) / 50).rounded() * 50)
                out.append(MemoryItem(id: "insight.weekend", text: "Weekend intake runs about \(rounded) kcal \(diff > 0 ? "higher" : "lower") than weekdays",
                                      category: .insights, source: .learned, createdAt: snapshot.now, confidenceWord: "likely",
                                      evidence: "Learned from \(max(1, month.count / 7)) weeks of data"))
            }
        }
        return out
    }

    static func hourText(_ h: Int) -> String {
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12) \(h < 12 ? "am" : "pm")"
    }

    /// Calendar weekday (1 = Sunday) → Monday-first index.
    static func mondayIndex(_ weekday: Int) -> Int { (weekday + 5) % 7 }
}
