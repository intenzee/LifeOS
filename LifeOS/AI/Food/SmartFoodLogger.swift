import Foundation

/// A meal ready for the confirmation card (F02 §4, F03 §4.2).
nonisolated struct MealDraft: Sendable, Hashable {
    var items: [ResolvedFoodItem]
    var meal: ParsedMeal.MealSlot
    var mealWasInferred: Bool
    /// Which tier parsed the text (nil for presets) — drives the source chip.
    var parsedBy: ProviderID?
    var preset: FoodPreset?
    var sourceText: String

    var totals: Macros { items.reduce(.zero) { $0 + $1.macros } }
    var confidence: Double {
        guard !items.isEmpty else { return 0 }
        return items.map(\.confidence).reduce(0, +) / Double(items.count)
    }
    var band: ConfidenceBand { ConfidenceBand(confidence) }
    var needsReview: Bool { items.contains { $0.needsReview } }
    var isEmpty: Bool { items.isEmpty }
}

nonisolated enum SmartLogOutcome: Sendable {
    case draft(MealDraft)
    /// "my usual" matched several presets — let the user pick (F03 §4.2).
    case choosePreset([FoodPreset], modifications: String?)
    /// "Remember gym shake is 1 scoop whey, 300 ml milk and a banana."
    case definePreset(name: String, draft: MealDraft)
    /// "Save this as my usual breakfast" while a draft is open.
    case saveDraftAsPreset(name: String)
    case notFood(String)
}

/// Orchestrates text/voice logging end to end: intent → parse (gateway) →
/// nutrition (resolver) → optional model estimates → meal inference → draft.
/// Works fully offline on any iPhone; a BYOK key only improves parsing and
/// fills in foods the catalog doesn't know.
nonisolated struct SmartFoodLogger: Sendable {
    let gateway: any AIGatewaying
    let presets: any PresetRepository
    var userFoods: @Sendable () async -> [UserFood] = { [] }
    var calendar: Calendar = .current
    /// When this user eats each meal (F05/F02 learned windows; FOOD-16).
    var mealWindows: @Sendable () async -> MealWindows = { .empty }
    /// "My katori is 120 ml" and similar memories (F04 hints).
    var portionHints: @Sendable () async -> PortionHints = { .none }

    // MARK: Interpret

    func interpret(_ text: String, now: Date = Date(), current: MealDraft? = nil) async -> SmartLogOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notFood("Say or type what you ate.") }

        if let name = Self.saveCurrentIntent(trimmed) {
            guard current?.isEmpty == false else { return .notFood("Log a meal first, then say “save this as…”.") }
            return .saveDraftAsPreset(name: name)
        }

        let resolver = NutritionResolver(userFoods: await userFoods(), portionHints: await portionHints())

        if let definition = Self.defineIntent(trimmed) {
            let draft = await parseDraft(definition.items, now: now, resolver: resolver)
            guard let draft, !draft.isEmpty else { return .notFood("I couldn't find foods in that preset.") }
            return .definePreset(name: definition.name, draft: draft)
        }

        // Presets: "my usual breakfast", "gym shake", "usual lunch but no curd".
        let library = await presets.all()
        if !library.isEmpty {
            let (base, modifications) = MealModificationParser.splitVariant(trimmed)
            let presetResolver = PresetResolver(presets: library, calendar: calendar)
            let saysUsual = !Set(PresetResolver.clean(base).split(separator: " ").map(String.init))
                .isDisjoint(with: PresetResolver.usualWords)
            let ranked = presetResolver.rank(base, now: now)
            if let top = ranked.first, saysUsual || top.score >= 0.9 {
                switch presetResolver.decide(ranked) {
                case .match(let preset):
                    return .draft(draft(from: preset, modifications: modifications, now: now, resolver: resolver))
                case .ambiguous(let options):
                    return .choosePreset(options, modifications: modifications)
                case .none:
                    break
                }
            } else if saysUsual {
                // "my usual" with nothing that fits: fall through to parsing the rest.
            }
        }

        guard let draft = await parseDraft(trimmed, now: now, resolver: resolver) else {
            return .notFood("Couldn't read that. Try “2 rotis and dal”.")
        }
        guard !draft.isEmpty else {
            return .notFood("I didn't hear any food in that. Try “2 rotis, dal and curd for lunch”.")
        }
        return .draft(draft)
    }

    /// Applies a spoken/typed correction to an open draft ("no curd, 3 rotis").
    func refine(_ draft: MealDraft, with text: String) async -> MealDraft {
        let resolver = NutritionResolver(userFoods: await userFoods(), portionHints: await portionHints())
        var operations = MealModificationParser.parse(text, current: draft.items)
        if operations.isEmpty {
            // Unrecognised correction: treat it as more food.
            operations = DeterministicFoodParser.parse(text).items.map { .add($0) }
        }
        var updated = draft
        updated.items = MealModificationParser.apply(operations, to: draft.items, resolver: resolver)
        if let meal = Self.mealWord(in: text) {
            updated.meal = meal
            updated.mealWasInferred = false
        }
        updated.items = await estimateUnresolved(updated.items)
        return updated
    }

    func draft(from preset: FoodPreset, modifications: String?, now: Date = Date(),
               resolver: NutritionResolver = NutritionResolver()) -> MealDraft {
        var items = preset.items.map { item -> ResolvedFoodItem in
            var copy = item
            copy.id = UUID()
            return copy
        }
        if let modifications {
            items = MealModificationParser.apply(MealModificationParser.parse(modifications, current: items),
                                                 to: items, resolver: resolver)
        }
        let meal = preset.defaultMeal ?? Self.inferMeal(at: now, calendar: calendar)
        return MealDraft(items: items, meal: meal, mealWasInferred: preset.defaultMeal == nil, parsedBy: nil,
                         preset: preset, sourceText: preset.name)
    }

    // MARK: Presets

    func savePreset(named rawName: String, from draft: MealDraft, source: FoodPreset.Source = .user) async -> FoodPreset {
        let name = Self.presetDisplayName(rawName)
        var preset = FoodPreset(name: name, aliases: Self.aliases(for: rawName, name: name), items: draft.items,
                                defaultMeal: draft.meal == .unknown ? nil : draft.meal, source: source)
        preset.recordUse(at: Date())
        await presets.save(preset)
        return preset
    }

    /// Call after a draft is logged so preset usage and windows are learned.
    func didLog(_ draft: MealDraft, at date: Date = Date()) async {
        if let preset = draft.preset { await presets.recordUse(preset.id, at: date) }
    }

    // MARK: Parsing

    private func parseDraft(_ text: String, now: Date, resolver: NutritionResolver) async -> MealDraft? {
        let request = AIRequest<ParsedMeal>(task: .foodTextParse, prompt: PromptRegistry.foodTextParse(text),
                                            input: .text(text), privacy: .personal, latencyBudget: .seconds(10),
                                            generation: AIGenerationOptions(temperature: 0))
        let parsed: ParsedMeal
        let provider: ProviderID
        do {
            let result = try await gateway.run(request)
            parsed = result.output
            provider = result.provider
        } catch {
            // The gateway already tried the rule parser; this is belt and braces.
            parsed = DeterministicFoodParser.parse(text)
            provider = .deterministic
        }
        var items = resolver.resolve(parsed)
        items = await estimateUnresolved(items)
        let inferred = parsed.mealType == .unknown
        let meal = inferred ? await mealSlot(at: now) : parsed.mealType
        return MealDraft(items: items, meal: meal,
                         mealWasInferred: inferred, parsedBy: provider, preset: nil, sourceText: text)
    }

    /// Asks a model for foods the catalog doesn't know — only when one is
    /// reachable (a key on non-Apple-Intelligence phones). Otherwise items stay
    /// flagged "Check this" for the user to fill in.
    private func estimateUnresolved(_ items: [ResolvedFoodItem]) async -> [ResolvedFoodItem] {
        let unresolved = items.indices.filter { items[$0].matchKind == .unresolved }
        guard !unresolved.isEmpty, await gateway.availability(for: .nutritionEstimate).isAvailable else { return items }
        var result = items
        await withTaskGroup(of: (Int, NutritionEstimate?).self) { group in
            for index in unresolved.prefix(4) {
                let item = items[index]
                let amount = "\(item.quantity.formatted()) \(item.unit)" + (item.preparation.isEmpty ? "" : ", \(item.preparation)")
                let request = AIRequest<NutritionEstimate>(task: .nutritionEstimate,
                                                           prompt: PromptRegistry.nutritionEstimate(item: item.displayName, quantity: amount),
                                                           input: .text(item.displayName), privacy: .personal,
                                                           latencyBudget: .seconds(8), generation: AIGenerationOptions(temperature: 0))
                let gateway = self.gateway
                group.addTask { (index, try? await gateway.run(request).output) }
            }
            for await (index, estimate) in group {
                if let estimate { result[index] = NutritionResolver.applyingEstimate(estimate, to: result[index]) }
            }
        }
        return result
    }

    // MARK: Intents & helpers

    static func saveCurrentIntent(_ text: String) -> String? {
        let pattern = #/^(?:please\s+)?(?:save|remember|store|keep)\s+(?:this|that|it|these)(?:\s+meal)?\s+(?:as|like)\s+(.+)$/#
        guard let match = text.lowercased().firstMatch(of: pattern) else { return nil }
        return String(match.1).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    static func defineIntent(_ text: String) -> (name: String, items: String)? {
        let pattern = #/^(?:please\s+)?(?:remember|save|create|define|make|add)\s+(?:that\s+|a\s+)?(?:preset\s+)?(?:called\s+|named\s+)?["“']?(.+?)["”']?\s+(?:is|=|means|as|has|consists of|contains)\s+(.+)$/#
        guard let match = text.firstMatch(of: pattern) else { return nil }
        let name = String(match.1).trimmingCharacters(in: .whitespaces)
        let items = String(match.2).trimmingCharacters(in: .whitespaces)
        guard !["this", "that", "it"].contains(name.lowercased()), !items.isEmpty else { return nil }
        return (name, items)
    }

    /// "my usual breakfast" → "Usual breakfast"
    static func presetDisplayName(_ raw: String) -> String {
        var words = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: "\"", with: "").split(separator: " ").map(String.init)
        if let first = words.first, ["my", "the", "a"].contains(first.lowercased()) { words.removeFirst() }
        guard !words.isEmpty else { return "My meal" }
        let joined = words.joined(separator: " ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    static func aliases(for raw: String, name: String) -> [String] {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower == name.lowercased() ? [] : [lower]
    }

    /// Learned windows first; fixed clock hours when the user has no history yet.
    func mealSlot(at date: Date) async -> ParsedMeal.MealSlot {
        (await mealWindows()).slot(at: date, calendar: calendar) ?? Self.inferMeal(at: date, calendar: calendar)
    }

    static func inferMeal(at date: Date, calendar: Calendar = .current) -> ParsedMeal.MealSlot {
        switch calendar.component(.hour, from: date) {
        case 5..<11: .breakfast
        case 11..<16: .lunch
        case 16..<19: .snacks
        default: .dinner
        }
    }

    static func mealWord(in text: String) -> ParsedMeal.MealSlot? {
        PresetResolver.mealWord(in: Set(FoodNameNormalizer.normalise(text).split(separator: " ").map(String.init)))
    }
}

nonisolated extension PresetResolver {
    /// Candidates with scores, best first.
    func rank(_ phrase: String, now: Date = Date(), meal: ParsedMeal.MealSlot? = nil) -> [(preset: FoodPreset, score: Double)] {
        scored(phrase, now: now, meal: meal)
    }

    func decide(_ ranked: [(preset: FoodPreset, score: Double)]) -> PresetResolution {
        guard let top = ranked.first else { return .none }
        let runnerUp = ranked.dropFirst().first?.score ?? 0
        if top.score >= 0.75, top.score - runnerUp >= 0.15 { return .match(top.preset) }
        return .ambiguous(Array(ranked.prefix(3).map(\.preset)))
    }
}
