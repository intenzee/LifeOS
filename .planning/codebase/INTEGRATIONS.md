# External Integrations

**Analysis Date:** 2026-06-19

## APIs & External Services

**Food Barcode Lookup:**
- OpenFoodFacts API - Looking up commercial food items and their macronutrient distribution using a scanned barcode string.
  - SDK/Client: REST API via `URLSession` wrapper in [BarcodeFoodLookup.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Services/BarcodeFoodLookup.swift).
  - Auth: Unauthenticated (requires custom `User-Agent: LifeOS/1.0 (support@lifeos.app)` header).
  - Endpoints used: `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json`

## Apple HealthKit Integration

**Health Tracking:**
- Apple HealthKit SDK - Bidirectional sync of fitness, sleep, and nutrition data.
  - SDK/Client: System `HealthKit` framework via [HealthManager.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/HealthManager.swift).
  - Auth: Direct authorization request inside the app to read and write specific data types.
  - Data Types Read:
    - `.dietaryEnergyConsumed` (Dietary calories consumed)
    - `.bodyMass` (User body weight)
    - `.activeEnergyBurned` (Workout calories burned)
    - `.sleepAnalysis` (Sleep duration logs)
  - Data Types Written:
    - `.bodyMass` (Saved when user inputs weight in dashboard)
    - `.activeEnergyBurned` (Logged when completing gym/cardio routines)

## Data Storage

**Local Settings & Data:**
- iOS `UserDefaults` - Flat-file key-value system for storing application state and historical logs.
  - Client: [PersistenceManager.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/PersistenceManager.swift), [FoodDatabaseManager.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/FoodDatabaseManager.swift), and [WorkoutDatabaseManager.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/WorkoutDatabaseManager.swift).
  - Serializer: `JSONEncoder` / `JSONDecoder` for array and dictionary types.
  - Key-Value Schemas:
    - `userProfile` -> `UserProfile` struct
    - `waterCount_YYYY-MM-dd` -> `Int`
    - `targetWeight` -> `Double`
    - `currentWeight` -> `Double`
    - `weekFoodLog` -> `[String: DayMeals]`
    - `weekTodoList` -> `[String: [TodoItem]]`
    - `weekGymLog` -> `[String: DayWorkout]`
    - `recentFoods` -> `[FoodItem]`
    - `favoriteFoods` -> `[FoodItem]`
    - `customFoods` -> `[FoodItem]`
    - `allDailyFoodLogs` -> `[String: DailyFoodLog]`
    - `allDailyWorkouts` -> `[String: DayWorkout]`
    - `dailySummaries` -> `[String: DailySummary]` (Streaks tracking data)

## Authentication & Identity

**Mock Authentication:**
- Guest Profile - Local-only mockup of user authentication.
  - Implementation: SwiftUI `@AppStorage` properties in [TabViews.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Views/Tabs/TabViews.swift).
  - Keys: `profileIsLoggedIn`, `profileDisplayName`, `profileEmail`.
  - No external auth providers (like Firebase or Sign In with Apple) are currently configured.

## Monitoring & Observability

**Console Output:**
- Native Swift print statements - Log activity updates and errors to Xcode output stream.
  - Output patterns: Standard strings tagged with visual status emojis:
    - `🔔` for notifications updates
    - `✅` for success operations
    - `❌` for errors/failures
    - `🔥` for calorie bank adjustments
  - No external monitoring SDKs (like Sentry or Firebase Crashlytics) are integrated.

## CI/CD & Deployment

**Local Compilation:**
- Local Xcode Build - Building directly onto local simulators or provisioned developer devices.
- Apple Developer Program - Uses automatic provisioning profiles for code signing entitlements required for HealthKit and push alerts.

## Environment Configuration

**Device Storage Configuration:**
- No environment files (like `.env` or configurations) exist.
- All configurations are loaded dynamically from settings saved in `UserDefaults` via:
  - [CalorieSettings.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/CalorieSettings.swift) (banks calorie percentage offset, default `0.5`).
  - [CalorieLimitSettings](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/CalorieSettings.swift) (default `2200` calories baseline).
  - [SmokingSettings](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/CalorieSettings.swift) (boolean indicating user lifestyle category).

## Local Notifications

**Task Alerts:**
- Apple UserNotifications SDK - Scheduling time-based local reminders for items in the checklist.
  - SDK/Client: `UNUserNotificationCenter` in [NotificationService.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Services/NotificationService.swift).
  - Trigger: Calendar-based push alerts (repeats disabled) using target deadline components.
  - Cancel Mechanism: `removePendingNotificationRequests` using the identifier `TodoItem.id.uuidString`.

---

*Integration audit: 2026-06-19*
*Update when adding/removing external services*
