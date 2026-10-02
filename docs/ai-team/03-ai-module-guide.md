# 03 — AI module guide (`LifeOS/AI`)

Every AI call in LifeOS goes through `AIServices.shared.gateway` (an `AIGateway` actor). Product code never talks to a model directly. Design: `docs/ai-team/features/F01-ai-gateway-model-router.md`.

```
Gateway/        core types, AIGateway (routing, fallback, timeout, repair), schema + validator,
                privacy gate + consent, quota/circuit breaker, response cache, remote config,
                telemetry, MockAIProvider, AIStack (standard wiring)
Providers/      AppleOnDevice (T1), ApplePCC (T2), GeminiBYOK / GroqBYOK (T3), REST + Keychain support
Food/           ParsedMeal / MealPhotoEstimate output types, DeterministicFoodParser (T0)
Prompts/        PromptRegistry (versioned; every result records the version)
AppIntegration/ iOS-only glue: AIServices, Vision-legacy provider (T4), AI diagnostics screen
```

## Using it
```swift
let request = AIRequest<ParsedMeal>(task: .foodTextParse,
                                    prompt: PromptRegistry.foodTextParse(text),
                                    input: .text(text), privacy: .personal)
let result = try await AIServices.shared.gateway.run(request)
result.output        // typed, schema-validated
result.provider      // which tier answered → provenance badge
result.degradedFrom  // what failed first → banners/diagnostics
```
- **New output type:** conform to `AIOutput` and declare `static let schema: AISchema`. That one schema becomes Apple's guided-generation schema, Gemini's `responseSchema`, the Groq JSON instruction, and the validator contract.
- **New task:** add an `AITask` case, a route in `RoutingTable.v1`, and a prompt in `PromptRegistry`. Bump `PromptRegistry.version` whenever wording changes.
- **Privacy:** declare `.public`, `.personal` or `.health`. Third-party cloud (T3) requires consent. `.health` requires the explicit consent sheet, and memory tasks never leave Apple's boundary.

## Tests and evals (no Xcode needed)
The sources compile both into the app (synchronized folder) and into the root `Package.swift`. The package mirrors the app's concurrency settings (MainActor default isolation, approachable concurrency).
```bash
swift test                                      # unit tests + smoke eval gate
swift run ai-eval food-text --tiers deterministic,appleOnDevice
LIFEOS_LIVE_EVALS=1 swift test --filter liveOnDevice   # needs an Apple Intelligence Mac
```
`AppIntegration/` is excluded from the package (UIKit), so build it with Xcode.
