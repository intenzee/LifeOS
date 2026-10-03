import Foundation
import LifeOSCore

/// Connects the AI assistant engine (F05–F08, F07) to the Experience layer's
/// assistant (UI/UX Phase 4). The Experience layer keeps its screens, cards and
/// rule brain; this adds, in order:
///  1. safety on every turn (before anything else),
///  2. memory commands and statements, with sensitive facts held for "Remember?",
///  3. deterministic tools (water, weight, todos, budget why, log search, stats),
///  4. for open questions: a token-budgeted, privacy-filtered context packet and,
///     with a model, tool planning with a numbers-grounding check.
/// Writes go through `IntentRuntime.store()` → `ExperienceStore`, so streaks,
/// the Watch snapshot and widgets update exactly as for any other write.
@MainActor
final class AIAssistantBridge {
    static let shared = AIAssistantBridge()

    let contextEngine = ContextEngine()
    private var conversation = ConversationLog()
    private var undo: [String: () async -> Void] = [:]
    private var lastCredit: (day: String, kcal: Double)?
    private var announcedWorkouts: Set<UUID> = []
    private var observer: NSObjectProtocol?

    var engine: AssistantEngine { AssistantEngine(gateway: AIServices.shared.gateway, contextEngine: contextEngine) }

    private var region: String? { Locale.current.region?.identifier }

    // MARK: Context

    func lifeContext(_ snap: IntelligenceSnapshot) async -> LifeContext {
        let store = await IntentRuntime.store()
        let presets = await AIServices.shared.presets.all()
        let window = conversation.window()
        let context = LifeContextBuilder.make(snap, store: store, presets: presets, memories: AIMemoryBridge.shared.records,
                                              conversationSummary: window.summary)
        await AIMemoryBridge.shared.sync(snap.memories)
        await AIMemoryBridge.shared.consolidateIfNeeded(context)
        return context
    }

    /// The packet the Experience layer's open-question chat sends (replaces its
    /// hand-built context). The gateway still enforces consent per provider.
    func context(for text: String, _ snap: IntelligenceSnapshot) async -> ContextPacket {
        let context = await lifeContext(snap)
        let primary = await AIServices.shared.gateway.availability(for: .assistantChat).primary
        return await engine.contextPacket(for: text, context: context, provider: primary).packet
    }

    // MARK: 1–3. Before the rule brain

    func preempt(_ text: String, _ snap: IntelligenceSnapshot) async -> AssistantReply? {
        let context = await lifeContext(snap)
        guard let outcome = engine.preempt(text, context: context, region: region) else { return nil }
        conversation.append(user: text)
        let reply = await reply(for: outcome, snap: snap, context: context)
        conversation.append(assistant: reply.text)
        return reply
    }

    // MARK: 4. Open questions with a model

    /// A tool-planned, grounded answer when a model is reachable; nil otherwise
    /// (the caller then streams as before, or explains what's needed).
    func modelReply(_ text: String, _ snap: IntelligenceSnapshot) async -> (reply: AssistantReply, source: String)? {
        guard await engine.canPlan() else { return nil }
        let context = await lifeContext(snap)
        guard let outcome = await engine.answer(text, context: context, conversation: conversation) else { return nil }
        conversation.append(user: text)
        let reply = await reply(for: outcome, snap: snap, context: context)
        conversation.append(assistant: reply.text)
        return (reply, outcome.provider.displayName)
    }

    /// After a streamed answer: keep it only if every number is in the packet or
    /// the question; otherwise return the rule brain's fallback text.
    func grounded(_ answer: String, packet: ContextPacket, question: String, fallback: String) -> String {
        let check = GroundingValidator.validate(answer, allowed: [], sourceTexts: [packet.rendered(), question])
        return check.isGrounded ? answer : "I'd rather not guess at numbers. " + fallback
    }

    func noteTurn(user: String, assistant: String) {
        conversation.append(user: user)
        conversation.append(assistant: assistant)
    }

    func resetConversation() { conversation = ConversationLog() }

    // MARK: Undo

    func undo(_ id: String) async -> Bool {
        guard let action = undo.removeValue(forKey: id) else { return false }
        await action()
        return true
    }

    // MARK: Mapping outcomes to Experience replies

    private func reply(for outcome: AssistantOutcome, snap: IntelligenceSnapshot, context: LifeContext) async -> AssistantReply {
        let used = snap.memories.filter { outcome.usedMemoryIDs.contains($0.id) }
        switch outcome.route {
        case .safety:
            return AssistantReply(text: outcome.text, isSafetyRedirect: true)

        case .memory:
            if let query = outcome.forgetQuery { return forgetReply(query, snap: snap) }
            return rememberReply(outcome.memoryCandidates, text: outcome.text)

        case .command, .model:
            var texts: [String] = []
            var card: AssistantReply.Card = .none
            var based: String?
            // Only a deterministic parse of what the person typed acts at once (with
            // Undo). Anything a cloud model planned waits for a tap: a misread must
            // never log food, water or weight nobody asked for.
            let modelPlanned = outcome.route == .model
            for result in outcome.results where result.action == nil {
                based = based ?? Self.basedOn(result.call)
                if case .none = card, result.series.count >= 2, let unit = result.seriesUnit {
                    card = .chart(title: Self.chartTitle(result.call), points: result.series.map { .init(date: $0.date, value: $0.value) },
                                  goal: result.call["metric"] == "protein" ? context.macroTargets?.protein : nil, unit: unit)
                }
            }
            let plan = ActionPlan.split(outcome.results)
            if !plan.batch.isEmpty {
                if modelPlanned {
                    let id = UUID().uuidString
                    pending[id] = plan.batch
                    texts.append(plan.batch.count == 1 ? "Want me to do this?" : "Want me to do these?")
                    card = .pendingAction(summary: plan.batchSummary, actionID: id)
                } else if let done = await performBatch(plan.batch, snap: snap) {
                    texts.append(done.text)
                    card = done.card
                }
            }
            if let special = plan.ownCard, let action = special.action {
                let (text, specialCard) = modelPlanned ? propose(action, snap: snap) : await perform(action, snap: snap)
                texts.append(text)
                if case .none = card { card = specialCard } else { texts.append("Ask me again for: \(action.summary().lowercased()).") }
            }
            if let deferred = plan.deferredText { texts.append(deferred) }
            let readsOnly = outcome.results.allSatisfy { $0.action == nil }
            let text = readsOnly ? outcome.text : texts.joined(separator: " ")
            return AssistantReply(text: text.isEmpty ? outcome.text : text, basedOn: based, card: card, usedMemories: used)
        }
    }

    private func rememberReply(_ candidates: [MemoryCandidate], text: String) -> AssistantReply {
        guard let first = candidates.first else { return AssistantReply(text: text) }
        let item = AIMemoryBridge.shared.item(for: first)
        if first.needsConfirmation {
            return AssistantReply(text: text, card: .confirmMemory(item))
        }
        // Extra facts from the same sentence ("I hate karela and brinjal") are saved too.
        for extra in candidates.dropFirst() where !extra.needsConfirmation {
            IntelligenceStore.shared.remember(AIMemoryBridge.shared.item(for: extra))
        }
        let all = candidates.filter { !$0.needsConfirmation }.map(\.statement)
        let said = all.count > 1 ? " " + all.joined(separator: "; ") + "." : ""
        return AssistantReply(text: text + said, card: .remembered(item))
    }

    private func forgetReply(_ query: String, snap: IntelligenceSnapshot) -> AssistantReply {
        let ids = Set(MemoryReconciler.matches(forget: query, in: AIMemoryBridge.shared.records, embedder: DefaultEmbedder()).map(\.id))
        let words = Set(HashingEmbedder.words(query).filter { $0.count > 3 })
        let hits = snap.memories.filter { m in ids.contains(m.id) || words.contains { m.text.lowercased().contains($0) } }
        guard !hits.isEmpty else {
            return AssistantReply(text: "I couldn't find that in what I know. You can see everything in You → What LifeOS knows.")
        }
        return AssistantReply(text: "Forget \(hits.count == 1 ? "this" : "these \(hits.count)")?", card: .forgotten(hits))
    }

    static func basedOn(_ call: ToolCall) -> String {
        switch call.name {
        case .explainBudget: "The calorie engine's breakdown for today"
        case .searchFoodLog: "Your food log"
        case .queryStats: "Your logs"
        case .getTodayStatus: "Today's log and budget"
        case .listMemories: "What LifeOS knows"
        default: "Your data"
        }
    }

    static func chartTitle(_ call: ToolCall) -> String {
        let metric = ["kcal": "Calories", "protein": "Protein", "water": "Water", "weight": "Weight", "workouts": "Workouts",
                      "steps": "Steps", "sleep": "Sleep"][call["metric"] ?? ""] ?? "Trend"
        return "\(metric), \(call["aggregation"] == "compare" ? "this week" : "recent days")"
    }

    // MARK: Proposals (cloud-model writes wait for a tap)

    private var pending: [String: [ToolResult]] = [:]

    /// Cards for model-planned writes that need their own confirmation UI.
    private func propose(_ action: AssistantAction, snap: IntelligenceSnapshot) -> (String, AssistantReply.Card) {
        switch action {
        case .logFood(let text, _): return ("Log this?", .logProposal(sentence: text))
        case .scheduleReminder(let text):
            if let rule = AutomationParser.parse(text) { return ("Here's the rule. Turn it on?", .rule(rule)) }
            return ("Try “remind me to drink water every 2 hours”.", .none)
        case .remember(let candidate):
            // Asked, never saved silently, when a model suggested it.
            return ("Remember this?", .confirmMemory(AIMemoryBridge.shared.item(for: candidate)))
        case .forget(let query):
            let reply = forgetReply(query, snap: snap)
            return (reply.text, reply.card)
        default:
            // Batchable writes never reach here (ActionPlan batches them).
            return ("Want me to do this?", .none)
        }
    }

    /// Performs a proposed write after "Log it"; returns the Undo chip.
    func confirmPending(_ id: String) async -> (summary: String, undoID: String)? {
        guard let batch = pending.removeValue(forKey: id), let snap = IntelligenceStore.shared.snapshot(),
              let done = await performBatch(batch, snap: snap), case let .done(summary, undoID) = done.card else { return nil }
        return (summary, undoID)
    }

    /// Performs every write in the batch; one Undo token reverts them all, newest first.
    private func performBatch(_ batch: [ToolResult], snap: IntelligenceSnapshot) async -> (text: String, card: AssistantReply.Card)? {
        var texts: [String] = [], summaries: [String] = [], tokens: [String] = []
        for result in batch {
            guard let action = result.action else { continue }
            let (text, card) = await perform(action, snap: snap)
            texts.append(text)
            if case let .done(summary, token) = card {
                summaries.append(summary)
                tokens.append(token)
            }
        }
        guard !texts.isEmpty else { return nil }
        guard !tokens.isEmpty else { return (texts.joined(separator: " "), .none) }
        if tokens.count == 1 { return (texts.joined(separator: " "), .done(summary: summaries[0], undoID: tokens[0])) }
        let combined = UUID().uuidString
        undo[combined] = { [weak self] in
            for token in tokens.reversed() { _ = await self?.undo(token) }
        }
        return (texts.joined(separator: " "), .done(summary: summaries.joined(separator: " · "), undoID: combined))
    }

    // MARK: Writes (through ExperienceStore)

    private func perform(_ action: AssistantAction, snap: IntelligenceSnapshot) async -> (String, AssistantReply.Card) {
        let store = await IntentRuntime.store()
        let token = UUID().uuidString
        switch action {
        case .logWater(let glasses):
            guard store.isToday else { return ("Water can only be added to today.", .none) }
            let before = store.waterCount
            store.addWater(glasses)
            let added = store.waterCount - before
            guard added > 0 else { return ("You're already at the daily maximum of 12 glasses.", .none) }
            undo[token] = { store.addWater(-added) }
            let text = "Added \(added) glass\(added == 1 ? "" : "es") of water. \(store.waterCount) of \(store.waterTarget) today."
            return (text, .done(summary: "Water +\(added)", undoID: token))

        case .logWeight(let kg):
            let previous = store.currentWeight
            store.logWeight(kg: kg)
            if previous > 0 { undo[token] = { store.logWeight(kg: previous) } }
            let text = ExperienceStore.weightText(kg, units: store.profile?.units)
            return ("Logged \(text).", .done(summary: "Weight \(text)", undoID: token))

        case .addTodo(let title, let due):
            guard let id = store.addTodo(title: title, due: due) else {
                return ("I can add todos for this week from here. For later dates, use the Todo tab.", .none)
            }
            undo[token] = { store.removeTodo(id) }
            let reminder = store.todoReminder(id) != nil
            let when = due.map { " for \(TimePhrase.text($0, Calendar.current))" } ?? ""
            return ("Added “\(title)”\(when)\(reminder ? ", with a reminder" : "").", .done(summary: "Todo added", undoID: token))

        case .completeTodo(let title):
            guard let todo = store.todos.first(where: { $0.title == title && !$0.isCompleted }) else { return ("I couldn't find that todo today.", .none) }
            store.toggleTodo(todo.id)
            undo[token] = { store.toggleTodo(todo.id) }
            return ("Marked “\(title)” done.", .done(summary: "Todo done", undoID: token))

        case .updateTodo(let title, let due):
            let week = PersistenceManager.shared.loadWeekTodoList().values.flatMap { $0 }
            guard let todo = week.first(where: { $0.title == title }) else { return ("I couldn't find that todo this week.", .none) }
            let previous = todo.reminderDate
            store.rescheduleTodo(todo.id, to: due)
            undo[token] = { store.rescheduleTodo(todo.id, to: previous) }
            return ("Moved “\(title)” to \(TimePhrase.text(due, Calendar.current)).", .done(summary: "Todo moved", undoID: token))

        case .logPreset(let name, let modifications):
            let presets = await AIServices.shared.presets.all()
            guard let preset = presets.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                return ("I couldn't find a preset called \(name).", .none)
            }
            let logger = AIServices.shared.foodLogger
            let draft = logger.draft(from: preset, modifications: modifications)
            let mealType = draft.meal.mealType ?? store.currentSlot.mealType
            let foods = draft.items.map {
                FoodItem(name: $0.displayName.capitalizedFirst, calories: $0.macros.kcal.rounded(), protein: $0.macros.protein,
                         carbs: $0.macros.carbs, fat: $0.macros.fat, servingSize: $0.servingDescription, mealType: mealType,
                         source: .preset, aiConfidence: $0.confidence)
            }
            let ids = store.log(foods, slot: ExperienceMealSlot(mealType), source: .preset)
            await logger.didLog(draft)
            undo[token] = { store.remove(ids) }
            return ("Logged \(preset.name), \(Int(draft.totals.kcal.rounded())) kcal.", .done(summary: "Logged \(preset.name)", undoID: token))

        case .logFood(let text, _):
            return ("Log this?", .logProposal(sentence: text))

        case .scheduleReminder(let text):
            if let rule = AutomationParser.parse(text) { return ("Here's the rule. Turn it on?", .rule(rule)) }
            return ("Try “remind me to drink water every 2 hours”.", .none)

        case .createPreset(let name, let items):
            let logger = AIServices.shared.foodLogger
            guard case .draft(let draft) = await logger.interpret(items) else { return ("I couldn't read those foods.", .none) }
            let preset = await logger.savePreset(named: name, from: draft)
            undo[token] = { await AIServices.shared.presets.delete(preset.id) }
            return ("Saved “\(preset.name)”, \(Int(draft.totals.kcal.rounded())) kcal.", .done(summary: "Preset saved", undoID: token))

        case .remember(let candidate):
            let reply = rememberReply([candidate], text: AssistantEngine.rememberReply([candidate]))
            return (reply.text, reply.card)

        case .forget(let query):
            let reply = forgetReply(query, snap: snap)
            return (reply.text, reply.card)
        }
    }

    // MARK: Post-workout card (F07 §6, AI-307)

    /// Shows "+145 kcal added from your 42-min run · 91 g protein to go" when a
    /// new workout syncs. `.healthWorkoutSynced` fires after the budget flush, so
    /// the engine numbers already include the workout (engineering contract).
    func startObservingWorkouts() {
        guard observer == nil else { return }
        lastCredit = currentCredit()
        observer = NotificationCenter.default.addObserver(forName: .healthWorkoutSynced, object: nil, queue: .main) { note in
            guard let session = note.object as? WorkoutSession else { return }
            MainActor.assumeIsolated { AIAssistantBridge.shared.workoutSynced(session) }
        }
    }

    private func currentCredit() -> (day: String, kcal: Double)? {
        let day = MemoryConsolidator.dayKey(Date(), .current)
        return (day, EngineBudget.breakdown(on: .today())?.credit ?? 0)
    }

    private func workoutSynced(_ session: WorkoutSession) {
        guard announcedWorkouts.insert(session.id).inserted else { return }
        let before = lastCredit.flatMap { $0.day == MemoryConsolidator.dayKey(Date(), .current) ? $0.kcal : nil }
        lastCredit = currentCredit()
        Task {
            await contextEngine.invalidate(.workoutIngested)
            guard let snap = IntelligenceStore.shared.snapshot() else { return }
            let context = await lifeContext(snap)
            let card = PostWorkoutCard.make(workout: LifeContextBuilder.workout(session), creditBefore: before, context: context)
            IntelligenceStore.shared.eventBanner = .init(ruleID: "ai.postWorkout", text: card.body)
        }
    }
}
