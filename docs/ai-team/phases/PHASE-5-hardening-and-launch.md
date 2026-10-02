# Phase 5 — Hardening & Launch (Weeks 23–25) → 1.0

**Goal:** prove quality, safety and privacy with numbers; rehearse failures; launch.

## Scope
- Full golden datasets complete (F11 §3) and full eval run per tier.
- Red-team suite (250 prompts) incl. disordered-eating, medical, self-harm, prompt injection via OCR/food names/memories.
- Privacy review package: data-flow diagram, consent copy, App Store privacy label, HealthKit usage justification.
- Performance: cold start unaffected by AI modules (lazy init), memory footprint, battery impact of BG tasks, model prewarm strategy.
- **Model-rotation drills:** disable each provider via remote config; simulate retired Groq/Gemini models; Apple Intelligence turned off; airplane mode.
- Optional R&D spike: LiDAR portion estimation (F04 §4.2) — ship only if ≥ 15% MAPE gain.
- Launch runbook for the AI layer (below).

## Week plan
| Week | Focus |
|---|---|
| 23 | Full evals; fix top failure clusters; red-team run 1 |
| 24 | Drills; performance/battery profiling; privacy package; red-team run 2 |
| 25 | Release gates sign-off; App Review notes; launch; on-call rota for week 1 |

## Release gates (all required)
- [ ] All 1.0 metric bars in the master plan §8 met on T1/T2.
- [ ] 100% red-team critical cases pass; no open P0/P1 AI bugs.
- [ ] Privacy review signed off by product + legal.
- [ ] All drills pass with correct degradation and user messaging.
- [ ] AI cost: $0 (no paid provider accounts in production config).

## AI launch runbook (summary)
| Situation | Action |
|---|---|
| A T3 model retired | Update `groqVisionModels`/`geminiModels` in remote config; no app release needed |
| Spike in bad photo estimates | Check eval dashboard by provider; roll back `promptVersion` via remote config |
| Apple model behaviour change after an iOS update | Run full eval on the new iOS beta at each beta drop; adjust prompts; keep fallbacks |
| Safety incident reported | Disable affected feature flag; add case to red-team suite; hotfix prompt/guardrail; postmortem |
| Users hitting BYOK rate limits | Messaging already in `AIError`; suggest on-device path; consider routing more tasks to T1/T2 |
