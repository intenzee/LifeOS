import Foundation
@testable import LifeOSAI

// LifeOS AI eval harness (F11 §2, tickets AI-051/AI-052).
//
// Each eval = dataset (JSONL) + runner (gateway pinned to one tier) + scorer +
// threshold. Reports are JSON (machine) + Markdown (humans, CI summary).

// MARK: - Datasets

nonisolated enum EvalDatasets {
    /// Repo-relative dataset directory, resolved from this source file so tests
    /// and the CLI work from any working directory.
    static var directory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Datasets", isDirectory: true)
    }

    static func loadJSONL<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try text.split(whereSeparator: \.isNewline).enumerated().compactMap { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else { return nil }
            do {
                return try decoder.decode(T.self, from: Data(trimmed.utf8))
            } catch {
                throw EvalError.badLine(url.lastPathComponent, index + 1, String(describing: error))
            }
        }
    }
}

nonisolated enum EvalError: Error, CustomStringConvertible {
    case badLine(String, Int, String)
    var description: String {
        switch self {
        case .badLine(let file, let line, let detail): "\(file):\(line): \(detail)"
        }
    }
}

// MARK: - Food text

nonisolated struct FoodTextCase: Codable, Sendable {
    nonisolated struct ExpectedItem: Codable, Sendable {
        var name: String
        var aliases: [String]?
        var quantity: Double?
        /// Reasonable to mention or not (e.g. "pav" inside "pav bhaji with 2 pav").
        var optional: Bool?
    }
    var id: String
    var category: String
    var text: String
    var mealType: String?
    var items: [ExpectedItem]
    var refersToPreset: Bool?
}

nonisolated struct FoodTextCaseResult: Codable, Sendable {
    var id: String
    var category: String
    var truePositives: Int
    var falsePositives: Int
    var falseNegatives: Int
    var mealTypeCorrect: Bool?
    var presetCorrect: Bool?
    var latencyMs: Int
    var provider: String?
    var error: String?
    /// Predicted items as "qty unit name" — the user text itself is not repeated.
    var predicted: [String]
    var missed: [String]
    var extra: [String]
}

nonisolated enum FoodTextScorer {
    /// F11 "Item F1 (text)": canonical item match + quantity within ±25%.
    static let quantityTolerance = 0.25

    static func normalise(_ name: String) -> String {
        let cleaned = name.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
            .split(separator: " ").joined(separator: " ")
        return DeterministicFoodParser.singular(cleaned)
    }

    static func namesMatch(_ predicted: String, _ expected: FoodTextCase.ExpectedItem) -> Bool {
        let p = normalise(predicted)
        let candidates = ([expected.name] + (expected.aliases ?? [])).map(normalise)
        return candidates.contains { c in
            p == c || containsWord(p, c) || containsWord(c, p)
        }
    }

    private static func containsWord(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty, needle.count >= 3 else { return false }
        return " \(haystack) ".contains(" \(needle) ")
    }

    static func quantityMatches(_ predicted: Double, _ expected: Double?) -> Bool {
        guard let expected else { return true }
        guard expected > 0 else { return predicted == 0 }
        return abs(predicted - expected) / expected <= quantityTolerance
    }

    static func score(_ testCase: FoodTextCase, parsed: ParsedMeal, latencyMs: Int, provider: ProviderID?) -> FoodTextCaseResult {
        var remaining = parsed.items
        var tp = 0, fn = 0
        var missed: [String] = []
        for expected in testCase.items {
            if let index = remaining.firstIndex(where: { namesMatch($0.name, expected) && quantityMatches($0.quantity, expected.quantity) }) {
                tp += 1
                remaining.remove(at: index)
            } else if expected.optional != true {
                fn += 1
                missed.append("\(expected.quantity.map { $0.formatted() } ?? "?") \(expected.name)")
            }
        }
        // Extra items that merely re-state an expected dish (e.g. "rajma" + "rice"
        // for "rajma chawal") are not penalised twice; anything else is a false positive.
        let extras = remaining.filter { item in !testCase.items.contains { namesMatch(item.name, $0) } }
        let mealTypeCorrect = testCase.mealType.map { $0 == parsed.mealType.rawValue }
        let presetCorrect = testCase.refersToPreset.map { $0 == parsed.refersToPreset }
        return FoodTextCaseResult(
            id: testCase.id, category: testCase.category, truePositives: tp, falsePositives: extras.count,
            falseNegatives: fn, mealTypeCorrect: mealTypeCorrect, presetCorrect: presetCorrect, latencyMs: latencyMs,
            provider: provider?.rawValue, error: nil,
            predicted: parsed.items.map { "\($0.quantity.formatted()) \($0.unit) \($0.name)" },
            missed: missed, extra: extras.map(\.name))
    }

    static func failed(_ testCase: FoodTextCase, error: String, latencyMs: Int) -> FoodTextCaseResult {
        let required = testCase.items.filter { $0.optional != true }
        return FoodTextCaseResult(id: testCase.id, category: testCase.category, truePositives: 0, falsePositives: 0,
                                  falseNegatives: required.count, mealTypeCorrect: testCase.mealType == nil ? nil : false,
                                  presetCorrect: testCase.refersToPreset == nil ? nil : false, latencyMs: latencyMs,
                                  provider: nil, error: error, predicted: [],
                                  missed: required.map(\.name), extra: [])
    }
}

// MARK: - Metrics & report

nonisolated struct EvalMetrics: Codable, Sendable {
    var cases: Int
    var errors: Int
    var precision: Double
    var recall: Double
    var f1: Double
    var mealTypeAccuracy: Double?
    var nonFoodAccuracy: Double?
    var presetAccuracy: Double?
    var latencyP50Ms: Int
    var latencyP95Ms: Int
    var f1ByCategory: [String: Double]

    static func compute(_ results: [FoodTextCaseResult], cases: [FoodTextCase]) -> EvalMetrics {
        func f1(_ rs: [FoodTextCaseResult]) -> (Double, Double, Double) {
            let tp = Double(rs.map(\.truePositives).reduce(0, +))
            let fp = Double(rs.map(\.falsePositives).reduce(0, +))
            let fn = Double(rs.map(\.falseNegatives).reduce(0, +))
            let p = tp + fp == 0 ? 1 : tp / (tp + fp)
            let r = tp + fn == 0 ? 1 : tp / (tp + fn)
            return (p, r, p + r == 0 ? 0 : 2 * p * r / (p + r))
        }
        let (p, r, f) = f1(results)
        let mealTyped = results.compactMap(\.mealTypeCorrect)
        let presets = results.compactMap(\.presetCorrect)
        let nonFoodIDs = Set(cases.filter { $0.items.isEmpty && $0.refersToPreset != true }.map(\.id))
        let nonFood = results.filter { nonFoodIDs.contains($0.id) }
        let latencies = results.filter { $0.error == nil }.map(\.latencyMs).sorted()
        var byCategory: [String: Double] = [:]
        for (category, group) in Dictionary(grouping: results, by: \.category) {
            byCategory[category] = f1(group).2
        }
        return EvalMetrics(
            cases: results.count, errors: results.filter { $0.error != nil }.count,
            precision: p, recall: r, f1: f,
            mealTypeAccuracy: mealTyped.isEmpty ? nil : Double(mealTyped.filter { $0 }.count) / Double(mealTyped.count),
            nonFoodAccuracy: nonFood.isEmpty ? nil : Double(nonFood.filter { $0.falsePositives == 0 && $0.error == nil }.count) / Double(nonFood.count),
            presetAccuracy: presets.isEmpty ? nil : Double(presets.filter { $0 }.count) / Double(presets.count),
            latencyP50Ms: AIEventLog.percentile(latencies, 0.5), latencyP95Ms: AIEventLog.percentile(latencies, 0.95),
            f1ByCategory: byCategory)
    }
}

nonisolated struct EvalReport: Codable, Sendable {
    var eval: String
    var dataset: String
    var tier: String
    var status: String          // "ran" | "skipped: <reason>"
    var promptVersion: String
    var date: Date
    var host: String
    var metrics: EvalMetrics?
    var results: [FoodTextCaseResult]
}

nonisolated enum EvalThresholds {
    /// Smoke bars per tier (F02 §8: T1 ≥ 0.92 at 1.0, deterministic ≥ 0.80).
    /// Phase 0 gates CI on the deterministic tier only — CI runners have no
    /// Apple Intelligence and no provider keys; model tiers are reported.
    static let foodTextF1: [ProviderID: Double] = [
        .deterministic: 0.80,
        .appleOnDevice: 0.92,
        .applePCC: 0.92,
        .geminiBYOK: 0.92,
        .groqBYOK: 0.92,
    ]
}

// MARK: - Runner

nonisolated enum FoodTextEval {

    static let datasetName = "food_text_smoke.jsonl"

    static func loadSmokeSet() throws -> [FoodTextCase] {
        try EvalDatasets.loadJSONL(FoodTextCase.self, from: EvalDatasets.directory.appendingPathComponent(datasetName))
    }

    /// Runs every case through the gateway with the chain pinned to `tier`.
    static func run(cases: [FoodTextCase], tier: ProviderID, gateway: AIGateway,
                    progress: (@Sendable (Int, Int) -> Void)? = nil) async -> EvalReport {
        let original = await gateway.debugOverrides
        var pinned = original
        pinned.forcedChains[.foodTextParse] = [tier]
        await gateway.setDebugOverrides(pinned)
        let report = await runPinned(cases: cases, tier: tier, gateway: gateway, progress: progress)
        await gateway.setDebugOverrides(original)
        return report
    }

    private static func runPinned(cases: [FoodTextCase], tier: ProviderID, gateway: AIGateway,
                                  progress: (@Sendable (Int, Int) -> Void)?) async -> EvalReport {

        let base = EvalReport(eval: "food_text", dataset: datasetName, tier: tier.rawValue, status: "ran",
                              promptVersion: PromptRegistry.version, date: Date(),
                              host: ProcessInfo.processInfo.hostName, metrics: nil, results: [])

        let availability = await gateway.availability(for: .foodTextParse)
        if case .unavailable(let reason)? = availability.chain.first?.availability {
            var skipped = base
            skipped.status = "skipped: \(reason.rawValue)"
            return skipped
        }

        let clock = ContinuousClock()
        var results: [FoodTextCaseResult] = []
        for (index, testCase) in cases.enumerated() {
            progress?(index + 1, cases.count)
            // Evals measure each case independently: a tripped breaker would
            // otherwise skip the rest of the run after three slow answers.
            await gateway.resetCircuit(tier)
            let request = AIRequest<ParsedMeal>(task: .foodTextParse, prompt: PromptRegistry.foodTextParse(testCase.text),
                                                input: .text(testCase.text), privacy: .personal,
                                                latencyBudget: .seconds(60), cachePolicy: .bypass,
                                                generation: AIGenerationOptions(temperature: 0))
            let start = clock.now
            do {
                let result = try await gateway.run(request)
                results.append(FoodTextScorer.score(testCase, parsed: result.output,
                                                    latencyMs: (clock.now - start).milliseconds, provider: result.provider))
            } catch {
                let code = (error as? AIError).map { e -> String in
                    if case .exhausted(let attempts) = e { return attempts.map { "\($0.provider.rawValue):\($0.error.code)" }.joined(separator: ",") }
                    return e.code
                } ?? "\(error)"
                results.append(FoodTextScorer.failed(testCase, error: code, latencyMs: (clock.now - start).milliseconds))
            }
        }
        var report = base
        report.results = results
        report.metrics = EvalMetrics.compute(results, cases: cases)
        return report
    }
}

// MARK: - Rendering

nonisolated enum EvalReportRenderer {
    static func markdown(_ reports: [EvalReport]) -> String {
        func pct(_ v: Double?) -> String { v.map { String(format: "%.1f%%", $0 * 100) } ?? "—" }
        var out = "## Food-text smoke eval (`\(FoodTextEval.datasetName)`, prompt \(PromptRegistry.version))\n\n"
        out += "| Tier | Status | Item F1 | Precision | Recall | Meal type | Non-food | Preset | p50 | p95 | Errors | Bar |\n"
        out += "|---|---|---|---|---|---|---|---|---|---|---|---|\n"
        for r in reports {
            let bar = ProviderID(rawValue: r.tier).flatMap { EvalThresholds.foodTextF1[$0] }
            guard let m = r.metrics else {
                out += "| \(r.tier) | \(r.status) | — | — | — | — | — | — | — | — | — | \(pct(bar)) |\n"
                continue
            }
            let verdict = bar.map { m.f1 >= $0 ? "✅ \(pct($0))" : "❌ \(pct($0))" } ?? "—"
            out += "| \(r.tier) | \(r.status) | **\(pct(m.f1))** | \(pct(m.precision)) | \(pct(m.recall)) | \(pct(m.mealTypeAccuracy)) | \(pct(m.nonFoodAccuracy)) | \(pct(m.presetAccuracy)) | \(m.latencyP50Ms) ms | \(m.latencyP95Ms) ms | \(m.errors) | \(verdict) |\n"
        }
        for r in reports where r.metrics != nil {
            let misses = r.results.filter { !$0.missed.isEmpty || !$0.extra.isEmpty || $0.error != nil }
            guard !misses.isEmpty else { continue }
            out += "\n<details><summary>\(r.tier): \(misses.count) imperfect case(s)</summary>\n\n"
            out += "| Case | Category | Predicted | Missed | Extra | Error |\n|---|---|---|---|---|---|\n"
            for m in misses {
                out += "| \(m.id) | \(m.category) | \(m.predicted.joined(separator: "; ")) | \(m.missed.joined(separator: "; ")) | \(m.extra.joined(separator: "; ")) | \(m.error ?? "") |\n"
            }
            out += "\n</details>\n"
        }
        if let first = reports.first(where: { $0.metrics != nil })?.metrics {
            out += "\nF1 by category (\(reports.first { $0.metrics != nil }!.tier)): "
            out += first.f1ByCategory.sorted { $0.key < $1.key }.map { "\($0.key) \(pct($0.value))" }.joined(separator: " · ")
            out += "\n"
        }
        return out
    }

    static func json(_ reports: [EvalReport]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(reports)
    }
}
