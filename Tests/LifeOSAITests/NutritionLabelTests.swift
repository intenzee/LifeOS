import Foundation
import Testing
@testable import LifeOSAI

@Suite("Nutrition label parser (on-device label scanning)")
struct NutritionLabelTests {

    @Test("Indian FSSAI two-column table: per 100 g and per serve")
    func indianTwoColumn() throws {
        let facts = NutritionLabelParser.parse(lines: [
            "Masala Munch",
            "NUTRITIONAL INFORMATION (Approx.)",
            "Per 100 g | Per Serve (30 g)",
            "Energy (kcal) 520 156",
            "Protein (g) 6,5 2.0",
            "Carbohydrate (g) 60.2 18.1",
            "of which Sugars (g) 4.1 1.2",
            "Total Fat (g) 28.0 8.4",
            "Saturated Fat (g) 12.5 3.8",
            "Sodium (mg) 780 234",
        ])
        #expect(facts.productName == "Masala Munch")
        #expect(facts.servingGrams == 30)
        let per100 = try #require(facts.per100g)
        #expect(per100.kcal == 520 && per100.protein == 6.5 && per100.carbs == 60.2 && per100.fat == 28)
        let serving = try #require(facts.perServing)
        #expect(serving.kcal == 156 && serving.fat == 8.4)
        #expect(facts.confidence >= 0.8)
        #expect(facts.macros(grams: 50)?.kcal == 260)
    }

    @Test("US Nutrition Facts panel with % daily values")
    func usPanel() throws {
        let facts = NutritionLabelParser.parse(lines: [
            "Nutrition Facts", "8 servings per container", "Serving size 2/3 cup (55g)",
            "Calories 230", "Total Fat 8g 10%", "Saturated Fat 1g 5%", "Trans Fat 0g",
            "Sodium 160mg 7%", "Total Carbohydrate 37g 13%", "Dietary Fiber 4g 14%", "Total Sugars 12g", "Protein 3g",
        ])
        #expect(facts.servingGrams == 55)
        #expect(facts.servingsPerPack == 8)
        let serving = try #require(facts.perServing)
        #expect(serving.kcal == 230 && serving.fat == 8 && serving.carbs == 37 && serving.protein == 3)
        #expect(abs((facts.per100g?.kcal ?? 0) - 418.2) < 0.5)
        #expect(facts.macros(servings: 2)?.kcal == 460)
    }

    @Test("kJ + kcal rows, split cells and per-100 only")
    func kilojoulesAndSplitRows() throws {
        let facts = NutritionLabelParser.parse(lines: [
            "Typical values per 100g",
            "Energy 1966 kJ / 470 kcal",
            "Fat", "21 g",
            "Carbohydrate 60 g",
            "Protein 7.1 g",
        ])
        let per100 = try #require(facts.per100g)
        #expect(per100.kcal == 470 && per100.fat == 21 && per100.carbs == 60 && per100.protein == 7.1)
        #expect(facts.perServing == nil)
        #expect(facts.macros(grams: 25)?.kcal == 117.5)

        let kjOnly = NutritionLabelParser.parse(lines: ["per 100 g", "Energy 2000 kJ", "Protein 10 g"])
        #expect(abs((kjOnly.per100g?.kcal ?? 0) - 478) < 1)
    }

    @Test("Unreadable labels are reported as unusable, never invented")
    func unusable() {
        let facts = NutritionLabelParser.parse(lines: ["Ingredients: wheat flour, sugar, edible oil", "Best before 6 months"])
        #expect(!facts.isUsable)
        #expect(facts.confidence <= 0.1)
    }

    @Test("OCR fragments are assembled into reading-order rows")
    func assembler() {
        let lines = OCRLineAssembler.lines(from: [
            .init(text: "156", minX: 0.8, midY: 0.70, height: 0.03),
            .init(text: "Energy (kcal)", minX: 0.1, midY: 0.705, height: 0.03),
            .init(text: "520", minX: 0.55, midY: 0.70, height: 0.03),
            .init(text: "Protein (g)", minX: 0.1, midY: 0.65, height: 0.03),
            .init(text: "6.5", minX: 0.55, midY: 0.652, height: 0.03),
        ])
        #expect(lines == ["Energy (kcal) 520 156", "Protein (g) 6.5"])
    }
}
