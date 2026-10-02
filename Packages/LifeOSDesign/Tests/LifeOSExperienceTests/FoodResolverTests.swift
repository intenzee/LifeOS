import Foundation
import Testing
@testable import LifeOSExperienceCore

@Suite struct FoodResolverTests {
    private let mine = [
        ExperienceNutrient(name: "Eggs (2 large)", kcal: 140, protein: 12, carbs: 1, fat: 10, serving: "2 eggs"),
        ExperienceNutrient(name: "Office lunch", kcal: 620, protein: 30, carbs: 70, fat: 22),
        ExperienceNutrient(name: "Chicken Breast (100g)", kcal: 165, protein: 31, carbs: 0, fat: 3.6, serving: "100g"),
    ]
    private func steakTable(_ s: String) -> ExperienceNutrient? {
        // Mimics NutritionDatabase's loose contains-match.
        "steak".contains(s.lowercased()) ? ExperienceNutrient(name: "Steak", kcal: 271) : nil
    }

    @Test func usersOwnFoodsWinWithHighConfidence() {
        let r = ExperienceFoodResolver.resolve(name: "office lunch", quantity: 1, unit: "serving", id: "1", userFoods: mine, bundled: { _ in nil })
        #expect(r.confidence == .high)
        #expect(r.nutrient.kcal == 620)
    }

    @Test func staplesResolveAndScaleByCount() {
        let r = ExperienceFoodResolver.resolve(name: "rotis", quantity: 2, unit: "piece", id: "1", userFoods: [], bundled: { _ in nil })
        #expect(r.name == "Roti")
        #expect(r.nutrient.kcal == 208)
        #expect(r.confidence == .medium)
        let chai = ExperienceFoodResolver.resolve(name: "cup of tea", quantity: 1, unit: "cup", id: "2", userFoods: [], bundled: steakTable)
        #expect(chai.name == "Chai")
    }

    @Test func looseTableMatchesNeedASharedWord() {
        let r = ExperienceFoodResolver.resolve(name: "te", quantity: 1, unit: "cup", id: "1", userFoods: [], bundled: steakTable)
        #expect(r.confidence == .low)
        #expect(r.nutrient.kcal == 0)
    }

    @Test func gramsScaleAgainstGramServings() {
        let r = ExperienceFoodResolver.resolve(name: "chicken breast", quantity: 200, unit: "g", id: "1", userFoods: mine, bundled: { _ in nil })
        #expect(r.nutrient.kcal == 330)
        #expect(abs(r.nutrient.protein - 62) < 0.01)
        // Grams against a "1 bowl" serving assume ~150 g, never 300×.
        let dal = ExperienceFoodResolver.resolve(name: "dal", quantity: 300, unit: "g", id: "2", userFoods: [], bundled: { _ in nil })
        #expect(dal.nutrient.kcal == 360)
    }

    @Test func unknownFoodsAreLowConfidenceZero() {
        let r = ExperienceFoodResolver.resolve(name: "mystery stew", quantity: .nan, unit: "", id: "1", userFoods: mine, bundled: { _ in nil })
        #expect(r.confidence == .low)
        #expect(r.quantity == 1)
        #expect(r.unit == "serving")
        #expect(r.name == "Mystery stew")
    }

    @Test func presetsRankBySlotThenFavouriteThenRecency() {
        let now = Date()
        func c(_ n: String, _ s: ExperienceMealSlot?, fav: Bool = false, ago: Double = 0) -> ExperiencePresetCandidate {
            ExperiencePresetCandidate(id: n, nutrient: .init(name: n, kcal: 100), slot: s, isFavorite: fav, lastUsed: now.addingTimeInterval(-ago))
        }
        let ranked = ExperiencePresetCandidate.ranked([
            c("Old dinner", .dinner, ago: 99), c("Poha", .breakfast, ago: 50), c("Fav snack", .snack, fav: true),
            c("Fav breakfast", .breakfast, fav: true, ago: 500), c("poha", .breakfast),
        ], for: .breakfast)
        #expect(ranked.map(\.id) == ["Fav breakfast", "Poha", "Fav snack", "Old dinner"])
    }
}

@Suite struct TimelineTests {
    @Test func timedNewestFirstThenSummaries() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let rows = ExperienceTimelineEntry.ordered([
            .init(id: "w", kind: .water, title: "Water", detail: "", kcal: nil, time: nil, source: .manual),
            .init(id: "b", kind: .meal, title: "Breakfast", detail: "", kcal: 300, time: t0, source: .manual),
            .init(id: "g", kind: .workout, title: "Gym", detail: "", kcal: -200, time: nil, source: .manual),
            .init(id: "l", kind: .meal, title: "Lunch", detail: "", kcal: 500, time: t0.addingTimeInterval(3600), source: .voice),
        ])
        #expect(rows.map(\.id) == ["l", "b", "g", "w"])
    }

    @Test func nextUpRules() {
        let preset = ExperiencePresetCandidate(id: "p", nutrient: .init(name: "Poha", kcal: 250), slot: .breakfast, isFavorite: true, lastUsed: nil)
        let first = ExperienceNextUp.make(hasLoggedToday: false, slot: .breakfast, slotIsLogged: false, topPreset: preset, waterGlasses: 0, waterTarget: 8, hour: 9)
        #expect(first?.action == .capture)
        let usual = ExperienceNextUp.make(hasLoggedToday: true, slot: .lunch, slotIsLogged: false, topPreset: preset, waterGlasses: 0, waterTarget: 8, hour: 13)
        #expect(usual?.action == .logPreset(id: "p"))
        #expect(usual?.message == "Lunch not logged yet. Usual: Poha, 250 kcal.")
        let water = ExperienceNextUp.make(hasLoggedToday: true, slot: .lunch, slotIsLogged: true, topPreset: nil, waterGlasses: 1, waterTarget: 8, hour: 15)
        #expect(water?.action == .addWater)
        let quiet = ExperienceNextUp.make(hasLoggedToday: true, slot: .lunch, slotIsLogged: true, topPreset: nil, waterGlasses: 6, waterTarget: 8, hour: 15)
        #expect(quiet == nil)
    }
}
