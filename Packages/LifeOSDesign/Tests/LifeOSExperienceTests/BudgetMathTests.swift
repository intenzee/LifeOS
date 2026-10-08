import Foundation
import Testing
@testable import LifeOSExperienceCore

@Suite struct BudgetMathTests {
    @Test func matchesThePlansWorkedExample() {
        // Phase 3 §3.10 shape: base + earned (50% of active) − eaten.
        let b = ExperienceBudget(baseLimit: 1571, activeEnergy: 443, eatBackShare: 0.5, eaten: 1153)
        #expect(b.earned == 222)          // 221.5 rounds to 222
        #expect(b.budget == 1793)
        #expect(b.remaining == 640)
        #expect(!b.isOver)
        #expect(ExperienceCopy.remainingHeadline(b).label == "kcal left")
    }

    @Test func overBudgetIsCalmAndExplicit() {
        let b = ExperienceBudget(baseLimit: 1500, activeEnergy: 0, eatBackShare: 0.5, eaten: 1620)
        #expect(b.isOver)
        #expect(ExperienceCopy.remainingHeadline(b) == ("120", "over today"))
        #expect(ExperienceCopy.overNote(b) == "120 over today. Tomorrow resets.")
        #expect(b.lines().last?.label == "Over today")
    }

    @Test func neverNaNOrNegativeInputs() {
        let zero = ExperienceBudget(baseLimit: 0, activeEnergy: .nan, eatBackShare: .infinity, eaten: 300)
        #expect(zero.fill == 0)
        #expect(zero.earned == 0)
        let weird = ExperienceBudget(baseLimit: -50, activeEnergy: -100, eatBackShare: 2, eaten: -10)
        #expect(weird.budget == 0)
        #expect(weird.remaining == 0)
    }

    @Test func explainerLinesTellTheStory() {
        let b = ExperienceBudget(baseLimit: 1571, activeEnergy: 443, eatBackShare: 0.5, eaten: 1153)
        let lines = b.lines(activeSourceNote: "Apple Health")
        #expect(lines.map(\.id) == ["base", "earned", "budget", "eaten", "remaining"])
        #expect(lines[1].note == "50% of 443 active kcal.")
        #expect(lines[1].source == "Apple Health")
        let off = ExperienceBudget(baseLimit: 1500, activeEnergy: 300, eatBackShare: 0, eaten: 0)
        #expect(off.lines()[1].note == "0% of 300 active kcal.")
        let noActivity = ExperienceBudget(baseLimit: 1500, activeEnergy: 0, eatBackShare: 0, eaten: 0)
        #expect(noActivity.lines()[1].note == "Counting activity is off in Settings.")
    }

    @Test func mealSlotFromTimeOfDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        func at(_ h: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: h, minute: 5))! }
        #expect(ExperienceMealSlot.slot(for: at(8), calendar: cal) == .breakfast)
        #expect(ExperienceMealSlot.slot(for: at(13), calendar: cal) == .lunch)
        #expect(ExperienceMealSlot.slot(for: at(17), calendar: cal) == .snack)
        #expect(ExperienceMealSlot.slot(for: at(21), calendar: cal) == .dinner)
        #expect(ExperienceMealSlot.slot(for: at(2), calendar: cal) == .dinner)
    }

    @Test func autoTargetShowsTheSpecLayout() {
        let b = ExperienceBudget(baseLimit: 1571, activeEnergy: 443, eatBackShare: 0.5, eaten: 1153)
        let lines = b.lines(derivation: .init(maintenance: 2121, adjustment: -550, weeklyChangeKg: -0.5))
        #expect(lines.map(\.id) == ["maintenance", "goal", "base", "earned", "budget", "eaten", "remaining"])
        #expect(lines[1].label == "Goal: lose 0.5 kg/week")
        #expect(lines[1].kcal == -550)
        #expect(lines[2].note == nil)
    }

    @Test func floorIsExplained() {
        let b = ExperienceBudget(baseLimit: 1500, activeEnergy: 0, eatBackShare: 0.5, eaten: 0)
        let lines = b.lines(derivation: .init(maintenance: 1800, adjustment: -550, weeklyChangeKg: -0.5))
        #expect(lines.first(where: { $0.id == "base" })?.note == "Raised to a safe minimum of 1,500 kcal.")
        let maintain = ExperienceBudget(baseLimit: 2100, activeEnergy: 0, eatBackShare: 0.5, eaten: 0)
        #expect(Array(maintain.lines(derivation: .init(maintenance: 2100, adjustment: 0, weeklyChangeKg: 0)).map(\.id).prefix(2)) == ["maintenance", "base"])
    }

    @Test func engineBudgetIsTakenAsIs() {
        // CAL-03: the engine capped the credit (300 of 50% × 800), so earned is
        // its credit, not a share of active energy, and the total is its total.
        let b = ExperienceBudget.engine(budget: 2100, credit: 300, rawActive: 800, eatBack: 0.5, eaten: 1500,
                                        lines: [.init(kind: .bmr, kcal: 1500), .init(kind: .everydayActivity, kcal: 300),
                                                .init(kind: .goal, kcal: -300), .init(kind: .floorTopUp, kcal: 300),
                                                .init(kind: .exerciseCredit, kcal: 300)])
        #expect(b.earned == 300)
        #expect(b.budget == 2100)
        #expect(b.remaining == 600)
        let ids = b.lines().map(\.id)
        // Engine order (floor before credit, formula v2), then the totals.
        #expect(ids == ["bmr0", "everyday1", "goal2", "floor3", "earned", "budget", "eaten", "remaining"])
        #expect(b.lines().first { $0.id == "budget" }?.kcal == 2100)
    }

    @Test func engineWithoutCreditStillShowsEarnedLine() {
        let b = ExperienceBudget.engine(budget: 1800, credit: 0, rawActive: 0, eatBack: 0, eaten: 0,
                                        lines: [.init(kind: .manualTarget, kcal: 1800)])
        let earned = b.lines().first { $0.id == "earned" }
        #expect(earned?.kcal == 0)
        #expect(earned?.note == "Counting activity is off in Settings.")
    }

    @Test func activityNoteFollowsEngineMode() {
        // Measured: logged sets don't add credit, so the note must not promise it.
        let measuredIdle = ExperienceBudget.engine(budget: 1800, credit: 0, rawActive: 120, eatBack: 0.5, eaten: 0,
                                                   lines: [], mode: .measured, allowance: 300)
        #expect(measuredIdle.activityNote.hasPrefix("Measured by your Apple Watch"))
        #expect(!measuredIdle.activityNote.contains("Log sets"))
        let measured = ExperienceBudget.engine(budget: 2000, credit: 200, rawActive: 700, eatBack: 0.5, eaten: 0,
                                               lines: [.init(kind: .exerciseCredit, kcal: 200)], mode: .measured, allowance: 300)
        #expect(measured.activityNote == "50% of 700 active kcal, above your everyday 300, is added to your budget within your daily cap.")
        #expect(measured.lines().first { $0.id == "earned" }?.note?.contains("above your everyday 300") == true)
        let estimated = ExperienceBudget.engine(budget: 1800, credit: 0, rawActive: 0, eatBack: 0.5, eaten: 0,
                                                lines: [], mode: .estimated)
        #expect(estimated.activityNote.hasPrefix("Log sets"))
        let fixed = ExperienceBudget.engine(budget: 1800, credit: 0, rawActive: 0, eatBack: 0.5, eaten: 0,
                                            lines: [], mode: .off)
        #expect(fixed.activityNote.contains("fixed target"))
        let offShare = ExperienceBudget.engine(budget: 1800, credit: 0, rawActive: 500, eatBack: 0, eaten: 0,
                                               lines: [], mode: .measured, allowance: 300)
        #expect(offShare.activityNote.hasPrefix("Counting activity is off"))
    }

    @Test func loggedCopy() {
        #expect(ExperienceCopy.logged(kcal: 412, proteinG: 31) == "Logged. 412 kcal, 31 g protein.")
        #expect(ExperienceCopy.logged(kcal: 90, proteinG: 0) == "Logged. 90 kcal.")
    }
}
