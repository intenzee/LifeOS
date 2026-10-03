import Foundation
import Testing
@testable import LifeOSAI

@Suite("Context engine (F05)")
struct ContextEngineTests {
    let embedder = HashingEmbedder()

    func engine() -> ContextEngine { ContextEngine(embedder: embedder) }

    @Test("Intent plan: health intents always carry time and today")
    func plan() async {
        let ctx = LifeFixtures.steadyUser()
        for intent in AIIntent.allCases {
            let bundle = await engine().packet(for: ContextQuery(intent: intent, text: "hi"), context: ctx)
            #expect(bundle.slices.contains(.time), "\(intent) has no time")
            if intent.needsToday { #expect(bundle.slices.contains(.today), "\(intent) has no today") }
            #expect(bundle.tokenEstimate <= bundle.budget)
        }
        let explain = await engine().packet(for: ContextQuery(intent: .explainBudget), context: ctx)
        #expect(explain.slices.contains(.budget))
        let food = await engine().packet(for: ContextQuery(intent: .logFood, text: "log my usual lunch"), context: ctx)
        #expect(food.slices.contains(.mealWindow) && food.slices.contains(.preset))
        #expect(!food.slices.contains(.today))
    }

    @Test("Rendering is terse key=value text with exact numbers on device")
    func rendering() async {
        let ctx = LifeFixtures.steadyUser()
        let bundle = await engine().packet(for: ContextQuery(intent: .askProgress, text: "how am I doing"), context: ctx)
        let text = bundle.packet.rendered()
        #expect(text.hasPrefix(ContextEngine.preamble))
        #expect(text.contains("eaten=930/2,195 kcal; left=1,265"))
        #expect(text.contains("evening run 42 min 290 kcal (Apple Watch)"))
        #expect(text.contains("age=31"))
        #expect(!text.contains("{"))      // not JSON
    }

    @Test("Third-party packets: no age/sex, rounded numbers, no todo titles, only food-preference memories")
    func thirdParty() async {
        let memories = ["I don't eat oats", "Leg day is on Mondays", "I'm training for a 10k in December"].compactMap { LifeFixtures.memory($0) }
        var diabetes = MemoryReconciler.apply(MemoryExtractor.extract(from: "I have diabetes", now: LifeFixtures.now, calendar: LifeFixtures.calendar)[0],
                                              to: [], embedder: embedder, now: LifeFixtures.now).record
        diabetes.status = .active
        let ctx = LifeFixtures.steadyUser(memories: memories + [diabetes])

        for intent in [AIIntent.generalChat, .nudge, .whatShouldIEat, .askProgress, .briefing] {
            let bundle = await engine().packet(for: ContextQuery(intent: intent, text: "what should I eat, and my diabetes?", destination: .thirdParty),
                                               context: ctx)
            let text = bundle.packet.rendered()
            #expect(!text.contains("age="), "\(intent)")
            #expect(!text.contains("sex="), "\(intent)")
            #expect(!text.contains("Priya"), "\(intent)")          // todo title
            #expect(!text.lowercased().contains("diabetes"), "\(intent)")
            #expect(!text.contains("Leg day"), "\(intent)")
            #expect(!text.contains("2,195"), "\(intent)")          // rounded to 2,200
        }
        // A packet built for the device carries a restricted version the gateway uses for T3.
        let device = await engine().packet(for: ContextQuery(intent: .nudge, text: "remind me", destination: .onDevice), context: ctx)
        let forCloud = device.packet.forThirdParty(maxPrivacy: .health).rendered()
        #expect(device.packet.rendered().contains("Priya"))
        #expect(!forCloud.contains("Priya"))
        #expect(!forCloud.contains("age="))
    }

    @Test("Never exceeds the budget (randomised data, 300 runs)")
    func budgetProperty() async {
        var rng = SystemRandomNumberGenerator()
        let engine = engine()
        for run in 0..<300 {
            var ctx = LifeFixtures.steadyUser()
            // Random noise: very long meal names, many presets and memories, long todos.
            let n = Int.random(in: 0...40, using: &rng)
            ctx.presets += (0..<n).map { i in .init(id: "x\(i)", name: String(repeating: "masala ", count: Int.random(in: 1...12, using: &rng)), kcal: 300) }
            ctx.todos += (0..<Int.random(in: 0...20, using: &rng)).map { .init(id: "td\($0)", title: String(repeating: "errand ", count: 10)) }
            ctx.memories = (0..<Int.random(in: 0...30, using: &rng)).compactMap { i in
                LifeFixtures.memory(["I don't eat oats", "I love paneer \(i)", "Leg day is on Mondays", "my katori is about 1\(i % 9)0 ml"][i % 4])
            }
            if let last = ctx.days.indices.last {
                ctx.days[last].meals += (0..<Int.random(in: 0...30, using: &rng)).map { _ in
                    LifeFixtures.meal(String(repeating: "thali ", count: 8), .dinner, 100, at: LifeFixtures.now)
                }
            }
            let intent = AIIntent.allCases.randomElement(using: &rng)!
            let destination = ContextDestination.allCases.randomElement(using: &rng)!
            let budget = [150, 300, 600, 2_000].randomElement(using: &rng)!
            let bundle = await engine.packet(for: ContextQuery(intent: intent, text: "q", destination: destination), context: ctx, budget: budget)
            #expect(bundle.tokenEstimate <= budget || bundle.slices.allSatisfy { ContextEngine.required(for: intent).contains($0) },
                    "run \(run): \(bundle.tokenEstimate) > \(budget)")
        }
    }

    @Test("p95 packet build under 50 ms with a year of data")
    func latency() async {
        var ctx = LifeFixtures.steadyUser()
        let base = ctx.days[0]
        ctx.days = (0..<365).map { offset in
            var d = base
            d.date = LifeFixtures.calendar.date(byAdding: .day, value: -364 + offset, to: LifeFixtures.calendar.startOfDay(for: LifeFixtures.now))!
            return d
        }
        ctx.memories = (0..<300).compactMap { LifeFixtures.memory("I love food number \($0)") }
        let engine = engine()
        var times: [Double] = []
        for i in 0..<40 {
            let start = Date()
            _ = await engine.packet(for: ContextQuery(intent: AIIntent.allCases[i % AIIntent.allCases.count], text: "how am I doing this week"), context: ctx)
            times.append(Date().timeIntervalSince(start) * 1_000)
        }
        let p95 = times.sorted()[Int(Double(times.count) * 0.95) - 1]
        print("context packet p95: \(p95) ms")
        #expect(p95 < 50, "p95 \(p95) ms")
    }

    @Test("Cache: trend slice reused within 15 min, invalidated by events")
    func cache() async {
        let engine = engine()
        var ctx = LifeFixtures.steadyUser()
        let first = await engine.packet(for: ContextQuery(intent: .askProgress), context: ctx)
        ctx.days[ctx.days.count - 2].meals.append(LifeFixtures.meal("Pizza", .dinner, 900, at: LifeFixtures.date(1, 21)))
        let cached = await engine.packet(for: ContextQuery(intent: .askProgress), context: ctx)
        #expect(first.packet.sections.first { $0.title == "trend" } == cached.packet.sections.first { $0.title == "trend" })
        await engine.invalidate(.foodLogged)
        let fresh = await engine.packet(for: ContextQuery(intent: .askProgress), context: ctx)
        #expect(first.packet.sections.first { $0.title == "trend" } != fresh.packet.sections.first { $0.title == "trend" })
    }

    @Test("Diet memories filter presets out of food context")
    func presetsRespectDiet() async {
        let ctx = LifeFixtures.steadyUser(memories: [LifeFixtures.memory("I'm vegetarian")!])
        let bundle = await engine().packet(for: ContextQuery(intent: .whatShouldIEat, text: "dinner ideas"), context: ctx)
        #expect(!bundle.packet.rendered().contains("Chicken wrap"))
        #expect(bundle.packet.rendered().contains("You're vegetarian"))
        #expect(!bundle.usedMemoryIDs.isEmpty)
    }

    @Test("Intent classifier")
    func classify() {
        #expect(AIIntent.classify("Why is my target higher today?") == .explainBudget)
        #expect(AIIntent.classify("What should I eat for dinner?") == .whatShouldIEat)
        #expect(AIIntent.classify("log 2 eggs") == .logFood)
        #expect(AIIntent.classify("How did I do this week?") == .weeklyReview)
        #expect(AIIntent.classify("how many calories left") == .askProgress)
        #expect(AIIntent.classify("tell me a joke") == .generalChat)
    }
}

@Suite("Learned meal windows (F02/F05, FOOD-16)")
struct MealWindowTests {
    let cal = LifeFixtures.calendar

    /// Synthetic personas: (breakfast, lunch, snack, dinner) typical times in minutes.
    static let personas: [(name: String, times: [ParsedMeal.MealSlot: Int])] = [
        ("late eater", [.breakfast: 10 * 60 + 45, .lunch: 15 * 60 + 30, .snacks: 18 * 60 + 30, .dinner: 23 * 60]),
        ("early bird", [.breakfast: 6 * 60 + 30, .lunch: 11 * 60 + 45, .snacks: 15 * 60 + 30, .dinner: 18 * 60 + 45]),
        ("night shift", [.breakfast: 14 * 60, .lunch: 19 * 60, .dinner: 2 * 60 + 30]),
        ("typical", [.breakfast: 8 * 60 + 30, .lunch: 13 * 60 + 30, .snacks: 17 * 60 + 15, .dinner: 21 * 60]),
    ]

    func history(_ times: [ParsedMeal.MealSlot: Int], days: Int = 21) -> [(slot: ParsedMeal.MealSlot, time: Date)] {
        (0..<days).flatMap { day in
            times.map { slot, minute -> (slot: ParsedMeal.MealSlot, time: Date) in
                let jitter = (day * 37 % 61) - 30            // ±30 min, deterministic
                let base = cal.date(byAdding: .day, value: -day - 1, to: cal.startOfDay(for: LifeFixtures.now))!
                return (slot, base.addingTimeInterval(Double(minute + jitter) * 60))
            }
        }
    }

    @Test("Learned windows beat fixed hours by ≥ 10 points (Phase 2 exit criterion)")
    func improvement() {
        var fixedCorrect = 0, learnedCorrect = 0, total = 0
        for persona in Self.personas {
            let windows = MealWindows.learn(history(persona.times), calendar: cal)
            for (slot, minute) in persona.times {
                for offset in [-40, -15, 0, 20, 45] {
                    let t = cal.startOfDay(for: LifeFixtures.now).addingTimeInterval(Double(minute + offset) * 60)
                    total += 1
                    if SmartFoodLogger.inferMeal(at: t, calendar: cal) == slot { fixedCorrect += 1 }
                    if (windows.slot(at: t, calendar: cal) ?? SmartFoodLogger.inferMeal(at: t, calendar: cal)) == slot { learnedCorrect += 1 }
                }
            }
        }
        let fixed = Double(fixedCorrect) / Double(total), learned = Double(learnedCorrect) / Double(total)
        print("meal-type accuracy: fixed \(Int(fixed * 100))% → learned \(Int(learned * 100))% (\(total) cases)")
        #expect(learned - fixed >= 0.10)
        #expect(learned >= 0.9)
    }

    @Test("Too little history → nil (fixed hours take over); windows summarise as text")
    func sparse() {
        let few = MealWindows.learn([(.lunch, LifeFixtures.date(1, 13)), (.lunch, LifeFixtures.date(30, 13, month: 9))], calendar: cal)
        #expect(few.isEmpty)
        let typical = MealWindows.learn(history(Self.personas[3].times), calendar: cal)
        #expect(typical.summaryLines.first?.hasPrefix("usual breakfast 08:") == true)
    }

    @Test("Several items logged together count as one occasion")
    func occasions() {
        let d = LifeFixtures.date(1, 13)
        let windows = MealWindows.learn([(.lunch, d), (.lunch, d), (.lunch, d.addingTimeInterval(60))], calendar: cal)
        #expect(windows.isEmpty)
    }
}

@Suite("Portion hints from memory (F04)")
struct PortionHintTests {
    @Test("My katori and my roti change grams; nothing else does")
    func hints() {
        let memories = ["my katori is about 120 ml", "my roti weighs 30g"].compactMap { LifeFixtures.memory($0) }
        let hints = PortionHints(memories: memories, now: LifeFixtures.now)
        let plain = NutritionResolver()
        let mine = NutritionResolver(portionHints: hints)
        let dal = ParsedFoodItem(name: "dal", quantity: 1, unit: "katori")
        let roti = ParsedFoodItem(name: "roti", quantity: 2, unit: "piece")
        #expect(mine.resolve(dal).grams! < plain.resolve(dal).grams!)
        #expect(abs(mine.resolve(dal).grams! - plain.resolve(dal).grams! * 120 / 150) < 0.5)
        #expect(mine.resolve(roti).grams == 60)
        let rice = ParsedFoodItem(name: "rice", quantity: 1, unit: "cup")
        #expect(mine.resolve(rice).grams == plain.resolve(rice).grams)
    }

    @Test("SmartFoodLogger uses learned windows when inferring the meal")
    func loggerWindows() async {
        let gateway = AIStack.makeGateway(.init(credentials: StaticCredentials(), consents: InMemoryConsentStore()))
        await gateway.setDebugOverrides(.init(forcedUnavailable: [.appleOnDevice, .applePCC]))   // iPhone 15
        let late = MealWindows.learn(MealWindowTests().history(MealWindowTests.personas[0].times), calendar: LifeFixtures.calendar)
        var logger = SmartFoodLogger(gateway: gateway, presets: MemoryPresetRepository())
        logger.calendar = LifeFixtures.calendar
        logger.mealWindows = { late }
        // 16:00 is "snacks" by the clock, but this user has lunch at 15:30.
        let outcome = await logger.interpret("2 rotis and dal", now: LifeFixtures.date(2, 16))
        guard case .draft(let draft) = outcome else { Issue.record("no draft"); return }
        #expect(draft.meal == .lunch)
    }
}

@Suite("Sensitive memories never reach Gemini or Groq (memory card copy)")
struct SensitiveIsolationTests {
    let embedder = HashingEmbedder()

    func context() -> LifeContext {
        var pcos = MemoryReconciler.apply(MemoryExtractor.extract(from: "I have PCOS", now: LifeFixtures.now, calendar: LifeFixtures.calendar)[0],
                                          to: [], embedder: embedder, now: LifeFixtures.now).record
        pcos.status = .active          // the user tapped "Remember"
        pcos.pinned = true             // and pinned it, so retrieval ranks it first
        var ctx = LifeFixtures.steadyUser(memories: [pcos, LifeFixtures.memory("I don't eat oats")!])
        ctx.conversationSummary = ConversationLog(turns: [.init(fromUser: true, text: "I have PCOS, what should I eat?"),
                                                          .init(fromUser: true, text: "how's my protein")]).window().summary
        return ctx
    }

    @Test("Packets built for Gemini/Groq, and device packets as the gateway sends them, exclude it — every intent")
    func packets() async {
        let engine = ContextEngine(embedder: embedder)
        let ctx = context()
        for provider in [ProviderID.geminiBYOK, .groqBYOK] {
            #expect(ContextDestination(provider: provider) == .thirdParty)
            for intent in AIIntent.allCases {
                let direct = await engine.packet(for: ContextQuery(intent: intent, text: "pcos diet ideas", destination: ContextDestination(provider: provider)),
                                                 context: ctx)
                #expect(!direct.packet.rendered().lowercased().contains("pcos"), "\(provider) \(intent)")
            }
        }
        for intent in AIIntent.allCases {
            let device = await engine.packet(for: ContextQuery(intent: intent, text: "pcos diet ideas", destination: .onDevice), context: ctx)
            let sent = device.packet.forThirdParty(maxPrivacy: .health).rendered().lowercased()
            #expect(!sent.contains("pcos"), "fallback \(intent)")
        }
        // On device it is used.
        let device = await engine.packet(for: ContextQuery(intent: .generalChat, text: "pcos", destination: .onDevice), context: ctx)
        #expect(device.packet.rendered().contains("PCOS"))
    }

    @Test("End to end through the gateway: neither planner nor composer prompt carries it")
    func gatewayPath() async {
        let gemini = MockAIProvider(id: .geminiBYOK, script: [
            .respond(#"{"toolCalls":[{"name":"getTodayStatus","argumentsJSON":"{}"}]}"#),
            .respond("You've eaten 930 kcal so far."),
        ])
        let gateway = AIGateway(providers: [gemini], consents: InMemoryConsentStore([
            .geminiBYOK: CloudConsent(maxPrivacy: .health, grantedAt: Date(), source: .consentSheet),
        ]))
        let engine = AssistantEngine(gateway: gateway, contextEngine: ContextEngine(embedder: embedder))
        var log = ConversationLog()
        log.append(user: "I have PCOS")
        log.append(assistant: "That's health information, so I'll only keep it if you say so.")
        _ = await engine.answer("how am I doing today", context: context(), conversation: log)
        #expect(gemini.callCount == 2)
        for call in gemini.calls {
            let sent = (call.fullInstructions + call.fullUserText).lowercased()
            #expect(!sent.contains("pcos"))
        }
    }
}
