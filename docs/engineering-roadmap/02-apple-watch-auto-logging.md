# 02 — Apple Watch Auto-Logging & HealthKit Sync

> **Squad:** Health & Watch · **Phase:** P1 · **Depends on:** 01 (schema, `dayKey`, `SyncAnchor`, typed watch contract) · **Feeds:** 03 (calorie engine), 05 (assistant context), 06 (automation triggers)

---

## 1. Goal

**Any exercise the user does with an Apple Watch shows up in LifeOS automatically, and the calorie budget updates.** No manual entry. It doesn't matter whether the workout was recorded by Apple's Workout app, a third-party app, or our own watch app.

### User stories
- *As a user,* when I finish a run in Apple's Workout app, I open LifeOS and see "Outdoor Run · 5.2 km · 410 kcal · from Apple Watch" in today's Train feed, and my calories-remaining has gone up.
- *As a user,* I never have to log exercise twice. If I also tapped sets in LifeOS during the same gym session, they merge into one session.
- *As a user,* all-day movement (walking, stairs) also counts, not only formal workouts.
- *As a user,* I can see where every number came from ("Apple Watch", "iPhone", "estimated").

---

## 2. Current state

| Item | Today | Gap |
|---|---|---|
| Workouts | Manual sets per body part. Calories from MET × 2.5 min/set (`CalorieCalculator`). | Ignores Apple Watch entirely |
| HealthKit reads | Dietary energy, body mass, sleep, steps, active energy (statistics queries on demand) | No `HKWorkout`, no basal energy, no heart rate, no anchored/incremental sync, no background delivery |
| HealthKit writes | Body mass. Estimated active energy (after deleting today's samples — bug C3). | Pollutes Health and fails against Watch-owned samples |
| Watch app | Snapshot dashboard, water, todos, weight, rest timer, **motion rep counter** (`AutoSetTracker`). Deliberately *no* HealthKit entitlement. | Screen-off tracking, heart rate, real workout records and complications are all missing |
| Entitlements | iPhone: `com.apple.developer.healthkit`. Watch: none. | Background delivery entitlement missing |

---

## 3. Design

### 3.1 Data we ingest from HealthKit

| HK type | Use | Query |
|---|---|---|
| `HKWorkoutType.workoutType()` | Workout sessions (type, start/end, energy, distance, source) | `HKAnchoredObjectQuery` + observer |
| `.activeEnergyBurned` | All-day active energy (Watch + iPhone) | Daily `HKStatisticsCollectionQuery` (cumulative sum, **merged across sources by HealthKit**) |
| `.basalEnergyBurned` | Measured resting energy (Watch only) | Daily statistics collection |
| `.heartRate` (optional) | Workout avg/max HR for detail view and AI context | Statistics per workout interval |
| `.stepCount`, `.distanceWalkingRunning` | Movement context | Daily statistics collection |
| `.bodyMass` | Weight trend (doc 03 v2) | Anchored |
| `.sleepAnalysis` | Sleep context (doc 05) | Anchored |
| `.dietaryEnergyConsumed` etc. | **Read only to detect other apps' food logs.** Never double-add to our own food totals. | Anchored, excluding our own source |

> **Important:** use `HKStatisticsQuery`/`HKStatisticsCollectionQuery` with `.cumulativeSum` for energy. HealthKit de-duplicates overlapping iPhone and Watch samples in statistics queries. Summing raw samples yourself double counts.

### 3.2 Ingestion pipeline

```mermaid
sequenceDiagram
    participant HK as HealthKit
    participant OBS as HKObserverQuery (per type)
    participant ING as HealthIngestionService (actor)
    participant DB as LifeOSData store
    participant CE as CalorieEngine
    participant UI as UI / Widgets / Watch

    Note over OBS: registered at launch +<br/>enableBackgroundDelivery
    HK-->>OBS: new samples (foreground or background wake)
    OBS->>ING: sync(type)
    ING->>HK: HKAnchoredObjectQuery(since: stored anchor)
    HK-->>ING: added + deleted objects, new anchor
    ING->>DB: upsert WorkoutSession by healthKitUUID, delete removed
    ING->>HK: statistics collection for affected days (active, basal)
    ING->>DB: upsert EnergyDay(dayKey)
    ING->>DB: save new anchor (SyncAnchor)
    ING-->>OBS: completionHandler()  // MUST be called, or iOS stops waking us
    DB-->>CE: change notification
    CE->>DB: recompute budget for affected dayKeys
    CE-->>UI: publish; reload widgets; push watch snapshot
```

Triggers for `sync()` (belt and braces, since background delivery is best-effort):
1. `HKObserverQuery` with `enableBackgroundDelivery(for:frequency:)`: `.immediate` for workouts, `.hourly` for energy and steps.
2. App foreground (`scenePhase == .active`).
3. `BGAppRefreshTask` (doc 06).
4. Pull-to-refresh on Home/Train.
5. A watch "workout ended" message from our own watch app.

### 3.3 Workout ↔ manual-set merge rules
A manual/LifeOS gym log and a Watch "Traditional Strength Training" workout often describe the **same session**.

```
for each incoming HK workout W:
    candidates = local WorkoutSessions on same dayKey
                 where source in {manual, lifeosWatch}
                 and timeOverlap(W, s) ≥ 50% of the shorter one
                 (manual sessions without times: use first/last SetLog.completedAt ± 15 min)
    if exactly one candidate C and activity kinds are compatible:
        C.healthKitUUID = W.uuid
        C.start/end = W.start/end
        C.activeEnergyKcal = W energy  // measured beats estimated
        C.source = .watch (keep exercises/sets from C)
    else:
        insert new WorkoutSession from W
```
- **Energy precedence:** measured Watch energy > other-app HK energy > LifeOS MET estimate. The MET estimate is only used when no measured data overlaps the session.
- **Deletions:** if HK reports a workout deleted (anchored query `deletedObjects`), remove or unlink it locally.

### 3.4 What we write back to HealthKit (replacing C3)
| Data | Write? | How |
|---|---|---|
| Body weight | Yes (already) | `HKQuantitySample` |
| Food (per entry) | **Yes, new** | `HKCorrelation` `.food` with dietary energy and macros. Store `syncedToHealthKit`. Delete or update our own samples on edit. |
| Water | Yes, new | `.dietaryWater` |
| Strength sessions logged only in LifeOS (no Watch workout overlapping) | Optional, flag | A proper `HKWorkout` via `HKWorkoutBuilder` with estimated energy, marked in metadata `LifeOSEstimated = true` |
| Bare estimated active-energy samples | **No, never** | Removed (they double count in Activity rings) |

When reading, **always exclude our own source** for types we also write, so we never re-import our own data.

### 3.5 Our own watch app v2

Today the watch app avoids HealthKit so it signs on a free account. With decision **D5 = yes**:
- Add the HealthKit entitlement to the watch target, plus the **Workout processing** background mode.
- Start an `HKWorkoutSession` + `HKLiveWorkoutBuilder` when the user taps *Start* on the watch. This gives:
  - screen-off and background running, so `AutoSetTracker` keeps counting reps with the wrist down
  - live heart rate and active energy on the wrist
  - a real `HKWorkout` saved at the end, which then flows through §3.2 like any other workout (single code path)
- Exercises and sets from `AutoSetTracker` are attached as workout events/metadata **and** sent to the phone over the typed contract (FND-11) so they merge (§3.3).
- Complications / WidgetKit on watchOS: calories remaining, water, streak.
- Smart Stack relevance: show the "Start workout" widget around the user's usual training time (learned in doc 06).

### 3.6 Permissions UX
- Ask for HealthKit **in context**: on the onboarding "Connect Apple Health" step and again when the user opens Train without access. Never at cold launch.
- HealthKit doesn't reveal *read* authorization. Detect "probably denied" when queries keep returning empty data for 7 days while the user has a paired watch. Show a gentle "Not seeing your workouts?" card with a deep link to Settings → Health.
- The app already derives write status correctly (`refreshAuthorizationStatus()`), so keep it.

---

## 4. Tickets

### P1-A · Ingestion core
| ID | Title | Size | Acceptance criteria |
|---|---|---|---|
| WCH-01 | `HealthIngestionService` actor in `LifeOSHealth` | M | Async API: `start()`, `sync(_ type:)`, `syncAll()`. Anchors persisted in `SyncAnchor`. Unit-tested with an `HKHealthStore` protocol fake. |
| WCH-02 | Anchored workout sync | M | New, edited and deleted `HKWorkout`s are reflected in `WorkoutSession` within one sync. Dedupe by `healthKitUUID`. Our own source excluded. |
| WCH-03 | Daily energy statistics | M | `EnergyDay(dayKey)` holds active and basal kcal from `HKStatisticsCollectionQuery` (merged sources). Recomputed for every day touched by new samples. |
| WCH-04 | Observer queries + background delivery | M | Entitlement `com.apple.developer.healthkit.background-delivery` added. Observers registered at launch (inside `application(_:didFinishLaunching…)` equivalent, before the UI). `completionHandler` is always called (also on error/timeout ≤ 25 s). |
| WCH-05 | Multi-trigger sync scheduling | S | Foreground, BG refresh, pull-to-refresh and watch-message triggers all call `syncAll()`, coalesced (no concurrent duplicate syncs). |
| WCH-06 | Workout ↔ manual merge | M | Rules in §3.3. Unit tests for overlap, no overlap, two candidates, deletion and time-less manual logs. |
| WCH-07 | Replace C3 write path | S | Estimated active-energy writes are removed. Optional `HKWorkoutBuilder` write for LifeOS-only strength sessions, behind a flag. |
| WCH-08 | Food and water write-back | M | Each `FoodEntry` is written as an `HKCorrelation(.food)`. Edits and deletes are mirrored. Water is written as `.dietaryWater`. Setting toggle "Save food to Apple Health". |

### P1-B · Experience
| ID | Title | Size | Acceptance criteria |
|---|---|---|---|
| WCH-09 | Train feed with source badges | M | Today and history show imported workouts with icon, type, duration, kcal, avg HR and a source badge (Apple Watch / iPhone / app name / Estimated). Tapping opens the detail view. |
| WCH-10 | "Workout synced" moment | S | When a new Watch workout arrives in the foreground: haptic, toast "Run · +205 kcal added to today", and an animated budget-ring update (motion spec from doc 08). |
| WCH-11 | Health permission states | S | §3.6. All four states covered by UI tests (not determined / granted / likely denied / unavailable on iPad). |

### P1-C · Watch app v2 (requires D5)
| ID | Title | Size | Acceptance criteria |
|---|---|---|---|
| WCH-12 | Watch HealthKit + `HKWorkoutSession` | L | Workout runs with the screen off. Live HR and kcal shown. The session saves an `HKWorkout` that appears on the phone through WCH-02. |
| WCH-13 | `AutoSetTracker` inside the session | M | Rep counting continues in the background. Battery cost of a 60 min session ≤ 12% on Series 8 (measure). Manual "Log Set" fallback kept. |
| WCH-14 | Sets attached and merged | S | Sets recorded on the watch appear under the matching phone session after merge (WCH-06). |
| WCH-15 | Complications / Smart Stack widgets | M | Calories remaining, water, streak. Timeline reloads after each snapshot. Relevance hints for the training window. |
| WCH-16 | Typed snapshot v2 | S | Snapshot adds `budget`, `activeKcal`, `workoutsToday`, `schemaVersion`. The watch handles an unknown future version gracefully. |

---

## 5. Edge cases

| Case | Expected behaviour |
|---|---|
| User has no Apple Watch | Active energy comes from iPhone motion (lower). The engine (doc 03) falls back to the activity-factor model. The app says so. |
| Workout spans midnight | Assign it to the `dayKey` of the **start** time. Energy statistics are split by HealthKit naturally per day. |
| User edits or deletes a workout in Health | Anchored query delivers the deletion, so remove it locally and recompute the budget |
| Duplicate workouts from two apps (e.g. Strava + Apple) | Keep both in the feed, but energy comes from daily `activeEnergyBurned` statistics (already de-duplicated by HK), **not** by summing workouts. See doc 03. |
| Background delivery never fires | Foreground sync covers it. The "last synced" timestamp is visible in Settings → Health. |
| Time-zone travel | `dayKey` from the sample's start date in the *current* calendar. Documented limitation for retroactive changes. |

---

## 6. Test plan (summary — details in doc 10)
- Unit: the merge rules, anchor persistence, and the dedupe logic with fake stores.
- Integration: a simulator script writes synthetic `HKWorkout`s and energy samples through a debug-only "Health fixtures" screen, then asserts store contents.
- Device: a real Apple Watch run, strength session and walk. Compare against the Fitness app totals (±1%).
- Battery: 60-minute watch session on two hardware generations.

---

## 7. Open questions
1. D5 — approve the watch HealthKit entitlement (paid developer account)?
2. Should imported non-gym workouts (cycling, yoga) count toward the existing "gym streak", or get a new "move streak"?
