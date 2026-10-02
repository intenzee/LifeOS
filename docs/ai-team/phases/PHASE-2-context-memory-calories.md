# Phase 2 — Context, Memory & Workout-Aware Calories (Weeks 10–13) → Beta 2

**Goal:** give LifeOS a brain and a body sense — it knows the user's day, remembers what matters, and adapts calories to real Apple Watch workouts.

## Scope
| In | Out |
|---|---|
| F05 Context Engine (providers, budgeting, privacy filter, caching) | Chat UI (Phase 3) |
| F06 Memory (store, extraction, retrieval, remember/forget, consolidation, Memory screen APIs, migrate CorrectionStore) | iCloud memory sync |
| F08 reconciliation, budget policy, explanations, macro updates; adaptive TDEE (flagged) | |
| Context/memory wired into F02 (meal inference) and F04 (portion hints) | |

## Entry criteria (hard dependencies)
- **C1 SwiftData migration shipped** with date-keyed history (fixes audit B1–B3). *Phase 2 cannot start without it.*
- **C2 event bus** available.
- **C3 workout feed** from Health/Watch team in TestFlight, including background delivery.
- Design: Memory screen and budget explainer specs.

## Sprint plan
| Sprint | Weeks | Engineer A | Engineer B | QA |
|---|---|---|---|---|
| 4 | 10–11 | F08 reconciler + BudgetPolicy + caps/floors + budget events; synthetic workout data generator | F05 providers + intent plan + token budgeter + privacy filter; F06 store + embeddings + extractor | Reconcile scenarios (40); memory extraction set |
| 5 | 12–13 | F08 explanations + macro updates + adaptive TDEE (flag); wire context into F02/F04 | F06 retrieval, remember/forget, consolidation BG task, CorrectionStore migration, Memory screen APIs | Context QA set; end-to-end Watch workout test |

## Exit criteria
- [ ] Apple Watch workout → reflected in budget within 15 min (locked) in ≥ 95% of test runs; no double counting across the scenario matrix.
- [ ] Memory extraction precision ≥ 90%; wipe verified.
- [ ] Context packets within budget 100%; no deny-listed fields to T3.
- [ ] Meal-type inference uses learned windows (eval improvement vs. Phase 1 ≥ 10 pts).
- [ ] TestFlight **Beta 2**.

## Demo script
1. Finish a 30-minute run on the Watch → phone locked → unlock: ring shows "+150 · Apple Watch"; tap → explanation.
2. Log strength sets in LifeOS during a Watch strength workout → no double count.
3. Tell LifeOS "I don't eat oats" → later photo of muesli → suggestions avoid oats; Memory screen shows the fact; delete it.
