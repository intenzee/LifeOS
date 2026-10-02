# Phase 0 — Status & next steps

> Last updated 3 Oct 2026. Owner: Platform. Tickets are defined in `01-platform-foundation.md`, `09-security-privacy-compliance.md` and `10-quality-ci-release.md`.

## Decisions taken

| # | Decision | Record |
|---|---|---|
| D1 | Minimum stays **iOS 17.6** / watchOS 10 | [ADR 0001](../adr/0001-persistence.md) |
| D2 | **Date-keyed file store behind repository protocols** (not SwiftData/GRDB for now) | [ADR 0001](../adr/0001-persistence.md) |
| — | One `LifeOSKit` package with Core / Data / Connectivity products. Swift 6 mode. | [ADR 0002](../adr/0002-module-structure.md) |
| — | Build and test on the physical iPhone 15 + Watch only, no simulator | Product owner, 3 Oct |
| — | The store is unconditional (no `fileStore`/`legacyMigration` flags). Rollback = the untouched UserDefaults keys + backup. | Platform, 3 Oct |

## How to verify

```bash
./scripts/test-packages.sh                       # 74 tests (more counting parameterized cases)
./scripts/test-packages.sh --enable-code-coverage
```

Current numbers: all green. **89.7% line coverage** across the package (target: ≥80% Core, ≥60% others). A 365-day heavy-logger migration completes and verifies in **≈0.7 s** on a Mac (debug build, real files).

## Ticket status

✅ done · 🟡 package side done, app wiring pending (needs Xcode) · ⏳ not started

### P0-A · Data correctness
| ID | Status | Notes |
|---|---|---|
| FND-01 Persistence ADR | ✅ | ADR 0001 |
| FND-02 `DayKey` | ✅ | `LifeOSCore/Time/DayKey.swift`. Tests cover DST (23 h/25 h days, repeated 01:30), time-zone travel, midnight, leap years, Buddhist-calendar devices, strict parsing. |
| FND-03 Schema v1 + repositories | ✅ | `LifeOSCore/Models/*`, `LifeOSData/Repositories/*`. In-memory backend for tests. Deviations from the sketch are listed in ADR 0001. |
| FND-04 Legacy migrator | ✅ | Runs at launch (`LocalStore.bootstrap`). **Verified on the owner's iPhone, 3 Oct:** the first run (v1) skipped 6 meals whose UUID was reused by re-logging a recent food. v2 assigns stable new IDs and repairs v1 devices. Afterwards the store matched the backup exactly (11 items, 3,062 kcal, per-day counts). Regression tests in `DuplicateIDMigrationTests`. |
| FND-05 Remove weekday keying | 🟡 | **Storage is date-keyed.** Weekday names are resolved to the current week's date before saving, and `checkWeeklyReset` is gone, so history survives the week rollover. The browsed date now shows its real workout. Views still pass weekday names (the week-picker API). That goes with FND-12. |
| FND-06 Remove fake HealthKit defaults | ✅ | `caloriesConsumed` / `healthWeight` are optional (`nil` until HealthKit answers) |
| FND-07 Stop deleting other apps' samples | ✅ | The delete predicate is limited to `HKSource.default()`. The estimated-energy write is gated by `healthKitEstimatedEnergyWrite` (off). |
| FND-08 Debounced summary recompute | 🟡 | `StreakManager.recordToday` drops identical summaries and writes one record, debounced 500 ms (it used to re-encode every summary on each of 7 triggers). Wiring the package `SummaryService` and deleting the `.onChange` handlers waits for HomeView's split (FND-12). |

### P0-B · Structure & concurrency
| ID | Status | Notes |
|---|---|---|
| FND-10 Local SPM packages | ✅ | `Packages/LifeOSKit` is referenced by the Xcode project: iOS gets Core, Data and Connectivity; Watch gets Core and Connectivity. The app re-exports Core (`LifeOS/App/LifeOSKitExports.swift`), and the duplicated app types are deleted. `LifeOSHealth` deferred to P1 (ADR 0002). `LifeOSDesign` and `LifeOSAI` are owned by their teams. |
| FND-11 Typed watch contract | 🟡 | Wired into both apps. The phone sends the typed envelope plus v1 keys and accepts both mutation formats. The watch reads typed first and sends typed mutations (which name their day) once it has seen a typed snapshot. The duplicated watch catalog now delegates to `ExerciseCatalog`. `typedWatchContract` is a kill switch (on). **Open:** on-device phone ↔ watch test (build verified, not yet installed). |
| FND-12 Split monolith views | ⏳ | Needs Xcode (behaviour-neutral, snapshot-tested) |
| FND-13 Concurrency hygiene | 🟡 | Package: actors + complete strict concurrency, zero warnings. App managers not yet converted. |
| FND-14 Swift 6 mode for packages | ✅ | `swiftLanguageModes: [.v6]` |
| FND-15 Async app launch | 🟡 | `LaunchGate` waits for `LocalStore.bootstrap` (migrate, then load off-main), with a retry screen on failure. Writes go through one serial queue. **Open:** measure cold launch on device (QA-11). |

### P0-C · Observability, flags, hygiene
| ID | Status | Notes |
|---|---|---|
| FND-20 `os.Logger` | 🟡 | `Log` in Core. 17 `print` calls remain in the app. The SwiftLint `no_print` rule is in place. |
| FND-21 MetricKit | ⏳ | App-only |
| FND-22 Feature flags | ✅ | `FeatureFlags`: local override → remote → default. Unknown remote keys ignored. |
| FND-23 SwiftLint | ✅ | `.swiftlint.yml`. Strict on packages, report-only on app targets until FND-12. SwiftFormat config not added yet. |
| FND-24 Repo hygiene | ✅ | Nothing junk is tracked (`build/`, `.DS_Store` were already untracked). `.gitignore` extended. README tech sections rewritten to match the code. |
| FND-25 Error model | ✅ | `AppError` (code, user message, recovery, category). No silent `try?` in persistence paths: the app managers no longer encode to UserDefaults, and store write failures are logged. |

### Security & QA (P0 items)
| ID | Status | Notes |
|---|---|---|
| SEC-01 File protection | 🟡 | `FileStorageBackend` applies `.completeUntilFirstUserAuthentication` to files and directories. Needs on-device verification. |
| SEC-02 Privacy manifest | 🟡 | `LifeOSData/PrivacyInfo.xcprivacy` (UserDefaults CA92.1). The **app** manifest is still to add. |
| SEC-03 Logging privacy | 🟡 | Package logs user values as `.private`. App `print`s pending (FND-20). |
| QA-01 Test targets | 🟡 | Package test targets ✅. App unit/UI targets need Xcode. |
| QA-02 Baseline unit tests | 🟡 | Calculators, streaks, DayKey ✅. `GroqMealAnalyzer.isolateJSONObject`, `MealLearningEngine`, `AutoSetTracker` pending (app-target code). |
| QA-03 Persona fixtures | 🟡 | `LegacyFixture.heavyLogger(days:)` exists. Launch-argument seeding pending. |
| QA-04 CI pipeline | ✅ | `.github/workflows/ci.yml`: lint, LifeOSKit tests + coverage, AI harness tests, design-system tests + token check, iOS + watchOS build. Mark `lint`, `packages`, `design-system` and `app-build` as required on `main`. |
| QA-05 Snapshot testing | ⏳ | Needs Xcode. Coordinate with UI Engineering (design-system components). |

## App wiring progress

| Step | Status |
|---|---|
| 1. Package reference | ✅ |
| 2. Delete duplicated app types | ✅ (watch's `WatchExerciseCatalog` goes with step 7) |
| 3. FND-06/07 HealthKit fixes | ✅ |
| 4. Launch migration | ✅ verified on device |
| 5. Managers on repositories | ✅ Persistence, Food, Workout and Streak managers read a preloaded `DataSnapshot` and write through `LocalStore.enqueue` |
| 6. `SummaryService` + remove `.onChange` handlers | ⏳ with FND-12 |
| 7. Typed watch contract | 🟡 built for device, install and wrist test pending |
| 8. FND-12 splits, FND-20 prints, app privacy manifest, MetricKit, app test targets | ⏳ |

Every step was built for, installed on and launched on the iPhone 15. Each build had zero new warnings.

## P0 exit gate (unchanged)

- [ ] All existing features work on the new store (launches and migrates on device; a manual feature pass by the owner is pending)
- [x] Migration tested with real user data (owner's iPhone, 3 Oct)
- [ ] CI green on every PR
- [x] ≥70% unit coverage on `LifeOSCore`
- [ ] Cold launch < 1.0 s on iPhone 13 with 1 year of synthetic data
