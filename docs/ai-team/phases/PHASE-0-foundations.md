# Phase 0 — Foundations (Weeks 1–3)

> **Status (3 Oct 2026):** implemented — see [`../phase-0/PHASE-0-REPORT.md`](../phase-0/PHASE-0-REPORT.md) for results, spike findings and open items.

**Goal:** build the plumbing every AI feature will stand on, prove the free model tiers work on real devices, and put evals in CI before any user-facing AI ships.

## Scope
| In | Out |
|---|---|
| F01 AI Gateway (all providers, router, quota, validation, cache, privacy gate) | Any new user-facing AI feature |
| F11 baseline: test targets, eval harness, mock providers, logging rules, privacy classification | Full golden datasets (start collection only) |
| Port existing photo scan through the Gateway with zero behaviour change | Photo v2 improvements |
| Remote config for model lists + feature flags (with iOS Core, C10) | |
| Technical spikes (below) | |

## Entry criteria
- Contracts C1 (SwiftData plan + timeline), C7 (Gateway API review), C10 agreed with iOS Core.
- Test devices: at least 2 Apple Intelligence iPhones on the current iOS (one on the latest major), 1 older non-AI iPhone, 1 Apple Watch.
- Decisions 1–2 in the master plan §10 answered.

## Week-by-week
| Week | Work | Owner |
|---|---|---|
| 1 | **Spike S1:** Foundation Models on shipping SDK — availability states, `@Generable` food-parse prototype, token limits, latency on device. **Spike S2:** PCC access & terms; on-device image input. **Spike S3:** Gemini free-tier BYOK call with JSON schema. Gateway skeleton + core types + `MockAIProvider`. Create `LifeOSTests` & `LifeOSAIEvals` targets. | Lead / A / B / QA |
| 2 | Providers: AppleOnDevice, ApplePCC (flagged), GroqBYOK (port), GeminiBYOK, VisionLegacy. Router + routing table. SchemaValidator + repair. QuotaManager + circuit breaker. | A + B |
| 3 | Privacy gate + consent store. Response cache. Telemetry + debug diagnostics screen. Re-route `MealScannerEngine` through the Gateway; regression tests. Eval harness + 50-case smoke sets for food text and photos; CI job. Spike write-up. | All |

## Deliverables
- `LifeOS/AI/Gateway` module with ≥ 90% unit coverage.
- Spike report: measured latency/accuracy of T1/T2/T3 on 50 sample food sentences and 30 photos; go/no-go per tier.
- CI running smoke evals on PRs touching `LifeOS/AI/**`.
- Updated remote config with model lists.

## Exit criteria
- [ ] Current photo scanning works identically through the Gateway (regression suite green).
- [ ] Forcing each provider unavailable degrades correctly (automated test).
- [ ] `.health` requests provably never reach T3 without consent.
- [ ] Spike results reviewed; master-plan tier table confirmed or amended.

## Demo
Toggle providers live from the debug screen and show the same food sentence parsed by T1 → T2 → T3 → fallback, with provenance badges and latency.

## Risks
Shipping SDK differs from WWDC announcements (R1) → spike in week 1 decides; adjust tier table before Phase 1.
