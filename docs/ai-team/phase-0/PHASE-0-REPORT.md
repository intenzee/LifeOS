# Phase 0: Foundations, implementation report

| | |
|---|---|
| **Date** | 3 October 2026 |
| **Scope** | `phases/PHASE-0-foundations.md`: F01 AI Gateway and the F11 baseline |
| **Status** | Built and unit-tested. **Device build succeeded** (iPhone 15, Debug). On-device UAT of the photo flow is still pending. |
| **Base commit** | `0156906` plus the uncommitted working tree (MealVision and UI work in progress) |

## 1. What was built

| Ticket | Deliverable | Where |
|---|---|---|
| AI-001 | Gateway module, core types, `MockAIProvider` | `LifeOS/AI/Gateway/` |
| AI-002 | `AppleOnDeviceProvider` (availability, prewarm, guided generation via `DynamicGenerationSchema`, streaming, iOS 27 image input) | `Providers/AppleFoundationModels.swift` |
| AI-003 | `ApplePCCProvider` (iOS 27, flag `pccEnabled`) | same file |
| AI-004 | Groq client ported behind `GroqBYOKProvider` (model rotation, JSON mode, retry/backoff, prose → next model) | `Providers/GroqBYOKProvider.swift` |
| AI-005 | `GeminiBYOKProvider` (`responseSchema`, header auth, safety-block mapping) | `Providers/GeminiBYOKProvider.swift` |
| AI-006 | `VisionLegacyMealProvider` wrapping `OnDeviceMealAnalyzer` (T4) | `AppIntegration/` |
| AI-007 | Router plus the v1 routing table, with remote-config overrides, kill switches and feature-flagged entries | `Gateway/ProviderRouter.swift` |
| AI-008 | `QuotaManager`: per-minute and per-day buckets, plus a circuit breaker (3 faults → 10 min, then half-open) | `Gateway/QuotaManager.swift` |
| AI-009 | `SchemaValidator`: conservative coercion and one repair retry with the issues fed back | `Gateway/SchemaValidator.swift` |
| AI-010 | `AIResponseCache`: SHA-256 keyed, per-task TTL, disk-persisted except `.health` | `Gateway/ResponseCache.swift` |
| AI-011 | `PrivacyGate` and consent store: T3 requires consent; `.health` requires the consent sheet; memory tasks never go to T3; redaction; in-flight cancellation on revoke | `Gateway/PrivacyGate.swift` |
| AI-012 | Telemetry (`os.Logger` with private content, `OSSignposter`, content-free event log) and the **AI diagnostics** screen (Settings → AI diagnostics, debug and TestFlight only) | `Gateway/AITelemetry.swift`, `AppIntegration/AIDiagnosticsView.swift` |
| C10 | AI remote config (`{ "ai": … }`, tolerant decoding, 1 h cache, last-good copy on failure) | `Gateway/AIRemoteConfig.swift` |
| AI-050 | Test targets `LifeOSAITests` and `LifeOSAIEvals` (SwiftPM, see §5) | `Package.swift`, `Tests/` |
| AI-051 | Eval harness, `ai-eval` CLI and CI workflow | `Evals/EvalKit`, `Tools/ai-eval`, `.github/workflows/ai.yml` |
| AI-052 | 50-case food-text smoke set. **The photo set is blocked on collection** (`Evals/Datasets/meal_photos/README.md`) | `Evals/Datasets/` |
| AI-053 | Privacy baseline: classification on every request, consent store, logging rules | as above |

App changes:
- `MealScannerEngine` now runs through the gateway with the same public API.
- `MealAnalysis.Source` gains `gemini`, `appleOnDevice` and `appleCloud`, each with a badge in `MealResultView`.
- The key field now shows a data-use disclosure; saving a key records consent and deleting it revokes consent.
- `AIServices.shared.start()` runs at launch.
- `GroqMealAnalyzer.swift` is kept unchanged but unused, as a rollback path. Delete it after on-device sign-off.

## 2. Exit criteria

| Criterion | Result | Evidence |
|---|---|---|
| Photo scanning works identically through the Gateway | ✅ in tests, ⏳ on device | `MealPhotoFlowTests` covers every legacy branch: no key, Groq success with hints, Groq failure → on-device with banner, both fail, empty estimate, refine needs a key. `legacyPayloadParity` shows the Groq request JSON equals the legacy payload. **Still needs a manual scan on the iPhone.** |
| Forcing each provider unavailable degrades correctly (automated) | ✅ | `forcedUnavailableDegrades` for each of 4 tiers; `allModelTiersOff` |
| `.health` provably never reaches T3 without consent | ✅ | `healthNeverReachesT3`: a network stub records **zero** requests |
| Changing `groqVisionModels` in remote config changes the model with no app update | ✅ | `remoteConfigModels` |
| Gateway coverage ≥ 90% | ✅ **94.2%** | `swift test --enable-code-coverage` (Gateway 1634/1735 lines) |
| Spike results reviewed; tier table confirmed or amended | ⚠️ for review | §3 below |

Test totals: **87 unit tests in 12 suites plus 5 eval tests, all passing** (about 0.4 s). The app target builds for the iPhone with no new warnings.

## 3. Spike report (S1–S3)

### S1: Foundation Models on the shipping SDK (Xcode 27 / macOS 27.2, M1)
- `SystemLanguageModel.default.availability == .available`, `contextSize == 4096`.
- Guided generation with a `DynamicGenerationSchema` (no `@Generable` macros needed, so it compiles on the iOS 17.6 deployment target) parsed Indian and Hinglish meals correctly on the first try:
  - "two rotis, dal and a bowl of curd for lunch" → roti ×2 piece, dal ×1, curd ×1 bowl, lunch
  - "3 idlis with sambar and filter coffee in the morning" → breakfast, 3 items
- **Latency, measured in isolation:** 10.0 s cold, then 2.4 s and 1.7 s warm. `prewarm()` matters, and the food-log sheet must call `gateway.prewarm(for: .foodTextParse)` when it opens.
- **Latency on the 50-case run was not representative.** The Mac was under heavy load (you reported lag), so p50 rose to about 15 s. That run used a 30 s budget, so many cases timed out and the circuit breaker then skipped the rest. Of the 20 cases that completed, precision was 100% and recall was near-complete; the only miss was "butter" in ft-005. The harness now resets the breaker per case and allows 60 s. **Action:** re-run `LIFEOS_LIVE_EVALS=1 swift test --filter liveOnDevice` on an idle Apple Intelligence device and record p50/p95.
- **Schema gotcha found:** nested type names must be unique within a `GenerationSchema`. The converter derives names from property paths, and a test covers it.

### S2: PCC access and terms; on-device image input
- `PrivateCloudComputeLanguageModel` exists on the shipping SDK (iOS/macOS 27), with `availability`, `quotaUsage` and a typed error enum (`networkFailure`, `quotaLimitReached`, `serviceUnavailable`).
- Image input is real: `Attachment(cgImage)` inside a `Prompt` on iOS/macOS 27.
- **From an unsigned CLI, PCC reports `.available` but every call fails** with `ModelManagerError 1046`. This is almost certainly an entitlement or app-identity requirement. The gateway treats it as recoverable and falls back, as designed. **Action:** retest from the signed app on an iOS 27 Apple Intelligence device, and confirm the PCC terms (free under 2M downloads) with legal.
- **Device finding:** the team's test phone is an **iPhone 15 (A16), which is not Apple Intelligence-eligible**. On it T1 and T2 report `deviceNotEligible`, and food text goes to T3 if a key is present, otherwise to the rule parser. Risk R2 is real for this hardware. Phase 0 entry criteria called for at least two Apple Intelligence iPhones.

### S3: Gemini BYOK with JSON schema
- Implemented with `responseMimeType: application/json` plus `responseSchema`, generated from the same `AISchema`. The key goes in the `x-goog-api-key` header, never in the URL. The model list comes from remote config (`gemini-flash-lite-latest`, `gemini-flash-latest` aliases).
- **Not run live: no key was available.** Wire-level behaviour is covered by stub tests: request shape, a 400 "API key" response → `authFailed`, 404 → model rotation, and a safety block → `guardrail`. **Action:** run `GEMINI_API_KEY=… swift run ai-eval food-text --tiers geminiBYOK` (and the same for Groq).

### Food-text smoke eval (`Evals/Datasets/food_text_smoke.jsonl`, 50 cases)
| Tier | Item F1 | Notes |
|---|---|---|
| T0 deterministic | 100% | ⚠️ The rules were tuned on this same set, so this overstates real quality. Phase 1's held-out 500-utterance golden set is the honest measure (bar: ≥ 0.80). |
| T1 on-device | not representative | See S1. Completed cases were near-perfect. |
| T2 PCC | 0% | Entitlement issue from the CLI (S2) |
| T3 Gemini / Groq | skipped | No keys |

Raw reports are in `phase-0/eval-reports/`.

## 4. Decisions and spec amendments (for AI Lead review)
1. **Providers return raw text; the gateway validates and decodes centrally.** This amends the F01 §5.1 signature `generate<Output>`. Every engine is held to one contract, and one `AISchema` drives Apple, Gemini, Groq and the validator.
2. **Phase 0 photo routing** is Groq → Vision-legacy. The Apple and Gemini vision tiers are in the table but gated by the `photoAppleVision` flag (off), to meet the "identical behaviour" exit criterion. F04 turns the flag on.
3. **Consent migration:** users who already saved a Groq key get `.personal` consent (`legacyKeyEntry`). Saving a key on a screen that discloses data use also counts as `.personal` consent. `.health` always needs the explicit consent sheet (design kit C6).
4. **`ParsedFoodItem.quantity` range widened from 0…50 to 0…5000.** F02's range can't express "200 g paneer" or "300 ml milk".
5. **Photo answers are not cached in Phase 0**, to keep behaviour identical. Food-text parses are cached for 30 days.
6. **Test targets are SwiftPM** (root `Package.swift` compiling `LifeOS/AI`) rather than Xcode targets. That works with plain `swift test` locally and in CI, needs no `.pbxproj` edits, and mirrors the app's concurrency settings. Move it to `Packages/LifeOSAI` when iOS Core sets up the package layout (engineering roadmap 01).
7. **Known small difference from legacy:** when Groq returns valid JSON that is empty or all-zero, the gateway does a repair retry on the same provider instead of trying Groq's second model. The end result is the same (on-device fallback); this edge case costs one extra request.

## 5. How to run
```bash
swift test                                              # unit tests + eval gate (no Xcode needed)
swift run ai-eval food-text --tiers deterministic,appleOnDevice --out Evals/reports
GROQ_API_KEY=… GEMINI_API_KEY=… swift run ai-eval food-text --tiers groqBYOK,geminiBYOK
```
In the app: **Settings → AI diagnostics** (debug and TestFlight). From there you can toggle providers, run the same sentence on every tier with provenance and latency (the Phase 0 demo), and inspect quotas, consent, config and recent events.

## 6. Open items before Phase 1 entry
- [ ] On-device UAT: scan with and without a Groq key, with a bad key, in airplane mode, and refine. Check the diagnostics events.
- [ ] Live T1 and T2 numbers on an Apple Intelligence iPhone (iOS 27); live T3 numbers with keys.
- [ ] Remote config hosting URL (C10, iOS Core). Set the `LifeOSAIRemoteConfigURL` Info.plist key once it exists.
- [ ] Photo smoke set collection (≥ 30 weighed meals).
- [ ] Decide on Apple Intelligence test hardware (R2). The current phone can't run T1 or T2.
- [ ] Delete `GroqMealAnalyzer.swift` after on-device sign-off.
