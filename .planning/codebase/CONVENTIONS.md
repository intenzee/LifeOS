# Coding Conventions

**Analysis Date:** 2026-06-19

## Naming Patterns

**Files:**
- UpperCamelCase matching the primary type defined in the file (e.g., `HomeView.swift`, `PersistenceManager.swift`).

**Functions:**
- camelCase for all methods and function declarations (e.g., `fetchTodayCalories()`, `updateWaterCount()`).
- Verb-first naming style (e.g., `load()`, `save()`, `sync()`).

**Variables:**
- camelCase for all local variables, instance properties, and constants.
- Clear, descriptive names; avoid abbreviations (e.g., `dailyCalorieLimit`, `exerciseDaysPerWeek`).

**Types:**
- UpperCamelCase for all types: classes (`StreakManager`), structs (`UserProfile`), protocols (`DailyMetricsRepository`), and enums (`BiologicalSex`).
- Enum cases are camelCase (e.g., `case loseWeight`, `case metric`).

## Code Style

**Formatting:**
- 4-space indentation (standard Xcode formatting).
- Braces on the same line as the statement header (Allman/OTBS style).
- Standard SwiftUI view structuring:
  1. Properties (AppStorage, Environment, State, StateObject, ObservedObject).
  2. Initialization logic (`init`).
  3. Body computed property (`var body: some View`).
  4. Private view builders and helper elements.

**Clean Code Patterns:**
- Use `guard` statements at the beginning of methods to fail fast and reduce nested indentation layers.
- Prefer computed properties or `@ViewBuilder` helper functions over giant monolithic body layouts.

## Import Organization

**Order & Grouping:**
1. UI Framework: `import SwiftUI`
2. System Frameworks: `import Foundation`, `import Combine`, `import HealthKit`, `import UIKit`
- Blank lines between groups are not enforced. Alphabetical sorting within groups is not strictly required.
- No path aliases are defined (standard Xcode project targets).

## Error Handling

**Patterns:**
- Use structured concurrency (`async/await`) for network calls and health fetching.
- Use throwing functions (`throws`) when operations can fail, catching them at the View level to trigger fallback states (e.g., switching to manual barcode entry when OpenFoodFacts lookup throws).
- Use `guard let` and `if let` for safe optional unwrapping.

**Error Types:**
- Structs conform to `Error` (e.g., `enum APIClientError: Error`, `enum BarcodeFoodLookupError: Error`).

## Logging

**Framework:**
- Standard console outputs via Swift `print()` statements.

**Patterns:**
- Emojis prefixes are used to represent categories of logged events:
  - `🔔` for Local Reminders and Push Permission logs.
  - `✅` for successful actions (e.g., saving data to Apple Health).
  - `❌` for failures, catches, or authorization issues.
  - `🔥` for Calorie bank banking summaries.
  - `📅` for Date tracking logs.

## Comments

**When to Comment:**
- Document complex business logic, formulas, or metabolic metrics (e.g., Mifflin-St Jeor math, exercise MET values).
- Use `// MARK: - [Section]` comment syntax to split large source files (especially view bundles and manager segments).

**TODO Comments:**
- Standard inline `// TODO: description` tags.

---

*Convention analysis: 2026-06-19*
*Update when patterns change*
