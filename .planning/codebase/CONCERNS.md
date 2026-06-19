# Codebase Concerns

**Analysis Date:** 2026-06-19

## Tech Debt

**Monolithic View Files:**
- Issue: [TabViews.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Views/Tabs/TabViews.swift) contains over 1100 lines of code, wrapping multiple major views (`TodoTabView`, `ProfileHubView`, `StatsView`, `SettingsView`) and their sub-sheets/presets/pickers.
- Why: Rapid feature assembly during prototype phases.
- Impact: Decreased readability, high risk of git merge conflicts, and difficult code maintenance.
- Fix approach: Extract each major view structure into its own dedicated source file (e.g., `TodoTabView.swift`, `ProfileHubView.swift`, `SettingsView.swift`) under the `Views/Tabs/` directory.

**Redundant Persistence Schemas:**
- Issue: Storage formats are split between raw key-value logs in [PersistenceManager.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/PersistenceManager.swift) and secondary dictionaries in [FoodDatabaseManager.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/FoodDatabaseManager.swift#L16-L17) (`allDailyLogs`) and [WorkoutDatabaseManager.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/WorkoutDatabaseManager.swift#L7) (`allDailyWorkouts`).
- Why: Incremental implementation of screen views.
- Impact: Increased disk storage footprints, synchronization delays, and potential cache drift between state variables.
- Fix approach: Unify persistence models around repositories, migrating storage records to a structured local database (like CoreData or SwiftData).

## Known Bugs

**Async Thread Collisions during Launch Initialization:**
- Symptoms: Thread crashes and payload abortions (`__abort_with_payload`) during early loading cycles.
- Trigger: Background task execution and asynchronous assignments inside class initializers before the UI is fully mounted.
- Workaround: Debouncing updates or keeping manager initialization code on the `MainActor`.
- Root cause: Modifying `@Published` properties from thread contexts outside the main execution run loop during object initialization.
- Fix: Ensure all database loading is performed on standard background threads, and only assign values back to published caches on the `MainActor` using structured Task environments or `.receive(on: DispatchQueue.main)`.

## Security Considerations

**Unencrypted Personal Health Information (PHI):**
- Risk: Sensitive user metrics (body weight, dietary targets, calorie summaries) are stored in clear text inside standard plist records (`UserDefaults`). This data can be read from device backups or jailbroken operating systems.
- Current mitigation: None. Relies on the default sandbox security of the iOS filesystem.
- Recommendations: Migrate sensitive data fields to the device Keychain, or encrypt the local database store using SQLCipher or SwiftData security extensions.

**Unauthenticated Network Requests:**
- Risk: Food barcode lookups occur over unauthenticated requests to OpenFoodFacts. While HTTPS prevents eavesdropping, it makes the app vulnerable to client-side request tampering if a proxy is configured.
- Current mitigation: Requests are sent over TLS (HTTPS).
- Recommendations: Keep using HTTPS, but add basic SSL Pinning for OpenFoodFacts domain references to prevent man-in-the-middle exploits.

## Performance Bottlenecks

**Synchronous JSON Deserialization during App Launch:**
- Problem: Cold start delay or watch watchdog terminations due to blocking operations on the main thread.
- Cause: Reading, decoding, and parsing large JSON dictionaries containing months of daily logs from `UserDefaults` during synchronous `init` calls in [FoodDatabaseManager.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/FoodDatabaseManager.swift#L19) and [WorkoutDatabaseManager.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/WorkoutDatabaseManager.swift#L11).
- Improvement path: Wrap database deserialization inside asynchronous tasks, presenting a loading skeleton state on the UI while loading is performed in the background.

## Fragile Areas

**Apple HealthKit Authorization Status:**
- Why fragile: If a user revokes permissions in iOS System Settings -> Health -> Data Access & Devices, the HealthKit SDK queries return empty datasets or fail silently without raising catchable exceptions.
- Common failures: Fitness rings display 0 calories burned or sleep durations remain blank, leaving the user with no explanation.
- Safe modification: Check authorization status explicitly using `getRequestStatusForAuthorization` and prompt the user to re-enable settings if disabled.
- Test coverage: None.

**Multi-Trigger Streak Computations:**
- Why fragile: [HomeView.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Views/HomeView.swift#L438-L455) triggers `viewModel.syncStreaks()` via 7 separate `.onChange` handlers observing calorie limits, water counts, weights, completed tasks, and calorie burns.
- Common failures: Rapid consecutive updates (e.g. typing or holding water buttons) invoke multiple overlapping saves to disk, causing UI stutter and file write thrashing.
- Safe modification: Consolidate or debounce streak updates to avoid writing to `UserDefaults` multiple times in a fraction of a second.
- Test coverage: None.

## Scaling Limits

**UserDefaults Storage Bloat:**
- Current capacity: Suitable for minor configurations (<100KB).
- Limit: Performance degrades significantly as plists exceed 1-2MB. Large file reads block app initialization.
- Symptoms at limit: App launch times exceed 2 seconds, UI frame drops occur during changes.
- Scaling path: Migrate to a relational store (SwiftData or SQLite) to support paginated loads and index querying.

## Missing Critical Features

**Offline Barcode Lookup Caching:**
- Problem: Scanning a food barcode while offline or in poor network areas fails instantly.
- Current workaround: User must manually enter names and calorie values.
- Blocks: Core UX fails during common gym or grocery shopping scenarios.
- Implementation complexity: Low (Add a local database table caching previously looked up barcodes and their nutrition specs).

## Test Coverage Gaps

**Entire Codebase:**
- What's not tested: 100% of application code (zero unit, integration, or UI automation tests).
- Risk: Refactoring logic in calculations (BMR, calorie adjustments, streak computations) or database managers can cause silent regressions.
- Priority: High.
- Difficulty to test: Low. The codebase already uses a dependency container ([AppDependencies](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/LifeOSApp.swift#L10)), which makes it straightforward to mock services and inject mock repositories for unit tests.

---

*Concerns audit: 2026-06-19*
*Update as issues are fixed or new ones discovered*
