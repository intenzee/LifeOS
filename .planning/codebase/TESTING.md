# Testing Patterns

**Analysis Date:** 2026-06-19

## Test Framework

**Runner:**
- None. There are no automated test targets (XCTest/Swift Testing) configured in [LifeOS.xcodeproj](file:///Users/tanmayroy/Downloads/LifeOS-main/LifeOS.xcodeproj/project.pbxproj).

**Assertion Library:**
- None.

**Run Commands:**
- Automated test execution commands do not apply. `Cmd + U` in Xcode will report that the project contains no test targets to execute.

## Test File Organization

**Location:**
- No test folder or files exist in the repository workspace.

**Structure:**
- All files in the repository represent application code or resource assets.

## Verification Approach

Since automated testing is absent, all features must be verified via **Manual Developer Testing** on the iOS Simulator or a physical device.

### Manual Verification Checklist

**1. First-Launch Onboarding:**
- Trigger: Delete app container or reset simulator files.
- Steps:
  1. Open the app and verify the welcome splash page appears.
  2. Input medical parameters (Age, Weight, Height, Sex).
  3. Select goals and lifestyle preferences.
  4. Submit and verify that:
     - The onboarding view is dismissed with spring animation.
     - Correct BMR/TDEE target calculation is stored in `UserDefaults` and displayed in the home calorie ring.
     - Weight targets are initialized.

**2. Hydration Logging:**
- Steps:
  1. Locate the Water Card on the dashboard.
  2. Tap card and verify count increments.
  3. Long-press/scroll to adjust glasses, verifying count updates in real-time.
  4. Check that perfect day streak progress updates dynamically if water target is met.

**3. Fitness & Weight logging (HealthKit Sync):**
- Prerequisites: iOS Settings -> Health -> LifeOS permissions must be granted.
- Steps:
  1. Click Profile icon -> Health Profile -> Edit details. Save weight.
  2. Open the Apple Health app, search for "Weight/Body Mass", and verify the new entry was recorded successfully.
  3. Navigate to Gym Week View, add exercises, log sets.
  4. Verify workout calories calculate based on MET and sync to Apple Health.

**4. Barcode Food Lookup:**
- Steps:
  1. Tap Quick Actions (floating plus) -> scan barcode.
  2. Simulate camera or point at an item barcode.
  3. If recognized: Verify title, serving size, and nutrition details populate, and saving logs it under the current day.
  4. If unrecognized: Verify the alert popup appears offering a manual entry form. Save manual details and verify it logs.

**5. Todo Checklist:**
- Steps:
  1. Swipe to Todo Tab.
  2. Click Add, enter title, set reminder preset. Save.
  3. Verify task appears under the selected day list.
  4. Toggle checkmark, verify checkmark updates state and perfect day streak progress segments increment.
  5. Delete task, verify task disappears from list.

**6. Settings & Theme Customization:**
- Steps:
  1. Tap Profile -> Settings.
  2. Toggle between System/Light/Dark themes.
  3. Verify color updates occur across all layers (dashboard surface, scrim, liquid custom tab bar).
  4. Modify Calorie Bank percentage and verify that logged workouts calculate calorie adjustments based on updated multiplier.

---

*Testing analysis: 2026-06-19*
*Update when automated test targets are introduced*
