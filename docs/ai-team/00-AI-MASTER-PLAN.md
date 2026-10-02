# LifeOS — AI Team Master Plan

| | |
|---|---|
| **Audience** | AI/ML engineering team (lead + engineers), with read-only relevance to iOS Core, Health/Watch and UI/UX teams |
| **Status** | Draft v1.0 — for kickoff review |
| **Date** | 2 October 2026 |
| **Codebase reviewed** | `LifeOS-main` (iOS 17.6+ SwiftUI app + watchOS companion), commit `0156906` |
| **Scope** | Every AI capability in LifeOS: food understanding, photo capture, presets, context, memory, assistant, workout-aware calories, automation, Siri/Watch voice, evaluation and safety |

> **One-line goal:** turn LifeOS from "a tracker you feed" into "a private concierge that already knows" — it logs what you say, sees what you eat, remembers how you live, adapts your calories to what your Apple Watch actually measured, and does all of it at **zero AI running cost**.

---

## 1. How to read this document set

```
docs/ai-team/
├── 00-AI-MASTER-PLAN.md          ← you are here (vision, architecture, phases, roles, risks)
├── 01-current-state-audit.md     ← what AI already exists in the code, and what blocks us
├── 02-cross-team-contracts.md    ← what we need from iOS Core, Health/Watch and Design (and what we give back)
├── phases/
│   ├── PHASE-0-foundations.md
│   ├── PHASE-1-smart-food-logging.md
│   ├── PHASE-2-context-memory-calories.md
│   ├── PHASE-3-assistant-and-coaching.md
│   ├── PHASE-4-automation-and-ambient.md
│   └── PHASE-5-hardening-and-launch.md
└── features/
    ├── F01-ai-gateway-model-router.md
    ├── F02-natural-language-voice-food-logging.md
    ├── F03-ai-managed-food-presets.md
    ├── F04-meal-photo-capture-v2.md
    ├── F05-context-engine.md
    ├── F06-memory-system.md
    ├── F07-lifeos-assistant.md
    ├── F08-workout-aware-calorie-intelligence.md
    ├── F09-proactive-insights-and-automations.md
    ├── F10-siri-shortcuts-and-watch-voice.md
    └── F11-evals-safety-privacy.md
```

- **Phase docs** say *when* and *in what order* — sprint plans, deliverables, exit criteria.
- **Feature docs (F01–F11)** say *what* and *how* — requirements, architecture, data models, prompts, edge cases, acceptance criteria. Each is self-contained so it can be handed to one engineer.
- **Contracts doc** is the hand-shake with the other teams. Nothing in our phases should start until its row in that doc is agreed.

---

## 2. Product vision for AI in LifeOS

LifeOS is positioned as a premium, multipurpose "personal operating system" — health, nutrition, fitness, hydration, tasks and streaks in one place. The AI layer is what makes it feel premium: the user should almost never fill in a form.

| The user does… | LifeOS AI does… |
|---|---|
| Says *"log my usual breakfast"* or *"two rotis, dal and a bowl of curd for lunch"* | Parses it, resolves nutrition from trusted sources, shows a one-tap confirmation card, logs it (F02, F03) |
| Snaps a photo of a thali | Identifies each item, estimates portions and macros, learns from every correction (F04) |
| Eats the same thing three Mondays in a row | Offers to save it as a preset, then reminds/auto-logs it on Mondays if allowed (F03, F09) |
| Finishes a run with their Apple Watch | The workout appears automatically, today's calorie budget adjusts, and LifeOS can explain why (F08) |
| Asks *"why am I always over on Fridays?"* | Answers from their own data and memory, not generic advice (F05, F06, F07) |
| Says *"Hey Siri, log water"* on the Watch | Done, without opening the app (F10) |
| Does nothing | Gets one well-timed, useful nudge a day — not ten (F09) |

### Design principles (non-negotiable)

1. **The model understands; code computes.** LLMs parse language, recognise food and write explanations. Calorie maths, budgets, streaks and nutrition look-ups are deterministic Swift. A model-guessed calorie number is always labelled as an estimate.
2. **Never dead-end.** (Already the ethos of `MealScannerEngine`.) Every AI path has a cheaper fallback, ending in plain manual entry.
3. **Private by default.** On-device first, Apple Private Cloud Compute second, third-party cloud only with explicit, revocable consent.
4. **Every AI write is visible and undoable.** No silent changes to the user's log, budget or memory.
5. **Context is budgeted.** Small on-device models have small context windows; we assemble a compact, relevant context packet per request rather than dumping everything.
6. **Memory belongs to the user.** They can see it, edit it, pause it and wipe it.
7. **Free by architecture, not by luck.** We route around rate limits and model retirements instead of hoping they never happen.
8. **No feature ships without an eval.** Each feature has a golden dataset and a pass bar (F11).

---

## 3. "All of this is free" — what that really means

The brief requires zero running cost. That is achievable, but only with the tiered design below. Two facts the team must keep in mind:

- **Apple's models are the free backbone.** The Foundation Models framework gives apps an on-device LLM with structured output and tool calling at no cost (iOS 26+, Apple Intelligence-capable devices only). At WWDC26 Apple added image input for the on-device model and a Private Cloud Compute (PCC) server model with a larger context window, announced as free for apps under 2M first-time downloads (iOS 27+). These are the default engines. *Re-confirm the exact API surface and the PCC terms against the shipping SDK before Phase 0 ends.*
- **A Google One / Google AI Pro subscription does not give Gemini API access or credits.** It covers consumer Gemini in Google apps. The Gemini API has its own free tier through Google AI Studio, with rate limits per project, and Google's pricing page marks free-tier content as *used to improve Google's products*. That makes the free tier unsuitable as the default path for health data. We support it only as an opt-in, bring-your-own-key fallback.

### Model tiers

| Tier | Engine | Cost | Runs where | Needs | Used for |
|---|---|---|---|---|---|
| **T0** | Deterministic Swift + local nutrition DB + rules | Free | Device | Any iOS 17.6+ device | Nutrition maths, budgets, streaks, rule triggers, preset matching |
| **T1** | Apple on-device Foundation Model (`SystemLanguageModel`) | Free | Device | iOS 26+ and an Apple Intelligence iPhone; image input from iOS 27 | Food-text parsing, memory extraction, notification copy, short chat, photo analysis on iOS 27 |
| **T2** | Apple Private Cloud Compute model | Free (under Apple's download threshold) | Apple PCC | iOS 27+ / watchOS 27+ | Harder photos, longer conversations, weekly reviews, reasoning |
| **T3** | Bring-your-own-key cloud: Gemini free tier, Groq free tier (existing) | Free within the user's own rate limits | Google / Groq | Network, user key in Keychain, explicit consent | Older/non-Apple-Intelligence devices; power users |
| **T4** | Legacy on-device: Vision `VNClassifyImageRequest`, `NLEmbedding` | Free | Device | iOS 17+ | Last-resort photo guess, keyword search |

Routing between tiers is owned by the **AI Gateway** (F01). Product code never calls a model directly.

> ⚠️ **Coverage gap to plan for:** users on iPhones without Apple Intelligence get T0 + T3 (if they add a key) + T4 only. Product must decide whether "Smart" features are labelled as requiring a recent iPhone, or whether a server proxy (Cloudflare Workers free tier holding a key) is acceptable. See Risk R2.

---

## 4. Target AI architecture

```
                         ┌────────────────────────────────────────────┐
  UI (SwiftUI, Watch,    │                AI FEATURES                 │
  Siri/App Intents,      │  F02 NL/Voice log   F03 Presets  F04 Photo │
  widgets)  ───────────▶ │  F07 Assistant      F08 Calories F09 Nudges│
                         └───────────────┬────────────────────────────┘
                                         │ AIRequest(task, input, schema, privacyClass)
                         ┌───────────────▼────────────────────────────┐
                         │            F05 CONTEXT ENGINE              │
                         │ profile · today · trends · presets · memory│
                         │ token budget per tier · privacy filter     │
                         └───────────────┬────────────────────────────┘
                                         │ ContextPacket
┌──────────────────┐     ┌───────────────▼────────────────────────────┐
│ F06 MEMORY STORE │◀───▶│              F01 AI GATEWAY                │
│ facts · prefs ·  │     │ router · quota/circuit breaker · cache ·   │
│ episodes ·       │     │ schema validation & repair · telemetry     │
│ corrections      │     └──┬─────────┬─────────┬─────────┬───────────┘
│ (on-device,      │        │T1       │T2       │T3       │T4
│  encrypted)      │   On-device   Apple PCC  Gemini/   Vision /
└──────────────────┘   Foundation            Groq BYOK  NLEmbedding
                       Model
                                         ▲
┌────────────────────────────────────────┴───────────────────────────┐
│ DOMAIN DATA (owned by iOS Core / Health teams — see 02-contracts)  │
│ SwiftData store · FoodLog · Presets · Workouts (HealthKit feed) ·  │
│ Water · Weight · Todos · Streaks · DomainEvent bus                 │
└────────────────────────────────────────────────────────────────────┘
```

### New modules the AI team will own (proposed layout)

```
LifeOS/AI/
├── Gateway/        AIGateway, ProviderRouter, providers (AppleOnDevice, ApplePCC, GeminiBYOK, GroqBYOK, VisionLegacy), QuotaManager, SchemaValidator
├── Context/        ContextEngine, ContextProvider protocol + providers, TokenBudgeter, PrivacyFilter
├── Memory/         MemoryStore (SwiftData), MemoryExtractor, MemoryRetriever, Consolidator (BGTask)
├── Food/           FoodTextParser, NutritionResolver, PresetEngine, MealVision (moved from Services/MealVision)
├── Calories/       WorkoutReconciler, BudgetPolicy, AdaptiveTDEE, BudgetExplainer
├── Assistant/      AssistantSession, Tools/ (LogFoodTool, LogWaterTool, QueryStatsTool, …), Briefing
├── Automation/     TriggerEngine, NudgeRanker, Schedulers
├── Intents/        App Intents, App Shortcuts, Watch bridge
└── Evals/          Golden datasets, harness, metrics (test target)
```

The existing `Services/MealVision/` stack (Groq analyzer, on-device analyzer, learning engine, correction store) is good work and is **kept and wrapped**, not rewritten. See `01-current-state-audit.md`.

---

## 5. Phases at a glance

Estimates assume 1 AI lead + 2 AI/iOS engineers + 1 part-time eval/QA engineer, with the dependencies in `02-cross-team-contracts.md` delivered on time. Weeks are relative to kickoff.

| Phase | Weeks | Theme | Features | Ships to users? |
|---|---|---|---|---|
| **0** | 1–3 | Foundations | F01 Gateway, F11 eval harness + privacy baseline | No (internal) |
| **1** | 4–9 | Smart food logging | F02 NL/voice logging, F03 AI presets, F04 Photo v2 | ✅ Beta 1 |
| **2** | 10–13 | Context, memory, workout-aware calories | F05 Context, F06 Memory, F08 Calorie intelligence | ✅ Beta 2 |
| **3** | 14–18 | Assistant & coaching | F07 Assistant (chat + tools), daily briefing, weekly review | ✅ Beta 3 |
| **4** | 19–22 | Automation & ambient | F09 Proactive nudges/automations, F10 Siri/Shortcuts/Watch voice | ✅ Release candidate |
| **5** | 23–25 | Hardening & launch | F11 full eval pass, red-team, performance, model-rotation drills | ✅ 1.0 |

Each phase has its own document under `phases/` with a sprint-by-sprint breakdown and exit criteria.

```
Week:  1  2  3 | 4  5  6  7  8  9 | 10 11 12 13 | 14 15 16 17 18 | 19 20 21 22 | 23 24 25
P0    ████████ |                  |             |                |             |
P1             | ████████████████ |             |                |             |
P2             |                  | ███████████ |                |             |
P3             |                  |             | ██████████████ |             |
P4             |                  |             |                | ███████████ |
P5             |                  |             |                |             | ████████
F11 evals   ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ (continuous)
```

---

## 6. Feature index

| ID | Feature | Phase | Primary tier | Depends on |
|---|---|---|---|---|
| F01 | [AI Gateway & Model Router](features/F01-ai-gateway-model-router.md) | 0 | all | — |
| F02 | [Natural-language & voice food logging](features/F02-natural-language-voice-food-logging.md) | 1 | T1 → T3 | F01, nutrition DB |
| F03 | [AI-managed food presets](features/F03-ai-managed-food-presets.md) | 1 | T0 + T1 | F02, SwiftData |
| F04 | [Meal photo capture v2](features/F04-meal-photo-capture-v2.md) | 1 | T1(iOS 27)/T2 → T3 → T4 | F01, existing MealVision |
| F05 | [Context engine](features/F05-context-engine.md) | 2 | T0 | Domain repositories |
| F06 | [Memory system](features/F06-memory-system.md) | 2 | T1 + on-device embeddings | F05 |
| F07 | [LifeOS Assistant](features/F07-lifeos-assistant.md) | 3 | T1/T2 | F01, F05, F06, tools |
| F08 | [Workout-aware calorie intelligence](features/F08-workout-aware-calorie-intelligence.md) | 2 | T0 (+T1 for explanations) | HealthKit workout feed (Health team) |
| F09 | [Proactive insights & automations](features/F09-proactive-insights-and-automations.md) | 4 | T0 + T1 | F05, F06, F08 |
| F10 | [Siri, Shortcuts & Watch voice](features/F10-siri-shortcuts-and-watch-voice.md) | 4 | T1/T2 | F02, F03, F07 |
| F11 | [Evals, safety & privacy](features/F11-evals-safety-privacy.md) | 0→5 | — | all |

---

## 7. Team, roles and ceremonies

| Role | Owns |
|---|---|
| **AI Lead** | Architecture, Gateway (F01), model/vendor decisions, safety sign-off, weekly AI review |
| **AI Engineer A — "Food"** | F02, F03, F04, nutrition resolver, food evals |
| **AI Engineer B — "Brain"** | F05, F06, F07, F09, assistant tools |
| **Eval / QA engineer (part-time)** | F11 datasets, harness, red-team, regression gates in CI |
| **Shared with Health team** | F08 (Health team owns the HealthKit feed; AI team owns reconciliation + budget policy + explanations) |
| **Shared with iOS Core** | F10 App Intents plumbing, SwiftData migration |
| **Shared with Design** | Every AI surface (states, motion, confidence UI, consent sheets) — see contracts doc §4 |

**Ceremonies:** two-week sprints aligned with the other teams; a 30-minute weekly **AI quality review** (eval dashboard, new failure cases, model/provider changes); a demo at the end of each phase.

**Definition of Done for any AI feature:**
- [ ] Routed through `AIGateway` (no direct model calls)
- [ ] Works on the fallback path (tested with T1/T2 disabled)
- [ ] Golden-set eval added and passing its bar in CI
- [ ] Privacy class declared; nothing leaves the device without consent
- [ ] Every write is undoable and visible in the UI
- [ ] Unit tests for deterministic parts; snapshot tests for UI states agreed with Design
- [ ] Logged with `OSLog` categories (no PII in logs)

---

## 8. Success metrics (targets for 1.0)

| Metric | Target | Measured by |
|---|---|---|
| Median time to log a meal by voice/text or preset | ≤ 5 s | On-device telemetry (local, opt-in export) |
| Median time to log a meal by photo (incl. confirm) | ≤ 10 s | Telemetry |
| Share of meals logged through an AI path | ≥ 60% | Telemetry |
| Calorie error, text logging on known foods (MAPE) | ≤ 10% | F11 golden set |
| Calorie error, photo logging (MAPE) | ≤ 25% (stretch 20%) | F11 golden photo set (weighed meals) |
| Food item recall on photos | ≥ 85% | F11 |
| Assistant tool-call success (right tool, valid args) | ≥ 95% | F11 |
| Workouts from Apple Watch reflected in budget within 15 min | ≥ 95% | Health-team integration test |
| Users who keep memory enabled after 30 days | ≥ 80% | Telemetry |
| AI running cost to the company | **$0** | Billing (should be no bill) |
| Safety eval pass rate (disordered-eating, medical, injection) | 100% of critical cases | F11 red-team suite |

---

## 9. Top risks

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | Apple Foundation Models API or PCC terms differ from the WWDC26 announcement | Re-plan of T1/T2 | Gateway abstraction; spike in Phase 0 week 1 on shipping SDK |
| R2 | Many users lack Apple Intelligence hardware | "Smart" features unavailable to them | T3 BYOK + T0/T4 fallbacks; product decision on optional free-tier proxy; clear device messaging |
| R3 | Groq's current vision models are preview-only and can be removed at short notice (the code already survived one retirement in June 2026) | Photo path breaks for BYOK users | Keep the model-rotation list remotely configurable; Gemini as second BYOK option |
| R4 | Free-tier third-party providers may train on submitted content | Health-data privacy and App Review problems | T3 is opt-in only with explicit disclosure; strip identifiers; never send HealthKit-derived data without consent (F11) |
| R5 | Small on-device context window (a few thousand tokens) | Assistant forgets, truncation errors | Context Engine budgets (F05); session summarisation (F07); escalate long tasks to PCC |
| R6 | Data layer still on `UserDefaults`; workout history only addressable for the current week | Trends, memory and calorie learning have no reliable history | SwiftData migration is a **blocking** dependency on iOS Core (contracts doc §2) |
| R7 | Calorie features can harm users with disordered eating | User harm, reputational damage | Floors, tone rules, opt-out of numbers, safety evals (F08, F11) |
| R8 | Double-counting exercise (manual MET sets + Watch active energy) | Inflated budgets | Workout reconciliation in F08 |
| R9 | Photo portion estimation is inherently uncertain | Trust erosion | Show ranges/confidence honestly; fast correction UX; learning loop |

---

## 10. Decisions needed before kickoff

1. **Minimum OS for AI features** — recommend AI features require iOS 26+ (T1) with graceful fallback below; app stays iOS 17.6+.
2. **Third-party cloud policy** — confirm T3 is BYOK + opt-in only (recommended), or approve a free-tier proxy.
3. **Language scope for 1.0** — recommend English + Hinglish/romanised Hindi food names in parsing; full Hindi UI later.
4. **Auto-logging policy** — recommend presets can auto-log only after explicit per-preset opt-in, always with undo.
5. **Paid Apple Developer Program** — required for HealthKit background delivery and App Store release (the README notes the Watch currently avoids the HealthKit entitlement to sign on a free account).

---

## 11. Glossary

- **BYOK** — bring your own key: the user pastes their own provider API key; stored in Keychain (`AIKeyStore` already does this).
- **PCC** — Apple Private Cloud Compute.
- **Context packet** — the compact, privacy-filtered bundle of user state sent with a model request (F05).
- **Golden set** — fixed, labelled dataset used to score a feature before release (F11).
- **Preset** — a named, reusable meal or food combination ("my usual breakfast") (F03).
- **Reconciliation** — merging manual and Apple Watch workout data without double-counting (F08).
