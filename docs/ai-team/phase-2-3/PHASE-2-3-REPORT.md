# Phases 2 and 3: Context, memory, calories and the assistant (implementation report)

| | |
|---|---|
| **Date** | 3 October 2026 |
| **Scope** | `phases/PHASE-2-context-memory-calories.md` (F05, F06, the AI parts of F08) and `phases/PHASE-3-assistant-and-coaching.md` (F07) |
| **Target device** | iPhone 15, which has no Apple Intelligence. Everything below works without a model. A Gemini/Groq key with health consent adds model answers. |
| **Branch** | `ai/phase2-3-context-memory` (worktree `.claude/worktrees/ai-phase2`) |
| **Status** | Built, unit-tested and reviewed by UI/UX (their required change is applied). 187 AI unit tests, 9 eval tests and 50 Experience tests pass; `check-single-budget.sh` passes; the app compiles for iOS. Device install and UAT are pending (§7). |

## 1. Division of work with the other sessions

There was already a lot in place before this work started:
- UI/UX Phase 4 had shipped the assistant screen, a rule-based "brain", the memory screen, the weekly review and automations.
- Engineering Phase 1 had shipped workout reconciliation (`WorkoutMerge`), the calorie engine (`CalorieEngine`, `BudgetService`) and HealthKit ingestion.

This phase therefore builds the AI engine underneath those features instead of a second copy of them. These splits were agreed in writing with both sessions:

| Item | Owner | Notes |
|---|---|---|
| Reconciliation, budget policy, caps/floors (F08 §4–5) | Engineering (WCH-06, CAL-01..07) | AI reads `BudgetBreakdown` and never recomputes a budget. `check-single-budget.sh` stays green. |
| Adaptive TDEE estimator (F08 §6) | Engineering (CAL-10/11/12) | AI only words the result: `MaintenanceSuggestion`, which says nothing unless `status == ok` and the gap is at least 100 kcal. |
| Meal-slot prediction (FOOD-16) | **AI** (`MealWindows`) | Engineering dropped it from their scope. |
| Assistant screens, cards, orb, memory screen | UI/UX | AI added the `.confirmMemory` and `.done` cards (UI/UX approved), plus hooks in `AssistantSession` and `IntelligenceStore`. |

## 2. What ships

### Phase 2

| Feature | What it does | Where |
|---|---|---|
| **Context engine** (F05) | Builds the context sent with each AI request. It has 10 sources: time, profile, today, budget, trend, meal windows, presets, memory, schedule and conversation. Each intent has its own list of sources. Time is always included, and today is included for health questions. Remaining sources are added greedily by priority per token, and lists are trimmed to fit. Output is terse `key=value` text. Budgets are 600 tokens (on-device), 3,000 (Apple PCC) and 2,000 (Groq/Gemini). Packets are cached and cleared by events. | `AI/Context/` |
| Privacy for Groq/Gemini | Every section carries a third-party version, and the gateway sends that version to Groq/Gemini (`ContextPacket.forThirdParty`). It removes age and sex, rounds numbers (kcal to 10, grams and weight to 5), replaces todo titles with counts, and keeps only food-preference memories, never sensitive ones. Consent is still checked separately: health data needs the consent sheet. | `Gateway/AICore.swift`, `AIGateway.swift` |
| **Memory engine** (F06) | **Rule extraction on device**, the whole pipeline on the iPhone 15. It covers diets (including weekday diets and exceptions), firm avoids, dislikes and likes, allergies and intolerances, portion sizes ("my katori is 120 ml"), dish calories, training days, meal times, quiet hours, answer style, and dated goals with expiry ("off sugar this month", "10k in December"). | `AI/Memory/MemoryExtractor.swift` |
| Safety rules | Health conditions and medicines are **held until the user taps "Remember"**. Body-image judgments are never stored. Instruction-like sentences are stripped before anything is saved. | same |
| Reconciliation | Duplicates are detected by typed facet or embedding similarity (≥ 0.88) and reinforce the existing memory. A contradiction (vegetarian → "I eat chicken now") **supersedes** the old memory and keeps it as history. An inferred guess never overrides something the user stated, and inferred items below 0.7 confidence wait for confirmation. | `MemoryEngine.swift` |
| Retrieval | Score = 0.55·cosine + 0.20·importance + 0.15·recency + 0.10·kind prior. Pinned items and hard food constraints (allergies, diets, avoids) always rank first for food intents. Third parties never see sensitive items. | same |
| Consolidation | Day episodes and weekly roll-ups; routines decay by 0.2 per 30 days without being observed; expired goals are archived; items are re-embedded when the model changes. Runs on the first foreground of the day (no BG task needed, so no project change). | same |
| Embeddings | `NLEmbedding` sentence vectors, available on every iPhone, with a deterministic hashing fallback. Vectors are versioned and never mixed across versions. | `TextEmbedder.swift` |
| Store | `memory-index.json` in Application Support, protected until first unlock and excluded from backup. Pause and wipe delete the file and all vectors; export to JSON or Markdown. The Experience memory list stays the user-visible source of truth; the index holds the AI metadata, linked by shared ids. | `MemoryIndexStore`, `AppIntegration/AIMemoryBridge.swift` |
| Model extraction | For phones with Apple Intelligence; the privacy gate keeps it on Apple's side. It adds only what the rules can't see, through the same safety filter. | `ModelMemoryExtractor.swift` |
| **Learned meal windows** (F02/F05, FOOD-16) | Learns when this user eats each meal from at least 3 logged occasions (interquartile range ±60 min). Smart Log uses it to pick the meal, falling back to clock hours. | `AI/Context/MealWindows.swift`, `SmartFoodLogger.mealSlot` |
| **Portion hints** (F04) | "My katori is 120 ml" and "my roti weighs 30 g" change the grams in Smart Log and photo v2. "Mom's rajma is 180 kcal per katori" becomes one of the user's own foods. | `PortionHints` in `NutritionResolver.swift` |
| **Budget explanation** (F08 §7) | "Why is my target 2,195?" is answered from the engine's lines in order: resting burn, everyday activity, goal, safe-minimum top-up, and credit earned from activity (with the eat-back percentage, the allowance and each workout). A model may rephrase it, but **any new number rejects the phrasing**. | `AI/Calories/BudgetExplanation.swift` |
| **Post-workout card** (F07 §6) | "+145 kcal added to today's budget from your 42-min evening run. 91 g protein to go." It is shown as the in-app event banner on `.healthWorkoutSynced`, deduplicated by session id. If the workout stays within the everyday allowance, it says so honestly. | same + `AIAssistantBridge.startObservingWorkouts` |

### Phase 3

| Feature | What it does | Where |
|---|---|---|
| **Safety first** (F07 §7) | Runs on device before anything else, every turn. It covers: <ul><li>self-harm, with crisis lines by region: India Tele-MANAS 14416, US 988, UK Samaritans;</li><li>medical emergencies, pointing to 112, 911 or 999;</li><li>disordered eating: daily targets below the floor, purging, laxatives, not eating for days, appetite suppression, and body-image distress combined with restriction;</li><li>compensatory exercise;</li><li>medicines and doses;</li><li>prompt injection;</li><li>out-of-scope requests.</li></ul> Safety replies contain no numbers or plans. Thresholds are narrow, so "plan dinner under 800 kcal" and "I killed it at the gym" pass through. | `AI/Assistant/SafetyPolicy.swift` |
| **17 tools** (F07 §3) | <ul><li>**Reads**, computed exactly from the user's data: today's status, stats (average, total, max, min, compare), presets, budget explanation, food-log search, memory list.</li><li>**Writes**, which become actions the app performs through `IntentRuntime.store()` → `ExperienceStore`: water, weight, add/move/complete todo, log preset, log food (confirmation card), repeating reminder (the automation rule card), create preset, remember, forget.</li></ul> Destructive actions are not exposed. Limit: 4 calls per turn. | `AssistantTools.swift` |
| Commands without a model | Water (glasses, ml, litres, Hinglish "do glass paani"), weight (kg/lb), one-off todos with times, "why is my target higher", "what did I eat last Tuesday", "when did I last have biryani", week-on-week comparison, "what do you know about me". Repeating reminders are left to the existing automations parser. | `CommandRouter` in `AssistantEngine.swift` |
| With a key: tool planning | 1. The model plans tool calls as JSON (`assistantPlan` task). 2. Reads run locally against the user's data. 3. The model phrases an answer from the exact results. 4. Every number is checked against those results: on a failure it regenerates once, then falls back to the template. Writes are never phrased by the model; the card shows what will happen. Streamed chat answers get the same numbers check. | `AssistantEngine.answer`, `GroundingValidator.swift` |
| Conversation | Recent turns are kept word for word within a token budget. Older turns are folded into a summary line without needing a model. | `ConversationLog` |
| **C9 orb state** | `AssistantVisualState` and `AssistantPresence` (main actor, ≤ 30 Hz for mic level and progress; discrete states land immediately) for Design's orb. | `AssistantPresence.swift` |
| UI hooks (UI/UX approved) | <ul><li>`AssistantSession.answer` runs the AI preempt after the snapshot guard.</li><li>`askModel` tries tool planning, then streams with the new context packet, checking numbers.</li><li>New cards: `.confirmMemory` (Remember / Not now) and `.done` (Undo).</li><li>`IntelligenceStore` remember/forget/edit/forget-everything keep the index in sync.</li><li>`AssistantBrain` also asks before saving sensitive "remember …" statements, which covers the Siri path.</li></ul> | Experience files (diff sent to UI/UX) |

## 3. Quality evidence

| Check | Result |
|---|---|
| AI unit tests (`swift test`) | **187 pass**: 64 new across memory, context, sensitive isolation, write batching, meal windows, portion hints, tools, safety, grounding, engine, budget explanation and presence |
| Eval tests | **9 pass**: food text (5, from Phase 0) and assistant/memory/red-team/grounding (4, new) |
| Experience tests | **50 pass** (`swift test --package-path Packages/LifeOSDesign --filter LifeOSExperienceTests`), including the new `sensitiveMemoryAsksFirst` |
| Single budget source | `scripts/check-single-budget.sh` OK |
| Context budget | A property test over 300 random contexts never exceeds the budget. Build time p95 with a year of data and 300 memories: **4.4 ms** (Debug, Mac). It was 52 ms before switching the similarity maths to vDSP and dropping per-call number formatters. |
| Third-party packets | No age or sex, no todo titles, no sensitive or routine memories, numbers rounded (tested on 5 intents and on the gateway path) |
| Sensitive isolation | A confirmed, pinned health memory ("PCOS") and a health turn in the chat history never appear in a Gemini/Groq packet, for every intent, whether built directly or as the device packet the gateway falls back to. Planner and composer prompts are also checked end to end. |
| Meal-type inference | Synthetic personas (late eater, early bird, night shift, typical): fixed clock hours **72%** vs learned windows **100%** (75 cases). The Phase 2 exit bar is +10 points. |
| Tool routing (deterministic) | 90/90 names and 90/90 arguments; zero writes fired for the wrong request |
| Memory extraction | 80 cases: precision 100%, recall 100%; all 8 sensitive statements held for confirmation; 20 negatives (one-offs, body judgments, injection) stayed empty |
| Red team | 81/81. Includes 30 benign controls with **0 false positives**. |
| Grounding | Template answers state only repository numbers. A model answer that invents numbers is rejected, regenerated once, then replaced by the template (tested with a scripted model). |

> ⚠️ **These eval scores are optimistic.** I wrote the tool, memory and red-team sets alongside the rules, and the first run found 6 real bugs, which I fixed. They are regression gates, not held-out measurements. F11's held-out sets are still needed: 400 tool turns, 300 memory conversations, 150 grounding Q&A and a reviewed red-team v2 (§7).

## 4. Phone without Apple Intelligence (iPhone 15)

| Need | What runs |
|---|---|
| Memory extraction | Rules only. The privacy gate never sends `memoryExtract` to Groq/Gemini, by design (F06). |
| Assistant answers | Rule brain (UI/UX) plus AI commands and tools: no model needed for budget, protein, water, workouts, weight, food-log search, todos, memories or the budget explanation |
| Open questions | Gemini (or Groq) with the **health** consent: tool planning, then a grounded answer. Without consent the assistant explains what it needs, as before. |
| Embeddings | `NLEmbedding` (NaturalLanguage, on every iPhone), with a hashing fallback |
| Weekly review, briefing | UI/UX's deterministic versions (unchanged) |

## 5. Decisions (for AI lead review)

1. **Two memory stores, one truth.** The UI's `MemoryItem` JSON stays what the user sees and edits. The AI index holds facets, vectors, expiry and history under the same ids, kept in sync by four hooks. Merging them would have meant rewriting the UI/UX memory screen mid-phase.
2. **Consolidation on the first foreground of the day**, not a BGProcessingTask. The work takes under 10 ms and needs no Info.plist or entitlement change; the engineering session owns the project file.
3. **Tool planning is JSON-mode planning, not provider function-calling.** One `AISchema` works on Gemini, Groq and Apple without provider changes, and all tool code runs locally.
4. **Sensitive facts need a tap**, even when the user says "remember…". Allergies and intolerances are treated as food facts (needed for suggestions), not as sensitive data.
5. **Only what the person typed acts at once.** A command parsed on device (water, weight, todos, preset) executes immediately with Undo, per the F07 table. Anything a cloud model planned waits for a "Log it" tap (`.pendingAction`), including remember, which becomes "Remember this?". Logging food, repeating reminders and forgetting always use confirmation cards. A health fact is converted to "Remember?" by one helper (`AssistantSession.guardSensitive`) on every path: rule brain, AI preempt and cloud model.
6. **The safety replies don't offer "hide calorie numbers"**, because that setting doesn't exist yet (§7).
7. **Prompt registry `2026.10.2` is unchanged**: the new prompts carry their own ids (`assistant.plan`, `assistant.compose`, `budget.explain`, `memory.extract`).

## 6. How to try it on the iPhone

1. Assistant: say or type **"I don't eat oats"** → "Remembered" chip. Then "What do you know about me?"
2. **"I have PCOS"** → "Remember it?" with Remember / Not now. Check the memory screen after each choice.
3. **"I'm vegetarian"**, later **"I eat chicken now"**. The old fact leaves the list, but the AI index keeps it as history.
4. **"Log 2 glasses of water"** → done, with Undo. **"I weigh 72.4"**. **"Remind me to call mom at 6pm"** → a todo with a reminder.
5. **"Why is my target higher today?"** → the engine's breakdown in words.
6. Finish a Watch workout → the banner shows the credit added and the protein still to go.
7. **"I want to eat 600 calories a day"** → a supportive reply with no numbers.
8. With a Gemini key and health questions allowed: **"How did my protein compare to last week?"** → a planned, grounded answer with a chart.
9. Smart Log at an unusual hour (for example lunch at 15:30, if you usually eat then) → the meal is "lunch". "My katori is 120 ml" changes the grams for dal.

## 7. Open items

- [ ] **Device install and UAT** on the iPhone 15 (§6). The app compiles for iOS, but the phone was unavailable at build time.
- [ ] Held-out eval sets (F11): 400 tool turns, 300 memory conversations, 150 grounding Q&A, red-team v2 reviewed by the AI lead, product and ideally a nutrition advisor.
- [ ] A **"hide calorie numbers"** setting (Design and Engineering), then turn on `offerHideNumbers` in safety replies.
- [ ] Wording for adaptive TDEE in the UI once CAL-11/12 land (`MaintenanceSuggestion` is ready).
- [ ] Model-written prose for the daily briefing and weekly review (the deterministic versions ship; a grounded composer would reuse `GroundingValidator`).
- [ ] Phase 2 Watch end-to-end SLA (≤ 15 min locked) is engineering's WCH-04 device check. The AI side reacts within the same run loop as `.healthWorkoutSynced`.
- [ ] Apple Intelligence devices: live first-token latency (≤ 1.2 s target), and T1 memory extraction precision.
