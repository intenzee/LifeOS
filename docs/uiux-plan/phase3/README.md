# UI/UX Phase 3: Core Experience (first build)

This build implements the [Phase 3 plan](../03_Phase3_Core_Experience.md) on top of design system v1 (Phase 2). All screens run on your real data through one adapter. The classic UI is still there: switch it in **You → New layout**, or **Settings → New layout** from the classic screens.

## What's built

| # | Screen | Status | Where |
|---|---|---|---|
| — | 5-tab shell (Today · Nutrition · **Capture** · Training · You) | Done. Labelled tabs, a raised Capture button, and the last row clears the tab bar (A4) | `Experience/Views/ExperienceRootView.swift` |
| 3.1 | Today | Done. Orb with the number below it, budget chip, Next up, 4 metric tiles, timeline with source badges, plan (3 todos + streak), and past-day "Viewing … Back to today" | `TodayScreen.swift` |
| 3.2 | Capture sheet | Done. **Say** (live on-device transcript, ripple, stops after 1.5 s of silence), **Type**, preset chips ranked by time of day, quick water, quick weight, and routes to Photo, Scan and Search. Meal type is automatic but editable | `CaptureSheet.swift`, `Adapters/SpeechCapture.swift` |
| 3.3 | Proposal card | Done. Items with confidence (low confidence first, "Check portion"), totals, macro bar, inline edit that recalculates, **Log**, "Save as preset", and a toast "Logged. 412 kcal, 31 g protein." with Undo for 4 s | `CaptureSheet.swift` |
| 3.8 | Nutrition | Done. Day scroller, 120 pt orb, stacked macro ring with grams left, meal sections with "+", empty meals suggest the usual (A7), 30-day heat map (tap to open a day), My Meals | `NutritionScreen.swift` |
| 3.9 | Training | Partial. "Effect on today", Apple Health activity and steps, real sessions only for the last 7 days (no repeated treadmill rows), and logging via the classic gym sheet | `TrainingScreen.swift` |
| 3.10 | Budget explainer | Done. Maintenance → goal → base → earned → budget → eaten → remaining, where each line taps open to its explanation; eat-back 25/50/75/100% | `BudgetExplainerSheet.swift` |
| — | You | Done. Goal, weight, target, streaks, today's todos, and doors to Profile, Settings, Todos, Streaks and the layout switch | `YouScreen.swift` |

Photo (3.5), barcode (3.6) and portion (3.7) reuse the proven classic flows unchanged. Logging from them goes through the new store, so badges, the toast and Undo still work.

## How it fits together

```
LifeOS/Experience/
  Core/        pure Swift, unit-tested in Packages/LifeOSDesign (LifeOSExperienceTests)
    BudgetMath.swift      ExperienceBudget, lines + derivation, meal slot, copy rules
    FoodResolver.swift    parsed item → kcal: your foods → South Asian staples → bundled table
    TimelineModel.swift   timeline ordering, Next-up rules
  Adapters/
    ExperienceStore.swift the only bridge to the existing managers
    CaptureEngine.swift   AIGateway foodTextParse → DeterministicFoodParser fallback → resolver
    SpeechCapture.swift   SFSpeechRecognizer + AVAudioEngine (on-device when supported)
  Views/       the screens above + LegacyCaptureHost (classic photo/barcode/search)
```

**Same numbers everywhere.** `ExperienceStore` uses the same budget formula as the classic Home and the Watch: limit + logged-workout kcal × eat-back share. Every write ends in `afterWrite()`, which does what `HomeViewModel.syncStreaks()` does: it sends the Watch snapshot and records today's streak summary.

**Tests:** `cd Packages/LifeOSDesign && swift test --filter LifeOSExperienceTests` runs 16 tests. They cover the plan's worked example (1,571 + 222 − 1,153 = 640 left), over-budget copy, NaN safety, the derivation and safe-minimum floor, roti/chai resolution, "tea" never becoming "Steak", gram scaling, preset ranking, timeline order and the Next-up rules.

## Decisions and known gaps

- **Activity in the budget** still uses the MET estimate from logged sets, matching Home and the Watch. Apple Health active energy is shown next to it for reference. Switching the budget to Health energy is owned by the Health spec (CAL-07).
- **Eat-back 0%** isn't offered, because `CalorieSettings` reads a saved 0 back as 50%.
- **Says first** only when speech permission already exists. The sheet never shows a permission prompt the moment it opens; tapping the mic asks.
- **Sources** (Voice, Preset, Photo) are remembered locally (`lx.experience.sources.v1`, capped at 500), because `FoodItem` has no source field.
- **Not yet built:**
  - Full presets / My Meals editor (3.4): aliases, scaling UI, auto-log.
  - Redesigned camera, barcode and nutrition-label screens (3.5–3.7).
  - Watch-workout list from HealthKit (3.9).
  - Onboarding (3.11).
  - Meal-to-orb fly animation.
  - "Tell me what's different" refine on typed or spoken meals (it still exists in the photo flow).
- **Info.plist** gained `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` for Say.
