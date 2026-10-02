# 01 — Platform Foundation & Tech Debt

> **Squad:** Platform · **Phase:** P0 (blocking) · **Depends on:** nothing · **Blocks:** every other doc
> Read `00-MASTER-PLAN.md` §2 first for the audit summary.

---

## 1. Goal

Turn the current prototype-grade codebase into a platform that a 6-person team can work on in parallel without data loss, regressions or merge hell. Nothing user-visible changes in this phase except speed and correctness.

---

## 2. Current state (with evidence)

| Topic | Today | File(s) |
|---|---|---|
| Storage | JSON blobs in `UserDefaults`, loaded synchronously in `init()` | `Managers/PersistenceManager.swift`, `Managers/FoodDatabaseManager.swift`, `Managers/WorkoutDatabaseManager.swift`, `StreakManager.swift` |
| Day keying | Food log by `yyyy-MM-dd` (good). Workouts by **weekday name → this week's date**. Todos and `weekFoodLog`/`weekGymLog` by **weekday name only**. | `WorkoutDatabaseManager.dayToDateKey`, `PersistenceManager.loadWeekTodoList` |
| Weekly data deletion | `checkWeeklyReset()` removes Sunday on Mondays | `WorkoutDatabaseManager.swift` |
| Fake defaults | `caloriesConsumed = 1450`, `healthWeight = 72.5` | `Managers/HealthManager.swift` |
| HealthKit write | Deletes *all* of today's active-energy samples (any source), then writes an estimate | `HealthManager.saveWorkoutCalories` |
| Concurrency | `ObservableObject` singletons mutated from HealthKit callback queues via `DispatchQueue.main.async`. No `@MainActor` on managers. Swift 5 language mode. | Managers |
| Module structure | Single app target plus a watch target. Duplicated models and catalog on the watch side. | `LifeOS Watch App/Models/WatchModels.swift` |
| Large files | `FoodFlowViews.swift` 1,448 lines, `TabViews.swift` 1,175, `WorkoutAndWeightViews.swift` 934, `HomeView.swift` 915 | `Views/` |
| Logging | `print` with emoji | Everywhere |
| Tests / CI | None | — |
| Repo hygiene | `build/` and `.DS_Store` committed. README describes non-existent folders and SwiftData. | root |
| Streak writes | 7× `.onChange` → `syncStreaks()` → full JSON re-encode each time | `Views/HomeView.swift` |

---

## 3. Target state

```
LifeOS/
├── App/                       # LifeOSApp, AppDependencies, root routing
├── Features/
│   ├── Home/                  # one folder per feature, ≤400 lines per file
│   ├── Food/
│   ├── Train/
│   ├── Assistant/
│   ├── Tasks/
│   └── Profile/
Packages/                      # local Swift packages (SPM), shared by iOS + watchOS
├── LifeOSCore/                # pure Swift: models, calculators, dayKey, units — no UIKit/SwiftUI
├── LifeOSData/                # SwiftData schema, repositories, migrations
├── LifeOSHealth/              # HealthKit ingestion, anchors, background delivery
├── LifeOSAI/                  # LLM router, tools, prompt templates, MealVision
├── LifeOSDesign/              # tokens, components, motion, haptics
└── LifeOSConnectivity/        # typed phone↔watch contract (Codable)
LifeOS Watch App/              # depends on LifeOSCore + LifeOSConnectivity (+ LifeOSDesign subset)
LifeOSTests/ LifeOSUITests/    # + per-package test targets
```

---

## 4. Persistence design

### 4.1 Technology choice (FND-01, decision D2)
| Option | Pros | Cons |
|---|---|---|
| **SwiftData** (recommended if min iOS 18) | Native, `@Query` in SwiftUI, CloudKit-ready later, model macros | Some performance quirks. Migrations need care. Less control over SQL. |
| GRDB (SQLite) | Battle-tested, fast, full SQL, great migrations, works on iOS 17 | Third-party dependency, more boilerplate |
| Core Data | Mature | Verbose. SwiftData supersedes it for new code. |

Put a **repository protocol layer** in front of the store either way (the existing `DailyMetricsRepository` and `WeeklyLogRepository` are a good start). Then the store can be swapped and tests can use in-memory fakes.

### 4.2 Schema v1 (SwiftData sketch)

```swift
@Model final class FoodEntry {
    @Attribute(.unique) var id: UUID
    var dayKey: String              // "2026-10-02" — indexed
    var loggedAt: Date
    var mealSlot: MealSlot          // breakfast/lunch/dinner/snacks
    var name: String
    var servingDescription: String
    var quantity: Double            // multiplier of the base serving
    var calories: Double
    var proteinG: Double; var carbsG: Double; var fatG: Double
    var fiberG: Double?; var sugarG: Double?; var sodiumMg: Double?
    var barcode: String?
    var source: EntrySource         // manual, barcode, photoAI, nlAI, preset, assistant, automation, watch
    var presetID: UUID?
    var photoAssetID: String?       // file in app container, not Photos library
    var confidence: Double?         // AI confidence 0…1
    var syncedToHealthKit: Bool
}

@Model final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var dayKey: String
    var start: Date; var end: Date
    var activityType: ActivityKind  // strength, run, walk, cycle, hiit, yoga, other
    var activeEnergyKcal: Double?
    var totalEnergyKcal: Double?
    var avgHeartRate: Double?
    var source: EntrySource         // watch, healthKit(other app), manual
    var healthKitUUID: UUID?        // HKWorkout.uuid — dedupe key
    @Relationship(deleteRule: .cascade) var exercises: [ExerciseLog]
}

@Model final class ExerciseLog {          // replaces Exercise/DayWorkout
    var id: UUID; var bodyPart: BodyPart; var name: String?
    @Relationship(deleteRule: .cascade) var sets: [SetLog]
}
@Model final class SetLog { var reps: Int?; var weightKg: Double?; var completedAt: Date; var source: EntrySource }

@Model final class WaterEntry  { var id: UUID; var dayKey: String; var at: Date; var ml: Double; var source: EntrySource }
@Model final class WeightEntry { var id: UUID; var dayKey: String; var at: Date; var kg: Double; var source: EntrySource; var healthKitUUID: UUID? }
@Model final class TaskItem    { var id: UUID; var dayKey: String?; var title: String; var dueAt: Date?; var completedAt: Date?; var recurrence: Recurrence? }
@Model final class DailySummary { @Attribute(.unique) var dayKey: String; /* derived; recomputed, never edited by hand */ }
@Model final class EnergyDay   { @Attribute(.unique) var dayKey: String; var basalKcal: Double; var activeKcal: Double; var workoutKcal: Double; var budgetKcal: Double; var formulaVersion: Int }  // see doc 03
@Model final class MealPreset  { /* see doc 04 */ }
@Model final class MealCorrection { /* port from CorrectionStore, doc 04 */ }
@Model final class MemoryItem  { /* see doc 05 */ }
@Model final class AutomationRule { /* see doc 06 */ }
@Model final class SyncAnchor  { @Attribute(.unique) var key: String; var data: Data }  // HKQueryAnchor archives
```

Rules:
- `dayKey` is computed **once** at write time in the user's current time zone, by a single `DayKey.make(for:calendar:)` in `LifeOSCore`. It's never derived from weekday names.
- `source` is mandatory on every user-data record.
- `DailySummary` is **derived** and recomputed by a debounced `SummaryService`. Views never write it.

### 4.3 Migration from UserDefaults (FND-04)
1. On first launch of the new version, `LegacyMigrator` reads every legacy key (`allDailyFoodLogs`, `allDailyWorkouts`, `weekTodoList`, `weekGymLog`, `weekFoodLog`, `waterCount_*`, weight history, `dailySummaries`, `userProfile`, `recentFoods`, `favoriteFoods`, `customFoods`, plus the `CorrectionStore` JSON file).
2. It writes a **backup JSON export** to `Application Support/Backups/legacy-<timestamp>.json` before touching anything.
3. It maps weekday-keyed data to concrete dates using the **current week** (that's all the legacy model could represent). Anything ambiguous is logged and counted.
4. It sets `migration.v1.completed = true` only after a row-count verification passes. It is idempotent: re-running it does nothing.
5. Legacy keys stay readable but unused for two releases, then a cleanup task deletes them.

**Acceptance:** migration of a 365-day synthetic dataset finishes in < 2 s on iPhone 13, with zero record loss (verified by counts and checksums in a unit test).

---

## 5. Tickets

### P0-A · Data correctness (week 1–2)
| ID | Title | Size | Acceptance criteria |
|---|---|---|---|
| FND-01 | Persistence ADR + spike | S | ADR in `docs/adr/0001-persistence.md` comparing SwiftData vs GRDB using the real data shapes. Decision recorded. |
| FND-02 | `LifeOSCore.DayKey` + calendar utilities | S | One function for day bucketing, with tests across DST changes, time-zone travel and midnight edges |
| FND-03 | Schema v1 + repositories | L | Models from §4.2. Repository protocols for Food, Workout, Water, Weight, Task, Summary, Energy. In-memory implementations for tests. |
| FND-04 | Legacy migrator | L | §4.3 satisfied. Backup export written. Unit tests with fixture blobs captured from a real device. |
| FND-05 | Remove weekday keying and weekly deletion (C1) | M | `dayToDateKey(dayName)`, `checkWeeklyReset`, `weekTodoList`, `weekGymLog`, `weekFoodLog` removed. All callers use `Date`/`dayKey`. Browsing any past date shows the correct data. |
| FND-06 | Remove fake HealthKit defaults (C5) | S | `HealthManager` published values become optional or have an explicit `.loading/.unavailable/.denied` state. The UI shows skeletons or "Connect Health" instead of fake numbers. |
| FND-07 | Stop deleting other apps' HealthKit samples (C3) | S | No delete of samples where `sourceRevision.source != HKSource.default()`. Writing estimated active energy is disabled behind a flag until doc 02 replaces it with proper `HKWorkout` writes. |
| FND-08 | Debounced summary/streak recompute (C12) | S | A single `SummaryService` subscribes to store changes, debounced 500 ms. The 7 `.onChange` handlers are removed. Instruments shows ≤1 write per burst. |

### P0-B · Structure & concurrency (week 2–3)
| ID | Title | Size | Acceptance criteria |
|---|---|---|---|
| FND-10 | Create local SPM packages | M | Packages from §3 build for iOS and watchOS. The app and watch targets depend on them. |
| FND-11 | Shared phone↔watch contract | M | `LifeOSConnectivity` defines `enum WatchMessage: Codable` and `struct WatchSnapshot: Codable` with `schemaVersion`. `[String: Any]` is removed on both sides. The duplicated `WatchExerciseCatalog` is deleted (the shared `ExerciseCatalog` is used). |
| FND-12 | Split monolith views | L | No file > 400 lines in `Features/`. `TabViews.swift` → `TasksView`, `ProfileHubView`, `StatsView`, `SettingsView`. `FoodFlowViews.swift` → one file per screen. No behaviour change (snapshot tests before and after). |
| FND-13 | Concurrency hygiene | M | Managers/services are `@MainActor` (UI state) or `actor` (I/O). HealthKit uses async APIs (`HKSampleQueryDescriptor`, `HKStatisticsQueryDescriptor`, etc.) where available. Strict concurrency checking = `complete` in the packages, with zero warnings. |
| FND-14 | Swift 6 language mode for packages | M | Packages compile in Swift 6 mode. The app target can stay on 5 mode until P1 ends. |
| FND-15 | Async app launch | S | No store decode on the main thread. Home shows a skeleton until data is ready. Cold launch < 1.0 s (iPhone 13, 1 year of data). |

### P0-C · Observability, flags, hygiene (week 3–4)
| ID | Title | Size | Acceptance criteria |
|---|---|---|---|
| FND-20 | `os.Logger` everywhere | S | Subsystem `app.lifeos`. Categories: `health`, `food`, `ai`, `watch`, `data`, `automation`, `ui`. No `print` (SwiftLint rule). Privacy annotations (`privacy: .private`) on any user values. |
| FND-21 | Crash and performance reporting | S | MetricKit subscriber stores diagnostics locally. Optional Crashlytics behind a flag (privacy manifest updated, doc 09). |
| FND-22 | Feature flags | S | `FeatureFlags` with local defaults, and remote overrides from the backend config endpoint (doc 07, BE-08). Used for every P1+ feature. |
| FND-23 | SwiftLint + SwiftFormat | S | Config committed. CI enforces it. Rules: no `print`, no force-unwrap in packages, file length ≤ 400, function length ≤ 60. |
| FND-24 | Repo hygiene | S | `build/`, `.DS_Store` and `xcuserdata` are removed from git and added to `.gitignore`. The README is rewritten to match reality and links to this folder. |
| FND-25 | Error model | S | A shared `AppError` with user-facing message, recovery suggestion and log category. Silent `try?` is removed from persistence paths. |

### P0-D · Tests & CI → see `10-quality-ci-release.md` (QA-01…05)

---

## 6. Risks & notes

- **SwiftData + watchOS:** keep the watch **storage-light**. The watch shows snapshots and sends mutations. The phone is the source of truth. Only `LifeOSCore` and `LifeOSConnectivity` are needed on the watch.
- **Time zones:** a user flying Delhi → London must not get a duplicated or missing day. `dayKey` is stamped at write time and never recomputed.
- **Don't refactor and change behaviour in the same PR.** Every structural PR is behaviour-neutral, proven by snapshot tests.

---

## 7. Open questions
1. Confirm D1 (min iOS) and D2 (store) — see master plan §8.
2. Is there real user data in the field (TestFlight/App Store)? If yes, FND-04 needs a staged rollout with the migration flag.
