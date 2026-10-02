# ADR 0001 — Persistence: date-keyed file store behind repositories

- **Status:** Accepted (3 Oct 2026, product owner decision on D1/D2)
- **Ticket:** FND-01 (also FND-03, FND-04, FND-05, FND-15, SEC-01)
- **Supersedes:** the recommendation in `engineering-roadmap/00-MASTER-PLAN.md` §8 (SwiftData + iOS 18 minimum)

## Context

All user data lived in `UserDefaults` as large JSON blobs, decoded on the main thread at launch (C6). Workouts and todos were keyed by weekday name and deleted weekly (C1). The plan recommended SwiftData with an iOS 18 minimum, or GRDB as the alternative.

Constraints at decision time:

1. **Keep iOS 17.6** as the minimum. Raising it drops users, and nothing in P0/P1 needs iOS 18.
2. **Verifiable now.** The team's current build machine has only the Command Line Tools. SwiftData's `@Model` macros don't compile there, so a SwiftData schema would ship untested.
3. **Zero third-party dependencies** stays a goal (doc 09 §3.7).
4. The data is small. A heavy logger writes about 2,000 food entries a year. Every query we need today is "one day" or "a date range".

## Options

| Option | For | Against |
|---|---|---|
| SwiftData (iOS 18 min) | Native, `@Query`, CloudKit-ready | Forces iOS 18. Can't be compiled or tested on the current machine. Migration quirks. |
| GRDB | Full SQL, mature migrations, iOS 17 | Third-party dependency (licence and privacy-manifest sign-off). More boilerplate. |
| **File store behind repository protocols** | iOS 17. Zero dependencies. Every line compiled and unit-tested today. Off-main-thread by construction (actors). Data Protection per file. | No ad-hoc queries. We own the storage code. |

## Decision

A **date-keyed, month-sharded JSON file store** in `Packages/LifeOSKit/Sources/LifeOSData`, used only through **repository protocols**.

- Layout: `Application Support/LifeOSStore/v1/<collection>/<yyyy-MM>.json`, plus `documents/<name>.json` for singletons (profile, food library).
- `RecordStore<R>` is an actor per collection. Months load lazily and stay cached. Each shard write is atomic. A batch writes each touched shard once.
- Files use `.completeUntilFirstUserAuthentication` (SEC-01). Not `.complete`, because HealthKit background delivery must write while the phone is locked.
- Every record has a `dayKey` (`DayKey`, Gregorian `yyyy-MM-dd`, stamped once at write time) and, where it can be user-authored, a `source`.
- A shard that fails to decode is **quarantined** (renamed `.corrupt-<time>`, logged as a fault). The user can keep logging, and the bytes are kept for recovery.
- `ChangeBus` publishes `StoreChange(collection, days)`. `SummaryService` debounces it (500 ms) to recompute `DailySummary` (FND-08).
- Preferences (theme, reminder toggles, calorie limit, eat-back %) **stay in UserDefaults**. They are settings, not records.

### Deviations from the doc 01 §4.2 sketch

| Sketch | Implemented | Why |
|---|---|---|
| `WorkoutSession` + `ExerciseLog` + `SetLog` | `WorkoutDay` with `[Exercise]` (set counts) | Behaviour-neutral P0. HealthKit workouts arrive as their own record type in P1 (doc 02). |
| `WaterEntry` (ml per event) | `WaterDay` (glasses per day, `mlPerGlass = 250`) | The app counts glasses today. An event model can replace it later without changing callers. |
| `TaskItem.dayKey` optional | Required | Every legacy todo is day-bound. Inbox (undated) tasks are a later feature. |
| `DailySummary` derived | Derived, **but legacy history is migrated** | Past summaries can't be recomputed (old water/todo data was overwritten weekly). |

## Consequences

- Callers never see files. Moving to SwiftData later means a new set of `*Repository` implementations, with no feature changes.
- Range queries load the whole months they touch. That's fine at our scale (a year ≈ 12 shards per collection). Revisit if the assistant (doc 05) needs full-text search across years. The answer is likely an on-device index, not a new store.
- Moving a record to a day in another month requires `delete` then `save` (documented on `RecordStore.upsert`).

## Migration (FND-04)

`LegacyMigrator` runs once at launch behind `FeatureFlag.legacyMigration`:

1. If `migration/legacy-v1.json` exists, it does nothing (idempotent).
2. It writes the full `LegacySnapshot` to `backups/legacy-<time>.json` **first**.
3. It maps every key. Weekday-keyed data (`weekTodoList`, `weekGymLog`, `weekFoodLog`) goes into the current Monday-first week, which is all the old model could represent. Localized weekday names (e.g. "Montag") are recognised. Date-keyed workouts win over weekday-keyed ones.
4. It writes with stable IDs (legacy UUIDs, or `StableID` for weight), so a crashed half-run repeats safely.
5. It re-reads through a fresh store with no caches, checks every record and a SHA-256 checksum, and only then writes the marker with a report (counts, skip reasons, inferred-from-weekday count).
6. Legacy keys stay readable but unused for two releases.

Measured: 365 days of heavy logging (2,190 food entries plus workouts, water, weight and summaries) migrates and verifies in **≈0.7 s** on a Mac (debug build, real files). On-device confirmation is part of the P0 exit gate.
