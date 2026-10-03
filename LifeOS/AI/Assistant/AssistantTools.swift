import Foundation

// MARK: - Tool catalogue (F07 §3, AI-302)

nonisolated enum AssistantToolName: String, Sendable, Codable, CaseIterable {
    case logFood, logPreset, logWater, logWeight
    case addTodo, updateTodo, completeTodo, scheduleReminder
    case queryStats, getTodayStatus, listPresets, createPreset, explainBudget, searchFoodLog
    case rememberFact, forgetFact, listMemories
}

/// What the user sees before or after a write (F07 §3 "Confirmation").
nonisolated enum ToolConfirmation: String, Sendable {
    case none           // reads
    case undo           // done at once, Undo for at least 8 s
    case confirmCard    // shown first; saved only on "Yes"
}

nonisolated struct AssistantToolSpec: Sendable {
    var name: AssistantToolName
    var summary: String
    var arguments: [AISchemaProperty]
    var confirmation: ToolConfirmation
    var isWrite: Bool { confirmation != .none }

    /// One line per tool for the planner prompt.
    var promptLine: String {
        let args = arguments.map { "\($0.name)\($0.isOptional ? "?" : ""): \($0.schema.typeName)" + ($0.description.map { " (\($0))" } ?? "") }
        return "- \(name.rawValue)(\(args.joined(separator: ", "))): \(summary)"
    }
}

nonisolated enum AssistantTools {
    static let metrics = ["kcal", "protein", "water", "weight", "workouts", "steps", "sleep"]
    static let ranges = ["today", "yesterday", "thisWeek", "lastWeek", "last7", "last30", "thisMonth"]

    /// Destructive actions (delete logs, forget everything) are deliberately
    /// absent: they route the user to the UI (F07 §3 rules).
    static let all: [AssistantToolSpec] = [
        .init(name: .logFood, summary: "draft a food log from the user's words for them to confirm",
              arguments: [.init("text", .string(), description: "what they ate, in their words"),
                          .init("meal", .string(choices: ["breakfast", "lunch", "dinner", "snacks"]), optional: true)],
              confirmation: .confirmCard),
        .init(name: .logPreset, summary: "log a saved preset by name",
              arguments: [.init("name", .string()), .init("modifications", .string(), description: "e.g. no curd", optional: true)],
              confirmation: .undo),
        .init(name: .logWater, summary: "add water",
              arguments: [.init("glasses", .number(minimum: 0.5, maximum: 12), optional: true),
                          .init("ml", .number(minimum: 50, maximum: 5_000), optional: true)],
              confirmation: .undo),
        .init(name: .logWeight, summary: "record today's weight",
              arguments: [.init("value", .number(minimum: 20, maximum: 900)), .init("unit", .string(choices: ["kg", "lb"]))],
              confirmation: .undo),
        .init(name: .addTodo, summary: "add a one-off todo, optionally with a time reminder",
              arguments: [.init("title", .string()), .init("due", .string(), description: "HH:mm today, or 'tomorrow HH:mm'", optional: true)],
              confirmation: .undo),
        .init(name: .updateTodo, summary: "move a todo to a new time",
              arguments: [.init("query", .string(), description: "words from the todo title"), .init("due", .string())],
              confirmation: .undo),
        .init(name: .completeTodo, summary: "mark a todo done",
              arguments: [.init("query", .string())], confirmation: .undo),
        .init(name: .scheduleReminder, summary: "a repeating reminder (every N hours, daily at a time)",
              arguments: [.init("text", .string(), description: "the reminder in the user's words")],
              confirmation: .confirmCard),
        .init(name: .queryStats, summary: "numbers from the user's own logs",
              arguments: [.init("metric", .string(choices: metrics)), .init("range", .string(choices: ranges)),
                          .init("aggregation", .string(choices: ["average", "total", "max", "min", "count", "compare"]), optional: true)],
              confirmation: .none),
        .init(name: .getTodayStatus, summary: "today's budget, intake, macros, water and workouts", arguments: [], confirmation: .none),
        .init(name: .listPresets, summary: "the user's saved presets with kcal", arguments: [], confirmation: .none),
        .init(name: .createPreset, summary: "save a named preset from listed items",
              arguments: [.init("name", .string()), .init("items", .string(), description: "comma-separated foods with amounts")],
              confirmation: .confirmCard),
        .init(name: .explainBudget, summary: "why today's calorie target is what it is", arguments: [], confirmation: .none),
        .init(name: .searchFoodLog, summary: "find what the user ate on a day or when they last had a food",
              arguments: [.init("query", .string(), description: "a food, or empty for everything", optional: true),
                          .init("date", .string(), description: "yyyy-MM-dd, 'yesterday', or a weekday name", optional: true)],
              confirmation: .none),
        .init(name: .rememberFact, summary: "save something the user wants remembered",
              arguments: [.init("statement", .string())], confirmation: .undo),
        .init(name: .forgetFact, summary: "find memories to forget (the user confirms)",
              arguments: [.init("query", .string())], confirmation: .confirmCard),
        .init(name: .listMemories, summary: "what LifeOS knows about the user", arguments: [], confirmation: .none),
    ]

    static func spec(_ name: AssistantToolName) -> AssistantToolSpec { all.first { $0.name == name }! }

    /// The catalogue as the planner sees it.
    static var promptCatalogue: String { all.map(\.promptLine).joined(separator: "\n") }
}

nonisolated struct ToolCall: Sendable, Codable, Hashable {
    var name: AssistantToolName
    var arguments: [String: String]

    init(_ name: AssistantToolName, _ arguments: [String: String] = [:]) {
        self.name = name
        self.arguments = arguments
    }

    subscript(key: String) -> String? { arguments[key].flatMap { $0.isEmpty ? nil : $0 } }
    func number(_ key: String) -> Double? { self[key].flatMap { Double($0.replacingOccurrences(of: ",", with: "")) } }
}

// MARK: - Actions (what the app executes)

/// A write the app performs through its stores (IntentRuntime → ExperienceStore).
/// The AI layer never writes data itself.
nonisolated enum AssistantAction: Sendable, Equatable {
    case logFood(text: String, meal: ParsedMeal.MealSlot?)
    case logPreset(name: String, modifications: String?)
    case logWater(glasses: Int)
    case logWeight(kg: Double)
    case addTodo(title: String, due: Date?)
    case updateTodo(query: String, due: Date)
    case completeTodo(query: String)
    case scheduleReminder(text: String)
    case createPreset(name: String, items: String)
    case remember(MemoryCandidate)
    case forget(query: String)
}

nonisolated extension AssistantAction {
    /// Simple writes that share one "Log it" tap and one Undo when a turn has several.
    var isBatchable: Bool {
        switch self {
        case .logWater, .logWeight, .addTodo, .updateTodo, .completeTodo, .logPreset, .createPreset: true
        case .logFood, .scheduleReminder, .remember, .forget: false
        }
    }

    /// What the confirmation card says ("Add 2 glasses of water").
    func summary(calendar: Calendar = .current) -> String {
        switch self {
        case .logWater(let glasses): "Add \(glasses) glass\(glasses == 1 ? "" : "es") of water"
        case .logWeight(let kg): String(format: "Log your weight as %.1f kg", kg)
        case .addTodo(let title, let due): "Add “\(title)”" + (due.map { " for \(TimePhrase.text($0, calendar))" } ?? "")
        case .updateTodo(let title, let due): "Move “\(title)” to \(TimePhrase.text(due, calendar))"
        case .completeTodo(let title): "Mark “\(title)” done"
        case .logPreset(let name, let mods): "Log \(name)" + (mods.map { ", \($0)" } ?? "")
        case .createPreset(let name, let items): "Save “\(name)”: \(items)"
        case .logFood(let text, _): "Log \(text)"
        case .scheduleReminder(let text): "Set up: \(text)"
        case .remember(let candidate): "Remember: \(candidate.statement)"
        case .forget(let query): "Forget: \(query)"
        }
    }
}

/// How one turn's writes are presented: every simple write in one batch (one
/// tap, one Undo); the first write needing its own card gets it; any further
/// such writes are reported "one at a time" instead of silently dropped.
nonisolated struct ActionPlan: Sendable, Equatable {
    var batch: [ToolResult]
    var ownCard: ToolResult?
    var deferred: [ToolResult]

    static func split(_ results: [ToolResult]) -> ActionPlan {
        let writes = results.filter { $0.action != nil }
        let batch = writes.filter { $0.action!.isBatchable }
        let special = writes.filter { !$0.action!.isBatchable }
        return ActionPlan(batch: batch, ownCard: special.first, deferred: Array(special.dropFirst()))
    }

    var batchSummary: String { batch.compactMap { $0.action?.summary() }.joined(separator: " · ") }

    var deferredText: String? {
        guard !deferred.isEmpty else { return nil }
        return "One at a time: ask me again for " + deferred.compactMap { $0.action?.summary().lowercased() }.joined(separator: "; ") + "."
    }
}

nonisolated struct ToolResult: Sendable, Equatable {
    var call: ToolCall
    /// Compact text for the model (and the deterministic reply).
    var text: String
    /// Every number the text states (grounding).
    var numbers: [Double]
    var action: AssistantAction?
    var confirmation: ToolConfirmation
    /// A short chart for "how am I doing" style answers.
    var series: [(date: Date, value: Double)]
    var seriesUnit: String?

    init(call: ToolCall, text: String, numbers: [Double] = [], action: AssistantAction? = nil,
         confirmation: ToolConfirmation = .none, series: [(date: Date, value: Double)] = [], seriesUnit: String? = nil) {
        self.call = call
        self.text = text
        self.numbers = numbers
        self.action = action
        self.confirmation = confirmation
        self.series = series
        self.seriesUnit = seriesUnit
    }

    static func == (a: ToolResult, b: ToolResult) -> Bool {
        a.call == b.call && a.text == b.text && a.numbers == b.numbers && a.action == b.action
            && a.series.map(\.value) == b.series.map(\.value)
    }

    var isError: Bool { text.hasPrefix("error:") }
}

// MARK: - Executor

/// Runs tool calls against a `LifeContext`: reads are answered here (exact
/// repository numbers), writes become `AssistantAction`s for the app.
nonisolated enum AssistantToolExecutor {
    static let maxCallsPerTurn = 4

    static func run(_ calls: [ToolCall], context: LifeContext) -> [ToolResult] {
        calls.prefix(maxCallsPerTurn).map { run($0, context: context) }
    }

    static func run(_ call: ToolCall, context: LifeContext) -> ToolResult {
        let spec = AssistantTools.spec(call.name)
        switch call.name {
        case .getTodayStatus: return todayStatus(call, context)
        case .queryStats: return queryStats(call, context)
        case .listPresets: return listPresets(call, context)
        case .explainBudget:
            let e = BudgetExplanation.make(context)
            return ToolResult(call: call, text: e.sentence, numbers: e.allowedNumbers)
        case .searchFoodLog: return searchFoodLog(call, context)
        case .listMemories: return listMemories(call, context)

        case .logFood:
            guard let text = call["text"] else { return error(call, "text missing") }
            return ToolResult(call: call, text: "draft ready for: \(text)",
                              action: .logFood(text: text, meal: call["meal"].flatMap(ParsedMeal.MealSlot.init(rawValue:))),
                              confirmation: spec.confirmation)
        case .logPreset:
            guard let name = call["name"] else { return error(call, "name missing") }
            guard let preset = context.presets.first(where: { FoodNameNormalizer.normalise($0.name) == FoodNameNormalizer.normalise(name) })
                    ?? context.presets.first(where: { FoodNameNormalizer.normalise($0.name).contains(FoodNameNormalizer.normalise(name)) }) else {
                return error(call, "no preset called \(name)")
            }
            return ToolResult(call: call, text: "logging preset \(preset.name) (\(Num.kcal(preset.kcal)) kcal)", numbers: [preset.kcal],
                              action: .logPreset(name: preset.name, modifications: call["modifications"]), confirmation: spec.confirmation)
        case .logWater:
            let glasses = call.number("glasses") ?? call.number("ml").map { $0 / 250 } ?? 1
            let n = max(1, Int(glasses.rounded()))
            let current = context.today?.water ?? 0
            let target = context.today?.waterTarget ?? 8
            return ToolResult(call: call, text: "water +\(n) glass\(n == 1 ? "" : "es") → \(current + n)/\(target)",
                              numbers: [Double(n), Double(current + n), Double(target)], action: .logWater(glasses: n),
                              confirmation: spec.confirmation)
        case .logWeight:
            guard let value = call.number("value") else { return error(call, "value missing") }
            let kg = call["unit"] == "lb" ? value * 0.453_592 : value
            guard kg > 20, kg < 400 else { return error(call, "weight out of range") }
            let rounded = (kg * 10).rounded() / 10
            return ToolResult(call: call, text: String(format: "weight %.1f kg recorded", rounded), numbers: [rounded, value],
                              action: .logWeight(kg: rounded), confirmation: spec.confirmation)
        case .addTodo:
            guard let title = call["title"] else { return error(call, "title missing") }
            let due = call["due"].flatMap { TimePhrase.date($0, now: context.now, calendar: context.calendar) }
            return ToolResult(call: call, text: "todo added: \(title)" + (due.map { " at \(TimePhrase.text($0, context.calendar))" } ?? ""),
                              action: .addTodo(title: title, due: due), confirmation: spec.confirmation)
        case .updateTodo:
            guard let query = call["query"], let dueText = call["due"],
                  let due = TimePhrase.date(dueText, now: context.now, calendar: context.calendar) else { return error(call, "query or time missing") }
            guard let todo = TodoMatcher.best(query, in: context.todos) else { return error(call, "no todo matching \(query)") }
            return ToolResult(call: call, text: "moved \(todo.title) to \(TimePhrase.text(due, context.calendar))",
                              action: .updateTodo(query: todo.title, due: due), confirmation: spec.confirmation)
        case .completeTodo:
            guard let query = call["query"] else { return error(call, "query missing") }
            guard let todo = TodoMatcher.best(query, in: context.todos.filter { !$0.done }) else { return error(call, "no open todo matching \(query)") }
            return ToolResult(call: call, text: "done: \(todo.title)", action: .completeTodo(query: todo.title), confirmation: spec.confirmation)
        case .scheduleReminder:
            guard let text = call["text"] else { return error(call, "text missing") }
            return ToolResult(call: call, text: "reminder ready to confirm: \(text)", action: .scheduleReminder(text: text),
                              confirmation: spec.confirmation)
        case .createPreset:
            guard let name = call["name"], let items = call["items"] else { return error(call, "name or items missing") }
            return ToolResult(call: call, text: "preset \(name) ready to confirm", action: .createPreset(name: name, items: items),
                              confirmation: spec.confirmation)
        case .rememberFact:
            guard let statement = call["statement"] else { return error(call, "statement missing") }
            let candidate = MemoryExtractor.extract(from: statement, now: context.now, calendar: context.calendar, explicit: true).first
            guard let candidate else { return error(call, "nothing to remember") }
            return ToolResult(call: call, text: candidate.needsConfirmation ? "asking before saving: \(candidate.statement)" : "remembered: \(candidate.statement)",
                              action: .remember(candidate), confirmation: candidate.needsConfirmation ? .confirmCard : .undo)
        case .forgetFact:
            guard let query = call["query"] else { return error(call, "query missing") }
            return ToolResult(call: call, text: "matching memories shown for confirmation", action: .forget(query: query),
                              confirmation: spec.confirmation)
        }
    }

    static func error(_ call: ToolCall, _ message: String) -> ToolResult {
        ToolResult(call: call, text: "error: \(message)")
    }

    // MARK: Reads

    static func todayStatus(_ call: ToolCall, _ c: LifeContext) -> ToolResult {
        let day = c.today ?? LifeContext.Day(date: c.calendar.startOfDay(for: c.now))
        let budget = c.budget?.total ?? day.budget
        var parts: [String] = []
        var numbers: [Double] = [day.kcal, day.protein, Double(day.water), Double(day.waterTarget)]
        if budget > 0 {
            let left = budget - day.kcal
            parts.append(left >= 0 ? "eaten \(Num.kcal(day.kcal)) of \(Num.kcal(budget)) kcal, \(Num.kcal(left)) left"
                                   : "eaten \(Num.kcal(day.kcal)) of \(Num.kcal(budget)) kcal, \(Num.kcal(-left)) over")
            numbers += [budget, abs(left)]
        } else {
            parts.append("eaten \(Num.kcal(day.kcal)) kcal")
        }
        if let target = c.macroTargets?.protein, target > 0 {
            parts.append("protein \(Int(day.protein.rounded()))/\(Int(target.rounded())) g")
            numbers += [target, target - day.protein]
        } else {
            parts.append("protein \(Int(day.protein.rounded())) g")
        }
        parts.append("water \(day.water)/\(day.waterTarget)")
        if !day.workouts.isEmpty {
            parts.append("workouts: " + day.workouts.map(BudgetExplanation.describe).joined(separator: "; "))
            numbers += day.workouts.flatMap { [$0.kcal, Double($0.minutes)] }
        }
        if let credit = c.budget?.credit, credit >= 1 {
            parts.append("\(Num.kcal(credit)) kcal earned from activity")
            numbers.append(credit)
        }
        return ToolResult(call: call, text: parts.joined(separator: "; "), numbers: numbers)
    }

    static func range(_ name: String, _ c: LifeContext) -> (days: [LifeContext.Day], label: String) {
        let cal = c.calendar
        let sod = cal.startOfDay(for: c.now)
        switch name {
        case "today": return (c.lastDays(1), "today")
        case "yesterday":
            let y = cal.date(byAdding: .day, value: -1, to: sod) ?? sod
            return (c.days(from: y, to: y), "yesterday")
        case "lastWeek":
            let weekStart = cal.dateInterval(of: .weekOfYear, for: c.now)?.start ?? sod
            let from = cal.date(byAdding: .day, value: -7, to: weekStart) ?? sod
            let to = cal.date(byAdding: .day, value: -1, to: weekStart) ?? sod
            return (c.days(from: from, to: to), "last week")
        case "thisWeek":
            let weekStart = cal.dateInterval(of: .weekOfYear, for: c.now)?.start ?? sod
            return (c.days(from: weekStart, to: c.now), "this week")
        case "last30": return (c.lastDays(30), "the last 30 days")
        case "thisMonth":
            let start = cal.dateInterval(of: .month, for: c.now)?.start ?? sod
            return (c.days(from: start, to: c.now), "this month")
        default: return (c.lastDays(7), "the last 7 days")
        }
    }

    static func value(_ metric: String, _ d: LifeContext.Day) -> Double? {
        switch metric {
        case "kcal": d.hasFood ? d.kcal : nil
        case "protein": d.hasFood ? d.protein : nil
        case "water": Double(d.water)
        case "weight": d.weightKg
        case "workouts": Double(d.workouts.count)
        case "steps": d.steps.map(Double.init)
        case "sleep": d.sleepHours
        default: nil
        }
    }

    static func unit(_ metric: String) -> String {
        ["kcal": "kcal", "protein": "g", "water": "glasses", "weight": "kg", "workouts": "workouts", "steps": "steps", "sleep": "h"][metric] ?? ""
    }

    static func format(_ v: Double, _ metric: String) -> String {
        switch metric {
        case "weight", "sleep": String(format: "%.1f", v)
        default: Num.kcal(v)
        }
    }

    static func queryStats(_ call: ToolCall, _ c: LifeContext) -> ToolResult {
        let metric = AssistantTools.metrics.contains(call["metric"] ?? "") ? call["metric"]! : "kcal"
        let rangeName = call["range"] ?? "last7"
        let aggregation = call["aggregation"] ?? (metric == "workouts" ? "total" : "average")
        let (days, label) = range(rangeName, c)
        let u = unit(metric)

        if aggregation == "compare" {
            let (current, previous): (String, String) = rangeName == "thisMonth" ? ("thisMonth", "last30") : ("thisWeek", "lastWeek")
            let a = range(current, c), b = range(previous, c)
            let va = a.days.compactMap { value(metric, $0) }, vb = b.days.compactMap { value(metric, $0) }
            guard !va.isEmpty, !vb.isEmpty else { return ToolResult(call: call, text: "not enough \(metric) data to compare") }
            let total = metric == "workouts"
            let ma = total ? va.reduce(0, +) : va.reduce(0, +) / Double(va.count)
            let mb = total ? vb.reduce(0, +) : vb.reduce(0, +) / Double(vb.count)
            let what = total ? "\(metric)" : "average \(metric)"
            return ToolResult(call: call, text: "\(what) \(a.label) \(format(ma, metric)) \(u) vs \(format(mb, metric)) \(u) \(b.label) (\(ma >= mb ? "+" : "−")\(format(abs(ma - mb), metric)))",
                              numbers: [ma, mb, abs(ma - mb)],
                              series: a.days.compactMap { d in value(metric, d).map { (d.date, $0) } }, seriesUnit: u)
        }

        let values = days.compactMap { d in value(metric, d).map { (d.date, $0) } }
        guard !values.isEmpty else { return ToolResult(call: call, text: "no \(metric) logged \(label)") }
        let xs = values.map(\.1)
        let result: Double
        let word: String
        switch aggregation {
        case "total": result = xs.reduce(0, +); word = "total"
        case "max": result = xs.max() ?? 0; word = "highest"
        case "min": result = xs.min() ?? 0; word = "lowest"
        case "count": result = Double(xs.filter { $0 > 0 }.count); word = "days with"
        default: result = xs.reduce(0, +) / Double(xs.count); word = "average"
        }
        var text = "\(word) \(metric) \(label): \(format(result, metric)) \(u) over \(values.count) day\(values.count == 1 ? "" : "s")"
        var numbers = [result, Double(values.count)]
        if metric == "protein", let target = c.macroTargets?.protein, target > 0 {
            text += "; target \(Int(target.rounded())) g"
            numbers.append(target)
        }
        if metric == "kcal" {
            let budgeted = days.filter { $0.hasFood && $0.budget > 0 }
            if !budgeted.isEmpty {
                let avgBudget = budgeted.map(\.budget).reduce(0, +) / Double(budgeted.count)
                let onBudget = budgeted.filter { $0.kcal <= $0.budget }.count
                text += "; average budget \(Num.kcal(avgBudget)); on budget \(onBudget) of \(budgeted.count) days"
                numbers += [avgBudget, Double(onBudget), Double(budgeted.count)]
            }
        }
        if metric == "weight", let first = xs.first, let last = xs.last, xs.count >= 2 {
            text += String(format: "; %.1f → %.1f kg", first, last)
            numbers += [first, last, abs(last - first)]
        }
        return ToolResult(call: call, text: text, numbers: numbers, series: values.map { (date: $0.0, value: $0.1) }, seriesUnit: u)
    }

    static func listPresets(_ call: ToolCall, _ c: LifeContext) -> ToolResult {
        guard !c.presets.isEmpty else { return ToolResult(call: call, text: "no presets saved yet") }
        let top = c.presets.sorted { $0.uses > $1.uses }.prefix(8)
        return ToolResult(call: call, text: top.map { "\($0.name) \(Num.kcal($0.kcal)) kcal" }.joined(separator: "; "),
                          numbers: top.map(\.kcal))
    }

    static func searchFoodLog(_ call: ToolCall, _ c: LifeContext) -> ToolResult {
        let query = call["query"].map(FoodNameNormalizer.normalise) ?? ""
        if let dateText = call["date"], let date = TimePhrase.day(dateText, now: c.now, calendar: c.calendar) {
            guard let day = c.days(from: date, to: date).first, day.hasFood else {
                return ToolResult(call: call, text: "nothing logged on \(Num.shortDay(date, c.calendar))")
            }
            let meals = day.meals.filter { query.isEmpty || FoodNameNormalizer.normalise($0.name).contains(query) }
            guard !meals.isEmpty else { return ToolResult(call: call, text: "no \(query) on \(Num.shortDay(date, c.calendar))") }
            let grouped = Dictionary(grouping: meals, by: \.slot)
            let text = [ParsedMeal.MealSlot.breakfast, .lunch, .snacks, .dinner, .unknown].compactMap { slot -> String? in
                grouped[slot].map { "\(slot.rawValue): " + $0.map { "\($0.name) (\(Num.kcal($0.kcal)) kcal)" }.joined(separator: ", ") }
            }.joined(separator: "; ")
            let total = meals.reduce(0) { $0 + $1.kcal }
            return ToolResult(call: call, text: "\(Num.shortDay(date, c.calendar)): \(text); total \(Num.kcal(total)) kcal",
                              numbers: meals.map(\.kcal) + [total])
        }
        guard !query.isEmpty else { return error(call, "a food or a date is needed") }
        let hits = c.days.reversed().flatMap { day in
            day.meals.filter { FoodNameNormalizer.normalise($0.name).contains(query) }.map { (day.date, $0) }
        }
        guard let last = hits.first else { return ToolResult(call: call, text: "no \(query) in the last \(c.days.count) days") }
        let daysAgo = c.calendar.dateComponents([.day], from: c.calendar.startOfDay(for: last.0), to: c.calendar.startOfDay(for: c.now)).day ?? 0
        let ago = daysAgo == 0 ? "today" : daysAgo == 1 ? "yesterday" : "\(daysAgo) days ago"
        return ToolResult(call: call, text: "last had \(last.1.name) \(ago) (\(Num.shortDay(last.0, c.calendar)), \(Num.kcal(last.1.kcal)) kcal); \(hits.count) time\(hits.count == 1 ? "" : "s") in the last \(c.days.count) days",
                          numbers: [last.1.kcal, Double(hits.count), Double(daysAgo), Double(c.days.count)])
    }

    static func listMemories(_ call: ToolCall, _ c: LifeContext) -> ToolResult {
        let active = c.memories.filter { $0.isUsable(at: c.now) && $0.kind != .episode }
        guard !active.isEmpty else { return ToolResult(call: call, text: "nothing saved yet") }
        let order: [MemoryRecord.Kind] = [.fact, .foodFact, .preference, .routine, .goalContext]
        let text = order.compactMap { kind -> String? in
            let items = active.filter { $0.kind == kind }
            return items.isEmpty ? nil : "\(kind.rawValue): " + items.map(\.text).joined(separator: "; ")
        }.joined(separator: " | ")
        return ToolResult(call: call, text: text)
    }
}

// MARK: - Helpers

nonisolated enum TodoMatcher {
    static func best(_ query: String, in todos: [LifeContext.Todo]) -> LifeContext.Todo? {
        let q = Set(HashingEmbedder.words(query).filter { !["todo", "task", "the", "my"].contains($0) })
        guard !q.isEmpty else { return nil }
        return todos.map { ($0, q.intersection(HashingEmbedder.words($0.title)).count) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?.0
    }
}

/// "6pm", "18:30", "tomorrow 7am", "tonight", "in 2 hours" → a date.
nonisolated enum TimePhrase {
    static func date(_ raw: String, now: Date, calendar: Calendar) -> Date? {
        let t = raw.lowercased().trimmingCharacters(in: .whitespaces)
        let sod = calendar.startOfDay(for: now)
        if let g = Rx.groups(#"\bin (\d+|an|a|one|two|three) (hour|hr|minute|min)s?\b"#, t), g.count == 2 {
            let n = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3][g[0]] ?? Int(g[0]) ?? 1
            return calendar.date(byAdding: g[1].hasPrefix("h") ? .hour : .minute, value: n, to: now)
        }
        var base = sod
        if t.contains("tomorrow") { base = calendar.date(byAdding: .day, value: 1, to: sod) ?? sod }
        var hour: Int?
        var minute = 0
        if let g = Rx.groups(#"\b(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)\b"#, t), g.count == 3, var h = Int(g[0]) {
            minute = Int(g[1]) ?? 0
            if g[2] == "pm", h < 12 { h += 12 }
            if g[2] == "am", h == 12 { h = 0 }
            hour = h
        } else if let g = Rx.groups(#"\b(\d{1,2})[:.](\d{2})\b"#, t), g.count == 2, let h = Int(g[0]) {
            hour = h
            minute = Int(g[1]) ?? 0
        } else if let g = Rx.groups(#"\bat (\d{1,2})\b"#, t), let h = Int(g[0]) {
            // "at 6" → the next 6 o'clock that's still ahead (6 pm in the afternoon).
            hour = h < 12 && calendar.component(.hour, from: now) >= h && !t.contains("tomorrow") ? h + 12 : h
        } else if t.contains("tonight") {
            hour = 20
        } else if t.contains("morning") {
            hour = 8
        } else if t.contains("evening") {
            hour = 18
        } else if t.contains("tomorrow") {
            hour = 9
        }
        guard let hour, (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)
    }

    static func text(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let clock = ClockText.text((c.hour ?? 0) * 60 + (c.minute ?? 0))
        if calendar.isDate(date, inSameDayAs: Date()) { return clock }
        return "\(Num.shortDay(date, calendar)) \(clock)"
    }

    /// "yesterday", "monday", "last tuesday", "2026-10-01", "3 oct" → a day.
    static func day(_ raw: String, now: Date, calendar: Calendar) -> Date? {
        let t = raw.lowercased()
        let sod = calendar.startOfDay(for: now)
        if t.contains("today") { return sod }
        if t.contains("yesterday") { return calendar.date(byAdding: .day, value: -1, to: sod) }
        if let g = Rx.groups(#"(\d{4})-(\d{2})-(\d{2})"#, t), g.count == 3 {
            return calendar.date(from: DateComponents(year: Int(g[0]), month: Int(g[1]), day: Int(g[2])))
        }
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        if let g = Rx.groups(#"\b(\d{1,2})(?:st|nd|rd|th)? (jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)"#, t), g.count == 2,
           let d = Int(g[0]), let m = months.firstIndex(of: g[1]) {
            var year = calendar.component(.year, from: now)
            if m + 1 > calendar.component(.month, from: now) { year -= 1 }
            return calendar.date(from: DateComponents(year: year, month: m + 1, day: d))
        }
        if let target = WeekdayParser.keys.first(where: { t.contains($0.prefix) })?.day {
            let weekday = calendar.component(.weekday, from: now)
            var back = (weekday - target + 7) % 7
            if back == 0 { back = 7 }     // "monday" on a Monday = last Monday
            return calendar.date(byAdding: .day, value: -back, to: sod)
        }
        return nil
    }
}
