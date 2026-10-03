# UI/UX Phase 5: Ecosystem, Polish and Daily Use (first build)

This build implements the [Phase 5 plan](../05_Phase5_Ecosystem_Polish_Launch.md) on top of Phase 4. Everything here runs on a free Apple account. The installed profile on the test iPhone confirms that: `TimeToLive 7`.

## Status against gate D3

| # | Outcome | Status | Where |
|---|---|---|---|
| §9 | Backup, restore and the 7-day refresh reminder | **Done.** You → Data and backup: last backup line, Back up now (share sheet → Files), automatic daily backup keeping 7 (Files → On My iPhone → LifeOS → Backups), restore with preview ("This backup is from 3 Oct with 1,204 meals"), a safety backup before restoring, and CSV export (meals, workouts, weight). The expiry date is read from `embedded.mobileprovision`: a quiet banner in You 2 days before, it moves to Today on the last day, and there's one notification. Refresh help page included. API keys are never in backups. | `Experience/Core/BackupModel.swift`, `Adapters/BackupService.swift`, `Views/Ecosystem/DataBackupScreen.swift` |
| §5 | Siri / Shortcuts for the top 6 intents | **Done.** Calories left, Log a usual meal (confirms first), Add water, Log weight (with trend), Ask LifeOS (answered on device by the Phase 4 brain), Start gym session. Each has a snippet view, plus App Shortcuts phrases, short titles and icons. | `Views/Ecosystem/LifeOSIntents.swift`, `Adapters/IntentRuntime.swift` |
| §6 | 3D streak medals with AR Quick Look | **Done.** Six medals (First week, Month, Century, Ritual, Synced, Balance). The glass disc and accent metal rim are built in code (about 1.2k triangles, a 1024 px engraving), with a spin viewer, "View in your space" (USDZ → AR Quick Look), and a 2.5 s earning moment with one success haptic. You → Achievements shows progress. | `Core/AchievementsModel.swift`, `Adapters/AchievementStore.swift`, `Views/Ecosystem/MedalViews.swift` |
| §7 | Accessibility checklist | **First pass done.** Report: [accessibility-audit.md](accessibility-audit.md). Layouts reflow at accessibility text sizes; VoiceOver actions and summaries; contrast and Reduce Transparency fixes. The on-device VoiceOver walk-through is still to do. | `Views/Ecosystem/AccessibleLayout.swift` + fixes across screens |
| §2 | Apple Watch redesign | **Views done.** New theme mirroring the LX tokens, 2D orb glyph. Today (remaining kcal, training line, water bar, the Workout-app hint), Water (+1, Crown, glass fill, haptic per glass), Rest timer (full-screen ring, haptics at 10 s and 0 s), Weight (Crown, 0.1 kg, trend), Workout (big rep counter, set dots, elapsed time, "Keep this screen open", big Log set), Todos. | `LifeOS Watch App/Views/*` |
| §2 | Watch protein bar, "+N earned", Quick log | **Waiting** for the additive watch-contract fields (`proteinG`, `earnedKcal`, `presets`, `logPreset`), which the engineering session has written but not committed yet. | — |
| §2 | Complications + Smart Stack widget | **Waiting**: needs a watch widget extension target (project file). | — |
| §3 | iPhone widgets + StandBy | **Done.** One extension, `LifeOS Widgets` (`com.tanmay.LifeOS.widgets`), shares data through the App Group `group.com.tanmay.LifeOS`. **Today** (small = orb + kcal left, which is also the StandBy face; Lock Screen circular, rectangular and inline), **Today + log** (medium: 2 usual meals and +1 water as interactive buttons that run in the app, with a tick after logging), **Timeline** (large: macros + today's items). It refreshes on every write (debounced 400 ms), every 30 min, and at midnight. Tapping opens `lifeos://today`. | `LifeOSShared/*`, `LifeOS Widgets/TodayWidgets.swift`, `Adapters/WidgetBridge.swift` |
| §4 | Control Center controls (iOS 18) | **Done.** "Capture a meal" opens the Capture sheet; "Add a glass of water" logs without opening the app. | `LifeOS Widgets/LifeOSWidgetsBundle.swift`, `LifeOSShared/WidgetIntents.swift` |
| §4 | Live Activity (gym session + rest timer) | **Done.** Training → Start a live session. Lock Screen card with the current exercise, set dots and rest countdown, plus **Log set** / **Skip** buttons; Dynamic Island expanded, compact and minimal views. The rest length can be set (stored in `lx.gym.restSeconds`). | `LifeOSShared/LifeOSActivity.swift`, `LifeOS Widgets/LifeOSLiveActivity.swift`, `Adapters/GymLiveSession.swift` |
| §8 | Polish bug bash | Not started. It needs two weeks of daily use on the device. | — |

## Decisions

- **One extension per platform.** Intents live in the app target. Widgets, controls and the Live Activity share the single `LifeOS Widgets` extension (one extra App ID, within the free-account limit of 10 per 7 days). Widget buttons are `LiveActivityIntent`s, so `perform()` runs in the app process with the real stores; the extension only reads the snapshot. Code that only exists in the app is guarded with `#if !WIDGET_EXTENSION`.
- **The widget target was added without waiting for the engineering session**, as the user asked. Its project-file objects use the `5A…` ID prefix, and the merge is ours to do.
- **Restore closes the app.** Every manager keeps data in memory, so closing after the files are replaced guarantees nothing stale is written back. A safety backup ("LifeOS Before Restore …") is written first.
- **Medals are built in code**, not modelled in Blender: same look, no asset pipeline, and they export to USDZ on the device for AR Quick Look.
- **"Synced" counts training sessions logged in LifeOS** (iPhone or Watch) until per-source workout records (engineering WorkoutSession) land.
- **The Watch shows "kcal from training"** until `earnedKcal` arrives, because the eat-back share isn't on the Watch.
- **Info.plist** gained `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`, so Backups shows in Files.

## Tests

`cd Packages/LifeOSDesign && swift test --filter LifeOSExperienceTests` runs 47 tests, 15 of them new in Phase 5:
- Backup: round trip, rejects other files and newer versions, inclusion policy, once-a-day automatic backup, keep 7, CSV escaping.
- Refresh: expiry parsed from the profile envelope, the soon / last-day stages, copy, and notification timing.
- Medals: perfect runs, balanced weeks, progress text, and the first check celebrating only the latest medal.
