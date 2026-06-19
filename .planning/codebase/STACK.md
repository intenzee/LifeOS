# Technology Stack

**Analysis Date:** 2026-06-19

## Languages

**Primary:**
- Swift 5.0 - All application source code.

**Secondary:**
- None

## Runtime

**Environment:**
- iOS 17.6+ (Native Apple Platform runtime)

**Package Manager:**
- None - Vanilla Xcode project setup (no CocoaPods, Carthage, or Swift Package Manager packages are used).
- Lockfile: None

## Frameworks

**Core:**
- SwiftUI (Latest iOS 17 SDK) - Declarative UI layout and presentation.
- Combine - Functional reactive programming framework used for custom event publishing and state binding.

**Testing:**
- None (No unit or E2E testing targets are defined in the Xcode project).

**Build/Dev:**
- Xcode 15+ Build System - Compilation, packaging, code signing, and device deployment.

## Key Dependencies

**Critical:**
- HealthKit SDK - Querying and writing user fitness metrics (active energy burned, body mass, energy consumed, sleep analysis).
- UserNotifications SDK - Requesting authorization and scheduling local push reminders for checklist tasks.

**Infrastructure:**
- Foundation / URLSession - Sending async/await network requests to external OpenFoodFacts APIs.

## Configuration

**Environment:**
- User settings and preferences are stored locally via `UserDefaults` (using `@AppStorage` and raw property serialization). No external `.env` or configurations are required.

**Build:**
- `LifeOS/Info.plist` - Core app configurations, including permissions explanations for health access, camera, and photo library.
- `LifeOS/LifeOS.entitlements` - Code signing permissions enabling HealthKit integration.
- `LifeOS.xcodeproj/project.pbxproj` - Xcode build settings, compiler flags, and file grouping structures.

## Platform Requirements

**Development:**
- macOS with Xcode 15.0 or later.
- Apple Developer Account (required for code signing/entitlements on physical devices).

**Production:**
- iOS 17.6+ physical device or simulator.

---

*Stack analysis: 2026-06-19*
*Update after major dependency changes*
