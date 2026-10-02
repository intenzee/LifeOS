# 01 — Current State Audit (AI-relevant)

**Purpose:** give the AI team an accurate picture of what already exists in `LifeOS-main` so we extend it instead of rebuilding it, and list the code issues that block AI work.
**Reviewed:** all Swift sources under `LifeOS/` and `LifeOS Watch App/`, `.planning/codebase/*`, `README.md`, git history to `0156906`.

---

## 1. What already exists (and is worth keeping)

### 1.1 MealVision stack — `LifeOS/Services/MealVision/`

| File | What it does | Verdict |
|---|---|---|
| `MealScannerEngine.swift` | Orchestrator. Learned override → Groq (if key) → on-device fallback. "Never dead-ends." | **Keep.** Becomes the photo pipeline inside F04, called through the Gateway. |
| `GroqMealAnalyzer.swift` | Groq vision client. Prioritised model list with automatic skip of retired models, JSON-mode output, retry/backoff, defensive JSON isolation, natural-language **refine** pass. | **Keep as a T3 provider.** Move model list to remote config. |
| `OnDeviceMealAnalyzer.swift` | Apple Vision `VNClassifyImageRequest` + bundled `NutritionDatabase`. Single best-guess item. | **Keep as T4** last resort. |
| `NutritionDatabase.swift` | ~small bundled table of common foods with per-serving macros. | **Expand** into the Nutrition Resolver (F02) — needs Indian foods and per-100 g data. |
| `MealLearningEngine.swift` + `CorrectionStore.swift` + `ImageSignature.swift` | Learns from user corrections. Perceptual hash + Vision feature-print similarity. Near-duplicate photo → instant answer from memory; similar dishes → few-shot hints injected into prompt. | **Keep.** This is effectively the first slice of the Memory system (F06) — "correction memory". Migrate its store into the unified memory store later. |
| `MealImageProcessor.swift` | Downscale/JPEG-encode for upload size limits. | Keep. |
| `MealAnalysis.swift` | Unified result type + precise `MealScanError` taxonomy with user-facing messages. | Keep; extend with real confidence and per-item portions. |

### 1.2 Key storage
`AIKeyStore` (in `Managers/CalorieSettings.swift`) stores provider keys in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. **Keep**; move into `AI/Gateway/` and support multiple providers (Gemini, Groq).

### 1.3 Calorie model
- `CalorieGoalCalculator` — Mifflin-St Jeor BMR × activity + goal adjustment (−500 lose / +300 gain).
- `CalorieLimitSettings` — auto vs manual target; recomputes on profile change.
- `CalorieSettings` — "calorie bank" percentage (default **50%**) of exercise calories added back to the budget.
- `CalorieCalculator` — MET-based estimate: **2.5 min per set** at a body-part MET, plus treadmill at MET 8.5.
- `HomeViewModel.adjustedCalorieLimit = base + burned × bankPercentage`, where `burned` comes **only from manually logged sets/treadmill**.

### 1.4 Health & Watch
- `HealthManager` reads dietary energy, body mass, sleep, steps and active energy (today only, via statistics queries); writes body mass and a single "workout calories" sample (deleting today's earlier samples first).
- Watch app: `AutoSetTracker` counts reps/sets from CoreMotion (good, heuristic), syncs to phone over WatchConnectivity (`setWater`, `toggleTodo`, `updateExerciseSets`, `addExercise`, …).
- **The Watch target deliberately has no HealthKit entitlement** (to sign on a free developer account), so it runs no `HKWorkoutSession` and Apple Watch workouts are **not** read into LifeOS today.

---

## 2. Gaps vs. the AI vision

| Area | Today | Needed | Feature |
|---|---|---|---|
| Text / voice logging | None — manual forms, barcode, photo only | Natural-language + voice parsing in English/Hinglish | F02 |
| Presets | `recentFoods` (20), `favoriteFoods`, `customFoods` (50) — single items, no combos, no aliases | Named multi-item presets with aliases, voice triggers, AI suggestions | F03 |
| Photo | Groq BYOK or single-label on-device guess; confidence hard-coded `0.9` for Groq | Apple on-device/PCC vision first; per-item portions; calibrated confidence; label OCR | F04 |
| General LLM | None | Gateway with tiered providers | F01 |
| Context | None — each scan is stateless except correction hints | Context packets built from profile, today, trends, memory | F05 |
| Memory | Only meal-photo corrections | Facts, preferences, episodes, routines; user-controllable | F06 |
| Assistant | None | Chat + voice with tool calling | F07 |
| Watch workouts → calories | Not read; budget uses manual MET estimates only | HealthKit workout feed + reconciliation + adaptive budget | F08 |
| Automation | Todo reminders only (`NotificationService`) | Context-aware nudges, routines, background processing | F09 |
| Siri / Shortcuts | None (no App Intents) | App Intents, App Shortcuts, Watch voice | F10 |
| Evals / tests | **Zero tests in the project** | Golden sets, CI gates, red-team | F11 |

---

## 3. Code issues that block or endanger AI work

These are owned by **iOS Core** unless stated, but the AI team must track them because our features depend on them.

| # | Issue | Evidence | Why it matters for AI | Owner / ask |
|---|---|---|---|---|
| B1 | **All data in `UserDefaults` as JSON blobs** | `PersistenceManager`, `FoodDatabaseManager.allDailyLogs`, `WorkoutDatabaseManager.allDailyWorkouts` | No queries, no history ranges, slow launches as data grows; memory/trends impossible at scale | iOS Core: SwiftData migration (contracts §2) — **blocking for Phase 2** |
| B2 | **Workout history only addressable by weekday name of the current week** | `WorkoutDatabaseManager.dayToDateKey(_:)` maps "Monday"… to *this week's* date; `selectDate` converts a date to a day name, so browsing a past week shows the current week; `checkWeeklyReset` deletes last Sunday | Trend, memory and adaptive-TDEE features need true date-keyed history | iOS Core — fix in the same migration |
| B3 | Duplicate stores (`weekFoodLog` vs `allDailyFoodLogs`, `weekGymLog` vs `allDailyWorkouts`) | `.planning/codebase/CONCERNS.md` | The Context Engine needs one source of truth | iOS Core |
| B4 | `@Published` mutation off the main actor at launch (known crash) | CONCERNS.md "Known Bugs" | AI background tasks will add more concurrency; must be fixed first | iOS Core |
| B5 | Seven `.onChange` handlers trigger `syncStreaks()` | `HomeView.swift` | AI auto-logging will fire many changes; needs a debounced domain-event bus instead | iOS Core (event bus, contracts §2.3) |
| B6 | `HealthManager` uses completion handlers and writes one aggregated "workout calories" sample, deleting earlier ones | `saveWorkoutCalories` | Will fight with real Watch workouts; must stop writing synthetic energy once real workouts are read | Health team + AI (F08) |
| B7 | Health data stored unencrypted in plist | CONCERNS.md security | Memory will hold more sensitive data | iOS Core: file protection on the store; AI: memory store encryption (F06) |
| B8 | `GroqMealAnalyzer.candidateModels` are preview models on Groq | Groq model list shows the Qwen vision models as *preview* | Can be removed at short notice | AI: remote-config the list (F01) |
| B9 | No test target exists | CONCERNS.md, `TESTING.md` | Evals need a test target | AI + iOS Core create `LifeOSTests` + `LifeOSAIEvals` targets in Phase 0 |
| B10 | Logging via `print()` with emojis | Conventions doc | Can leak PII to device logs; not filterable | AI uses `Logger(subsystem:category:)` with privacy annotations from day one |

---

## 4. Things to preserve in the user experience

- The **"always logs something"** promise of the scanner.
- The **natural-language refine** ("it's egg fried rice, I added 4 eggs") — users love correcting in words; extend this pattern everywhere (F02, F04, F07).
- The **Learned Corrections** screen (`LearnedCorrectionsView`) — the seed of the user-facing Memory screen (F06).
- Clear **source badges** ("AI · full macros", "On-device", "Learned") in `MealResultView` — generalise to every AI output.
