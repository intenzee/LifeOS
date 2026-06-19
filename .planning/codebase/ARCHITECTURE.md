# Architecture

**Analysis Date:** 2026-06-19

## Pattern Overview

**Overall:** Native iOS Application using MVVM (Model-View-ViewModel) + Combine for reactive data binding.

**Key Characteristics:**
- Unidirectional Dependency Injection container ([AppDependencies](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/LifeOSApp.swift#L10-L42)).
- Reactive state updates using Combine publishers (`@Published`).
- Local-first architecture persisting state to the device via `UserDefaults`.
- Seamless background syncing with Apple HealthKit.

## Layers

**App / Entry Layer:**
- Purpose: Initialize application dependencies and set up the root view.
- Contains: Root App struct and the dependency container definition.
- Location: [LifeOSApp.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/LifeOSApp.swift)
- Depends on: View Layer (`ContentView`), Manager/Service Layer, Repository Layer.
- Used by: iOS System (App entry).

**View Layer:**
- Purpose: Render user interfaces, handle user layout interactions, and capture input.
- Contains: SwiftUI views, modifiers, custom drawing shapes, and layout keys.
- Location: `LifeOS/Views/` (e.g., [ContentView.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/ContentView.swift), [HomeView.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Views/HomeView.swift))
- Depends on: ViewModel Layer (`HomeViewModel`), Manager/Service Layer.
- Used by: iOS UI System.

**ViewModel / Controller Layer:**
- Purpose: Coordinate view state, process view actions, and format raw domain values.
- Contains: Screen-level state objects and interactive event handlers.
- Location: E.g., `HomeViewModel` within [HomeView.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Views/HomeView.swift#L50-L266).
- Depends on: Manager/Service Layer, Repository Layer.
- Used by: View Layer.

**Repository Layer:**
- Purpose: Abstract data storage details from screen-level view models.
- Contains: Repository protocols and local file-system/UserDefaults adapter classes.
- Location: [Repositories.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Data/Repositories.swift)
- Depends on: Manager Layer (`PersistenceManager`).
- Used by: ViewModel Layer.

**Manager / Service Layer:**
- Purpose: Execute domain operations, system integrations, and calculations.
- Contains: SDK controllers, BMR calculators, barcode lookups, and serialization systems.
- Location: `LifeOS/Managers/` and `LifeOS/Services/` (e.g., [HealthManager.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/HealthManager.swift))
- Depends on: Model Layer, external APIs, and iOS SDK frameworks.
- Used by: ViewModel Layer, View Layer.

**Model Layer:**
- Purpose: Represent domain entities, metrics, schedules, and structures.
- Contains: Swift types, structures, and helper enums.
- Location: `LifeOS/Models/` (e.g., [UserProfile.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Models/UserProfile.swift), [MealModels.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Models/MealModels.swift))
- Depends on: None.
- Used by: Manager Layer, Repository Layer, ViewModel Layer, View Layer.

## Data Flow

**Interactive Metric Syncing Flow (e.g., Logging Water):**
1. User taps the water card in [HomeView.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Views/HomeView.swift).
2. Taps trigger `HomeViewModel.updateWaterCount()`.
3. `HomeViewModel` writes the new count to `DailyMetricsRepository.saveWaterCount()`.
4. The repository invokes [PersistenceManager.saveWaterCount()](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/PersistenceManager.swift#L45-L48) to write data to `UserDefaults`.
5. View model updates its local `@Published var state` object, which triggers a SwiftUI refresh of the screen layout.
6. The state change on water triggers `HomeView`'s `.onChange(of: viewModel.state.waterCount)` handler.
7. This handler invokes `viewModel.syncStreaks()`, which calls `StreakManager.recordToday()`.
8. `StreakManager` evaluates all metrics (calories, water, gym, todo) and records the daily summary, saving it to disk and updating the UI streak indicators.

**State Management:**
- Persistent state: Saved locally via `UserDefaults` (using JSON data encoders).
- In-memory reactive state: Managed by managers conforming to `ObservableObject` using `@Published` properties. Screen views bind to these objects using `@ObservedObject` or `@StateObject`.

## Key Abstractions

**AppDependencies Container:**
- Purpose: Maintain and inject shared instances of repositories, managers, and API clients across view hierarchies.
- Examples: [AppDependencies](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/LifeOSApp.swift#L10)
- Pattern: Dependency Injection Container.

**DailyMetricsRepository / WeeklyLogRepository:**
- Purpose: Provide protocols that decouple storage details from view models, facilitating future database replacements (e.g., migrating to SwiftData or SQLite).
- Examples: Protocols in [Repositories.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Data/Repositories.swift).
- Pattern: Repository Pattern.

**ObservableObject Managers:**
- Purpose: Centralize database operations, state caching, and change broadcasting for specific domains (food database, workouts).
- Examples: [FoodDatabaseManager](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/FoodDatabaseManager.swift), [WorkoutDatabaseManager](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/WorkoutDatabaseManager.swift).
- Pattern: Shared Observer / Singleton.

## Entry Points

**App Launch:**
- Location: [LifeOSApp.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/LifeOSApp.swift)
- Triggers: OS launches the application executable.
- Responsibilities: Initialize `AppDependencies`, request user notification permissions, build `ContentView` and inject dependencies.

## Error Handling

**Strategy:** Propagate errors using standard Swift exceptions (`throws`), logging failures to debug streams using `print()`, and presenting fallbacks for API/Hardware failures.

**Patterns:**
- `URLSessionAPIClient` throws structured `APIClientError`.
- Views catch lookup errors inside scanner tasks and route users to manual inputs ([HomeView.swift:L771-L799](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Views/HomeView.swift#L771-L799)).
- Silently log system-level integration errors (HealthKit permissions, Push notification settings) via print indicators.

## Cross-Cutting Concerns

**App Theme & Styling:**
- App theme configuration (`AppTheme`) is saved in `UserDefaults`. Views use the [ThemePalette](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/AppTheme.swift#L68-L108) struct which detects the local environment context and dynamically adapts color properties across view frames.

**Notification Reminders:**
- Tasks use [NotificationService.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Services/NotificationService.swift) to register localized push alerts based on due date components.

---

*Architecture analysis: 2026-06-19*
*Update when major patterns change*
