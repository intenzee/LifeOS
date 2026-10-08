import Testing
@testable import LifeOSExperienceCore

struct PortionMathTests {
    @Test func gramsFromServingText() {
        #expect(PortionMath.grams(inServing: "30 g") == 30)
        #expect(PortionMath.grams(inServing: "1 bar (45g)") == 45)
        #expect(PortionMath.grams(inServing: "250ml") == 250)
        #expect(PortionMath.grams(inServing: "2 biscuits (18.5 g)") == 18.5)
        #expect(PortionMath.grams(inServing: "1,5 kg") == 1500)
        #expect(PortionMath.grams(inServing: "8 oz") == 226.8)
        #expect(PortionMath.grams(inServing: "100 grams") == 100)
        #expect(PortionMath.grams(inServing: "1 serving") == nil)
        #expect(PortionMath.grams(inServing: "") == nil)
        // "g" must be a unit on its own, not the start of a word.
        #expect(PortionMath.grams(inServing: "2 glasses") == nil)
    }

    @Test func chipsFollowTheServing() {
        #expect(PortionMath.chips(servingGrams: 30).map(\.grams) == [15, 30, 45, 60])
        #expect(PortionMath.chips(servingGrams: 30).map(\.label) == ["½", "1", "1½", "2"])
        #expect(PortionMath.chips(servingGrams: nil).map(\.grams) == [50, 100, 150, 200])
        #expect(PortionMath.defaultGrams(servingGrams: nil) == 100)
        #expect(PortionMath.defaultGrams(servingGrams: 45) == 45)
    }

    @Test func plateAndScalingAreSafe() {
        #expect(PortionMath.plateFill(grams: 30, servingGrams: 30) == 0.5)
        #expect(PortionMath.plateFill(grams: 900, servingGrams: nil) == 1)
        #expect(PortionMath.plateFill(grams: .nan, servingGrams: 30) == 0)
        #expect(PortionMath.scale(per100: 520, grams: 30) == 156)
        #expect(PortionMath.scale(per100: .infinity, grams: 30) == 0)
        #expect(PortionMath.per100(156, servingGrams: 30) == 520)
        #expect(PortionMath.per100(156, servingGrams: 0) == nil)
        #expect(PortionMath.sliderRange(servingGrams: 250).upperBound == 1000)
    }

    @Test func mealAmounts() {
        #expect(PortionMath.parseAmount("1 plate") == (1, "plate"))
        #expect(PortionMath.parseAmount("2 cups") == (2, "cup"))
        #expect(PortionMath.parseAmount("250 g") == (250, "gram"))
        #expect(PortionMath.parseAmount("a bowl") == (1, "bowl"))
        #expect(PortionMath.parseAmount("1 serving") == (1, "serving"))
        #expect(PortionMath.amountLabel(quantity: 1.5, unit: "bowl") == "1.5 bowls")
        #expect(PortionMath.amountLabel(quantity: 2, unit: "sandwich") == "2 sandwiches")
        #expect(PortionMath.amountLabel(quantity: 250, unit: "gram") == "250 g")
        #expect(PortionMath.amountLabel(quantity: 1, unit: "plate") == "1 plate")
        #expect(PortionMath.amountStep(unit: "gram") == 25)
    }
}

