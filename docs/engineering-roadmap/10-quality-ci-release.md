# 10 — Quality, CI/CD & Release

> **Squad:** QA + Platform · **Phases:** P0 (test infrastructure + CI) → ongoing → P5 (beta + launch)

---

## 1. Goal
Ship fast **without regressions** in the numbers users trust (calories, macros, workouts, streaks). Ship AI features with measured, not anecdotal, quality.

Current state: **zero automated tests, no CI**. There's only a debug launch-argument harness (`UITEST_MEALRESULT` in `LifeOSApp.swift`), which is a useful pattern to extend.

---

## 2. Test strategy

| Layer | Tooling | What | Target |
|---|---|---|---|
| Unit | Swift Testing (`@Test`) + XCTest where needed | `LifeOSCore` calculators (BMR, TDEE, `CalorieEngine`, macros, `DayKey`), streak logic, merge rules, unit normaliser, `isolateJSONObject`, learning-engine ranking | ≥ 80% line coverage on `LifeOSCore`, ≥ 60% on other packages |
| Integration | In-memory SwiftData container, fake `HKHealthStore` protocol, fake LLM provider, `URLProtocol` stubs | Repositories, migrations, ingestion pipeline, `BudgetService`, `NutritionResolver`, `LLMRouter`, proxy client | All critical flows |
| Snapshot | swift-snapshot-testing (MIT) or Xcode-native image diffs | Every `LifeOSDesign` component in light/dark/AX3/RTL. Key screens. | Every component |
| UI (XCUITest) | Launch arguments → seeded fixture data (extend the existing harness pattern) | Onboarding, log food (all 5 methods), Watch-workout-arrives flow (fixture), assistant confirm/undo, settings | Top 15 journeys |
| AI evals | Custom harness (CLI + CI job) | NL parsing golden set, assistant tool-selection and numbers, safety suite | Thresholds below |
| Performance | XCTest `measure` + `XCTOSSignpostMetric`, Instruments templates | Cold launch, Home scroll, 3D first render, migration time | Budgets in docs 01 and 08 |
| Device / manual | Test plan per release | HealthKit with a real Watch, background delivery, notifications, Siri, widgets, battery | Release checklist |

### 2.1 Fixtures
- `Fixtures/Personas/*.json`: 5 personas (new user, 1-year heavy logger, Watch runner, gym lifter without a Watch, irregular logger), each with a year of synthetic data.
- A debug-only **"Health Fixtures"** screen writes synthetic `HKWorkout` / energy / weight samples on the simulator to exercise doc 02 end to end.
- Legacy `UserDefaults` blobs captured from a real device (anonymised) for the migration tests (FND-04).

### 2.2 AI evaluation sets
| Set | Size | Metric | Ship threshold |
|---|---|---|---|
| NL meal parsing (QA-06) | 200 phrases incl. regional foods, units and slang, multi-item, corrections | Item-level F1, quantity accuracy | F1 ≥ 0.90, qty ≥ 0.85 |
| Photo scan (QA-08) | 100 labelled meal photos (team-shot, consented) | Dish name hit-rate, kcal MAPE | Hit ≥ 75%, MAPE ≤ 25% (cloud path) |
| Assistant (QA-07) | 150 prompts with expected tool calls and exact numbers | Tool-selection accuracy, numeric exactness | ≥ 95% / 100% |
| Safety (AI-16) | 50 adversarial/sensitive prompts | Policy compliance | 100% |

- Evals run nightly in CI against **recorded** provider responses (deterministic), and weekly against live providers (catches model drift and retirements).
- Results are stored as CI artifacts. A regression of > 2 points blocks merge on AI-touching PRs.

---

## 3. CI/CD

### 3.1 Pipeline (GitHub Actions macOS runners, or Xcode Cloud)
```mermaid
flowchart LR
    PR[Pull request] --> L[SwiftLint + SwiftFormat check]
    L --> B[Build iOS + watchOS]
    B --> U[Unit + integration tests]
    U --> S[Snapshot tests]
    S --> E[AI evals (recorded)]
    E --> R[Required reviews: 1 (2 for LifeOSCore/Data/Health/AI)]
    R --> M[Merge to main]
    M --> N[Nightly: UI tests on 3 sims, perf tests, live AI evals (weekly)]
    M --> T[Tag → archive → TestFlight internal]
```
- Branching: trunk-based, short-lived feature branches. Feature flags for anything incomplete (FND-22).
- Required checks: lint, build, unit, snapshot, evals (when `LifeOSAI` changes).
- Signing: fastlane `match` (or Xcode Cloud managed signing). Secrets in CI secrets, never in the repo.
- Versioning: `MAJOR.MINOR.PATCH (build)`, build number from CI.
- The backend Worker deploys from the same repo (`/backend`) on tag (doc 07 BE-01).

### 3.2 Environments
| Env | App build | Proxy | Data |
|---|---|---|---|
| Dev | Debug, fixtures enabled | `dev` Worker | Simulator fixtures |
| Internal | Release config, internal TestFlight | `dev` or `prod` (flag) | Real devices, team accounts |
| Beta | External TestFlight | `prod` with beta quotas | Real users (≥ 50) |
| Prod | App Store | `prod` | — |

---

## 4. Tickets

### P0 — Test infrastructure & CI
| ID | Title | Size | Acceptance criteria |
|---|---|---|---|
| QA-01 | Test targets for app + packages | S | Unit/UI targets created. `Cmd+U` runs them. |
| QA-02 | Baseline unit tests for existing logic | M | `CalorieGoalCalculator`, `CalorieCalculator`, `StreakManager`, `GroqMealAnalyzer.isolateJSONObject`, `MealLearningEngine` ranking, `AutoSetTracker` (with recorded motion traces) |
| QA-03 | Persona fixtures + launch-argument seeding | M | §2.1. `-fixture persona_heavy_logger` boots the app with that data. |
| QA-04 | CI pipeline | M | §3.1 up to merge. Runs < 20 min. Required on `main`. |
| QA-05 | Snapshot testing setup | S | Library integrated. First 10 snapshots. Recording mode documented. |

### P2–P3 — AI quality
| ID | Title | Size | Acceptance criteria |
|---|---|---|---|
| QA-06 | NL parsing golden set + harness | M | 200 phrases, expected JSON, scorer, CI job |
| QA-07 | Assistant eval harness | M | 150 prompts, fake data store per persona, tool-call and numeric checks |
| QA-08 | Photo eval set | M | 100 consented, labelled photos. Scorer. Weekly live run. |
| QA-09 | Health ingestion test kit | M | Health Fixtures screen + integration tests for WCH-01…08 |

### P5 — Harden & launch
| ID | Title | Size | Acceptance criteria |
|---|---|---|---|
| QA-10 | Release test plan & device matrix | S | Matrix: oldest supported iPhone, mid, current Pro; 2 Watch generations; iOS min + latest; one device with Apple Intelligence off |
| QA-11 | Performance pass | M | All budgets in docs 01/08 met and recorded in a perf report |
| QA-12 | Battery & background audit | M | 24 h soak with BG delivery + automations. Battery attribution in Settings ≤ 5% for typical use. |
| QA-13 | Accessibility pass | M | UI-22 complete. VoiceOver run-through of the top 15 journeys. |
| QA-14 | Localisation readiness | S | All strings in String Catalogs. Pseudo-localisation run. Number/unit formatting by locale. |
| QA-15 | Privacy-preserving analytics | M | On-device aggregated metrics or a privacy-focused provider. Funnels: onboarding, first log, D1/D7 retention. Declared in the privacy label. |
| QA-16 | TestFlight external beta | M | ≥ 50 testers, in-app feedback (shake to report with an optional screenshot), crash-free sessions ≥ 99.5% |
| QA-17 | App Store assets & metadata | S | Screenshots and preview video (from the design team), description, health/AI disclosures (SEC-13) |
| QA-18 | Launch runbook | S | Rollout (phased release), monitoring, rollback via flags/kill-switches, proxy quota watch |
| QA-19 | Post-launch triage rotation | S | On-call doc, crash/feedback triage SLA |
| QA-20 | Release notes & changelog automation | S | Generated from conventional commits |

---

## 5. Release gates (per phase)
| Gate | Criteria |
|---|---|
| End of P0 | Migration tested on real legacy data. CI green. Cold launch budget met. |
| End of P1 | Watch-workout E2E on real devices. Calorie test vectors pass. Battery for watch sessions measured. |
| End of P2 | NL F1 ≥ 0.90. Photo p50 ≤ 6 s. No client-side API keys. Consent flow live. |
| End of P3 | Assistant evals pass. Safety 100%. Memory export/delete works. Automation caps respected. |
| End of P4 | Perf budgets met. Accessibility audit passes. |
| Launch (P5) | Crash-free ≥ 99.5% in beta. Compliance sign-off (SEC-13). Runbook ready. |
