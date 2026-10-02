# ADR 0002 — Module structure: one `LifeOSKit` package, three products

- **Status:** Accepted (3 Oct 2026)
- **Ticket:** FND-10 (also FND-11, FND-13, FND-14)

## Context

Doc 01 §3 proposes six local packages (`LifeOSCore`, `LifeOSData`, `LifeOSHealth`, `LifeOSAI`, `LifeOSDesign`, `LifeOSConnectivity`). Several teams are now working in parallel in this repo:

| Area | Owner | Location |
|---|---|---|
| Core models, store, watch contract | Platform (this ADR) | `Packages/LifeOSKit/` |
| Design system | UI Engineering | `LifeOS/DesignSystem/`, `design/tokens/`, test-only manifest at `Packages/LifeOSDesign/` |
| AI | Nutrition & AI | `LifeOS/AI/`, `Evals/`, `Tools/ai-eval/`, root `Package.swift` |

## Decision

1. **One package, `Packages/LifeOSKit`, with three library products:**
   - `LifeOSCore`: pure Swift (Foundation + `os`). `DayKey`, records, `UserProfile`, calculators, streaks, `Log`, `AppError`, `FeatureFlags`. Safe on watchOS.
   - `LifeOSData`: depends on Core. File store, repositories, `LegacyMigrator`, `SummaryService`. iPhone only.
   - `LifeOSConnectivity`: depends on Core. `WatchSnapshot`, `WatchMutation`, `WatchWire`. Linked by both apps.
   One package means one local package reference in Xcode, one `Package.resolved`, and products picked per target.
2. **Swift 6 language mode and complete strict concurrency** for the whole package (FND-13/14). It builds with zero warnings. The app target stays in Swift 5 mode until P1 ends.
3. **`LifeOSHealth` is deferred to P1.** It's HealthKit-bound and gets rewritten in doc 02 anyway, so extracting today's `HealthManager` first would be wasted motion.
4. **`LifeOSDesign` and `LifeOSAI` belong to their teams** and live where they've put them. `LifeOSKit` never depends on either.
5. **Type names.** `LifeOSCore` deliberately reuses the app's names, with the same API, for types that move: `BodyPart`, `MealType`, `Exercise`, `ExerciseCatalog`, `UserProfile` (+ enums), `DailySummary`, `CalorieGoalCalculator`, `CalorieCalculator`. Wiring the app means deleting the app copy and adding `import LifeOSCore`. Nobody should add new types with these names.

## Wiring the app (needs Xcode, see `docs/engineering-roadmap/P0-STATUS.md`)

1. File ▸ Add Package Dependencies ▸ Add Local… ▸ `Packages/LifeOSKit`.
2. iOS target: `LifeOSCore`, `LifeOSData`, `LifeOSConnectivity`. Watch target: `LifeOSCore`, `LifeOSConnectivity`.
3. Delete the duplicated app types listed above, plus `WatchExerciseCatalog`, and add the imports.

## Consequences

- Packages build and test with `scripts/test-packages.sh`, with or without Xcode, and in CI.
- If a product later needs independent versioning or a different platform set, it can split out with no source changes.
