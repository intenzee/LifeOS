# Phase 3: Core Experience

**Weeks:** 6–12
**Owners:** product designer (lead), motion/3D designer (transitions, meal lift, orb moments), iOS UI engineer
**Depends on:** design system v1 (Phase 2). Engineering dependencies: Apple Watch / HealthKit sync, food presets and voice parsing, photo analysis (the engineering specs for these come from the engineering teams).

This phase redesigns the screens people use every day: Today, Capture (food logging by voice, text, photo, barcode and presets), Nutrition, Training with Apple Watch workouts, the calorie budget explanation, and onboarding. The aim: logging a usual meal takes one tap or one sentence, and every number explains itself.

---

## 1. Outcomes and success measures

| Outcome | Measured over one week of your own daily use (optionally plus 2–3 friends trying it on your phone) |
| --- | --- |
| Logging a saved preset is effortless | 2 taps or fewer, under 5 seconds |
| Logging by voice works first time | 8 of 10 voice logs need no correction to items |
| Photo logging is fast and trusted | Under 15 s from opening the camera to saved; you accept the estimate without edits most of the time |
| The budget is understood | At a glance you can say how many calories are left and why it changed after a workout |
| Onboarding is quick | A fresh install (after deleting the app) gets to the Today screen in under 2 minutes |

---

## 2. Screen inventory and order

| # | Screen | Replaces (current file) | Week |
| --- | --- | --- | --- |
| 3.1 | Today | `HomeView.swift`, `HomeComponents.swift` | 6–7 |
| 3.2 | Capture sheet | `QuickActionsMenu.swift` and the floating "+" | 6–8 |
| 3.3 | AI proposal card and confirmation | Parts of `MealResultView.swift` | 7–8 |
| 3.4 | Presets ("My Meals") | Favourites and custom foods in `FoodFlowViews.swift` | 8 |
| 3.5 | Camera and meal result | `AIMealScanView`, `MealResultView.swift`, `ImagePicker` | 8–9 |
| 3.6 | Barcode and nutrition label | `BarcodeScannerView`, `BarcodeUnrecognizedPromptView` | 9 |
| 3.7 | Food detail and portion | `MealDetailView`, `PortionSizeSelectorView`, `CustomFoodView` | 9 |
| 3.8 | Nutrition tab | Food week sheet (`WeekAndDateViews.swift`) | 10 |
| 3.9 | Training tab and workout detail | Gym week sheet, `WorkoutAndWeightViews.swift` | 10–11 |
| 3.10 | Budget explainer | New | 11 |
| 3.11 | Onboarding | `OnboardingView.swift`, `ProfileDetailsView.swift` | 11–12 |
| 3.12 | Permission and error states | Scattered alerts | 12 |

Every screen is delivered with all states: first run, loading, empty, partial, full, error, offline, permission denied, Reduce Motion, largest text size.

---

## 3.1 Today

**Job:** "In two seconds, tell me how my day is going and what to do next."

**Layout, top to bottom**

1. **Header:** large title showing the date ("Saturday, 3 Oct"); swipe left or right to change day, calendar button for jumps; "Ask" glass chip; profile avatar.
2. **Life Orb** (240 pt) with the remaining budget in `font.display.hero` inside or below it: "640 left".
3. **Budget explainer chip** under the number: "1,571 base + 222 earned from activity". Tap opens 3.10.
4. **Next up card** (AI-written, one line + one action), for example "Lunch usually around 1 pm · Log 'Office lunch'" with a one-tap button. Hidden if there is nothing useful to say.
5. **Metric row:** protein, water, activity, sleep tiles, each in its data colour with a progress hint.
6. **Today timeline:** meals, workouts, water and weight in time order, newest first, each with its source badge (Voice, Photo, Apple Watch, Preset).
7. **Plan preview:** today's todos (3 max) and the streak.

**Rules**

- No more than 3 numbers above the fold: remaining calories, earned calories, and one more chosen by context.
- Past days show the same layout in a quieter tone with "Viewing Thu, 1 Oct · Back to today".
- The floating "+" is removed; the Capture button in the tab bar replaces it. This also fixes the clipped last row (audit A4).

**Key motion moments**

- Meal logged: the item chip flies from the Capture sheet into the orb, the liquid rises (`motion.spring.gentle`), the number rolls, `.success` haptic.
- Apple Watch workout arrives: a workout card slides in at the top of the timeline, the orb rim pulses, the budget number rolls up, the explainer chip updates to "+222 earned".

**States:** first day (orb empty, Next up says "Log your first meal: just say it"), Apple Health not connected (activity tile shows "Connect Apple Health"), stale data (subtle "Updated 2 h ago").

---

## 3.2 Capture sheet

**Job:** "Let me log anything the fastest way I can, and let the app work out the details."

Opens from the centre tab button as a `.medium` sheet that can expand to `.large`.

| Mode | Trigger | What happens |
| --- | --- | --- |
| **Say** (default) | Sheet opens listening, or hold the Capture button | Live transcript appears word by word; the orb glyph ripples with the voice; stops after 1.5 s of silence |
| **Type** | Tap the text field | "2 rotis, dal, and a cup of chai" |
| **Photo** | Camera icon | Opens 3.5 |
| **Scan** | Barcode icon | Opens 3.6 |
| **Presets** | Row of preset chips above the keyboard | Sorted by what is usual at this time of day; one tap logs |

Also in the sheet: quick water (+1 glass), quick weight, and "Ask" (switches to the assistant, Phase 4).

**Meal type is automatic** from the time of day and the user's habits ("Breakfast" before 11 am by default). It is shown as an editable chip, never a required field.

**Error and edge states**

- Microphone permission denied: show Type mode with a one-line explanation and a Settings link.
- Nothing heard: "I didn't catch that. Try again or type it."
- Not understood: show what was heard and the closest presets or foods as chips.
- Offline: voice and on-device parsing still work; a badge says "Offline · on-device".

---

## 3.3 AI proposal card

Shown after any voice, text or photo input. The user always confirms before anything is saved, unless they switched on auto-logging for a preset.

**Anatomy**

- Header: meal type chip, time, source badge.
- One row per item: name, amount and unit (editable inline), kcal, a confidence dot (high / medium / low).
- Totals: kcal and P / C / F macro bar.
- Actions: **Log** (primary), **Edit**, "Save as preset" (secondary), "Tell me what's different" field (keeps today's refine feature from `MealResultView`).

**Rules**

- Low-confidence items are listed first with a quiet prompt: "Check portion".
- Editing a value recalculates totals immediately (numbers roll).
- After **Log**: sheet closes, toast "Logged · 412 kcal · Undo" for 4 seconds.

---

## 3.4 Presets ("My Meals")

**Job:** "My usual meals should take one tap or one sentence."

| Function | Design detail |
| --- | --- |
| Create | From a logged meal ("Save as preset"), by voice ("save this as usual breakfast"), from the proposal card, or manually |
| Name and aliases | Main name + aliases the user might say ("usual breakfast", "my eggs", "morning plate") |
| Contents | Items with amounts; total kcal and macros shown |
| Default time | Morning, midday, evening, any; drives sorting in Capture |
| Look | Photo (from a past meal) or SF Symbol + data colour |
| Scaling | "Half", "double", or a custom multiplier when logging ("half my usual lunch") |
| Auto-log (optional) | "Log this automatically on weekdays at 8:00, I'll confirm with a notification." Off by default |
| Manage | Reorder, edit, duplicate, delete; usage count shown ("Used 23 times") |

Preset chips in Capture show the name, kcal and a small photo. A long-press opens a preview with an Edit option.

---

## 3.5 Camera and meal result

**Camera screen**

- Full-screen viewfinder with a soft circular guide; shutter at the bottom; flash, gallery and "add another angle" controls on glass.
- Optional hint for portion accuracy: "Include your hand or a fork for size".
- After capture: **meal lift** (Phase 2, 9.3). The plate cut-out floats, the background dims, labels appear on each detected item while AI works.
- Progress copy changes over time: "Looking at your plate…" → "Estimating portions…" → "Almost done". Avoid a spinner alone.

**Meal result** uses the AI proposal card (3.3) with the photo on top, plus:

- Source line: "Estimated on device" or "Estimated with Groq" / "Estimated with Gemini" (your free key), so you always know where the photo went.
- When the result came from a past correction (existing learning feature): "Matched your earlier correction".
- When the cloud model failed and the on-device fallback answered: an inline banner "Quick estimate. Check the portions."

---

## 3.6 Barcode and nutrition label

- Live camera with the detected barcode outlined, plus a haptic and auto-capture on lock.
- Found: product card with photo, brand, serving selector → proposal card.
- Not found: offer "Scan the nutrition label instead". Text recognition reads the label and fills the values for review. This replaces today's dead-end prompt.

---

## 3.7 Food detail and portion

- Portion control: grams field, serving chips (½, 1, 1½, 2) and a visual slider showing a plate filling, so people can estimate without a scale.
- Macros update live with number rolls.
- "Add to preset" and "Mark as favourite" actions.

---

## 3.8 Nutrition tab

- **Header:** day scroller and a 120 pt Life Orb.
- **Meals:** Breakfast, Lunch, Dinner, Snacks as sections with items, kcal and a quick "+" each. An empty meal shows the most likely preset ("Usual breakfast · 420 kcal · Log") instead of "No items added" (audit A7).
- **Macros:** stacked ring with targets and remaining grams.
- **History:** 30-day calendar heat map in `color.data.energy`, tap a day to open it.
- **My Meals:** preset gallery entry point.

---

## 3.9 Training tab and Apple Watch workouts

**Workout list**

- Workouts recorded with Apple's own Workout app on the Watch appear automatically with the `applewatch` badge, activity icon, duration, active kcal and "+X kcal earned". The iPhone app reads them from Apple Health, which works on a free Apple account. (The Watch app itself can't use HealthKit on a free account, so this is the main way workouts arrive.)
- Manual gym sessions (today's body-part and sets logging) sit in the same list with a "Logged in LifeOS" badge.
- Week view shows real sessions only. The current design repeats "Treadmill 20 min · 15% incline" on every day (screenshot IMG_2360); planned sessions should look clearly different (outlined) from completed ones (filled).

**Workout detail**

- Hero: activity, duration, active kcal, average heart rate if Apple Health has it.
- Sets and reps (from the Watch auto-tracker or manual).
- "Effect on today": a mini budget explainer showing how much this workout added.

**New-workout moment:** when a Watch workout arrives while the app is open, show the card slide-in plus orb pulse (3.1). If the app is closed, the notification design comes from Phase 4 automations.

---

## 3.10 Budget explainer sheet

**Job:** "Show me exactly why my number is what it is."

```
Today's budget                    1,793 kcal
  Maintenance (BMR × 1.2)         2,121
  Goal: lose 0.5 kg/week           −550
  = Base budget                   1,571
  Earned from activity             +222   (50% of 443 active kcal above baseline)
Eaten so far                      1,153
Remaining                           640
```

- Each line is tappable for a one-sentence explanation and its source ("Active energy from Apple Watch, updated 6:52 pm").
- Settings at the bottom: "Count activity calories" (on/off) and "How much to eat back" (0%, 25%, 50%, 75%, 100%; today's default in `CalorieSettings` is 50%).
- The formula above is an example layout. The exact formula is owned by the Health engineering spec; design must show whatever lines that spec defines.

---

## 3.11 Onboarding

Goal: premium, short, and trusted. Six steps, each with one decision, and a progress indicator built from the orb (it fills a little each step).

| Step | Content | Notes |
| --- | --- | --- |
| 1 | Welcome: the orb forms from light, one line: "Your day, understood." | 3D moment; skip button visible |
| 2 | Your goal: lose, maintain, gain; target weight | Large tappable cards |
| 3 | About you: age, height, weight, sex | Units auto from region; privacy line "Stays on your iPhone" |
| 4 | Apple Health: why it helps (workouts, active energy, sleep), then the system prompt | Explain before the system sheet appears |
| 5 | Notifications: what kind and how often (max 4 a day by default) | Then the system prompt |
| 6 | AI and privacy: on-device by default (needs iPhone 15 Pro or newer); optionally paste a free Groq or Gemini key for better photo estimates | Plain language, "Skip for now", link to how to get a free key. Existing key screen in `FoodFlowViews.swift` is the starting point |

Finish: the orb settles into the Today screen with today's budget (zoom transition).

---

## 3.12 Permission and error states

| Situation | Design |
| --- | --- |
| Apple Health not connected or denied | Activity and sleep tiles show "Connect Apple Health" with a one-line benefit; budget explainer shows "Activity not counted" |
| Camera denied | Camera screen replaced with an explanation and Settings button; gallery still available |
| Microphone or speech denied | Capture opens in Type mode |
| No network | Badge "Offline"; cloud-only features say so in plain words; everything else works |
| AI quota reached for the day | "Using quick on-device estimates for the rest of today" banner, no error |

---

## 4. Copy guidelines (examples)

| Situation | Write | Avoid |
| --- | --- | --- |
| Meal logged | "Logged. 412 kcal, 31 g protein." | "Awesome!!! 🎉 Meal added!" |
| Over budget | "120 over today. Tomorrow resets." | "You exceeded your limit!" |
| Empty breakfast | "Usual breakfast? 420 kcal" | "No items added" |
| Workout synced | "Strength, 48 min · +190 kcal earned" | "Workout data received from HealthKit" |
| AI unsure | "Check the rice portion." | "Low confidence result" |

---

## 5. Weekly plan

| Week | Product designer | Motion/3D designer | iOS UI engineer |
| --- | --- | --- | --- |
| 6 | Today wireframes → hi-fi | Meal-to-orb and workout-arrival motion | Today shell with design-system components |
| 7 | Capture sheet, proposal card | Voice-reactive glyph | Today live data; Capture shell |
| 8 | Presets, camera | Meal lift polish | Capture modes, proposal card |
| 9 | Meal result, barcode, label, portion | Camera transitions | Camera, result, barcode |
| 10 | Nutrition tab, Training tab | Timeline insert motion | Nutrition and Training tabs |
| 11 | Workout detail, budget explainer, onboarding | Onboarding orb sequence | Budget explainer, workout detail |
| 12 | Permission/error states, one week of daily-use testing | Polish | Onboarding, states; install the build from Xcode for daily use |

## 6. Handoff checklist (per screen)

- [ ] All states designed (first run, loading, empty, partial, full, error, offline, permission denied)
- [ ] Light, dark, largest text size, Reduce Motion, Reduce Transparency
- [ ] VoiceOver order and labels written (for example "Remaining calories, 640. Budget 1,793, including 222 earned from activity.")
- [ ] Motion: video + token names; haptics listed
- [ ] Copy final and checked against the guidelines
- [ ] Findings from your daily-use week resolved or logged
