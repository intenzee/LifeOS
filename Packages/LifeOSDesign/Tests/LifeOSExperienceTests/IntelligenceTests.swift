import Foundation
import Testing
@testable import LifeOSExperienceCore

/// Fixtures: a fixed calendar and a synthetic 4-week history.
private enum Fx {
    static var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        c.firstWeekday = 2
        return c
    }()
    /// Saturday 3 Oct 2026, 7 pm.
    static let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 19))!

    static func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: now))! }
    static func at(_ d: Date, _ h: Int) -> Date { cal.date(bySettingHour: h, minute: 0, second: 0, of: d)! }

    static func history(weekendExtra: Double = 700, poha: Bool = true) -> [DayFacts] {
        (0..<28).reversed().map { off in
            let d = day(off)
            let weekend = cal.isDateInWeekend(d)
            var meals: [DayFacts.Meal] = []
            if poha { meals.append(.init(name: "Poha", slot: .breakfast, kcal: 250, protein: 5, time: at(d, 8))) }
            meals.append(.init(name: "Dal", slot: .lunch, kcal: 600, protein: 25, time: at(d, 13)))
            meals.append(.init(name: off % 2 == 0 ? "Paneer curry" : "Chicken curry", slot: .dinner, kcal: 700 + (weekend ? weekendExtra : 0),
                               protein: 30, time: at(d, 20)))
            let weekday = cal.component(.weekday, from: d)
            let gym = [2, 4, 6].contains(weekday)
            return DayFacts(date: d, meals: off == 0 ? Array(meals.prefix(2)) : meals, budget: 1800, water: off == 0 ? 3 : 8,
                            workoutKcal: gym ? 250 : 0, gymSets: gym ? 12 : 0, weightKg: off % 7 == 0 ? 80 - Double(28 - off) * 0.05 : nil)
        }
    }

    static func snapshot(memories: [MemoryItem] = [], days: [DayFacts] = history()) -> IntelligenceSnapshot {
        IntelligenceSnapshot(days: days, now: now, proteinTarget: 120,
                             budgetToday: ExperienceBudget(baseLimit: 1571, activeEnergy: 443, eatBackShare: 0.5, eaten: 850),
                             memories: memories, calendar: cal)
    }
}

@Suite struct AssistantBrainTests {
    @Test func budgetAnswerLeadsWithTheNumberAndExplains() {
        let r = AssistantBrain.reply(to: "Why is my budget higher today?", Fx.snapshot())
        #expect(r.text.hasPrefix("You're 943 under."))
        #expect(r.text.contains("700 kcal dinner keeps you on track"))
        #expect(r.text.contains("Budget 1,793 = 1,571 base + 222 earned from activity."))
        #expect(r.basedOn != nil)
    }

    @Test func proteinUsesTheWeekAndAChart() {
        let r = AssistantBrain.reply(to: "How's my protein this week?", Fx.snapshot())
        #expect(r.text.contains("under target"))
        if case let .chart(_, points, goal, unit) = r.card {
            #expect(points.count == 14)
            #expect(goal == 120)
            #expect(unit == "g")
        } else { Issue.record("expected a chart") }
    }

    @Test func safetyRedirectsAreKindAndFirm() {
        let low = AssistantBrain.reply(to: "Make me an 800 kcal a day diet plan", Fx.snapshot())
        #expect(low.isSafetyRedirect)
        #expect(low.text.contains("1,200"))
        let meds = AssistantBrain.reply(to: "Should I change my metformin dose?", Fx.snapshot())
        #expect(meds.isSafetyRedirect)
        #expect(meds.text.hasPrefix("I can't advise on medication"))
    }

    @Test func rememberAndForget() {
        let r = AssistantBrain.reply(to: "Remember that I'm vegetarian", Fx.snapshot())
        guard case let .remembered(item) = r.card else { Issue.record("expected memory"); return }
        #expect(item.text == "You're vegetarian")
        #expect(item.category == .foodHabits)
        #expect(item.source == .youSaid)
        let f = AssistantBrain.reply(to: "forget that I'm vegetarian", Fx.snapshot(memories: [item]))
        #expect(f.card == .forgotten([item]))
    }

    @Test func planRespectsMemoryAndCap() {
        let veg = MemoryItem(id: "v", text: "You're vegetarian", category: .foodHabits, source: .youSaid, createdAt: Fx.now)
        let r = AssistantBrain.reply(to: "Plan dinner under 800 kcal", Fx.snapshot(memories: [veg]))
        guard case let .list(_, rows) = r.card else { Issue.record("expected list"); return }
        #expect(!rows.contains { $0.title.lowercased().contains("chicken") })
        #expect(rows.allSatisfy { $0.kcal <= 800 })
        #expect(r.usedMemories == [veg])
    }

    @Test func routesLoggingRemindersAndUnknowns() {
        #expect(AssistantBrain.reply(to: "Log 2 eggs and toast", Fx.snapshot()).card == .logProposal(sentence: "2 eggs and toast"))
        if case let .rule(rule) = AssistantBrain.reply(to: "Remind me to drink water every 2 hours", Fx.snapshot()).card {
            #expect(rule.trigger == .everyHours(2, fromHour: 9, toHour: 21))
            #expect(rule.name == "Drink water")
        } else { Issue.record("expected rule") }
        #expect(AssistantBrain.reply(to: "What's the capital of France?", Fx.snapshot()).needsModel)
    }

    @Test func frequentDinners() {
        let r = AssistantBrain.reply(to: "What are my most frequent dinners?", Fx.snapshot())
        guard case let .list(_, rows) = r.card else { Issue.record("expected list"); return }
        #expect(Set(rows.map(\.title)) == ["Paneer curry", "Chicken curry"])
    }
}

@Suite struct MemoryTests {
    @Test func secondPersonRewrite() {
        #expect(MemoryPhrases.rememberedText(from: "remember I am training for a 10k.") == "You are training for a 10k")
        #expect(MemoryPhrases.rememberedText(from: "remember my gym is at 7 am") == "Your gym is at 7 am")
        #expect(MemoryPhrases.rememberedText(from: "how much protein") == nil)
        #expect(MemoryPhrases.category(for: "You prefer short answers") == .preferences)
    }

    @Test func infersUsualsRoutinesAndWeekendPattern() {
        let items = MemoryInference.infer(from: Fx.snapshot())
        let ids = Set(items.map(\.id))
        #expect(ids.contains("usual.breakfast"))
        #expect(items.first { $0.id == "usual.breakfast" }?.text == "Usual breakfast is Poha (250 kcal), usually around 8 am")
        #expect(items.first { $0.id == "routine.gym" }?.text == "Gym on Mon, Wed, Fri")
        #expect(items.first { $0.id == "insight.weekend" }?.text == "Weekend intake runs about 700 kcal higher than weekdays")
        #expect(items.allSatisfy { $0.confidenceWord == "likely" })
    }

    @Test func noPatternWithoutEvidence() {
        let items = MemoryInference.infer(from: Fx.snapshot(days: Fx.history(weekendExtra: 50, poha: false)))
        #expect(!items.contains { $0.id == "insight.weekend" || $0.id == "usual.breakfast" })
    }
}

@Suite struct InsightTests {
    @Test func eveningRecapCopy() {
        let d = DayFacts(date: Fx.day(0), meals: [.init(name: "x", slot: .lunch, kcal: 1840, protein: 118, time: Fx.now)], budget: 1920, water: 9)
        #expect(Briefs.eveningRecap(d, perfectDay: true) == "Today: 1,840 of 1,920 kcal, 118 g protein, 9 glasses. Perfect day kept.")
        let over = DayFacts(date: Fx.day(0), meals: [.init(name: "x", slot: .lunch, kcal: 2040, protein: 80, time: Fx.now)], budget: 1920, water: 1)
        #expect(Briefs.eveningRecap(over, perfectDay: false).hasSuffix("1 glass. 120 over. Tomorrow resets."))
    }

    @Test func weeklyReviewHasAllPages() throws {
        let r = try #require(WeeklyReview.make(Fx.snapshot()))
        #expect(r.daily.count == 7)
        #expect(r.workouts == 3)
        #expect(r.pattern?.id == "pattern.weekend")
        #expect(r.bestDay != nil)
        #expect(r.focus.actionTitle == "Create reminder")
        #expect(WeeklyReview.make(Fx.snapshot(days: [])) == nil)
    }
}

@Suite struct AutomationTests {
    private let water = AutomationTemplates.all.first { $0.rule.id == "t.water" }!.rule

    @Test func sentences() {
        #expect(AutomationText.sentence(water, calendar: Fx.cal) == "Every day at 2 pm, if I've had under 4 glasses, remind me: Have a glass of water")
        let breakfast = AutomationTemplates.all.first { $0.rule.id == "t.usualBreakfast" }!.rule
        #expect(AutomationText.sentence(breakfast, calendar: Fx.cal) == "On weekdays at 8 am, if breakfast isn't logged, suggest my usual breakfast")
    }

    @Test func parserReadsTimesAndDays() {
        let r = AutomationParser.parse("remind me to take my vitamins every monday at 7:30 am")
        #expect(r?.trigger == .time(hour: 7, minute: 30, weekdays: [2]))
        #expect(r?.name == "Take your vitamins")
        #expect(AutomationParser.parse("nudge me to stretch at 6")?.trigger == .time(hour: 18, minute: 0, weekdays: []))
        #expect(AutomationParser.parse("how much water today") == nil)
    }

    @Test func plannerDropsMetConditionsHonoursQuietHoursAndCap() {
        var today = Fx.history().last!
        let morning = Fx.cal.date(bySettingHour: 9, minute: 0, second: 0, of: Fx.now)!
        // 3 glasses so far: today's 2 pm water nudge is still due.
        var plan = AutomationPlanner.plan([water], now: morning, today: today, proteinTarget: 120, days: 2, calendar: Fx.cal)
        #expect(plan.count == 2)
        // 5 glasses: today's nudge is dropped, tomorrow's stays.
        today.water = 5
        plan = AutomationPlanner.plan([water], now: morning, today: today, proteinTarget: 120, days: 2, calendar: Fx.cal)
        #expect(plan.count == 1)
        // Hourly 9 am–11 pm: quiet hours remove 10 and 11 pm, cap keeps 4 a day.
        let hourly = AutomationRule(id: "h", name: "h", trigger: .everyHours(1, fromHour: 9, toHour: 23), action: .notify("x"))
        plan = AutomationPlanner.plan([hourly], now: Fx.day(-1), today: nil, proteinTarget: 0, days: 1, calendar: Fx.cal)
        #expect(plan.count == 4)
        #expect(plan.allSatisfy { Fx.cal.component(.hour, from: $0.fireDate) < 22 })
    }

    @Test func backtestCountsLastWeek() {
        let week = Array(Fx.history().suffix(7))
        let weighIn = AutomationTemplates.all.first { $0.rule.id == "t.weighIn" }!.rule
        #expect(AutomationPlanner.backtest(water, days: week, proteinTarget: 120, calendar: Fx.cal) == 1) // only today was under 4
        #expect(AutomationPlanner.backtest(weighIn, days: week, proteinTarget: 120, calendar: Fx.cal) <= 1)
    }
}
