import Foundation

/// A statement that might become a memory (F06 §5 `MemoryCandidate`).
nonisolated struct MemoryCandidate: Codable, Sendable, Hashable {
    var kind: MemoryRecord.Kind
    /// Second person, atomic: "You don't eat oats".
    var statement: String
    var facet: MemoryFacet?
    var confidence: Double
    var isUserStated: Bool
    var isSensitive: Bool
    var expiresAt: Date?
    var importance: Double

    init(kind: MemoryRecord.Kind, statement: String, facet: MemoryFacet? = nil, confidence: Double = 1,
         isUserStated: Bool = true, isSensitive: Bool = false, expiresAt: Date? = nil, importance: Double = 0.6) {
        self.kind = kind
        self.statement = statement
        self.facet = facet
        self.confidence = confidence
        self.isUserStated = isUserStated
        self.isSensitive = isSensitive
        self.expiresAt = expiresAt
        self.importance = importance
    }

    /// Sensitive statements are saved only after the user says yes (F06 §3).
    var needsConfirmation: Bool { isSensitive }
}

/// The user's command, when the turn is about memory itself (F06 §5.1).
nonisolated enum MemoryCommand: Sendable, Equatable {
    case remember([MemoryCandidate])
    case forget(query: String)
    case listAll
}

/// T0 memory extraction: the iPhone-15 path, and the candidate filter in front
/// of any model extractor (F06 §5). Extracts only durable facts the user
/// actually stated — habits, food preferences, diet, allergies, portions,
/// routines, goals with dates. Never infers health conditions; never stores
/// body-image judgments; strips anything that reads like an instruction.
nonisolated enum MemoryExtractor {

    // MARK: Commands

    static func command(in raw: String, now: Date = Date(), calendar: Calendar = .current) -> MemoryCommand? {
        let text = MemoryText.clean(raw)
        let lower = text.lowercased()
        if Rx.matches(#"^(what do you know about me|what do you remember( about me)?|what have you (learned|learnt) about me|show (me )?(my )?memor(y|ies))\b"#, lower) {
            return .listAll
        }
        if let rest = Rx.groups(#"^(?:please )?(?:forget|stop remembering|delete the memory)(?: that| about)?\s+(.+)$"#, lower)?.first {
            return .forget(query: rest.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)))
        }
        if let rest = Rx.groups(#"^(?:please )?(?:remember|note|keep in mind|don't forget)(?: that)?[:,]?\s+(.+)$"#, text)?.first {
            let found = extract(from: rest, now: now, calendar: calendar, explicit: true)
            return .remember(found)
        }
        return nil
    }

    // MARK: Extraction

    /// Durable facts in one user turn. `explicit` = the user said "remember …",
    /// so an unrecognised statement is still kept (as a plain fact).
    static func extract(from raw: String, now: Date = Date(), calendar: Calendar = .current,
                        explicit: Bool = false) -> [MemoryCandidate] {
        let sanitized = Safety.stripInstructions(MemoryText.clean(raw))
        guard !sanitized.isEmpty, !Safety.isBodyJudgment(sanitized) else { return [] }
        let lower = sanitized.lowercased()
        let expiry = Expiry.parse(lower, now: now, calendar: calendar)
        var out: [MemoryCandidate] = []

        if let sensitive = sensitiveCandidate(lower) { return [sensitive] }

        out += diet(lower)
        out += allergies(lower)
        let hasDiet = out.contains { if case .diet? = $0.facet { true } else { false } }
        out += avoids(lower, expiry: expiry, explicit: explicit).filter { candidate in
            // "I don't eat meat" is the diet, not a separate dislike.
            guard hasDiet, case .avoidsFood(let food)? = candidate.facet else { return true }
            return !["meat", "non veg", "non-veg", "nonveg"].contains(food)
        }
        out += likes(lower, explicit: explicit)
        out += unitSizes(lower)
        out += dishKcal(sanitized)
        out += training(lower)
        out += mealTimes(lower)
        out += preferences(lower)
        out += goals(sanitized, lower: lower, expiry: expiry, now: now, calendar: calendar)

        if out.isEmpty && explicit {
            // "Remember my sister is visiting" — keep what they said, in second person.
            let statement = MemoryText.sentence(Perspective.secondPerson(sanitized))
            guard statement.count >= 4 else { return [] }
            out.append(MemoryCandidate(kind: expiry == nil ? .fact : .goalContext, statement: statement,
                                       expiresAt: expiry, importance: 0.5))
        }
        // One statement per subject.
        var seen = Set<String>()
        return out.filter { seen.insert($0.facet?.subjectKey ?? $0.statement.lowercased()).inserted }
    }

    // MARK: Diet

    static func diet(_ t: String) -> [MemoryCandidate] {
        // Change of diet: "I eat chicken now", "started eating eggs", "not vegetarian anymore".
        if Rx.matches(#"\b(no longer|not) (a )?(vegetarian|veg)\b( any ?more)?|\bstopped being (vegetarian|vegan)"#, t)
            || Rx.matches(#"\b(now eat|started eating|have started eating) (chicken|meat|fish|mutton|non[ -]?veg)"#, t)
            || Rx.matches(#"\beat (chicken|meat|fish|mutton|non[ -]?veg)\w* now\b"#, t) {
            return [MemoryCandidate(kind: .fact, statement: "You eat non-vegetarian food", facet: .diet("non-vegetarian", exceptions: [], days: []),
                                    importance: 0.9)]
        }
        if Rx.matches(#"\b(started eating|now eat|eat) eggs( now)?\b"#, t), Rx.matches(#"\b(started|now)\b"#, t) {
            return [MemoryCandidate(kind: .fact, statement: "You're vegetarian but eat eggs", facet: .diet("eggetarian", exceptions: [], days: []),
                                    importance: 0.9)]
        }
        guard let g = Rx.groups(#"\bi(?:'m| am)\s+(?:a\s+)?(?:strict\s+|pure\s+|mostly\s+)?(vegetarian|vegan|eggetarian|pescatarian|jain|non[ -]?veg(?:etarian)?)\b"#, t),
              var diet = g.first else {
            if Rx.matches(#"\bi (?:don't|do not|dont|never) eat (?:any )?(?:meat|non[ -]?veg)\b"#, t) {
                return [MemoryCandidate(kind: .fact, statement: "You're vegetarian", facet: .diet("vegetarian", exceptions: [], days: []),
                                        importance: 0.9)]
            }
            return []
        }
        if diet.hasPrefix("non") { diet = "non-vegetarian" }
        var exceptions: [String] = []
        if let ex = Rx.groups(#"\b(?:except|but i eat|but eat|apart from|other than)\s+(eggs?|fish|seafood|chicken)"#, t)?.first {
            exceptions = [ex.hasPrefix("egg") ? "egg" : ex]
            if diet == "vegetarian" && ex.hasPrefix("egg") { diet = "eggetarian"; exceptions = [] }
        }
        let days = WeekdayParser.parse(t, requirePreposition: true)
        var statement: String
        switch diet {
        case "non-vegetarian": statement = "You eat non-vegetarian food"
        case "eggetarian": statement = "You're vegetarian but eat eggs"
        default: statement = "You're \(diet)"
        }
        if !exceptions.isEmpty { statement += " except \(exceptions.joined(separator: ", "))" }
        if !days.isEmpty { statement += " on \(WeekdayParser.names(days))" }
        return [MemoryCandidate(kind: .fact, statement: statement, facet: .diet(diet, exceptions: exceptions, days: days), importance: 0.9)]
    }

    // MARK: Allergies & intolerances (hard constraints)

    static func allergies(_ t: String) -> [MemoryCandidate] {
        var out: [MemoryCandidate] = []
        if let g = Rx.groups(#"\bi(?:'m| am| have been)? ?allergic to\s+([a-z ,&-]+?)(?:\.|$|,? so\b|,? and i\b)"#, t)?.first {
            for food in MemoryText.list(g) {
                out.append(MemoryCandidate(kind: .fact, statement: "You're allergic to \(food)", facet: .allergy(food), importance: 0.95))
            }
        }
        if let g = Rx.groups(#"\bi have (?:an? |a severe )?([a-z]+) allergy\b"#, t)?.first {
            out.append(MemoryCandidate(kind: .fact, statement: "You're allergic to \(g)", facet: .allergy(g), importance: 0.95))
        }
        if let g = Rx.groups(#"\bi(?:'m| am) (lactose|gluten) intolerant\b"#, t)?.first {
            out.append(MemoryCandidate(kind: .fact, statement: "You're \(g) intolerant", facet: .allergy(g), importance: 0.95))
        }
        return out
    }

    // MARK: Likes / dislikes

    static func avoids(_ t: String, expiry: Date?, explicit: Bool) -> [MemoryCandidate] {
        let patterns: [(String, Bool)] = [   // (regex, is a firm "don't eat" vs a dislike)
            (#"\bi (?:don't|do not|dont|never|can't|cannot|won't) (?:eat|have|drink|take)\s+(.+?)(?:\.|$| because| since| anymore| any more)"#, true),
            (#"\bi(?:'m| am) (?:off|avoiding|cutting out|quitting|giving up)\s+(.+?)(?:\.|$| this| for| till| until| because)"#, true),
            (#"\bi avoid\s+(.+?)(?:\.|$| because| this| for)"#, true),
            (#"\bno\s+(.+?)\s+for me\b"#, true),
            (#"\bi (?:hate|dislike|can't stand|cannot stand|don't like|do not like|dont like)\s+(.+?)(?:\.|$| because| at all)"#, false),
        ]
        for (pattern, firm) in patterns {
            guard let g = Rx.groups(pattern, t)?.first else { continue }
            let items = MemoryText.list(g).filter { explicit || FoodWords.isFoodish($0) }
            if items.isEmpty { continue }
            return items.map { food in
                let ingredient = FoodWords.ingredients.contains(food)
                let facet: MemoryFacet = ingredient ? .avoidsIngredient(food) : .avoidsFood(food)
                let statement: String
                if expiry != nil { statement = "You're off \(food)" + (Expiry.phrase(t).map { " \($0)" } ?? "") }
                else if firm { statement = "You don't eat \(food)" }
                else { statement = "You don't like \(food)" }
                return MemoryCandidate(kind: expiry != nil ? .goalContext : (firm ? .fact : .preference), statement: statement,
                                       facet: facet, expiresAt: expiry, importance: firm ? 0.8 : 0.6)
            }
        }
        return []
    }

    static func likes(_ t: String, explicit: Bool) -> [MemoryCandidate] {
        guard let g = Rx.groups(#"\b(?:i (?:really )?(?:love|like|enjoy|prefer)|my (?:favourite|favorite)(?: food| dish| snack| breakfast| meal)? is)\s+(.+?)(?:\.|$| because| for| but)"#, t)?.first else { return [] }
        // "I like short answers" is a preference, not a food.
        if g.contains("answer") || g.contains("repl") { return [] }
        let items = MemoryText.list(g).filter { explicit || FoodWords.isFoodish($0) }
        return items.map {
            MemoryCandidate(kind: .preference, statement: "You like \($0)", facet: .likesFood($0), importance: 0.5)
        }
    }

    // MARK: Portions (F04 hints)

    static func unitSizes(_ t: String) -> [MemoryCandidate] {
        guard let g = Rx.groups(#"\bmy (katori|bowl|cup|glass|mug|plate|tumbler|scoop|spoon|roti|chapati|chapatti|phulka|paratha|idli|dosa)s? (?:is|are|holds|hold|weighs|weigh|is about|is around)?\s*(?:about|around|roughly|approx(?:imately)?|~)?\s*(\d+(?:\.\d+)?)\s*(ml|g|gm|gms|grams?)\b"#, t),
              g.count == 3, let amount = Double(g[1]), amount > 0, amount <= 2_000 else { return [] }
        var unit = g[0]
        if ["chapati", "chapatti", "phulka"].contains(unit) { unit = "roti" }
        let measure = g[2].hasPrefix("m") ? "ml" : "g"
        let verb = ["katori", "bowl", "cup", "glass", "mug", "tumbler", "scoop", "spoon", "plate"].contains(unit) ? "holds" : "weighs"
        return [MemoryCandidate(kind: .foodFact, statement: "Your \(unit) \(verb) about \(MemoryText.number(amount)) \(measure)",
                                facet: .unitSize(unit: unit, grams: amount), importance: 0.7)]
    }

    static func dishKcal(_ original: String) -> [MemoryCandidate] {
        let t = original.lowercased()
        guard let g = Rx.groups(#"^(?:i think |fyi |so )?(.{3,40}?)\s+(?:is|has|comes to|=)\s*(?:about|around|roughly|approx(?:imately)?|~)?\s*(\d{2,4})\s*(?:kcal|cal|cals|calories)\s+(?:per|a|each|for one|for 1|for a)\s+(katori|bowl|piece|plate|cup|glass|serving|roti|slice|scoop|packet)\b"#, t),
              g.count == 3, let kcal = Double(g[1]), kcal > 0 else { return [] }
        var dish = g[0].trimmingCharacters(in: .whitespaces)
        for lead in ["my ", "our ", "the "] where dish.hasPrefix(lead) { dish = String(dish.dropFirst(lead.count)) }
        guard FoodWords.isFoodish(dish) || dish.contains("'s ") || dish.contains("’s ") else { return [] }
        let unit = g[2]
        return [MemoryCandidate(kind: .foodFact, statement: "\(MemoryText.capitalisedFirst(dish)) is about \(MemoryText.number(kcal)) kcal per \(unit)",
                                facet: .dishKcal(dish: dish, kcal: kcal, unit: unit), importance: 0.7)]
    }

    // MARK: Routines

    static func training(_ t: String) -> [MemoryCandidate] {
        let focusWords = ["leg", "legs", "chest", "back", "arm", "arms", "shoulder", "shoulders", "push", "pull", "cardio", "upper body", "lower body", "core", "yoga", "run", "running", "swim", "swimming"]
        guard Rx.matches(#"\b(gym|train|training|workout|work out|lift|lifting|run|running|yoga|swim|day is|day on|days are|leg day|chest day|back day|arm day|cardio)\b"#, t),
              !Rx.matches(#"\b(today|yesterday|tonight|this morning|last night)\b"#, t) || Rx.matches(#"\bevery\b"#, t) else { return [] }
        var days = WeekdayParser.parse(t, requirePreposition: false)
        if days.isEmpty, Rx.matches(#"\bevery ?day\b|\bdaily\b"#, t) { days = Array(1...7) }
        if days.isEmpty, Rx.matches(#"\bweekdays\b"#, t) { days = [2, 3, 4, 5, 6] }
        guard !days.isEmpty else { return [] }
        let focus = focusWords.first { Rx.matches("\\b\($0)( day)?\\b", t) && ($0 != "run" || !t.contains("gym")) }
            .map { $0.hasSuffix("s") && $0 != "legs" && $0 != "arms" ? String($0) : $0 }
            .map { ["legs": "leg", "arms": "arm", "shoulders": "shoulder", "running": "run", "swimming": "swim"][$0] ?? $0 }
        let what = focus.map { ["run": "You run", "swim": "You swim", "yoga": "Yoga", "cardio": "Cardio"][$0] ?? "\(MemoryText.capitalisedFirst($0)) day" } ?? "You train"
        let joiner = focus == nil || focus == "run" || focus == "swim" ? " on " : " is on "
        return [MemoryCandidate(kind: .routine, statement: what + joiner + WeekdayParser.names(days), facet: .trainingDays(days, focus: focus),
                                importance: 0.6)]
    }

    static func mealTimes(_ t: String) -> [MemoryCandidate] {
        // Present-tense habits only: "I usually have lunch at 1:30", "dinner is around 9".
        guard !Rx.matches(#"\b(had|ate|was|yesterday|today)\b"#, t) else { return [] }
        let pattern = #"\b(?:i (?:usually |normally |always |generally )?(?:have|eat) (?:my )?)?(breakfast|lunch|dinner)(?: is)? (?:usually |normally |always |generally )?(?:at|around|by|after|about) (\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)?"#
        guard let g = Rx.groups(pattern, t), g.count == 4, var hour = Int(g[1]),
              Rx.matches(#"\b(usually|normally|always|generally|every day|daily|is at|is around|is by)\b"#, t) || t.hasPrefix("i have") || t.hasPrefix("i eat") else { return [] }
        let minute = Int(g[2]) ?? 0
        let slot = ParsedMeal.MealSlot(rawValue: g[0]) ?? .unknown
        let ampm = g[3]
        if ampm == "pm", hour < 12 { hour += 12 }
        if ampm == "am", hour == 12 { hour = 0 }
        if ampm.isEmpty {   // "lunch at 2" → 14:00, "dinner at 9" → 21:00
            if (slot == .lunch && hour < 6) || (slot == .dinner && hour < 12) { hour += 12 }
        }
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return [] }
        let minutes = hour * 60 + minute
        return [MemoryCandidate(kind: .routine, statement: "\(MemoryText.capitalisedFirst(slot.rawValue)) is usually around \(ClockText.text(minutes))",
                                facet: .mealTime(slot: slot, minutes: minutes), importance: 0.5)]
    }

    // MARK: Preferences

    static func preferences(_ t: String) -> [MemoryCandidate] {
        var out: [MemoryCandidate] = []
        if let g = Rx.groups(#"\bno (?:notifications|reminders|nudges|pings|alerts) (?:before|until|till) (\d{1,2})\s*(am|pm)?"#, t),
           var hour = Int(g[0]) {
            if g.count > 1, g[1] == "pm", hour < 12 { hour += 12 }
            out.append(MemoryCandidate(kind: .preference, statement: "No notifications before \(ClockText.text(hour * 60))",
                                       facet: .quietBefore(hour: hour), importance: 0.7))
        }
        if Rx.matches(#"\b(keep|make) (?:your |the )?(?:answers|replies|responses|it) (short|brief)|\bshort answers\b|\bbe brief\b"#, t) {
            out.append(MemoryCandidate(kind: .preference, statement: "Prefers short answers", facet: .answerStyle("brief"), importance: 0.6))
        }
        if Rx.matches(#"\b(use|prefer) hindi (?:dish |food )?names\b"#, t) {
            out.append(MemoryCandidate(kind: .preference, statement: "Prefers Hindi dish names", facet: .answerStyle("hindi dish names"), importance: 0.5))
        }
        if Rx.matches(#"\b(no|don't give me|stop the|without) (calorie )?lectures\b|\bdon't lecture me\b|\bprotein tips\b"#, t) {
            out.append(MemoryCandidate(kind: .preference, statement: "Wants practical tips, not lectures", facet: .answerStyle("no lectures"), importance: 0.6))
        }
        return out
    }

    // MARK: Goals with dates

    static func goals(_ original: String, lower t: String, expiry: Date?, now: Date, calendar: Calendar) -> [MemoryCandidate] {
        if let g = Rx.groups(#"\bi(?:'m| am) (?:training|preparing|prepping|getting ready) for (?:a |an |the |my )?(.+?)(?:\s+(?:in|on|by|this|next)\s+(.+?))?(?:\.|$)"#, t)?.first {
            let goal = g.trimmingCharacters(in: .whitespaces)
            let until = expiry ?? calendar.date(byAdding: .month, value: 3, to: now)
            let when = Expiry.phrase(t).map { " \($0)" } ?? ""
            return [MemoryCandidate(kind: .goalContext, statement: "You're training for \(MemoryText.article(goal))\(goal)\(when)", facet: .goal(goal),
                                    expiresAt: until, importance: 0.7)]
        }
        if let g = Rx.groups(#"\bi(?:'m| am) (?:on (?:a )?(holiday|vacation|leave|trip)|travell?ing|fasting)\b"#, t), let expiry {
            let what = g.first.map { $0.isEmpty ? (t.contains("fasting") ? "fasting" : "travelling") : "on \($0)" } ?? "away"
            return [MemoryCandidate(kind: .goalContext, statement: "You're \(what)" + (Expiry.phrase(t).map { " \($0)" } ?? ""),
                                    facet: .goal(what), expiresAt: expiry, importance: 0.6)]
        }
        return []
    }

    // MARK: Sensitive (confirm before saving; never inferred)

    static func sensitiveCandidate(_ t: String) -> MemoryCandidate? {
        let conditions = "diabetes|diabetic|prediabetes|prediabetic|pcos|pcod|thyroid|hypothyroid|hyperthyroid|hypertension|high blood pressure|high bp|cholesterol|fatty liver|celiac|coeliac|ibs|gerd|acid reflux|kidney disease|heart disease|asthma|anaemia|anemia|depression|anxiety|gout|migraine|arthritis"
        if let g = Rx.groups("\\bi (?:have|got|was diagnosed with|suffer from|am being treated for)\\s+(?:type ?[12] )?(\(conditions))\\b", t)?.first
            ?? Rx.groups("\\bi(?:'m| am) (pregnant|breastfeeding|nursing|diabetic|prediabetic|anaemic|anemic)\\b", t)?.first {
            let statement: String
            if ["pregnant", "breastfeeding", "nursing", "diabetic", "prediabetic", "anaemic", "anemic"].contains(g) { statement = "You're \(g)" }
            else { statement = "You have \(["pcos": "PCOS", "pcod": "PCOD", "ibs": "IBS", "gerd": "GERD"][g] ?? g)" }
            return MemoryCandidate(kind: .fact, statement: statement, isSensitive: true, importance: 0.9)
        }
        if let g = Rx.groups(#"\bi(?: take| am on|'m on| started taking) (metformin|insulin|thyroxine|thyronorm|eltroxin|ozempic|semaglutide|mounjaro|tirzepatide|statins?|blood pressure (?:medicine|tablets|pills)|thyroid (?:medicine|tablets|pills))\b"#, t)?.first {
            return MemoryCandidate(kind: .fact, statement: "You take \(g)", isSensitive: true, importance: 0.9)
        }
        return nil
    }
}

// MARK: - Safety helpers

extension MemoryExtractor {
    nonisolated enum Safety {
        /// Removes sentences that read like instructions to the assistant (F06 §9).
        static func stripInstructions(_ text: String) -> String {
            let sentences = text.split(whereSeparator: { ".!?\n".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }
            let kept = sentences.filter { s in
                !Rx.matches(#"\b(ignore|disregard|forget) (all |any |the |your |previous |prior |above )*(instructions|rules|prompt|context)|\bsystem prompt\b|\byou are now\b|\byou must\b|\bact as\b|\bfrom now on (you|always)\b|\balways (reply|respond|answer|say)\b|\bnew instructions\b|\bdeveloper mode\b"#, s.lowercased())
            }
            return kept.joined(separator: ". ")
        }

        /// Health conditions, medicines, pregnancy, eating disorders: text that must
        /// stay on device (never in a third-party packet or chat history).
        static func mentionsHealth(_ text: String) -> Bool {
            let t = " " + text.lowercased() + " "
            if sensitiveCandidate(t) != nil { return true }
            return Rx.matches(#"\b(diabet\w*|pcos|pcod|thyroid|hypertension|blood pressure|cholesterol|pregnan\w*|breastfeed\w*|metformin|insulin|ozempic|semaglutide|mounjaro|medication|eating disorder|anorexi\w*|bulimi\w*|binge eating|depression|celiac|coeliac)\b"#, t)
        }

        /// Body-image judgments and restriction rules are never memories (F06 §9).
        static func isBodyJudgment(_ text: String) -> Bool {
            Rx.matches(#"\bi(?:'m| am| look| feel) (?:so |really |too |very )?(fat|ugly|disgusting|gross|huge|obese|worthless)\b|\bhate my body\b|\b(starve|starving) myself\b|\bshould(n't| not)? (eat|be allowed)\b.*\b(punish|deserve)\b|\b(purge|purging|throw up after)\b"#, text.lowercased())
        }
    }
}

// MARK: - Text utilities

nonisolated enum Rx {
    static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    static func matches(_ pattern: String, _ text: String) -> Bool {
        guard let re = regex(pattern) else { return false }
        return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Capture groups of the first match ("" for groups that didn't participate).
    static func groups(_ pattern: String, _ text: String) -> [String]? {
        guard let re = regex(pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        guard m.numberOfRanges > 1 else { return [] }
        return (1..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }

    /// Every match's capture groups.
    static func allGroups(_ pattern: String, _ text: String) -> [[String]] {
        guard let re = regex(pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
            (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } ?? "" }
        }
    }
}

nonisolated enum MemoryText {
    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "oats, maida and white sugar" → ["oats", "maida", "white sugar"].
    static func list(_ s: String) -> [String] {
        s.replacingOccurrences(of: " and ", with: ",").replacingOccurrences(of: " or ", with: ",")
            .replacingOccurrences(of: " & ", with: ",").replacingOccurrences(of: "/", with: ",")
            .split(separator: ",")
            .map { item -> String in
                var w = item.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
                for lead in ["any ", "the ", "a ", "an ", "much ", "too much ", "more ", "eating ", "having ", "drinking "] where w.hasPrefix(lead) {
                    w = String(w.dropFirst(lead.count))
                }
                for tail in [" at all", " anymore", " any more", " now", " please"] where w.hasSuffix(tail) {
                    w = String(w.dropLast(tail.count))
                }
                return w
            }
            .filter { !$0.isEmpty && $0.count <= 30 && $0.split(separator: " ").count <= 4 }
    }

    static func capitalisedFirst(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    static func sentence(_ s: String) -> String {
        capitalisedFirst(s.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".!"))))
    }

    static func number(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
    }

    static func article(_ noun: String) -> String {
        if noun.hasPrefix("my ") || noun.hasPrefix("the ") { return "" }
        if let d = noun.first, d.isNumber { return noun.hasPrefix("8") || noun.hasPrefix("11") || noun.hasPrefix("18") ? "an " : "a " }
        return "aeiou".contains(noun.prefix(1).lowercased()) ? "an " : "a "
    }
}

/// First person → second person, word by word.
nonisolated enum Perspective {
    static func secondPerson(_ s: String) -> String {
        let map: [String: String] = ["i'm": "you're", "i": "you", "my": "your", "me": "you", "mine": "yours",
                                     "myself": "yourself", "i've": "you've", "i'd": "you'd", "i'll": "you'll", "we": "you", "our": "your"]
        var out: [String] = []
        var previous = ""
        for raw in s.split(separator: " ", omittingEmptySubsequences: true) {
            var word = String(raw)
            var trailing = ""
            while let last = word.last, last.isPunctuation, last != "'" {
                trailing = String(last) + trailing
                word.removeLast()
            }
            let key = word.lowercased()
            var replacement = map[key] ?? word
            if key == "am" && previous == "i" { replacement = "are" }
            if key == "was" && previous == "i" { replacement = "were" }
            out.append(replacement + trailing)
            previous = key
        }
        return out.joined(separator: " ")
    }
}

nonisolated enum WeekdayParser {
    static let keys: [(prefix: String, day: Int)] = [("sun", 1), ("mon", 2), ("tue", 3), ("wed", 4), ("thu", 5), ("fri", 6), ("sat", 7)]

    /// WeekdayParser (1 = Sunday) named in the text. `requirePreposition` only counts
    /// "on Tuesdays"-style mentions (so "Monday I ate…" doesn't make a diet rule).
    static func parse(_ t: String, requirePreposition: Bool) -> [Int] {
        let scope: String
        if requirePreposition {
            guard let g = Rx.groups(#"\b(?:on|every)\s+((?:(?:sun|mon|tue|tues|wed|thu|thur|thurs|fri|sat)[a-z]*(?:\s*(?:,|and|&|or)?\s*)?)+)"#, t)?.first else { return [] }
            scope = g
        } else {
            scope = t
        }
        var days: [Int] = []
        for m in Rx.allGroups(#"\b(sun|mon|tue|wed|thu|fri|sat)(?:day|days|s|\.)?\b|\b(tues|thur|thurs)(?:day|days)?\b"#, scope) {
            let token = (m.count > 1 && !m[1].isEmpty ? m[1] : (m.count > 2 ? m[2] : "")).lowercased()
            if let d = keys.first(where: { token.hasPrefix($0.prefix) })?.day, !days.contains(d) { days.append(d) }
        }
        return days.sorted { mondayIndex($0) < mondayIndex($1) }
    }

    static func mondayIndex(_ weekday: Int) -> Int { (weekday + 5) % 7 }

    static func names(_ days: [Int]) -> String {
        let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        if Set(days) == Set(1...7) { return "every day" }
        if Set(days) == Set([2, 3, 4, 5, 6]) { return "weekdays" }
        let names = days.sorted { mondayIndex($0) < mondayIndex($1) }.map { symbols[$0 - 1] }
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
}

nonisolated enum ClockText {
    static func text(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return m == 0 ? "\(h12) \(h < 12 ? "am" : "pm")" : String(format: "%d:%02d %@", h12, m, h < 12 ? "am" : "pm")
    }
}

/// "this month", "till Sunday", "for 2 weeks", "in December" → an expiry date.
nonisolated enum Expiry {
    static func parse(_ t: String, now: Date, calendar: Calendar) -> Date? {
        let sod = calendar.startOfDay(for: now)
        func endOfDay(_ d: Date) -> Date { calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: d)) ?? d }
        if Rx.matches(#"\b(today|tonight)\b"#, t) { return endOfDay(now) }
        if Rx.matches(#"\bthis week\b"#, t) {
            let weekday = calendar.component(.weekday, from: now)      // Sunday = 1 → week ends Sunday
            let toSunday = (8 - weekday) % 7
            return calendar.date(byAdding: .day, value: toSunday, to: sod).map(endOfDay)
        }
        if Rx.matches(#"\bthis month\b"#, t) {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? sod
            return calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start)
        }
        if let g = Rx.groups(#"\bfor (?:the next )?(\d+|a|one|two|three|four) (day|week|month)s?\b"#, t), g.count == 2 {
            let n = ["a": 1, "one": 1, "two": 2, "three": 3, "four": 4][g[0]] ?? Int(g[0]) ?? 1
            let unit: Calendar.Component = g[1] == "day" ? .day : g[1] == "week" ? .weekOfYear : .month
            return calendar.date(byAdding: unit, value: n, to: now)
        }
        if let g = Rx.groups(#"\b(?:till|until|untill|upto|up to|through) (sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#, t)?.first,
           let target = WeekdayParser.keys.first(where: { g.hasPrefix($0.prefix) })?.day {
            let weekday = calendar.component(.weekday, from: now)
            var ahead = (target - weekday + 7) % 7
            if ahead == 0 { ahead = 7 }
            return calendar.date(byAdding: .day, value: ahead, to: sod).map(endOfDay)
        }
        let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        if let g = Rx.groups(#"\b(?:in|by|till|until|this|next) (january|february|march|april|may|june|july|august|september|october|november|december)\b"#, t)?.first,
           let index = months.firstIndex(of: g) {
            let month = index + 1
            let current = calendar.component(.month, from: now)
            var year = calendar.component(.year, from: now)
            if month < current { year += 1 }
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
            return calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start)
        }
        return nil
    }

    static func capitaliseNames(_ phrase: String) -> String {
        let names = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november",
                     "december", "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        return phrase.split(separator: " ").map { names.contains(String($0)) ? MemoryText.capitalisedFirst(String($0)) : String($0) }
            .joined(separator: " ")
    }

    /// The human phrase that set the expiry, for the statement ("this month").
    static func phrase(_ t: String) -> String? {
        for pattern in [#"\b(this (?:week|month))\b"#, #"\b(for (?:the next )?(?:\d+|a|one|two|three|four) (?:day|week|month)s?)\b"#,
                        #"\b((?:till|until) (?:sunday|monday|tuesday|wednesday|thursday|friday|saturday))\b"#,
                        #"\b((?:in|by) (?:january|february|march|april|may|june|july|august|september|october|november|december))\b"#] {
            if let g = Rx.groups(pattern, t)?.first { return capitaliseNames(g) }
        }
        return nil
    }
}

/// Is this word about food? (So "I hate Mondays" never becomes a food dislike.)
nonisolated enum FoodWords {
    static let ingredients: Set<String> = ["sugar", "salt", "oil", "onion", "garlic", "onion garlic", "gluten", "dairy", "caffeine",
                                           "maida", "refined flour", "white rice", "fried food", "junk food", "sweets", "dessert",
                                           "desserts", "alcohol", "soda", "soft drinks", "spicy food", "carbs", "red meat", "processed food"]
    static let extra: Set<String> = ["meat", "non veg", "non-veg", "seafood", "beef", "pork", "chicken", "mutton", "fish", "egg", "eggs",
                                     "mushroom", "mushrooms", "brinjal", "baingan", "karela", "bitter gourd", "lauki", "tofu", "coffee",
                                     "tea", "chai", "milk", "nuts", "peanuts", "beer", "wine", "whiskey", "spicy", "coriander", "capsicum",
                                     "okra", "bhindi", "cauliflower", "gobi", "cabbage", "beans", "lentils", "rajma", "chole", "oats",
                                     "pineapple", "papaya", "mango", "banana", "avocado", "olives", "cheese", "paneer", "curd", "ghee"]

    static func isFoodish(_ phrase: String) -> Bool {
        let p = phrase.lowercased()
        if ingredients.contains(p) || extra.contains(p) || DietRules.meat.contains(p) || DietRules.seafood.contains(p)
            || DietRules.egg.contains(p) || DietRules.dairy.contains(p) { return true }
        let key = FoodNameNormalizer.normalise(p)
        if FoodCatalog.index[key] != nil { return true }
        if NutritionResolver().matchCatalog(key) != nil, key.count >= 4 { return true }
        return p.split(separator: " ").contains { ingredients.contains(String($0)) || extra.contains(String($0)) }
    }
}
