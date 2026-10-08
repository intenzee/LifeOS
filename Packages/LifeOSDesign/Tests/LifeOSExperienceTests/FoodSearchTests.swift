import Testing
@testable import LifeOSExperienceCore

struct FoodSearchTests {
    @Test func rankingPrefersPrefixesAndNeedsEveryWord() {
        let names = ["Brown Rice (1 cup)", "Rice Krispies", "Chicken fried rice", "Crème brûlée", "Dal"]
        #expect(FoodSearch.rank(names, query: "rice") == [1, 0, 2])
        #expect(FoodSearch.rank(names, query: "fried rice") == [2])
        #expect(FoodSearch.rank(names, query: "creme") == [3])
        #expect(FoodSearch.rank(names, query: "  DAL ") == [4])
        #expect(FoodSearch.rank(names, query: "") == [0, 1, 2, 3, 4])
        #expect(FoodSearch.rank(names, query: "pizza").isEmpty)
    }
}
