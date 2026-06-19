# Codebase Structure

**Analysis Date:** 2026-06-19

## Directory Layout

```
LifeOS/
├── LifeOSApp.swift                  # App lifecycle entry point
├── ContentView.swift                # Root view container with floating tab bar
├── StreakManager.swift              # Streaks manager and summaries calculator
├── Info.plist                       # Permissions & app capabilities plist
├── LifeOS.entitlements              # Apple HealthKit entitlement configs
├── Models/                          # Core domain structures
│   ├── UserProfile.swift            # Onboarding settings, MSJ equation, units
│   └── MealModels.swift             # Meal, workout, food item, todo models
├── Managers/                        # Persistent storage and system SDK sync engines
│   ├── AppTheme.swift               # Styling rules, design tokens, color palette
│   ├── CalorieSettings.swift        # Calorie limits, bank percentages, smoking settings
│   ├── FoodDatabaseManager.swift    # Persistent daily food logger & favorites cache
│   ├── WorkoutDatabaseManager.swift # Daily workout scheduler & treadmill tracker
│   ├── HealthManager.swift          # HealthKit permissions & read/write queries
│   └── PersistenceManager.swift     # Raw UserDefaults serialization
├── Services/                        # Calculation & integration modules
│   ├── CalorieCalculator.swift      # Metabolic intensity & MET calculation services
│   ├── CalorieGoalCalculator.swift  # Mifflin-St Jeor daily budget generator
│   ├── BarcodeFoodLookup.swift      # OpenFoodFacts API parser
│   └── NotificationService.swift    # Local push notification scheduler
├── Data/                            # Repository and network clients
│   ├── Repositories.swift           # Concrete local repositories for view models
│   └── APIClient.swift              # Protocol-based URLSession request client
└── Views/                           # SwiftUI Layout templates
    ├── HomeView.swift               # Dashboard layout
    ├── FoodFlowViews.swift          # Food logging screens & barcode scanners
    ├── WeekAndDateViews.swift       # Weekly calendar and timeline sheets
    ├── WorkoutAndWeightViews.swift  # Workout entry forms and weight trackers
    ├── Tabs/                        # Bottom navigation destination tabs
    │   └── TabViews.swift           # Todo tab, Settings view, profile sheets
    ├── Onboarding/                  # First-launch onboarding flows
    │   ├── OnboardingView.swift     # Welcome splash pages
    │   └── ProfileDetailsView.swift # Medical stats form (BMR calculations)
    └── Components/                  # Modular view widgets
        ├── HomeComponents.swift     # Calorie rings, stats grid cards
        ├── QuickActionsMenu.swift   # Floating plus action context sheet
        └── ScrollOffsetPreferenceKey.swift # Scroll offset measurement keys
```

## Directory Purposes

**Models/**
- Purpose: Define data schemas and domain objects representing fitness goals, exercises, ingredients, and checklists.
- Contains: `UserProfile.swift`, `MealModels.swift`.
- Key files: [MealModels.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Models/MealModels.swift) - specifies the base structures (`TodoItem`, `FoodItem`, `DayWorkout`) used across all states.

**Managers/**
- Purpose: Handle data synchronization, device caching, and communication with system frameworks (Apple HealthKit).
- Contains: Swift manager classes conformed to `ObservableObject`.
- Key files: [HealthManager.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/HealthManager.swift) - queries sleep, calories, weight, and writes workouts.

**Services/**
- Purpose: Wrap API payloads, compute complex formulas (e.g. BMR targets), and schedule triggers.
- Contains: Stateless calculators and system client wrappers.
- Key files: [BarcodeFoodLookup.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Services/BarcodeFoodLookup.swift) - queries OpenFoodFacts database.

**Views/**
- Purpose: Present UI elements and observe ViewModel changes.
- Contains: SwiftUI Views grouped by feature folders.
- Subdirectories: `Tabs/`, `Onboarding/`, `Components/`.

## Key File Locations

**Entry Points:**
- `LifeOS/LifeOSApp.swift` - Standard main entry point.
- `LifeOS/ContentView.swift` - Application wrapper routing to Onboarding or Dashboard TabView.

**Configuration:**
- `LifeOS/Info.plist` - iOS permissions keys.
- `LifeOS/LifeOS.entitlements` - Security entitlement keys.

**Core Logic:**
- `LifeOS/StreakManager.swift` - Streak rules and scorecard calculations.
- `LifeOS/Services/CalorieCalculator.swift` - Metabolic calculations.

**Testing:**
- None. (No unit or E2E tests exist in the workspace).

**Documentation:**
- `README.md` - Developer deployment guides.

## Naming Conventions

**Files:**
- UpperCamelCase for all `.swift` source files.
- Extensions are grouped under matching names or subfolders.

**Directories:**
- UpperCamelCase for feature components (e.g., `Components/`, `Onboarding/`).
- Pluralization for domain-level containers (`Models/`, `Managers/`, `Services/`, `Views/`).

## Where to Add New Code

**New Dashboard Widget / Tab:**
- UI View: Create file under `LifeOS/Views/Tabs/` or `LifeOS/Views/Components/`.
- Tab Routing: Register the tab case in [ContentView.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/ContentView.swift#L104-L145).

**New Integration / Manager:**
- Core Adapter: Create under `LifeOS/Managers/` or `LifeOS/Services/`.
- Dependency Registration: Add to `AppDependencies` in [LifeOSApp.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/LifeOSApp.swift#L10-L42).

**New Data Type:**
- Model struct: Define in `LifeOS/Models/` or create a new file in `Models/`.
- Serialization: Add encoder/decoder blocks in [PersistenceManager.swift](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS/Managers/PersistenceManager.swift) and coordinate with domain database managers.

---

*Structure analysis: 2026-06-19*
*Update when directory structure changes*
