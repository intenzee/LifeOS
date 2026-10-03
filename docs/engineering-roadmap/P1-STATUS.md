# Phase 1 — Health & Energy: status

> Started 3 Oct 2026. Owner: Health & Watch (Platform). Tickets are defined in `02-apple-watch-auto-logging.md` (WCH) and `03-adaptive-calorie-engine.md` (CAL). UI-01…06 belong to UI Engineering and the UI/UX plan.

**Goal:** Apple Watch exercise logs itself, and the calorie budget updates automatically, from one formula everywhere.

## How it fits together

```
Apple Health ──► HealthIngestionService (LifeOSHealth, actor)
                   anchored workouts + daily statistics
                   │ writes WorkoutSession, EnergyDay (HK fields), HealthSyncState
                   ▼
                 LifeOSData store ──ChangeBus──► BudgetService (LifeOSData, actor)
                                                   re-merges gym log ↔ Watch workout (WCH-06)
                                                   CalorieEngine → EnergyDay.budgetKcal
                   ▼
                 HealthSync (app, @MainActor) ──► Home ring, Watch snapshot, streaks,
                                                  Settings, Experience screens (UI/UX)
```

- **One number.** Every consumer reads `HealthSync.budget(on:)`, which is `EnergyDay.budgetKcal`. `scripts/check-single-budget.sh` (CI) fails if app code re-adds `limit + burned × eat-back`.
- **Energy comes from HealthKit statistics** (sources merged by HealthKit), never from summing workouts. Watch-only active energy is a second statistics query filtered by device model, and it decides measured vs estimated mode.
- **The merge is derived.** It's recomputed for the whole day on every change, so deleting or editing a workout in Health un-merges cleanly.
- **Past days freeze** once they're 36 h old and a sync has completed since. Late HealthKit data can unfreeze a day once.

## Verify

```bash
./scripts/test-packages.sh            # 144 tests
./scripts/check-single-budget.sh
```

**On device (iPhone 15 + Watch Series 9, 3 Oct):** the first sync imported 39 Watch workouts and 28 days of energy. Today's active energy matched the Watch-only figure. Home shows the engine budget and the Watch's measured burn. The build has the `healthkit.background-delivery` entitlement (the team profile grants it).

## Tickets

✅ done · 🟡 done, device check pending · ⏳ not started

### P1-A · Ingestion core
| ID | Status | Notes |
|---|---|---|
| WCH-01 `HealthIngestionService` | ✅ | `LifeOSHealth` target. `HealthStoreClient` protocol with value types; `FakeHealthStore` in tests. Anchors in `HealthSyncState`. |
| WCH-02 Anchored workout sync | ✅ | Upsert by `healthKitUUID`, deletions via a UUID→day index, edits that move day, own source excluded, first sync limited to 28 days. Verified on device. |
| WCH-03 Daily energy statistics | ✅ | Active, basal, Watch-only active, steps. "No data" stays `nil`, not 0. |
| WCH-04 Observers + background delivery | 🟡 | Entitlement added. Observers registered in `didFinishLaunching` (`LifeOSAppDelegate`). The completion handler is called once, at the latest after 25 s. **Open:** confirm a background wake on device (record a workout with the app closed). |
| WCH-05 Multi-trigger sync | ✅ | Launch, foreground, observer, pull-to-refresh on Home, watch `workoutEnded` mutation, and after authorization. Concurrent calls coalesce into one run plus at most one follow-up (tested). |
| WCH-06 Workout ↔ manual merge | ✅ | `WorkoutMerge` (Core): overlap rules, two-candidate refusal, set-time windows, dedupe of duplicate recordings, measured beats MET. Legacy logs have no set times, so they merge only when one strength/HIIT workout exists that day. |
| WCH-07 Replace C3 write path | ✅ | `saveWorkoutCalories` / `deleteTodaysWorkoutSamples` and the flag deleted. Active energy is no longer requested for write. `healthKitWorkoutWrite` flag reserved for the optional `HKWorkoutBuilder` write (⏳). |
| WCH-08 Food and water write-back | 🟡 | `HealthWriteBackService` (LifeOSHealth) listens to food/water store changes, so every way of logging is covered. Each entry is an `HKCorrelation(.food)` (energy + non-zero macros, food name). Water is written as increments, so Health shows when it was drunk. Edits and deletes are mirrored for 30 days. **Instead of `syncedToHealthKit` on `FoodEntry`**, a ledger (`HealthWriteState`, `documents/healthWrites.json`) maps entry → write id, so the food schema the AI team owns is unchanged. Write ids derive from the content, and every save deletes its id first, so a retry never duplicates. Passes are serialised. Off by default: the Settings toggle "Save food & water to Apple Health" asks for permission and writes from that day on (no backfill). Imported (`.healthKit`) entries are never written back. 14 tests. **Open:** a device check (toggle on, log/edit/delete, look in Health › Nutrition). |

### P1-B · Experience
| ID | Status | Notes |
|---|---|---|
| WCH-09 Train feed with source badges | 🟡 | `HealthWorkoutsCard` on Home: icon, type, duration, kcal, distance, avg HR, badge (Apple Watch / app name / Estimated), and a detail sheet. History view and the Experience Training screen are UI/UX's (they read `HealthSync.todaySessions`). |
| WCH-10 "Workout synced" moment | 🟡 | `.healthWorkoutSynced` notification → toast + success haptic + VoiceOver announcement. Reduce Motion respected. Budget ring animation is UI/UX's. |
| WCH-11 Health permission states | 🟡 | `HealthSync.status`: unavailable / notDetermined / connected / likelyDenied (7 synced days with no energy). `HealthStatusBanner`. UI tests pending (QA-01 app test target). |

### P1-C · Watch app v2
| ID | Status | Notes |
|---|---|---|
| WCH-12 Watch HealthKit + `HKWorkoutSession` | 🟡 | `StrengthWorkoutSession`: strength session + live builder (HR, kcal, timer), crash recovery, saves an `HKWorkout`, then sends `workoutEnded` so the phone syncs now. Watch entitlement + `WKBackgroundModes: workout-processing` (watch `Info.plist`). The team profile signs it: verified build, installed on the Watch. **Open:** run one session on the wrist. |
| WCH-13 `AutoSetTracker` in the session | 🟡 | The session keeps the app running wrist-down, so the existing tracker keeps counting. Manual "Log Set" kept. **Open:** the 60-min battery measurement (target ≤ 12%). |
| WCH-14 Sets attached and merged | 🟡 | Every new set becomes an `HKWorkoutEvent` marker (exercise, set number) and still goes to the phone as `setExerciseSets`. The phone merges the log into the Watch workout (WCH-06). Using the markers as the merge window is a follow-up. |
| WCH-15 Complications / Smart Stack | ⏳ | Needs a watchOS widget extension and an App Group. Paused to share the App Group with UI/UX Phase 5's widget target. |
| WCH-16 Typed snapshot v2 | ✅ | Optional `budgetMode`, `activeKcal`, `earnedKcal`, `workoutsToday` (plus UI/UX's `proteinG`, `proteinTargetG`, `presets`, and `logPreset`). No schema bump: an older watch decodes it unchanged. New mutation `workoutEnded(day:)`. |

### Calorie engine v1
| ID | Status | Notes |
|---|---|---|
| CAL-01 Engine | ✅ | Doc 03 §6 test vectors A–E added as tests. Formula v2 (P1-D1). |
| CAL-02 `BudgetService` + `EnergyDay.budgetKcal` | ✅ | Debounced; recomputes on energy, sessions, gym log, profile and settings changes; freeze rule. Mode: measured when ≥ 3 of 7 days have Watch energy. |
| CAL-03 Remove duplicate formulas | ✅ | `HomeViewModel.adjustedCalorieLimit` and the watch snapshot read `HealthSync`. CI grep check. |
| CAL-04 Allowance personalisation | ✅ | Median active kcal on workout-free days (≥ 14 days of history, ≥ 5 rest days in 28), clamped. Runs once a day on the first sync. Moves to a BG task with doc 06. |
| CAL-05 Settings | ✅ | "Exercise & Budget" card: Adds exercise / Fixed, eat-back 0–100% in 10% steps, cap 300–1,500. Legacy keys migrate once and stay readable for rollback. |
| CAL-06 Macro targets v1 | ✅ (engine) | `MacroConfig`: protein g/kg by goal, diet-type split of the rest, fibre. **Defaults are placeholders pending nutrition sign-off** (doc 03 §7 Q2). Not yet shown in the UI. |
| CAL-07 Breakdown contract | ✅ | `HealthSync.todayBreakdown`. |
| CAL-08 Streaks use per-day budgets | 🟡 | Today's summary records `HealthSync.budget(on: today)`. Moving summaries fully onto `SummaryService` waits for FND-08/FND-12. |

## Decisions taken

| # | Decision | Record |
|---|---|---|
| P1-D1 | **The floor applies to the baseline, then exercise credit is added:** `max(floor, baseline) + credit`. Formula v2. Before this, an aggressive goal put the baseline under the floor and workouts never moved the budget (an 876 kcal Watch day showed 1,500 on the owner's phone). | Product owner, 3 Oct. Doc 03 §3.1 updated. Days frozen under v1 keep their stored budget. |

## Decisions needed

| # | Question | Why it matters now |
|---|---|---|
| P1-D2 | Eat-back default for Watch energy: 50% or 30% (doc 03 §7 Q1) | Wrist energy runs high |
| P1-D3 | Do imported non-gym workouts count toward the gym streak? (doc 02 §7 Q2) | Today only logged sets do |

## Cross-team contracts (new)

| Contract | Consumers | Notes |
|---|---|---|
| `HealthSync.budget(on:)`, `.todayBreakdown`, `.todaySessions`, `.status`, `.exerciseKcal(on:)` | UI/UX Experience (TrainingScreen, BudgetExplainerSheet, ExperienceStore) | Replace `BudgetMath` / `HealthManager.activeEnergyToday` / `loadPercentage()`. The CAL-03 check will flag the old formula. |
| `EnergyDay`, `WorkoutSession` (LifeOSCore) | Assistant tools (doc 05), automation (doc 06) | `budgetKcal` is final per day; `formulaVersion` is stored with it. |
| `WatchSnapshot.workoutsToday` / `WatchMutation.workoutEnded` | Watch app v2 | Optional fields, schema v2. |
