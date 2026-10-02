import Foundation
@testable import LifeOSAI
@testable import LifeOSAIEvalKit

// ai-eval — runs LifeOS AI evals per tier and writes JSON + Markdown reports.
//
//   swift run ai-eval food-text [--tiers deterministic,appleOnDevice,applePCC,geminiBYOK,groqBYOK]
//                               [--out Evals/reports] [--gate]
//   swift run ai-eval availability
//
// BYOK tiers read GROQ_API_KEY / GEMINI_API_KEY from the environment. `--gate`
// exits non-zero when a tier with a CI bar (deterministic in Phase 0) misses it.

@main
struct AIEvalCLI {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        let command = args.isEmpty ? "food-text" : args.removeFirst()

        func option(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let gate = args.contains("--gate")
        let outDir = URL(fileURLWithPath: option("--out") ?? "Evals/reports", isDirectory: true)
        let tiers = (option("--tiers") ?? "deterministic,appleOnDevice,applePCC,geminiBYOK,groqBYOK")
            .split(separator: ",").compactMap { ProviderID(rawValue: String($0)) }

        let credentials = StaticCredentials.fromEnvironment()
        // Evals send only the public golden set, so BYOK tiers get personal-data
        // consent here when (and only when) a key is present.
        let consents = InMemoryConsentStore()
        for provider in [ProviderID.groqBYOK, .geminiBYOK] where credentials.apiKey(for: provider) != nil {
            consents.grant(CloudConsent(maxPrivacy: .personal, grantedAt: Date(), source: .consentSheet), for: provider)
        }
        let gateway = AIStack.makeGateway(.init(credentials: credentials, consents: consents))

        switch command {
        case "availability":
            for task in [AITask.foodTextParse, .mealPhotoAnalyze, .assistantChat] {
                let summary = await gateway.availability(for: task)
                print("\(task.rawValue): " + summary.chain.map { "\($0.provider.rawValue)=\($0.availability)" }.joined(separator: "  "))
            }

        case "food-text":
            do {
                let cases = try FoodTextEval.loadSmokeSet()
                var reports: [EvalReport] = []
                for tier in tiers {
                    FileHandle.standardError.write(Data("▶︎ \(tier.rawValue) (\(cases.count) cases)\n".utf8))
                    let report = await FoodTextEval.run(cases: cases, tier: tier, gateway: gateway) { done, total in
                        if done % 10 == 0 || done == total {
                            FileHandle.standardError.write(Data("   \(done)/\(total)\n".utf8))
                        }
                    }
                    reports.append(report)
                }
                let markdown = EvalReportRenderer.markdown(reports)
                print(markdown)
                try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
                try EvalReportRenderer.json(reports).write(to: outDir.appendingPathComponent("food_text_smoke.json"))
                try Data(markdown.utf8).write(to: outDir.appendingPathComponent("food_text_smoke.md"))
                if let summary = ProcessInfo.processInfo.environment["GITHUB_STEP_SUMMARY"] {
                    if let handle = FileHandle(forWritingAtPath: summary) {
                        handle.seekToEndOfFile(); handle.write(Data(markdown.utf8)); handle.closeFile()
                    }
                }
                if gate {
                    let failures = reports.filter { report in
                        guard report.tier == ProviderID.deterministic.rawValue, let m = report.metrics,
                              let bar = EvalThresholds.foodTextF1[.deterministic] else { return false }
                        return m.f1 < bar
                    }
                    if !failures.isEmpty {
                        FileHandle.standardError.write(Data("✘ eval gate failed: \(failures.map(\.tier))\n".utf8))
                        exit(1)
                    }
                }
            } catch {
                FileHandle.standardError.write(Data("ai-eval: \(error)\n".utf8))
                exit(2)
            }

        default:
            FileHandle.standardError.write(Data("usage: ai-eval [food-text|availability] [--tiers a,b] [--out dir] [--gate]\n".utf8))
            exit(64)
        }
    }
}
