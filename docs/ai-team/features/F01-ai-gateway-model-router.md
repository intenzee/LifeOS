# F01 — AI Gateway & Model Router

| | |
|---|---|
| **Phase** | 0 (Foundations) |
| **Owner** | AI Lead |
| **Tiers** | All (T1–T4) |
| **Depends on** | Remote config (C10) |
| **Consumed by** | Every AI feature (F02–F10) |

## 1. Problem
Today the only model call lives inside `GroqMealAnalyzer`, hard-wired to one vendor, one task and a user-supplied key. Adding text parsing, chat, memory extraction and nudges the same way would scatter vendor code across the app, make "free forever" impossible to guarantee, and make privacy rules unenforceable.

## 2. Outcome
One internal API — `AIGateway.run(_:)` — that every feature calls with a **task**, an **input**, a **typed output schema** and a **privacy class**. The gateway decides which engine runs it, handles fallbacks, quotas, retries, validation and logging, and returns a typed result with provenance.

## 3. Functional requirements
| ID | Requirement |
|---|---|
| FR1 | Typed requests: `AIRequest<Output: Decodable>` with task, instructions, input (text and/or images), context packet, output schema, privacy class, latency budget. |
| FR2 | Provider abstraction: `AIProvider` protocol implemented by `AppleOnDeviceProvider`, `ApplePCCProvider`, `GeminiBYOKProvider`, `GroqBYOKProvider`, `VisionLegacyProvider`. |
| FR3 | Routing table per task: ordered provider chain with conditions (OS/device availability, privacy consent, network, quota, input type). Table is code-defined with remote-config overrides. |
| FR4 | Availability probing: `SystemLanguageModel.default.availability` (device not eligible / Apple Intelligence off / model not ready), PCC availability, key presence, reachability. Cached and refreshed on app activation. |
| FR5 | Structured output: on Apple providers use `@Generable` types (guided generation); on REST providers use JSON mode + JSON Schema in prompt; validate with a schema validator; one automatic **repair** retry with the validation error fed back. |
| FR6 | Fallback: on recoverable errors (model unavailable, guardrail false positive, context overflow, 5xx, timeout, invalid output after repair) move to next provider. On user-actionable errors (bad key, rate limit) surface them and still try non-cloud fallbacks. Reuse the error taxonomy from `MealScanError`, generalised to `AIError`. |
| FR7 | Quota manager: per-provider token bucket (requests/min, requests/day) seeded from remote config; circuit breaker opens for 10 min after 3 consecutive failures. |
| FR8 | Model rotation: model IDs for T3 come from remote config (`groqVisionModels`, `geminiModels`); unknown/retired models (400/404/422) are skipped automatically — same pattern as `GroqMealAnalyzer.run`. |
| FR9 | Response cache: content-hash keyed (task + normalised input + context hash + prompt version), TTL per task (e.g. food-text parse 30 days, chat none). |
| FR10 | Prompt registry: all instructions live in versioned Swift files (`Prompts/v2026_10_1/…`), referenced by ID; version recorded in every result for eval traceability. |
| FR11 | Privacy enforcement: requests carry `PrivacyClass` (`.public`, `.personal`, `.health`); gateway refuses to route `.health`/`.personal` to T3 unless the user has granted third-party-cloud consent, and applies the Context Engine's redaction for that destination. |
| FR12 | Streaming: `stream(_:)` returns `AsyncThrowingStream<PartialOutput, Error>` for chat (Apple `streamResponse`, SSE for REST). |
| FR13 | Cancellation: honours Swift task cancellation end-to-end. |
| FR14 | Telemetry: `os.Logger` + `OSSignposter` (task, provider, latency, tokens if known, outcome) with `privacy: .private` on any content. Optional local metrics file for the in-app "AI diagnostics" screen (debug builds + TestFlight). |
| FR15 | Test doubles: `MockAIProvider` with scripted responses for unit tests and evals. |

## 4. Non-functional
- Gateway overhead < 15 ms per request (excluding model time).
- Zero third-party SDKs required; plain `URLSession` for REST.
- No API key ever compiled into the binary.
- All public API `Sendable`, actor-isolated where stateful (`actor QuotaManager`).

## 5. Architecture

```
AIRequest ─▶ AIGateway (actor)
              ├─ PrivacyGate        (consent + redaction policy)
              ├─ CacheLookup
              ├─ Router             (task → [ProviderCandidate])
              │    for candidate in chain:
              │      ├─ Availability check
              │      ├─ QuotaManager.reserve()
              │      ├─ provider.generate(...)
              │      ├─ SchemaValidator (+1 repair retry)
              │      └─ success → cache, telemetry, return
              │         recoverable failure → next
              └─ all failed → AIError.exhausted(lastError)  // caller shows manual path
```

### 5.1 Core types

```swift
enum AITask: String, Sendable {
    case foodTextParse, mealPhotoAnalyze, mealPhotoRefine, nutritionLabelRead
    case memoryExtract, memoryConsolidate
    case assistantChat, briefingCompose, weeklyReview, budgetExplain
    case nudgeCompose, presetSuggestName
}
enum PrivacyClass: Sendable { case `public`, personal, health }
enum ProviderID: String, Sendable { case appleOnDevice, applePCC, geminiBYOK, groqBYOK, visionLegacy, deterministic }

struct AIRequest<Output: Decodable & Sendable>: Sendable {
    var task: AITask
    var promptID: PromptID
    var input: AIInput                   // .text(String) | .image(CGImage) | .multimodal([...])
    var context: ContextPacket?          // from F05
    var privacy: PrivacyClass
    var latencyBudget: Duration = .seconds(8)
    var tools: [any AITool] = []         // F07
}
struct AIResult<Output: Sendable>: Sendable {
    var output: Output
    var provider: ProviderID
    var model: String
    var promptVersion: String
    var latency: Duration
    var degradedFrom: [AIError]          // what failed before success (for badges/diagnostics)
}
protocol AIProvider: Sendable {
    var id: ProviderID { get }
    var capabilities: Set<AICapability> { get }   // .text, .vision, .tools, .streaming, .longContext
    func availability() async -> AIAvailability
    func generate<Output: Decodable & Sendable>(_ request: AIRequest<Output>) async throws -> AIResult<Output>
}
```

### 5.2 Default routing table (v1)

| Task | Chain (first available wins) | Notes |
|---|---|---|
| `foodTextParse` | appleOnDevice → applePCC → geminiBYOK → groqBYOK → deterministic (regex + DB fuzzy) | Short prompts; on-device ideal |
| `mealPhotoAnalyze` | learned override (MealLearningEngine) → appleOnDevice (iOS 27 vision) → applePCC → geminiBYOK → groqBYOK → visionLegacy | Keeps today's "never dead-ends" |
| `mealPhotoRefine` | same as analyze minus learned/visionLegacy | |
| `nutritionLabelRead` | Vision text recognition (on-device) → appleOnDevice for structuring | No cloud needed |
| `memoryExtract` / `memoryConsolidate` | appleOnDevice → applePCC | **Never** T3 (health data) |
| `assistantChat` | appleOnDevice (short) → applePCC (long/complex) → geminiBYOK (consent) | Escalation rule in F07 |
| `briefingCompose`, `nudgeCompose`, `budgetExplain` | appleOnDevice → template fallback | Templates guarantee output |
| `weeklyReview` | applePCC → appleOnDevice (shortened) → template | |

## 6. Apple Foundation Models specifics (verify on shipping SDK)
- Check `SystemLanguageModel.default.availability` before use; handle `.unavailable(.deviceNotEligible | .appleIntelligenceNotEnabled | .modelNotReady)` with distinct UI.
- Context is small (a few thousand tokens; read `contextSize` at runtime where available and budget with `tokenCount(for:)`). Map the context-window-exceeded error to a recoverable `AIError.contextOverflow` → escalate to PCC or trim context.
- Use one `LanguageModelSession` per task invocation except the Assistant (F07), which keeps a session per conversation.
- Use `@Generable`/`@Guide` for outputs; constrain numbers with ranges (e.g. quantity 0…50).
- Map guardrail violations to `AIError.guardrail` → try next tier only for benign tasks (food parsing false positives), never for safety-relevant prompts.
- Call `prewarm()` when the user opens a screen that will likely need the model (food log sheet, assistant).

## 7. BYOK providers
- Keys in Keychain via `AIKeyStore` (moved + extended for `gemini`, `groq`).
- Onboarding sheet with step-by-step key creation and a **data-use disclosure** (free tiers may use content to improve the provider's products).
- Gemini: REST `generateContent` with `responseMimeType: application/json` and response schema; model IDs from remote config (Flash / Flash-Lite class models on the free tier).
- Groq: existing client, generalised; model list from remote config.

## 8. Edge cases
- Airplane mode → only T0/T1/T4; UI shows "offline · on-device".
- Apple Intelligence downloading → show "getting ready" and use fallback silently.
- User revokes cloud consent mid-request → cancel in-flight T3 request.
- Locale not supported by on-device model → route to PCC or T3; parse with deterministic fallback.
- Background execution (BGTask) → only on-device providers, respect time limits.

## 9. Acceptance criteria
- [ ] All existing photo-scan behaviour reproduced through the gateway with identical fallbacks (regression test against current `MealScannerEngine`).
- [ ] With T1/T2 forced unavailable, every task still returns either a result or a typed error within its latency budget.
- [ ] A request with `.health` privacy is never sent to T3 without consent (unit test + network-stub assertion).
- [ ] Changing `groqVisionModels` in remote config changes the model used without an app update.
- [ ] Gateway unit-test coverage ≥ 90%.

## 10. Tickets
1. `AI-001` Create `LifeOS/AI/Gateway` module, core types, `MockAIProvider`.
2. `AI-002` `AppleOnDeviceProvider` (+ availability, prewarm, generable mapping).
3. `AI-003` `ApplePCCProvider` (iOS 27, feature-flagged).
4. `AI-004` Port `GroqMealAnalyzer` behind `GroqBYOKProvider`.
5. `AI-005` `GeminiBYOKProvider`.
6. `AI-006` `VisionLegacyProvider` wrapping `OnDeviceMealAnalyzer`.
7. `AI-007` Router + routing table + remote-config overrides.
8. `AI-008` QuotaManager + circuit breaker.
9. `AI-009` SchemaValidator + repair retry.
10. `AI-010` Response cache.
11. `AI-011` Privacy gate + consent store.
12. `AI-012` Telemetry + debug "AI diagnostics" screen.
