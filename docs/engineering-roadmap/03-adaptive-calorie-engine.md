# 03 — Adaptive Calorie Engine

> **Squad:** Health & Watch · **Phases:** v1 in P1, v2 (adaptive TDEE) in P3 · **Depends on:** 01 (`EnergyDay`, `dayKey`), 02 (measured energy) · **Feeds:** Home ring, Watch, widgets, streaks, assistant

---

## 1. Goal

One engine, one formula and one number. The daily calorie budget is the same on Home, the Watch, widgets, streaks and the assistant. It updates automatically from Apple Watch data, and every user can see exactly why it is what it is.

---

## 2. Current state & problems

```text
HomeViewModel.adjustedCalorieLimit
  = CalorieLimitSettings.loadLimit()                  // TDEE(activityFactor) + goal-gap adjustment, floored
  + WorkoutDatabaseManager.getTotalCaloriesBurned()   // MET × 2.5 min per set (+ treadmill)
    × CalorieSettings.loadPercentage()                // eat-back %, default 0.5
```
The same formula is **duplicated** in `WatchConnectivityManager.makeSnapshot()`.

| Problem | Why it's wrong |
|---|---|
| Activity factor + exercise credit (C4) | `activityFactor` (1.375–1.725 for people who exercise) already includes exercise. Adding workout calories on top double counts. |
| MET × 2.5 min/set | Ignores rest time, load and intensity. Real Watch data is ignored. |
| Formula duplicated in 2 places | Drift risk. The Watch and phone can disagree. |
| Budget not stored per day | `DailySummary.calorieLimit` is a snapshot at the last `recordToday`. Past days can't be re-explained. |
| `CalorieLimitSettings` manual vs auto | Good idea. Keep it, but it should live inside the engine. |

---

## 3. Engine v1 (P1)

### 3.1 Modes
| Mode | When | Baseline | Exercise credit |
|---|---|---|---|
| **Measured** (default if Watch data exists) | ≥ 3 of the last 7 days have `activeEnergyBurned` statistics from a Watch | `BMR × 1.2 + goalAdj` | `eatBack × clamp(activeKcal − allowance, 0, cap)` |
| **Estimated** | No Watch / no Health access | `BMR × 1.2 + goalAdj` | `eatBack × MET estimate of logged sessions` (existing `CalorieCalculator`) |
| **Fixed** | User opts out of dynamic budgets, or set a manual target | `TDEE(activityFactor) + goalAdj`, or the manual number | none |

Where:
- `BMR` = Mifflin-St Jeor from the profile (existing `CalorieGoalCalculator.bmr`).
- `goalAdj` = existing `CalorieGoalCalculator.weightGoalAdjustment` (goal-gap / 10 weeks, safe-rate clamped).
- `1.2` = the sedentary multiplier. Everyday non-exercise activity is "pre-paid" in the baseline, which removes the C4 double count.
- `allowance` = the active energy the user burns on a normal *non-workout* day. That's already covered by the 1.2 baseline.
  - Default: `BMR × 0.2`.
  - Personalised after 14 days: median `activeKcal` across days with no workout session, clamped to `[BMR×0.1, BMR×0.35]`.
- `eatBack` = existing `CalorieSettings` percentage (default 0.5). It's user-adjustable 0–100% in 10% steps.
- `cap` = 1,000 kcal/day by default (protects against over-estimated Watch energy and runaway eating-back).
- Final: `budget = max(floor, baseline + credit)`, where `floor` = 1,200 (female) / 1,500 (male/other), the same as the existing `CalorieGoalCalculator`.

### 3.2 Pseudocode (in `LifeOSCore`, pure and fully unit-tested)

```swift
public struct EnergyInputs: Sendable {
    public var profile: ProfileSnapshot          // age, sex, height, current/target weight, activityFactor
    public var mode: BudgetMode                  // .measured, .estimated, .fixed(manual: Double?)
    public var activeKcal: Double?               // HK statistics for dayKey (merged sources)
    public var estimatedSessionKcal: Double      // MET estimate of LifeOS-only sessions
    public var allowanceOverride: Double?        // personalised non-workout baseline
    public var eatBack: Double                   // 0…1
    public var cap: Double                       // default 1000
}

public struct BudgetBreakdown: Sendable, Equatable {
    public var bmr, baseline, goalAdjustment, allowance, rawActive, credit, floor, budget: Double
    public var mode: BudgetMode
    public var formulaVersion: Int               // bump on any change; stored in EnergyDay
}

public enum CalorieEngine {
    public static func budget(for i: EnergyInputs) -> BudgetBreakdown { ... }
}
```

### 3.3 Where it runs
- `BudgetService` (`@MainActor`, in `LifeOSData`) observes `EnergyDay` and profile changes, calls `CalorieEngine.budget`, and stores `budgetKcal` + `formulaVersion` in `EnergyDay(dayKey)`.
- **All consumers read `EnergyDay.budgetKcal`.** That includes Home, Watch snapshot, widgets, `SummaryService`/streaks and assistant tools. Delete `adjustedCalorieLimit` and the duplicate in `makeSnapshot()`.
- **Past days are frozen** once the day is ≥ 36 h old and the last sync completed. Late HealthKit data can unfreeze a day once (logged).

### 3.4 Macro targets
Today the split is a fixed 30/40/30 % of calories. v1 changes:
- **Protein anchored to body weight** (g/kg, configurable per goal, defaults set by product/nutrition advisor). The rest is split by diet type (`DietType` already exists, e.g. keto changes the carb/fat split).
- Targets scale with the day's budget, except protein, which stays constant.
- Fibre target added (needs `fiberG` on `FoodEntry`, doc 01).

> Default g/kg values and diet-type splits are **product/nutrition decisions**. Engineering exposes them as config, not hard-coded constants.

### 3.5 "Why this number?" breakdown (UI contract)
`BudgetBreakdown` drives a waterfall sheet:
```
BMR (Mifflin-St Jeor)              1,650
Everyday activity (×1.2)            +330
Goal: lose 0.5 kg/week              −550
Apple Watch active 780 − 330 base
  × 50% eat-back                    +225
───────────────────────────────────────
Today's budget                     1,655   ← floor 1,500 not hit
```
This replaces and extends the existing `CalorieGoalCalculator.explanation(profile:)` string.

---

## 4. Engine v2 — Adaptive TDEE (P3)

**Idea:** after enough data, estimate the user's real expenditure from what they ate and how their weight actually moved. Formulas get it wrong for 10–20% of people, and the adaptive estimate corrects for that.

### 4.1 Method
1. **Trend weight:** an exponentially smoothed weight series (α ≈ 0.1/day) over `WeightEntry` and HK body mass, so daily water noise is ignored.
2. **Window:** last 21–28 days. Each day must have intake logged (≥ 60% of the budget, or flagged complete by the user). The window needs ≥ 80% qualifying days.
3. **Estimate:** `TDEE_obs = mean(intake) − (Δtrend_kg × 7700 / days)`.
4. **Blend:** `TDEE_used = w × TDEE_obs + (1 − w) × TDEE_formula`, where `w` grows with data quality (0 → 0.8).
5. **Rate limit:** the budget may change by at most ±100 kcal per week. Changes are announced: "Your budget adapted: +80 kcal. You're losing slower than planned."
6. **Plug-in:** in Measured mode, v2 replaces `BMR × 1.2` with `TDEE_used − typical_active_credit`, so Watch credit still works on top without double counting.

### 4.2 Guardrails
- Never below `floor`. Never applies if fewer than 14 days are logged.
- Pause adaptation for illness, travel or "didn't log properly" weeks (user toggle, and automatic when logging coverage drops).
- Show the confidence and the data used. Allow "reset to formula".

---

## 5. Tickets

### P1 — Engine v1
| ID | Title | Size | Acceptance criteria |
|---|---|---|---|
| CAL-01 | `CalorieEngine` pure module | M | §3.1–3.2 in `LifeOSCore`. 100% branch coverage. Table-driven tests for all modes, the floor, the cap, eat-back 0/50/100%, and allowance personalisation. |
| CAL-02 | `BudgetService` + `EnergyDay.budgetKcal` | M | A single source of truth. Recompute on energy, profile, setting or day-rollover changes. Debounced. |
| CAL-03 | Remove duplicate formulas | S | `HomeViewModel.adjustedCalorieLimit` and the snapshot formula are deleted. All consumers read `EnergyDay`. A grep check in CI for `loadPercentage()` outside the engine. |
| CAL-04 | Allowance personalisation job | S | Nightly (BG task, doc 06) computes the median non-workout active kcal. Stored in profile settings. Unit-tested. |
| CAL-05 | Settings: mode, eat-back %, cap | S | Settings UI. Changes recompute today immediately and never rewrite frozen days. |
| CAL-06 | Macro targets v1 | M | §3.4. Config-driven. Unit tests per diet type. |
| CAL-07 | Breakdown sheet data contract | S | `BudgetBreakdown` exposed to UI. UI implementation in doc 08 (UI-14). |
| CAL-08 | Streaks use frozen per-day budgets | S | `DailySummary.hitCalorieGoal` uses `EnergyDay.budgetKcal` of that day |

### P3 — Engine v2
| ID | Title | Size | Acceptance criteria |
|---|---|---|---|
| CAL-10 | Trend-weight series | M | EWMA over manual + HK weights, handling gaps. Exposed to Trends and the assistant. |
| CAL-11 | Adaptive TDEE estimator | L | §4.1. Validated on 3 synthetic personas (accurate logger, under-logger, water-weight noise) with expected outputs. |
| CAL-12 | Adaptation UX + guardrails | M | §4.2. Notification and in-app card on change, pause toggle, reset. |
| CAL-13 | Engine telemetry (local) | S | Formula version, mode and data quality per day are logged for debugging (on-device only) |

---

## 6. Test vectors (must pass)

| Persona | Inputs | Expected |
|---|---|---|
| A: male, 30 y, 180 cm, 80 kg → 75 kg, Measured, active 780, eatBack 0.5, allowance default | BMR = 10·80 + 6.25·180 − 5·30 + 5 = **1,780** · baseline 2,136 · goalAdj = clamp(−5/10 = −0.5 kg/wk) → −550 · allowance 356 · credit 0.5·(780−356) = 212 | **≈ 1,798** |
| B: same, rest day, active 300 | credit 0 | **1,586** |
| C: same, 2,600 active (marathon) | credit capped at 0.5·min(2,244, 1,000) = 500 | **2,086** |
| D: female, 1,250 computed, Measured | floor | **1,200** |
| E: Fixed mode, manual 2,000 | — | **2,000**, no credit |

(Round as the engine does. Write these as XCTest/Swift Testing cases.)

---

## 7. Open questions
1. Default eat-back: keep 50% (current default) or lower to 30% for Watch-measured energy, given wrist-based over-estimation?
2. Protein g/kg defaults per goal, and diet-type macro splits — need a nutrition advisor's sign-off.
3. Should the budget be **live** during the day (rises as you move) or **projected** (estimate the full day each morning)? v1 = live. Revisit with user research.
