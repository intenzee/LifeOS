import Foundation
import Testing
@testable import LifeOSAI
@testable import LifeOSAIEvalKit

/// CI eval gate (F11 §2): runs on every PR touching LifeOS/AI/**.
@Suite("Food-text smoke evals")
struct FoodTextSmokeEvals {

    @Test("Golden smoke set is well-formed: 50 cases, unique ids, category mix per F02")
    func datasetShape() throws {
        let cases = try FoodTextEval.loadSmokeSet()
        #expect(cases.count == 50)
        #expect(Set(cases.map(\.id)).count == cases.count)
        let byCategory = Dictionary(grouping: cases, by: \.category).mapValues(\.count)
        #expect((byCategory["indian"] ?? 0) + (byCategory["hinglish"] ?? 0) >= 25, "≥ 50% Indian foods")
        #expect((byCategory["hinglish"] ?? 0) >= 5)
        #expect((byCategory["branded"] ?? 0) >= 5)
        #expect((byCategory["edge"] ?? 0) >= 3)
    }

    @Test("Deterministic tier meets its bar (F1 ≥ 0.80)")
    func deterministicGate() async throws {
        let cases = try FoodTextEval.loadSmokeSet()
        let gateway = AIStack.makeGateway(.init(credentials: StaticCredentials(), consents: InMemoryConsentStore()))
        let report = await FoodTextEval.run(cases: cases, tier: .deterministic, gateway: gateway)
        let metrics = try #require(report.metrics)
        print(EvalReportRenderer.markdown([report]))
        #expect(metrics.errors == 0)
        #expect(metrics.f1 >= EvalThresholds.foodTextF1[.deterministic]!, "F1 \(metrics.f1)")
    }

    @Test("Live Apple on-device tier (set LIFEOS_LIVE_EVALS=1 on an Apple Intelligence Mac)",
          .enabled(if: ProcessInfo.processInfo.environment["LIFEOS_LIVE_EVALS"] == "1"))
    func liveOnDevice() async throws {
        let cases = try FoodTextEval.loadSmokeSet()
        let gateway = AIStack.makeGateway(.init(credentials: StaticCredentials(), consents: InMemoryConsentStore()))
        let report = await FoodTextEval.run(cases: cases, tier: .appleOnDevice, gateway: gateway)
        print(EvalReportRenderer.markdown([report]))
        // Phase 0 reports T1 rather than gating on it (1.0 bar is 0.92, F02 §8).
        if report.status == "ran" { #expect(try #require(report.metrics).errors < cases.count) }
    }
}

@Suite("Food-text scorer")
struct FoodTextScorerTests {
    private let testCase = FoodTextCase(id: "t", category: "indian", text: "", mealType: "lunch", items: [
        .init(name: "roti", aliases: ["chapati"], quantity: 2, optional: nil),
        .init(name: "curd", aliases: ["dahi"], quantity: 1, optional: nil),
        .init(name: "pav", aliases: nil, quantity: 2, optional: true),
    ], refersToPreset: nil)

    @Test("Aliases, plurals and word containment match; quantity tolerance is ±25%")
    func matching() {
        let parsed = ParsedMeal(items: [ParsedFoodItem(name: "Chapatis", quantity: 2), ParsedFoodItem(name: "plain dahi", quantity: 1.2)],
                                mealType: .lunch)
        let result = FoodTextScorer.score(testCase, parsed: parsed, latencyMs: 5, provider: .deterministic)
        #expect(result.truePositives == 2 && result.falseNegatives == 0 && result.falsePositives == 0)
        #expect(result.mealTypeCorrect == true)
    }

    @Test("Wrong quantities and invented items are penalised; optional misses are not")
    func penalties() {
        let parsed = ParsedMeal(items: [ParsedFoodItem(name: "roti", quantity: 4), ParsedFoodItem(name: "curd"),
                                        ParsedFoodItem(name: "pickle")], mealType: .dinner)
        let result = FoodTextScorer.score(testCase, parsed: parsed, latencyMs: 5, provider: nil)
        #expect(result.truePositives == 1)
        #expect(result.falseNegatives == 1)
        #expect(result.falsePositives == 1)
        #expect(result.mealTypeCorrect == false)
        let metrics = EvalMetrics.compute([result], cases: [testCase])
        #expect(abs(metrics.f1 - 0.5) < 0.0001)
    }
}
