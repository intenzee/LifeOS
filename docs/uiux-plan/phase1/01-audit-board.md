# Phase 1 · Audit board

**Phase 1 §3 deliverable.** This audit was done from the code, against the worktree baseline `ba282da` (dated 3 Oct 2026). File:line references are as of that commit.
**Still to do on device:** screenshots in light and dark, at default and at the largest text size. Xcode was not installed when this audit was written, so the owner should add screenshots at the next on-device session (see the [decision record](05-decision-record.md)).

Principles:
- **P1** Calm by default
- **P2** The app does the work
- **P3** Every number explains itself
- **P4** Tactile, not noisy
- **P5** Discreet by design

---

## 1. Summary metrics

| Metric | Count | Notes |
|---|---|---|
| Swift files under `LifeOS/` / Watch views | 43 / 8 | |
| Raw named colours (`.white .gray .black .orange .green .red .blue .yellow .purple .pink`) | **342** | `.white` 121, `.gray` 86, `.black` 63, `.orange` 24, `.green` 15, `.red` 12, `.blue` 10 |
| `Color(red:…)` literals | **79** | About 66 are in views; the rest are the palette definitions |
| Hard-coded white text (`.foregroundColor(.white)`) | **89** | Breaks light mode wherever the surface is not forced dark |
| Forced colour-scheme overrides | 5 | `QuickActionsMenu:58`, `FoodFlowViews:822`, `MealResultView:96`, `LearnedCorrectionsView:18`, `TabViews:584` |
| Hard-coded corner radii | **153** | 15 distinct values (2 to 32); `DesignSystem.Radius` is used 5 times |
| Fixed `.font(.system(size:))` (no Dynamic Type) | **190** | 165 on iOS, 25 on Watch; 4 are under 10 pt (8 pt at `WorkoutAndWeightViews:346,366`) |
| `@Environment(\.palette)` adoption | 0 | Every view builds its own `ThemePalette(colorScheme:)` |
| Emoji used as UI | 18 lines | `StreaksView` 12, `WeekAndDateViews` 6 |
| Custom centred or full-screen overlays | **~22** | See §4 |
| Native `.sheet` / `.fullScreenCover` / detents | 9 / 1 / 3 | |
| Accessibility modifiers | **0** | No `accessibilityReduceMotion` and no `dynamicTypeSize` checks either |
| Haptics | 14 call sites | 7 are in onboarding. None for meal logged, water +1, todo done or streak; `sensoryFeedback` used 0 times |
| `contentTransition(.numericText())` | 6 | Only 1 outside onboarding and profile |
| Files over 500 lines | 5 | `FoodFlowViews` 1448, `TabViews` 1175, `WorkoutAndWeightViews` 934, `HomeView` 915, `WeekAndDateViews` 722 |

**Raw colours by file (top 10):**

| File | Raw colours |
|---|---|
| `FoodFlowViews` | 120 |
| `TabViews` | 50 |
| `FitnessTools` | 49 |
| `WeekAndDateViews` | 37 |
| `StreaksView` | 36 |
| `MealResultView` | 28 |
| `WorkoutAndWeightViews` | 19 |
| `AppTheme` | 18 (palette) |
| `LearnedCorrectionsView` | 15 |
| `DesignSystemKit` | 12 (palette) |

---

## 2. Issue register

A1–A12 come from the master plan and the Phase 1 doc. A13 onwards were found in this audit.

| ID | Title | Severity |
|---|---|---|
| A1 | Colour has no fixed meaning; four different macro palettes are in use | High |
| A2 | The hero ring does not explain the budget, and over-budget amounts are hidden (`max(0, …)`) | High |
| A3 | Every card has the same weight; far more than three numbers above the fold | High |
| A4 | Floating "+" covers content; the tab-bar spacer (90 pt) is shorter than the bar (~106 pt) | Medium |
| A5 | About 22 centred or full-screen custom overlays instead of native sheets | High |
| A6 | Date navigation is duplicated (Home and the meal sheet) and force-unwrapped | Low |
| A7 | Empty states say "No items added" or "Waiting for input…" | Medium |
| A8 | No type scale; emoji used as icons | Medium |
| A9 | Default springs only; no haptics on core logging | Medium |
| A10 | Five view files are over 700 lines | High |
| A11 | Mint `#70EDC6` is 1.44:1 on white; white-on-mint buttons are about 1.4:1 | High |
| A12 | Status colours are hard-coded (`.orange`, `.blue`, `.green`) | Medium |
| **A13** | Light mode is broken: dark-only RGB surfaces, 89 `.white` text colours, shadows tuned for dark | **High** |
| **A14** | Dead controls: Home bell, Focus "ADD TASK", To-Do tile, food-search tabs, task location/flag, fake Log In | **High** |
| **A15** | Destructive actions with no confirmation or undo (food row, exercise, todo, correction) | Medium |
| **A16** | Alarm red and shaming copy or emoji for shortfalls ("❌ No high-protein meals yet"; a 0/4 day shown red) | Medium |
| **A17** | No accessibility semantics, fixed font sizes, no Reduce Motion path | **High** |
| **A18** | The water target differs across Home tile (8), drag pill (12) and streak logic (profile goal) | **High** |
| **A19** | Streak chips light up by score count, not by which goal was hit (hitting only water lights "Cal") | **High** |
| **A20** | Meal result: changing the unit keeps the base quantity, so macros can be multiplied by 26 | **High** |
| **A21** | Weight copy assumes a weight-loss goal; "Target 70" has no unit | Medium |
| **A22** | The calorie target can be silently replaced (profile save) or left unsaved (preset tap and dismiss) | Medium |
| **A23** | Icon-only tab bar with no labels; the dumbbell tab opens Streaks; Reminders cannot be reached | **High** |
| **A24** | Data is keyed by weekday name, not date; Home tiles ignore the selected date | Medium |
| **A25** | Protein is manual HIGH/LOW toggles and ignores logged grams | **High** |
| **A26** | Groq key setup sits inside the logging flow; weak disclosure that the photo leaves the device | Medium |
| **A27** | Task notes are discarded; "Urgent" is a 5-second reminder; the edit sheet is titled "New Task" | Medium |
| **A28** | Barcode scanner shows a silent black screen when the camera is unavailable or denied | Medium |
| **A29** | Rest timers are view-local and stop when the view closes (phone and Watch) | Medium |
| **A30** | Watch: a different mint from the phone, cramped preset row, kg only | Medium |
| **A31** | Design tokens exist but are barely adopted | High |
| **A32** | Dead code: `TodoWeekView`, `StatsView`, `SettingsView.ProfileView`, UITabBar appearance setup | Low |

A18, A19, A20, A22 and A27 are **functional bugs**, not visual ones. They are handed to engineering rather than waiting for the Phase 3 redesign.

---

## 3. Per-screen audit

### 3.1 Onboarding
Files: `OnboardingView.swift` (445 lines), `ProfileDetailsView.swift` (285).

| ID | Evidence | Problem | P | Sev | Fix direction |
|---|---|---|---|---|---|
| A11 | `OnboardingView:300,339,361` | Hero answers (64/56/52 pt) are mint, unreadable on light surfaces | P3 | High | `accentPrimary` token (light variant `#0B7A5E`) |
| P5 | `OnboardingView:23,31,40,48` | Asks sex and smoking with no privacy note and no welcome page | P5 | Med | Welcome and privacy step; "Stays on your iPhone" |
| P2 | `OnboardingView:6-18,402-414` | 12 mandatory steps, no skip, no HealthKit prefill | P2 | Med | 6 steps (Phase 3 §3.11), prefill from Health |
| A17 | `OnboardingView:342-369` | Slider-only input; imperial steps jump 1.1 lb | P3 | Low | Unit-native steps, `accessibilityValue` |
| A17 | `OnboardingView:120…324`, `:161-224` | Fixed sizes; no Reduce Motion variant | P4 | Med | `lxFont`, `lxAnimation` |
| A22 | `ProfileDetailsView:282` → `CalorieSettings:41-44` | Profile save silently overwrites a manual calorie target | P3 | Med | Keep the manual target; offer "Use recommended" |
| good | `OnboardingView:438-444` | Selection haptics and `numericText` | P4 | n/a | Reference pattern |

### 3.2 Home
Files: `HomeView.swift` (915), `HomeComponents.swift` (319), `ContentView.swift` (224).

| ID | Evidence | Problem | P | Sev | Fix direction |
|---|---|---|---|---|---|
| A2 | `HomeComponents:278-290`, `HomeView:120-126,360-362` | Budget = base + burned × % is never shown; tapping opens meal detail | P3 | High | Budget explainer chip and sheet |
| A2 | `HomeComponents:268` | `max(0, …)` hides how far over budget you are | P3 | Med | "120 over" in `status.over` |
| A1 | `HomeComponents:131-143` | Orange for a neutral "0/0 Done", water under target and Low Protein alike | P3 | High | Separate data and status tokens |
| A3 | `HomeView:352-382` | Ring + 3 sub-metrics + 3 cards + 6 tiles; same `glassCard(32)` everywhere | P1 | High | One hero answer, progressive disclosure |
| A4 | `HomeView:393-421`, `ContentView:127,161-168` | FAB over content; spacer 90 < bar ~106 | P1 | Med | Capture button in the tab bar; safe-area inset |
| A14 | `HomeView:743`, `:592-594`, `:258-259` | Bell, ADD TASK and To-Do tile do nothing | P2 | High | Wire up or remove |
| A7 | `HomeView:699-705` | "Waiting for input..." | P2 | Low | "Usual lunch? 520 kcal" |
| A13 | `HomeView:555,564,623,677`; `AppTheme:140-164` | `.white` on material; dark-tuned sheen and shadow in light mode | P1 | High | Semantic tokens; per-scheme elevation |
| A18 | `HomeView:368-382,226,266,297`; `HomeComponents:7,186,201,243` | Water goal is 8, 12 or the profile goal depending on where you look | P3 | High | Single source |
| A21 | `HomeComponents:94-96` | No unit; assumes a weight-loss goal | P3 | Med | Goal-aware copy |
| A25 | `HomeComponents:75,102,123` | "Low Protein" comes from manual toggles | P3 | High | From logged grams |
| A24 | `HomeView:94-106` vs `:353` | Changing the date updates the ring but not the tiles | P3 | Med | Key every tile by the selected date |
| A23 | `ContentView:148-192,152-153` | Unlabelled icons; dumbbell → Streaks | P1 | High | 5 labelled tabs (Phase 1 IA) |
| A32 | `ContentView:21,34-67` | UITabBar appearance set up but unused | n/a | Low | Delete |
| A9 | `HomeComponents:183-188` | No haptic on water | P4 | Med | `lxHaptic(.logged)` |

### 3.3 Quick actions
File: `QuickActionsMenu.swift` (233). The menu is 1 hero + 9 grid items + 4 meal bubbles.

| ID | Evidence | Problem | P | Sev | Fix direction |
|---|---|---|---|---|---|
| A5 | `:54-95` | Centred card over a forced-dark scrim, own ✕, no drag to dismiss | P1 | Med | Capture sheet with detents |
| A13 | `:185,220` | White text on glass that follows light mode | P1 | Med | Tokens |
| A23 | `:41-51` | Reminders missing, so `RemindersView` cannot be reached | P2 | Med | Entry point under You |
| A12 | `:34-39` | 4 `Color(red:)` meal tints | P3 | Low | Tokens |
| good | `:16-23,124,138-143` | Meal type chosen from time of day; long-press haptic | P2 | n/a | Keep (Phase 3 §3.2) |

### 3.4 Food flows
Files: `FoodFlowViews.swift` (1448), `MealResultView.swift` (491), `LearnedCorrectionsView.swift` (194).

| ID | Evidence | Problem | P | Sev | Fix direction |
|---|---|---|---|---|---|
| A5 | `FoodFlowViews:28-102` | Meal detail is a centred card; ✕ below the title | P1 | High | Native sheet |
| A13 | `FoodFlowViews:98…1445` | Dark RGB surfaces and 33 `.white` text colours regardless of theme | P1 | High | Tokens |
| A1 | `FoodFlowViews:82-84,1386-1392`; `MealResultView:206-208`; `FitnessTools:245-247` | Four different macro palettes | P3 | High | `data.protein/carbs/fat` |
| A16 | `FoodFlowViews:84` | Fat shown in alarm red | P5 | Med | `data.fat` |
| A7 | `FoodFlowViews:137-152` | "No items added · 0 cal" | P2 | Med | Likely preset |
| A15 | `FoodFlowViews:179-185` | One-tap delete | P5 | Med | Swipe + undo toast |
| A14 | `FoodFlowViews:272-276,366-370` | Recent and Favorites tabs are `Button(action: {})` | P2 | High | Implement or remove |
| P2 | `FoodFlowViews:539-552` | Custom food saves empty fields at 0 kcal | P2 | Med | Validate |
| A11 | `FoodFlowViews:553…1419` | White on mint | P3 | High | `onAccent` |
| A28 | `FoodFlowViews:714-727` | Scanner shows a silent black screen | P2 | Med | Permission state + "Enter code" |
| A26 | `FoodFlowViews:842-870,1008-1075` | Key setup sits inside the logging flow; weak disclosure | P5 | Med | Key in Settings; source badge before Analyse |
| P2 | `FoodFlowViews:897-936` | Separate Analyse tap after taking the photo | P2 | Low | Auto-analyse |
| A20 | `MealResultView:86,234-237,396-399` | Unit change keeps the base quantity, so macros ×26 | P3 | High | Convert or reset the base |
| good | `MealResultView:162-167,476-490` | Source badge ("On-device estimate / Learned / AI") | P5 | n/a | Becomes component 26 |
| good | `LearnedCorrectionsView:43-53,115-134` | Confirmation dialog and a helpful empty state | P2 | n/a | Reference |
| A5 | `PortionSizeSelectorView` `FoodFlowViews:1299-1429` | Centred card; defaults to 100 g instead of the label serving | P2 | Med | Sheet; label serving |

### 3.5 Week views
File: `WeekAndDateViews.swift` (722).

| ID | Evidence | Problem | P | Sev | Fix direction |
|---|---|---|---|---|---|
| A16/A8 | `:377-385,483` | Emoji in status copy (🎯💪⚠️🔴❌) | P5 | Med | Calm copy, SF Symbols |
| A16/A1 | `:360-366,433-470,564-577` | Red, orange and blue used as a rating scale | P5 | Med | Single-hue intensity ramp |
| A25 | `:542-546,667-676` | Manual HIGH/LOW protein | P2 | High | Computed from logs |
| A24 | `:204-221` | Keyed by weekday name; past weeks are overwritten | P3 | Med | Date-keyed history |
| A5 | `HomeView:813-822`, `:295-322` | Full-screen overlay with a custom back button | P1 | Med | Nutrition tab (Phase 3 §3.8) |
| A17 | `:343-346` | 9 pt text | P1 | Med | Type tokens |
| A32 | `:3-193` | `TodoWeekView` has no call sites | n/a | Low | Delete |

### 3.6 Training and tools
Files: `WorkoutAndWeightViews.swift` (934), `FitnessTools.swift` (431).

| ID | Evidence | Problem | P | Sev | Fix direction |
|---|---|---|---|---|---|
| P3 | `WorkoutAndWeightViews:48-52,204,241-250` | "Intensity %" = kcal / 450, with the cap unexplained | P3 | Med | Show kcal + "how computed" |
| A5 | `HomeView:823-833`; `:77-141,544,650` | Full-screen overlay; tapping the background dismisses; custom popups | P1 | Med | Training tab + sheets |
| A4 | `:113-131` | A second, differently styled FAB | P1 | Low | Capture button |
| A13 | `:206,522,680,830,855` | White numbers in light mode | P1 | High | Tokens |
| A15 | `:482-491` | ✕ deletes immediately | P5 | Med | Swipe + undo |
| A17 | `:200,346,366` | 8–9 pt text; 60 fixed sizes | P1 | Med | Type tokens |
| A21 | `:886-908` | "Target achieved!" is wrong for weight-gain goals | P3 | Med | Goal-aware copy |
| A5/A13 | `FitnessTools:6-30` | Five tools in a `black 0.9` overlay | P1 | High | Native sheets |
| A29 | `FitnessTools:92-105` | Rest timer dies when the view closes | P2 | Med | End-date model + notification |
| A1 | `FitnessTools:245-254,338,372` | A fourth macro palette; ad-hoc colour "bridge" | P3 | Med | Tokens |

### 3.7 Streaks
File: `StreaksView.swift` (341).

| ID | Evidence | Problem | P | Sev | Fix direction |
|---|---|---|---|---|---|
| A19 | `:103-106` vs `:304-307` | Chips light up by count | P3 | High | Bind each chip to its `hit*Goal` |
| A8/A16 | `:54,103-176,230,318` | 12 emoji used as icons | P1 | Med | SF Symbols |
| A16 | `:227,248,315` | 0/4 days shown red | P5 | Med | Neutral→accent ramp |
| P3 | `:216-254` | 30 unlabelled, untappable cells | P3 | Med | Tap a day for its breakdown |

### 3.8 Todo
File: `TabViews.swift` lines 1–605.

| ID | Evidence | Problem | P | Sev | Fix direction |
|---|---|---|---|---|---|
| A24 | `:11,39-48,208,235` | Keyed by weekday; fixed 520 pt pager with nested scrolling | P1 | Med | Date-based list |
| A15 | `:259-263,291-295` | Instant delete | P5 | Med | Swipe + undo |
| A27 | `:450,495`→`:61,297`; `:328,351,399`; `:74,417` | Notes dropped; "Urgent" = 5 s; edit sheet titled "New Task" | P2 | Med | Fix |
| A14 | `:486-487` | Location and flag icons do nothing | P2 | Med | Remove |
| A13 | `:413,540,584` | Dark RGB + forced `.colorScheme(.dark)` | P1 | Med | Tokens |

### 3.9 Profile and settings
File: `TabViews.swift` lines 607–1175.

| ID | Evidence | Problem | P | Sev | Fix direction |
|---|---|---|---|---|---|
| A14 | `:609-611,659-670` | Fake "LifeOS User / user@example.com" login | P5 | Med | Remove; on-device privacy card |
| A22 | `:1101-1104,1038-1041,997-999` | Tapping a preset and dismissing leaves the target unsaved | P3 | Med | Persist on select |
| A5 | `:787-789,993-1056` | Centred card inside a sheet | P1 | Med | Push |
| P3 | `:926-950` | "Metabolic Intensity" jargon; the percentage is never shown | P3 | Med | "Eat back 50% of activity" |
| good | `:1061-1099` | `CalorieGoalCalculator.explanation` | P3 | n/a | Reuse in the budget explainer |
| A32 | `:724-734,863-881` | Placeholder screens with no call sites | n/a | Low | Delete |

### 3.10 Apple Watch
Files: `LifeOS Watch App/Views/` (8 files, 592 lines).

| ID | Evidence | Problem | P | Sev | Fix direction |
|---|---|---|---|---|---|
| A30 | `WatchTheme:5` vs `AppTheme:100` | The Watch uses a different mint from the phone | P3 | Med | Generate from the same token source |
| P3 | `WatchDashboardView:38-45` | Watch shows consumed / limit; the phone shows remaining | P3 | Med | Same hero metric on both |
| A30 | `WatchRestTimerView:31-43` | 5 presets in one row at 12 pt (check on 41 mm) | P1 | Med | Crown picker |
| A29 | `WatchRestTimerView:10,62-75` | View-local timer | P2 | Med | End-date model |
| A30 | `WatchWeightView:26,35,67` | kg only; defaults to 70 | P3 | Low | Units from snapshot |
| A17 | 25 fixed sizes | No Dynamic Type | P1 | Med | Watch text styles |

---

## 4. Presentation inventory

**Custom overlays.** 15 entry points, about 22 overlays in total. Each has its own close control, no drag to dismiss and no system back gesture. On Home they are driven by 16 `show*` booleans (`HomeView:11-28`).

1. `QuickActionsMenu` (`:54`), including the meal-bubble sub-overlay (`:174`)
2. `MealDetailView` (`FoodFlowViews:29`)
3. `FoodSearchView` (`:225`)
4. `CustomFoodView` (`:460`)
5. `BarcodeUnrecognizedPromptView` (`:577`)
6. `BarcodeScannerView` (`:645`)
7. `AIMealScanView` (`:819`)
8. `PortionSizeSelectorView` (`:1300`)
9. `MealResultView` (`:93`)
10. `FoodWeekView` (`WeekAndDateViews:262`)
11. `TodoWeekView` (unused)
12. `GymWeekView`, plus its 2 popups
13. `WeightPickerView`
14. `ToolScaffold`, which hosts 5 tools
15. `SettingsView.calorieLimitPicker`

**Native presentations** (9 sheets, 1 full-screen cover, 1 alert, 1 confirmation dialog): the Profile hub, date picker, add/edit task, reminder picker, Settings, Health Profile ×2, image picker, Learned corrections.

## 5. Numeric safety (NaN and divide-by-zero)

- **Guarded:**
  - `RingGauge`, `LinearProgress` and `CaloriesRing.progress`
  - Tile progress, rest timers and macros
  - Watch snapshot and `RingView`
  - The Watch set ring
- **Residual low risk:**
  - `Int(limit)` at `HomeComponents:268` and `Int(...)` at `WorkoutAndWeightViews:51` trap if a stored value is non-finite.
  - `LifeOrbState` already clamps and guards non-finite input (`LifeOrb.swift`).

## 6. Hotspots, ranked

1. `FoodFlowViews.swift`
2. `HomeView.swift` + `HomeComponents.swift`
3. `TabViews.swift`
4. `StreaksView.swift`
5. `WorkoutAndWeightViews.swift`
6. `MealResultView.swift`
7. `WeekAndDateViews.swift`
8. `FitnessTools.swift`
9. `ContentView.swift`
10. `WatchTheme.swift`

## 7. Migration list (input to Phase 2 §1, last criterion)

| File | Replace |
|---|---|
| `Managers/AppTheme.swift` | Point `ThemePalette` and `GlassSurface` at `LXTheme` roles; light accent and on-accent colour; per-scheme sheen and shadow |
| `Managers/DesignSystemKit.swift` | `Radius` → `LX.Radius`; retire `\.palette` in favour of `\.lxTheme`; `MetricTile`/`SectionHeader` → LX components |
| `ContentView.swift` | 5-tab labelled Liquid Glass bar with a Capture button (`LXTabBar`); safe-area inset; delete the UITabBar setup |
| `Views/HomeView.swift` | `enum HomeSheet` + `.sheet(item:)` instead of 16 flags; Today layout (Phase 3 §3.1) |
| `Views/Components/HomeComponents.swift` | `LifeOrb` + budget explainer; one water goal; protein from grams |
| `Views/Components/QuickActionsMenu.swift` | Capture sheet |
| `Views/FoodFlowViews.swift` | Split into 6 files; tokens; undo toasts; permission states; move the key to Settings |
| `Views/MealResultView.swift` | Fix A20; AI proposal card |
| `Views/WeekAndDateViews.swift` | Nutrition tab; remove emoji and red; delete `TodoWeekView` |
| `Views/WorkoutAndWeightViews.swift` | Training tab; native sheets; type tokens |
| `Views/Tools/FitnessTools.swift` | Native sheets; end-date timer |
| `StreaksView.swift` | Fix A19; SF Symbols; neutral ramp |
| `Views/Tabs/TabViews.swift` | Split into Todo / Profile / Settings; fix A22, A27 and A14 |
| `Views/Onboarding/*` | 6-step orb onboarding (Phase 3 §3.11) |
| Watch `WatchTheme.swift` | Generated from `design/tokens` |
