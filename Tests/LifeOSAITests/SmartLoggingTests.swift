import Foundation
import Testing
@testable import LifeOSAI

/// In-memory preset store for tests.
actor MemoryPresetRepository: PresetRepository {
    var presets: [UUID: FoodPreset] = [:]
    init(_ initial: [FoodPreset] = []) { presets = Dictionary(initial.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    func all() -> [FoodPreset] { presets.values.sorted { $0.createdAt < $1.createdAt } }
    func save(_ preset: FoodPreset) { presets[preset.id] = preset }
    func delete(_ id: UUID) { presets[id] = nil }
    func recordUse(_ id: UUID, at date: Date) { presets[id]?.recordUse(at: date) }
}

/// An iPhone 15: no Apple Intelligence, no key → rules + catalog only.
nonisolated func nonAIGateway() -> AIGateway {
    let gateway = AIStack.makeGateway(.init(credentials: StaticCredentials(), consents: InMemoryConsentStore()))
    return gateway
}

nonisolated func date(_ hour: Int, dayOffset: Int = 0) -> Date {
    var c = DateComponents(year: 2026, month: 10, day: 5 + dayOffset, hour: hour, minute: 15)   // Mon 5 Oct 2026
    c.timeZone = TimeZone(identifier: "Asia/Kolkata")
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return cal.date(from: c)!
}

nonisolated var istCalendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return cal
}

@Suite("Smart food logging on a non-Apple-Intelligence phone (Phase 1 demo script)")
struct SmartLoggingTests {

    private func logger(_ repo: MemoryPresetRepository = MemoryPresetRepository(), gateway: AIGateway = nonAIGateway()) async -> SmartFoodLogger {
        await gateway.setDebugOverrides(.init(forcedUnavailable: [.appleOnDevice, .applePCC]))   // iPhone 15
        var logger = SmartFoodLogger(gateway: gateway, presets: repo)
        logger.calendar = istCalendar
        return logger
    }

    @Test("Demo 1: say a meal → resolved card with grams, kcal, confidence and provenance")
    func sayAMeal() async throws {
        let outcome = await logger().interpret("two rotis, dal makhani and curd for lunch", now: date(13))
        guard case .draft(let draft) = outcome else { Issue.record("expected a draft, got \(outcome)"); return }
        #expect(draft.items.map(\.displayName) == ["roti", "dal makhani", "curd"])
        #expect(draft.meal == .lunch && !draft.mealWasInferred)
        #expect(draft.parsedBy == .deterministic)
        #expect(draft.items[0].grams == 80)
        #expect(abs(draft.totals.kcal - (237.6 + 225 + 91.5)) < 1)
        // Amounts were defaulted for dal and curd → honest "medium", but nothing flagged.
        #expect(draft.band == .medium)
        #expect(!draft.needsReview)
        #expect(draft.items.allSatisfy { $0.sourceRef.hasPrefix("db:") })
    }

    @Test("Demo 2: save as preset, then next day 'log my usual lunch but no curd'")
    func presetRoundTrip() async throws {
        let repo = MemoryPresetRepository()
        let logger = await logger(repo)
        guard case .draft(let lunch) = await logger.interpret("two rotis, dal makhani and curd for lunch", now: date(13)) else {
            Issue.record("no draft"); return
        }
        guard case .saveDraftAsPreset(let name) = await logger.interpret("save this as my usual lunch", now: date(13), current: lunch) else {
            Issue.record("expected save intent"); return
        }
        let preset = await logger.savePreset(named: name, from: lunch)
        #expect(preset.name == "Usual lunch")
        #expect(preset.defaultMeal == .lunch)

        let outcome = await logger.interpret("log my usual lunch but no curd", now: date(13, dayOffset: 1))
        guard case .draft(let variant) = outcome else { Issue.record("expected preset draft, got \(outcome)"); return }
        #expect(variant.preset?.id == preset.id)
        #expect(variant.items.map(\.displayName) == ["roti", "dal makhani"])
        #expect(Set(variant.items.map(\.id)).isDisjoint(with: preset.items.map(\.id)), "logged copies get fresh IDs")
        await logger.didLog(variant, at: date(13, dayOffset: 1))
        #expect(await repo.all().first?.usageCount == 2)
    }

    @Test("Define a preset by voice, then use it by name")
    func defineByVoice() async throws {
        let repo = MemoryPresetRepository()
        let logger = await logger(repo)
        let outcome = await logger.interpret("remember gym shake is 1 scoop whey, 300 ml milk and a banana", now: date(18))
        guard case .definePreset(let name, let draft) = outcome else { Issue.record("expected define, got \(outcome)"); return }
        #expect(name == "gym shake")
        #expect(draft.items.map(\.displayName) == ["whey protein", "milk", "banana"])
        _ = await logger.savePreset(named: name, from: draft)

        guard case .draft(let used) = await logger.interpret("log gym shake", now: date(19, dayOffset: 1)) else {
            Issue.record("expected the preset"); return
        }
        #expect(used.preset?.name == "Gym shake")
        #expect(abs(used.totals.kcal - draft.totals.kcal) < 0.01)
    }

    @Test("'my usual' picks by meal slot; several plausible presets → picker")
    func usualDisambiguation() async throws {
        let breakfast = FoodPreset(name: "Usual breakfast", items: [], defaultMeal: .breakfast)
        let lunch = FoodPreset(name: "Usual lunch", items: [], defaultMeal: .lunch)
        let logger = await logger(MemoryPresetRepository([breakfast, lunch]))
        guard case .draft(let morning) = await logger.interpret("my usual", now: date(8)) else { Issue.record("draft"); return }
        #expect(morning.preset?.id == breakfast.id)
        guard case .draft(let explicit) = await logger.interpret("my usual lunch", now: date(8)) else { Issue.record("draft"); return }
        #expect(explicit.preset?.id == lunch.id)

        // Exact name beats a longer near-match.
        let gymA = FoodPreset(name: "Gym shake", items: [])
        let gymB = FoodPreset(name: "Gym shake large", items: [])
        guard case .draft(let exact) = await self.logger(MemoryPresetRepository([gymA, gymB])).interpret("my usual gym shake", now: date(18)) else {
            Issue.record("draft"); return
        }
        #expect(exact.preset?.id == gymA.id)

        // Bare "my usual" with presets that carry no meal or time signal → picker.
        let ambiguous = await self.logger(MemoryPresetRepository([gymA, FoodPreset(name: "Protein oats", items: [])]))
            .interpret("my usual", now: date(18))
        guard case .choosePreset(let options, _) = ambiguous else { Issue.record("expected a picker, got \(ambiguous)"); return }
        #expect(options.count == 2)
    }

    @Test("Ordinary food is not hijacked by a loosely similar preset")
    func noFalsePresetMatch() async {
        let preset = FoodPreset(name: "Dal rice combo", items: [])
        let outcome = await logger(MemoryPresetRepository([preset])).interpret("2 rotis and dal", now: date(13))
        guard case .draft(let draft) = outcome else { Issue.record("draft"); return }
        #expect(draft.preset == nil)
    }

    @Test("Refine by text: remove, change quantity, swap, add, no sugar")
    func refine() async throws {
        let logger = await logger()
        guard case .draft(let draft) = await logger.interpret("2 rotis, chicken curry, chai", now: date(20)) else { Issue.record("draft"); return }
        #expect(draft.meal == .dinner && draft.mealWasInferred)

        let fewer = await logger.refine(draft, with: "3 rotis instead of 2")
        #expect(fewer.items.first?.quantity == 3)
        let swapped = await logger.refine(draft, with: "paneer butter masala instead of chicken curry")
        #expect(swapped.items.map(\.displayName) == ["roti", "paneer butter masala", "chai"])
        let noSugar = await logger.refine(draft, with: "no sugar")
        #expect(noSugar.items.count == 3)
        #expect(noSugar.items[2].macros.kcal < draft.items[2].macros.kcal)
        #expect(noSugar.items[0].macros == draft.items[0].macros, "sugar change only touches the drink")
        let removed = await logger.refine(draft, with: "no chai, add a banana")
        #expect(removed.items.map(\.displayName) == ["roti", "chicken curry", "banana"])
        let mealFix = await logger.refine(draft, with: "it was lunch")
        #expect(mealFix.meal == .lunch && !mealFix.mealWasInferred)
    }

    @Test("Unknown foods stay as 'check this' without a key; with a key the model estimates them")
    func unknownFoods() async throws {
        guard case .draft(let offline) = await logger().interpret("a bowl of zorblax stew", now: date(13)) else { Issue.record("draft"); return }
        #expect(offline.items.first?.matchKind == .unresolved)
        #expect(offline.needsReview)

        let groq = MockAIProvider(id: .groqBYOK, script: [.compute { call in
            call.task == .nutritionEstimate ? #"{"grams":250,"kcal":310,"protein":12,"carbs":30,"fat":15}"#
                                            : #"{"items":[{"name":"zorblax stew","quantity":1,"unit":"bowl"}],"mealType":"lunch"}"#
        }])
        let keyed = await Fixtures.gateway([AIStack.deterministicProvider(), groq],
                                           consents: InMemoryConsentStore([.groqBYOK: Fixtures.personalConsent]))
        guard case .draft(let online) = await logger(gateway: keyed).interpret("a bowl of zorblax stew", now: date(13)) else {
            Issue.record("draft"); return
        }
        #expect(online.parsedBy == .groqBYOK)
        #expect(online.items.first?.matchKind == .modelEstimate)
        #expect(online.items.first?.macros.kcal == 310)
    }

    @Test("Non-food and empty input")
    func notFood() async {
        let logger = await logger()
        guard case .notFood = await logger.interpret("remind me to call mom", now: date(9)) else { Issue.record("expected notFood"); return }
        guard case .notFood = await logger.interpret("   ", now: date(9)) else { Issue.record("expected notFood"); return }
        guard case .notFood = await logger.interpret("save this as dinner", now: date(9), current: nil) else { Issue.record("expected notFood"); return }
    }

    @Test("Meal inference from time of day and display names")
    func helpers() {
        #expect(SmartFoodLogger.inferMeal(at: date(7), calendar: istCalendar) == .breakfast)
        #expect(SmartFoodLogger.inferMeal(at: date(13), calendar: istCalendar) == .lunch)
        #expect(SmartFoodLogger.inferMeal(at: date(17), calendar: istCalendar) == .snacks)
        #expect(SmartFoodLogger.inferMeal(at: date(23), calendar: istCalendar) == .dinner)
        #expect(SmartFoodLogger.presetDisplayName("my usual breakfast") == "Usual breakfast")
        #expect(SmartFoodLogger.presetDisplayName("\"gym shake\"") == "Gym shake")
        #expect(SmartFoodLogger.defineIntent("save this as lunch") == nil)
        #expect(SmartFoodLogger.saveCurrentIntent("please save it as my usual dinner") == "my usual dinner")
    }
}

@Suite("Meal modification parser")
struct MealModificationTests {
    let resolver = NutritionResolver()

    private func items(_ text: String) -> [ResolvedFoodItem] { resolver.resolve(DeterministicFoodParser.parse(text)) }

    @Test("Variant splitting")
    func split() {
        #expect(MealModificationParser.splitVariant("usual breakfast but no sugar").modifications == "no sugar")
        #expect(MealModificationParser.splitVariant("usual breakfast without curd").modifications == "no curd")
        #expect(MealModificationParser.splitVariant("usual breakfast").modifications == nil)
    }

    @Test("Operations are recognised", arguments: [
        ("no curd", "remove"), ("curd nahi", "remove"), ("2 eggs instead of 1", "setQuantity"),
        ("only 1 roti", "setQuantity"), ("poha instead of upma", "replace"), ("add a banana", "add"),
        ("extra ghee", "prepare"), ("without sugar", "prepare"), ("half the rice", "setQuantity"),
    ])
    func operations(_ text: String, _ kind: String) {
        let current = items("2 rotis, curd, 1 egg, upma, rice, chai")
        let ops = MealModificationParser.parse(text, current: current)
        let names = ops.map { op -> String in
            switch op {
            case .remove: "remove"
            case .setQuantity: "setQuantity"
            case .replace: "replace"
            case .add: "add"
            case .prepare: "prepare"
            }
        }
        #expect(names == [kind], "\(text) → \(ops)")
    }

    @Test("Applying ops keeps IDs for edited items")
    func applyKeepsIDs() {
        let current = items("2 eggs, toast")
        let updated = MealModificationParser.apply([.setQuantity(target: "egg", quantity: 3, unit: nil)], to: current, resolver: resolver)
        #expect(updated[0].id == current[0].id && updated[0].quantity == 3)
        let grams = MealModificationParser.apply([.setQuantity(target: "toast", quantity: 60, unit: "g")], to: current, resolver: resolver)
        #expect(grams[1].grams == 60 && grams[1].id == current[1].id)
    }
}

@Suite("Preset resolver & routine miner")
struct PresetMiningTests {

    private func meal(_ names: [String], dayOffset: Int, hour: Int = 8, slot: ParsedMeal.MealSlot = .breakfast) -> LoggedMeal {
        LoggedMeal(date: date(hour, dayOffset: dayOffset), meal: slot,
                   items: names.map { .init(name: $0, macros: Macros(kcal: 100, protein: 2, carbs: 15, fat: 3), servingDescription: "1 serving") })
    }

    @Test("Exact, alias, typo and time-window resolution")
    func resolution() {
        var shake = FoodPreset(name: "Gym shake", aliases: ["protein shake"], items: [])
        for day in 0..<4 { shake.recordUse(at: date(18, dayOffset: -day)) }
        let breakfast = FoodPreset(name: "Usual breakfast", items: [], defaultMeal: .breakfast)
        let resolver = PresetResolver(presets: [shake, breakfast], calendar: istCalendar)
        #expect(resolver.resolve("gym shake") == .match(shake))
        #expect(resolver.resolve("protein shake") == .match(shake))
        #expect(resolver.resolve("gim shak") == .match(shake))
        #expect(resolver.resolve("usual breakfast") == .match(breakfast))
        #expect(resolver.resolve("pizza") == .none)
        #expect(shake.typicalHourRange(calendar: istCalendar)?.contains(18.25) == true)
        var archived = shake
        archived.archived = true
        #expect(PresetResolver(presets: [archived]).resolve("gym shake") == .none)
    }

    @Test("Finds a weekday routine, skips covered and dismissed ones, ignores noise")
    func mining() throws {
        // Mon 5 Oct … : poha + chai on weekdays, random lunches.
        var history: [LoggedMeal] = []
        for offset in [-14, -11, -10, -9, -8, -7, -4, -3, -2, -1] where !istCalendar.isDateInWeekend(date(8, dayOffset: offset)) {
            history.append(meal(["Poha", "Chai"], dayOffset: offset))
        }
        history.append(meal(["Pizza", "Cola"], dayOffset: -5, hour: 13, slot: .lunch))
        history.append(meal(["Biryani", "Raita"], dayOffset: -6, hour: 13, slot: .lunch))

        let suggestion = try #require(RoutineMiner.suggest(history: history, existing: [], now: date(9), calendar: istCalendar))
        #expect(suggestion.name == "Poha & Chai")
        #expect(suggestion.meal == .breakfast)
        #expect(suggestion.weekdaysOnly)
        #expect(suggestion.occurrences >= 3)
        #expect(suggestion.message.contains("poha and chai"))

        let covered = FoodPreset(name: "Morning", items: suggestion.items)
        #expect(RoutineMiner.suggest(history: history, existing: [covered], now: date(9), calendar: istCalendar) == nil)
        #expect(RoutineMiner.suggest(history: history, existing: [], dismissed: [suggestion.id], now: date(9), calendar: istCalendar) == nil)
        #expect(RoutineMiner.suggest(history: Array(history.prefix(2)), existing: [], now: date(9), calendar: istCalendar) == nil)
    }

    @Test("File preset store persists and records usage")
    func fileStore() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("presets-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FilePresetRepository(url: url)
        let preset = FoodPreset(name: "Gym shake", items: [])
        await store.save(preset)
        await store.recordUse(preset.id, at: date(18))
        let reloaded = FilePresetRepository(url: url)
        #expect(await reloaded.all().first?.usageCount == 1)
        await reloaded.delete(preset.id)
        #expect(await reloaded.all().isEmpty)
    }

    @Test("Namer")
    func namer() {
        #expect(PresetNamer.suggest(items: ["poha"], meal: .breakfast) == "Poha")
        #expect(PresetNamer.suggest(items: ["roti", "dal", "curd"], meal: .lunch) == "Usual lunch")
        #expect(PresetNamer.suggest(items: ["roti", "dal", "curd"], meal: .lunch, weekdaysOnly: true) == "Weekday lunch")
    }
}
