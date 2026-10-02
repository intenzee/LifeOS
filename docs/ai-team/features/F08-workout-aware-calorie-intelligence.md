# F08 — Workout-Aware Calorie Intelligence (Apple Watch → budget)

| | |
|---|---|
| **Phase** | 2 |
| **Owner** | AI Engineer B with the Health/Watch team |
| **Tiers** | T0 (all maths) + T1 (explanations only) |
| **Depends on** | Workout feed C3 (Health team), SwiftData (C1), event bus (C2) |

## 1. Problem
The budget today is `base + manualBurned × bank%`, where `manualBurned` is a MET estimate (2.5 min per set). Apple Watch workouts never reach LifeOS, and the app writes a synthetic "workout calories" sample back to Health. Users with a Watch see wrong numbers and must log twice.

## 2. Outcome
- Any workout recorded on the Apple Watch (or another Health-connected app) **appears in LifeOS automatically**.
- Today's calorie (and protein) targets **update automatically** using measured energy, without double-counting.
- Users can ask "why did my target change?" and get a precise breakdown.
- Over weeks, the base target **self-calibrates** to the user's real expenditure (opt-in).

## 3. Responsibilities split
| Health/Watch team (C3) | AI team (this doc) |
|---|---|
| HealthKit observer + anchored queries, background delivery, persistence to `WorkoutSession`, `workoutIngested` events, stop synthetic writes, optional `HKWorkoutSession` on Watch | Reconciliation, budget policy, adaptive TDEE, explanations, post-workout suggestions, evals |

## 4. Workout reconciliation (dedupe)
Sources: `appleWatch`, `iPhone`, `thirdParty`, `manualLifeOS` (sets/treadmill), `watchAutoSet` (LifeOS Watch tracker).

Algorithm (runs on every `workoutIngested` and on manual log changes):
1. Group sessions per day.
2. For each manual/auto-set LifeOS session:
   - If it has times and overlaps a measured session by ≥ 50% → **merge**: energy = measured; attach exercises/sets as detail.
   - If it has no times (legacy data) and the day has exactly one measured strength-type workout → merge into it.
   - Else keep separately with `estimatedKcal`.
3. Measured sessions from multiple sources overlapping ≥ 80% (e.g. Watch + third-party app recording the same run) → keep the one from Apple Watch, else the longer.
4. Output: `ReconciledDay { sessions: [ReconciledSession], exerciseKcal: Double, provenance }`.

*(Requires manual sets to carry timestamps from now on — ask in C1.)*

## 5. Budget policy

```
dailyTarget = baseTarget + bankPercent × exerciseKcal(reconciled)
```
- `baseTarget` = existing Mifflin-St Jeor × activity multiplier + goal adjustment (or manual override) — unchanged by default.
- `exerciseKcal` = sum of reconciled workout energy (**workouts only**, not all-day active energy, because the activity multiplier already covers daily movement).
- `bankPercent` keeps the existing user setting (default 50%), because wearable and MET estimates tend to overestimate.
- **Advanced "activity-aware" mode** (opt-in): base uses the *sedentary* multiplier and `exerciseKcal` = all-day active energy from Health → avoids double counting for users who prefer it.
- Guardrails: added-back calories capped at +1,000 kcal/day by default; target never below a **floor** (placeholder `max(BMR, 1,200 kcal)` — final value to be set with a qualified nutrition advisor); goal deficits never exceed 25% of estimated TDEE.
- Macro targets: protein target recomputed from body weight and goal; extra carbs allocated proportionally to added calories for endurance sessions > 45 min.
- Recompute triggers: `workoutIngested`, manual workout change, weight change, day rollover, settings change. Emits `budgetChanged(old, new, reason)`.

## 6. Adaptive TDEE (opt-in, Phase 2 late / Phase 3)
Estimate real maintenance from the user's own data:
```
expenditure_t ≈ intake_t − 7,700 kcal/kg × Δ(trend weight)/Δt
```
- Trend weight: exponential moving average of daily weights (α ≈ 0.1) to remove water noise.
- Use a 21–28-day window; require ≥ 80% logged days and ≥ 8 weigh-ins; otherwise "not enough data".
- Smooth the estimate (EMA) and propose changes of at most ±100 kcal per week.
- Presented as a weekly suggestion: "Your real maintenance looks ~150 kcal higher than estimated. Update your target?" Auto-apply only if the user turned on "Adaptive target".

## 7. Explanations (T1)
`budgetExplain` receives a deterministic breakdown and only phrases it:
```
base 2,050 (Mifflin-St Jeor, moderately active, lose weight −500)
+ 50% of 360 kcal workouts = +180 (Evening run 42 min, Watch, 290 kcal; Upper body 35 min, LifeOS sets merged into Watch strength workout, 70 kcal)
= 2,230 today
```
Template fallback renders the same breakdown without a model.

## 8. UX moments (with Design)
- Home calorie ring animates the increase with a source chip ("+180 · Apple Watch").
- Post-workout card (F07 §6).
- Settings: data source (workouts only / activity-aware), bank %, adaptive target toggle, "hide calorie numbers" (safety option).

## 9. Edge cases
Workout deleted in Health → remove and recompute (anchored query deletions) · Workout recorded after midnight for previous day → attribute by start date · Very long sessions (> 4 h) → flag for confirmation · No Watch → current manual behaviour unchanged · Health permission revoked → detect and show re-enable banner (CONCERNS.md fragile area).

## 10. Acceptance criteria
- [ ] Reconciliation unit tests cover 40 scenarios (overlaps, legacy untimed sets, multi-source duplicates, deletions).
- [ ] No double counting in any scenario of the test matrix.
- [ ] End-to-end: Watch workout → budget updated within 15 min (locked) / 10 s (foreground).
- [ ] Adaptive TDEE within ±10% of ground-truth expenditure on synthetic datasets with known TDEE and realistic noise.
- [ ] Floors and caps enforced in 100% of property-based tests.

## 11. Tickets
`AI-240` ReconciledDay model + reconciler · `AI-241` BudgetPolicy (+ activity-aware mode, caps, floors) · `AI-242` Macro target updater · `AI-243` Budget change events + Home integration contract · `AI-244` Explanation prompt + template · `AI-245` Adaptive TDEE estimator · `AI-246` Settings data APIs · `AI-247` Tests/evals with synthetic data generator.
