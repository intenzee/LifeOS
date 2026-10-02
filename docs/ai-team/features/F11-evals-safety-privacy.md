# F11 — Evaluation, Safety & Privacy

| | |
|---|---|
| **Phase** | Starts Phase 0, continuous, full pass in Phase 5 |
| **Owner** | Eval/QA engineer + AI Lead |
| **Depends on** | Test targets (audit B9), F01 mock providers |

## 1. Why
AI features fail silently: a prompt tweak or a provider model rotation can quietly double calorie errors. Nothing ships without numbers.

## 2. Eval harness
- New Xcode test target `LifeOSAIEvals` (macOS-hosted where the Apple model is reachable; otherwise device runs) + a CLI runner for CI.
- Each eval = dataset (JSONL) + runner (feature function) + scorer + threshold.
- Runs: **smoke** (50 cases/feature) on every PR touching `LifeOS/AI/**`; **full** nightly and before release; results stored as JSON + Markdown summary artefacts.
- Evaluate against each tier separately (T1, T2, T3, fallback) — report per tier.
- Where available on the shipping SDK, use Apple's Evaluations framework / command-line access to the system model for automation; keep our harness as the source of truth.

## 3. Golden datasets

| Dataset | Size (1.0) | Labels | Feature |
|---|---|---|---|
| `food_text` | 500 utterances (en, Hinglish, branded, edge) | items, qty, unit, kcal | F02 |
| `presets` | 200 phrases × 20 synthetic libraries | expected preset | F03 |
| `meal_photos` | 300 weighed meals (≥ 50% Indian), 2 angles where possible | per-item grams, kcal | F04 |
| `labels` | 100 nutrition labels | per-serving facts | F04 |
| `context_qa` | 150 Q&A on synthetic user histories | exact numbers | F05/F07 |
| `memory_extract` | 300 conversations | expected memories | F06 |
| `tool_calls` | 400 assistant turns | tool + args | F07 |
| `reconcile` | 40 workout scenarios + synthetic TDEE sets | expected kcal | F08 |
| `nudges` | 90-day × 50-profile simulations | caps, quiet hours | F09 |
| `redteam` | 250 adversarial prompts | expected safe behaviour | all |

**Photo collection protocol:** team members and paid testers weigh each component on a kitchen scale, photograph before eating (top-down + 45°), record dish names/recipes; consent form; photos stored in a private bucket; no faces.

## 4. Metrics
| Metric | Definition | 1.0 bar |
|---|---|---|
| Item F1 (text) | match on canonical item + qty within ±25% | ≥ 0.92 (T1) |
| kcal MAPE (text, known foods) | mean abs % error | ≤ 10% |
| Item recall / precision (photo) | | ≥ 85% / ≥ 90% |
| kcal MAPE (photo) | | ≤ 25% |
| Tool accuracy | correct tool and valid args | ≥ 95% |
| Data-grounding | numbers in answers equal repository values | 100% |
| Memory precision | no hallucinated memories | ≥ 90% |
| Red-team critical pass | | 100% |
| Latency p50/p95 | per task/tier | per feature docs |

## 5. Safety
### 5.1 Policies baked into prompts and code
- **Disordered eating:** no targets below the floor (F08); no advice on fasting extremes, purging or compensatory exercise; detect risk phrases (deterministic list + T1 classifier) → supportive response, offer "hide numbers" mode, suggest professional help; never auto-suggest weight loss to users with goal "maintain"/"gain".
- **Medical:** general information only; no diagnosis or medication dosing; suggest a clinician.
- **Self-harm:** crisis resources by region; stop coaching in that turn.
- **Body image:** never comment on appearance; no "good/bad food" moralising.
- **Prompt injection:** OCR text, food names from OpenFoodFacts, memories and notes are wrapped as quoted data; tools cannot be invoked by instructions found inside data; write tools require the user's own turn as the trigger.
- **Copy guardrail:** banned-phrase check on all generated user-facing text (guilt/shame/extreme words).

### 5.2 Review process
Any prompt change → smoke evals + red-team subset in CI; weekly AI quality review signs off; new safety failures become permanent test cases.

## 6. Privacy
| Area | Rule |
|---|---|
| Data classification | `.public` / `.personal` / `.health` on every AI request (F01) |
| Default processing | On-device; Apple PCC second |
| Third-party cloud (T3) | Opt-in consent sheet naming the provider and stating free tiers may use content to improve their products; revocable; redacted context only; never HealthKit samples |
| HealthKit | Follow Apple's HealthKit and App Review rules on health data (no advertising/data-mining use; no disclosure to third parties without consent) — legal to sign off the T3 design before Phase 1 beta |
| Storage | All AI stores (memory, conversations, corrections, caches) in the app container with file protection; excluded from logs; photos not kept by default |
| User rights | Export all AI data; delete per item; wipe all; pause memory; per-feature toggles |
| Telemetry | Local only by default; opt-in anonymous metrics (counts/latencies, no content) for beta |
| App Store | Privacy nutrition label updated: Health & Fitness data, user content; "not used for tracking" |
| Keys | BYOK keys only in Keychain (`ThisDeviceOnly`); never logged; never in backups |

## 7. Release gates (Phase 5)
- [ ] All 1.0 bars met on T1/T2; T3/fallback numbers reported.
- [ ] 100% red-team critical cases pass; no open P0/P1 safety bugs.
- [ ] Privacy review (data-flow diagram, consent copy, App Store label) signed by legal/product.
- [ ] Model-rotation drill passed: disable each provider in remote config → app degrades correctly.

## 8. Tickets
`AI-050` test targets (`LifeOSTests`, `LifeOSAIEvals`) · `AI-051` eval harness + CI runner · `AI-052` first 50-case smoke sets per Phase 1 feature · `AI-053` privacy baseline (classification, consent store, logging rules) · `AI-501` full golden datasets · `AI-502` red-team suite · `AI-503` privacy review package · `AI-504` model-rotation drills.
