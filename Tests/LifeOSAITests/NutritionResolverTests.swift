import Foundation
import Testing
@testable import LifeOSAI

@Suite("Food catalog integrity")
struct FoodCatalogTests {

    @Test("IDs and lookup keys are unique; every default unit has a weight")
    func structure() {
        let ids = FoodCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate ids: \(Dictionary(grouping: ids, by: { $0 }).filter { $1.count > 1 }.keys)")
        var seen: [String: String] = [:]
        for record in FoodCatalog.all {
            for key in [record.name] + record.aliases {
                let n = FoodNameNormalizer.normalise(key)
                if let owner = seen[n], owner != record.id {
                    Issue.record("alias '\(key)' maps to both \(owner) and \(record.id)")
                }
                seen[n] = record.id
            }
            #expect(record.servingGrams > 0, "\(record.id) has no serving weight")
            #expect(record.units[record.defaultUnit] != nil || NutritionUnits.genericGrams[record.defaultUnit] != nil,
                    "\(record.id) default unit \(record.defaultUnit) unknown")
        }
        #expect(FoodCatalog.all.count >= 225)
        let indian: Set<FoodRecord.Category> = [.bread, .rice, .dal, .vegCurry, .nonVegCurry, .southIndian, .snack, .sweet]
        #expect(FoodCatalog.all.filter { indian.contains($0.category) }.count >= 110)
    }

    @Test("Energy roughly equals 4P + 4C + 9F for every food (catches data-entry errors)")
    func atwater() {
        for record in FoodCatalog.all where record.kcal >= 20 && !["beer", "wine", "whisky"].contains(record.id) {
            let computed = 4 * record.protein + 4 * record.carbs + 9 * record.fat
            let error = abs(computed - record.kcal) / record.kcal
            #expect(error <= 0.2, "\(record.id): stated \(record.kcal) kcal vs \(Int(computed)) from macros")
        }
    }
}

@Suite("NutritionResolver")
struct NutritionResolverTests {
    let resolver = NutritionResolver()

    private func item(_ name: String, _ qty: Double = 1, _ unit: String = "serving", prep: String = "",
                      text: String = "x", brand: String = "") -> ParsedFoodItem {
        ParsedFoodItem(name: name, originalText: text, quantity: qty, unit: unit, preparation: prep, brand: brand)
    }

    @Test("Household units resolve to grams with full confidence")
    func householdUnits() throws {
        let roti = resolver.resolve(item("roti", 2, "piece", text: "2 rotis"))
        #expect(roti.grams == 80)
        #expect(abs(roti.macros.kcal - 237.6) < 0.5)
        #expect(roti.sourceRef == "db:\(FoodCatalog.version):roti")
        #expect(roti.band == .high)
        #expect(roti.servingDescription == "2 piece (80 g)")

        let dal = resolver.resolve(item("dal", 1, "bowl", text: "a bowl of dal"))
        #expect(dal.grams == 150)
        #expect(abs(dal.macros.kcal - 157.5) < 0.5)

        let katori = resolver.resolve(item("rajma", 1, "katori", text: "1 katori rajma"))
        #expect(katori.grams == 150 && katori.unitConfidence == 1.0)
    }

    @Test("Exact weights, sizes and the food's natural unit")
    func weightsAndSizes() {
        let paneer = resolver.resolve(item("paneer bhurji", 200, "g", text: "200 g paneer bhurji"))
        #expect(paneer.grams == 200 && abs(paneer.macros.kcal - 500) < 0.5)
        let latte = resolver.resolve(item("latte", 1, "large", text: "large latte"))
        #expect(latte.grams == 470)
        let dhokla = resolver.resolve(item("dhokla", 4, "serving", text: "dhokla 4 pieces"))
        #expect(dhokla.unit == "piece" && dhokla.grams == 120)
        let milk = resolver.resolve(item("milk", 300, "ml", text: "300 ml milk"))
        #expect(abs(milk.macros.kcal - 183) < 0.5)
    }

    @Test("Aliases, plurals, typos and head nouns")
    func matching() {
        #expect(resolver.resolve(item("chapatis")).matchKind == .catalog)
        #expect(resolver.resolve(item("dahi")).sourceRef.hasSuffix(":curd"))
        let typo = resolver.resolve(item("chappati"))
        #expect(typo.matchKind == .catalogFuzzy && typo.sourceRef.hasSuffix(":roti"))
        #expect(resolver.resolve(item("biriyani")).sourceRef.hasSuffix(":chicken biryani"))
        let headNoun = resolver.resolve(item("mushroom paratha", text: "mushroom paratha"))
        #expect(headNoun.matchKind == .headNoun && headNoun.sourceRef.hasSuffix(":paratha"))
        #expect(headNoun.needsReview)
        let brand = resolver.resolve(item("cheese slice", brand: "Amul"))
        #expect(brand.sourceRef.hasSuffix(":cheese"))
    }

    @Test("Unknown foods stay in the meal as unresolved, flagged for review")
    func unresolved() {
        let unknown = resolver.resolve(item("zorblax stew"))
        #expect(unknown.matchKind == .unresolved)
        #expect(unknown.macros == .zero)
        #expect(unknown.needsReview && unknown.band == .low)
        let estimated = NutritionResolver.applyingEstimate(NutritionEstimate(grams: 250, kcal: 300, protein: 10, carbs: 30, fat: 15),
                                                           to: unknown)
        #expect(estimated.matchKind == .modelEstimate && estimated.sourceRef == "llm-estimate")
        #expect(estimated.macros.kcal == 300 && estimated.isEstimate)
    }

    @Test("Preparation changes the numbers: ghee, no sugar, fried")
    func preparation() {
        let plain = resolver.resolve(item("paratha", 2, "piece"))
        let ghee = resolver.resolve(item("paratha", 2, "piece", prep: "with ghee"))
        #expect(abs(ghee.macros.kcal - plain.macros.kcal - 90) < 0.5)
        let chai = resolver.resolve(item("chai", 1, "cup"))
        let noSugar = resolver.resolve(item("chai", 1, "cup", prep: "no sugar"))
        #expect(noSugar.macros.kcal < chai.macros.kcal - 25)
        let fried = resolver.resolve(item("egg", 2, "piece", prep: "fried"))
        #expect(fried.sourceRef.hasSuffix(":fried egg"))
    }

    @Test("User's own foods win over the catalog")
    func userFoodsFirst() {
        let mine = UserFood(name: "Mom's Rajma", macros: Macros(kcal: 180, protein: 9, carbs: 25, fat: 4),
                            servingDescription: "1 katori", kind: .custom)
        let resolver = NutritionResolver(userFoods: [mine])
        let exact = resolver.resolve(item("mom's rajma", 2))
        #expect(exact.matchKind == .userFood && exact.macros.kcal == 360)
        #expect(exact.sourceRef == "user:custom:mom rajma")
        let generic = resolver.resolve(item("rajma"))
        #expect(generic.matchKind == .catalog)
    }

    @Test("Stated vs defaulted quantities and quantity edits")
    func confidenceAndEdits() {
        #expect(NutritionResolver.parseConfidence(item("roti", text: "2 rotis")) == 1.0)
        #expect(NutritionResolver.parseConfidence(item("roti", text: "do roti")) == 1.0)
        #expect(NutritionResolver.parseConfidence(item("dal", text: "dal")) == 0.8)
        var roti = resolver.resolve(item("roti", 2, "piece", text: "rotis"))
        roti.setQuantity(3)
        #expect(roti.grams == 120 && abs(roti.macros.kcal - 356.4) < 0.5 && roti.parseConfidence == 1.0)
    }

    @Test("Edit distance")
    func editDistance() {
        #expect(FoodNameNormalizer.editDistance("roti", "roti") == 0)
        #expect(FoodNameNormalizer.editDistance("chappati", "chapati") == 1)
        #expect(FoodNameNormalizer.editDistance("abc", "xyz", limit: 1) == 2)
        #expect(FoodNameNormalizer.editDistance("", "abc") == 3)
        #expect(FoodNameNormalizer.normalise("Parle-G Biscuits!") == "parle g biscuit")
    }
}
