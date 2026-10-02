# Phase 1: Discovery and Direction

**Weeks:** 1–3 · **Gate:** D1 "Direction locked" at the start of week 4
**Owners:** product designer (lead), motion/3D designer, iOS UI engineer (feasibility)
**Part of:** `00_UIUX_Master_Plan.md`

By the end of week 3 one visual direction for LifeOS is chosen, based on how the owner actually uses the app. It is shown on four key screens, the app icon and the Life Orb concept, and a rough build proves it runs at full frame rate on the owner's iPhone. Everything in this phase is free.

---

## 1. Outcomes and exit criteria

| Outcome | Exit criterion for gate D1 |
| --- | --- |
| Shared understanding of today's UI | Audit board covers every current screen, each issue tagged and rated |
| Evidence from real use | 5-day usage diary done (section 4.1), summarised as 5–8 jobs to be done |
| Three explored directions | Each shown on the same 4 screens + app icon + Watch face |
| One chosen direction | Scored with the rubric in section 6 after looking at each direction's mockups on your own iPhone (as images in Photos) for a day; signed off by the owner |
| Feasibility confirmed | A rough build of the chosen Life Orb concept, installed from Xcode, runs at the display's frame rate on the owner's iPhone |

---

## 2. Week-by-week plan

| Week | Product designer | Motion/3D designer | iOS UI engineer |
| --- | --- | --- | --- |
| 1 | Screen audit, start the 5-day usage diary, reference teardown | Motion and 3D reference library, Life Orb sketches | Screen-recording walkthrough of every flow; list of reusable SwiftUI components |
| 2 | Finish diary; draft three directions on the Today screen | 3D orb look-development in Blender for each direction | Spike: `RealityView` orb and Metal-shader orb, measure frame time |
| 3 | Extend directions to 4 screens + icon + Watch; score with the rubric | Motion studies (10 s clips) per direction | Spike: Liquid Glass tab bar and sheets on iOS 26 |
| 4 (day 1) | Gate D1 review | Gate D1 review | Gate D1 review |

One person can run this whole phase alone; expect about 5 weeks instead of 3.

---

## 3. Audit of the current UI

### 3.1 Screens to audit

Take every screen on a real iPhone in both light and dark, at default and the largest text size.

| Area | Screens (source file) |
| --- | --- |
| Onboarding | Welcome pages, profile details form (`Onboarding/OnboardingView.swift`, `ProfileDetailsView.swift`) |
| Home | Today header, calorie ring, Daily Progress grid, floating "+" (`HomeView.swift`, `Components/HomeComponents.swift`) |
| Quick actions | 14-item menu (`Components/QuickActionsMenu.swift`) |
| Food | Meal detail, food search, custom food, portion selector, barcode scanner, barcode-not-found prompt, AI meal scan, meal result, learned corrections (`FoodFlowViews.swift`, `MealResultView.swift`, `LearnedCorrectionsView.swift`) |
| Week views | Food week, gym week, date picker (`WeekAndDateViews.swift`) |
| Training | Workout entry, weight picker (`WorkoutAndWeightViews.swift`); rest timer, strength tools, macros, trends, reminders (`Tools/FitnessTools.swift`) |
| Streaks | Streak overview, 30-day grid (`StreaksView.swift`) |
| Todo | Day lists, add task sheet, reminder presets (`Tabs/TabViews.swift`) |
| Profile and settings | Profile hub, settings, profile editor (`Tabs/TabViews.swift`) |
| Apple Watch | Dashboard, workout auto-track, rest timer, water, weight, todos (`LifeOS Watch App/Views/`) |

### 3.2 How to log each issue

One row per issue on the audit board:

| Field | Example |
| --- | --- |
| ID | A1 |
| Screen | Home, Daily Progress grid |
| Screenshot | Cropped, annotated |
| Problem | Orange used for both "0/0 Done" (neutral) and "Low Protein" (warning) |
| Principle broken | 3 "Every number explains itself" |
| Severity | High / Medium / Low |
| Fix direction | Separate data colours from status colours (Phase 2 tokens) |

Start from the 10 issues already found (A1–A10 in the master plan). Two more were found during the code review:

- **A11:** the mint accent `#70EDC6` has a contrast ratio of only 1.4:1 on white, so it cannot be used for text or icons in light mode. Light mode needs its own darker accent.
- **A12:** status colours are hard-coded in places (`.orange`, `.blue`, `.green` in the screenshots) rather than taken from `ThemePalette`, so a palette change will not reach every screen until those are replaced.

---

## 4. Research

### 4.1 Five-day usage diary (the owner is the only user)

Use the current LifeOS build normally for 5 days and keep a note (Apple Notes is fine) every time something is slow, confusing or ugly. Answer these at the end of each day:

1. When did I think about food, exercise or health today, and did I open LifeOS for it?
2. Every meal I logged: how long did it take, and what was annoying?
3. Every meal I *didn't* log: why not?
4. Did my Apple Watch workout show up anywhere useful? What did I expect to happen?
5. Which number on the Today screen did I actually look at, and did I understand it?
6. If an assistant could log things for me, what would I let it do without asking?
7. Which other apps on my phone feel premium? What exactly makes them feel that way?

**Output:** one page with 5–8 jobs to be done, top 5 friction points, and the words you naturally use (for button labels and voice commands such as "usual breakfast").

**Optional, still free:** show the current app to 2–3 friends over a video call and ask question 5 and question 7. Fresh eyes catch things the owner no longer notices.

### 4.2 Reference teardown

Study patterns, never copy layouts or assets. Use only free sources: apps' free versions, their App Store screenshots and public walkthrough videos. Skip free trials that ask for a card, and never pay for a subscription. For each product capture: first screen, logging flow, how data is explained, motion and haptics, premium cues.

| Group | Products to study | What to look for |
| --- | --- | --- |
| Health and fitness | Apple Fitness and Health, Oura, Whoop, MacroFactor, MyFitnessPal, a photo-calorie app such as Cal AI | Data density, ring and score metaphors, logging speed |
| Premium non-health | A private-banking app, a luxury watch or car companion app, a high-end hotel app | Restraint, typography, tone of voice |
| Craft benchmarks | Things 3, Apple Weather, Apple Journal | Motion choreography, empty states, haptics |

---

## 5. Three directions to explore

All three share the same information architecture (master plan section 5) and the same data colours, so the test compares look and feel, not features. Hex values are starting points; Phase 2 tunes them. Contrast ratios are calculated (WCAG 2.x formula).

### Direction A: "Obsidian & Champagne"

- **Mood:** a private members' club at night. Near-black, warm metallic accents, serif numerals.
- **Palette:** background `#0B0B0D`, surface `#16161A`, raised `#1F1F24`, primary text `#F4F1EA` (17.4:1 on background), secondary text `#A7A29A` (7.8:1), champagne accent `#D8C3A5` (11.5:1), deep brass `#B89A6A` for fills only.
- **Type:** New York Large for hero numbers, SF Pro Text for UI.
- **Materials:** matte surfaces, Liquid Glass only on floating controls; fine 0.5 pt champagne hairlines.
- **Life Orb:** smoked glass with liquid gold filling it.
- **Motion personality:** slow, weighty, precise (soft springs, no bounce).
- **Risk:** can look dated or "gold-plated" if over-used. Keep champagne to under 5% of any screen.

### Direction B: "Porcelain"

- **Mood:** a luxury editorial magazine in daylight. Warm ivory, ink, one deep emerald.
- **Palette:** background `#F6F3EE`, surface `#FFFFFF`, primary text `#15140F` (16.7:1), secondary text `#6E6A63` (4.9:1, the minimum for body text), emerald accent `#0F5C4A` (7.2:1), brass `#8C6D3F` for large text and icons only (4.3:1).
- **Type:** New York for headlines and numbers, generous white space.
- **Materials:** paper-like flat cards, soft shadows, Liquid Glass on the tab bar.
- **Life Orb:** frosted porcelain sphere with an emerald liquid fill.
- **Motion personality:** gentle, editorial (cross-fades, slow reveals).
- **Risk:** dark mode must be designed separately; outdoor glare is fine but night use is weaker.

### Direction C: "Aurora Glass" (evolution of today's look)

- **Mood:** deep space and light. Keeps the current mint and violet but makes them luminous and rare.
- **Palette:** background `#07090F`, glass surfaces, primary text `#EEF2FF` (17.8:1), secondary text `#9AA3B5` (7.8:1), mint `#70EDC6` (13.9:1 on background), violet `#8C99FA` (7.6:1), slow `MeshGradient` aurora behind the hero only.
- **Type:** SF Pro Rounded for numbers, SF Pro for UI.
- **Materials:** Liquid Glass everywhere it is allowed, light refraction on edges.
- **Life Orb:** clear glass with a mint-to-violet aurora inside.
- **Motion personality:** fluid, lightly springy.
- **Risk:** closest to many existing fitness apps, so least distinctive; mint fails as text in light mode (1.4:1 on white) and needs a darker light-mode variant.

### Each direction is shown on

1. **Today**: Life Orb, budget explanation chip, three key cards, tab bar.
2. **Capture sheet**: voice, text, photo, barcode, presets.
3. **Meal result card**: photo with lift effect, items, macros, confidence.
4. **Workout synced card**: Apple Watch workout with "+222 kcal earned".
5. **App icon** (3 sizes) and **wordmark**.
6. **Apple Watch** dashboard and one complication.

---

## 6. Choosing the direction

Put each direction's screens on your iPhone as images and live with them for a day each. Then score them. If friends helped in section 4.1, ask them the 5-second question too ("How many calories are left?").

| Criterion | Weight | How it is measured |
| --- | --- | --- |
| Feels premium to you | 25% | 1–7 rating after a day with the mockups |
| Clarity of the main number | 20% | 5-second test on the Today mockup: is "calories left" obvious? |
| Distinctiveness | 15% | Does it look like LifeOS, or like another fitness app you know? |
| Data readability | 15% | Can you find today's protein and tell if it is on track in under 3 seconds? |
| Feasibility and performance | 15% | Spike result: frame time on your iPhone, effort to build |
| Accessibility | 10% | All text pairs at least 4.5:1, large text at least 3:1, works with Reduce Transparency |

A hybrid is fine (for example A's type with C's materials). If you choose one, write down exactly which parts come from which direction.

---

## 7. Brand mark and app icon

- Optional for a personal app. The current icon files (`AppIcon.appiconset/Gemini_Generated_Image_*.png`) work, but a simple vector mark matching the chosen direction makes the app feel finished.
- If you redo it: explore 3 concepts per direction, a monogram, an abstract orb, and a wordmark-only option.
- Deliver as layered icon artwork for iOS 26 (light, dark, tinted and clear variants), built in Apple's Icon Composer (free with Xcode).
- The mark must read at 29 pt (Settings) and on the Watch.

---

## 8. Deliverables checklist

- [ ] Audit board: all screens, issues A1–A12 and new ones, each with severity
- [ ] Usage diary synthesis: jobs to be done, friction points, your own vocabulary
- [ ] Reference teardown board (free sources only)
- [ ] Three directions × 6 artefacts (section 5)
- [ ] Motion study clip per direction (10 seconds each)
- [ ] Life Orb concept render per direction
- [ ] Rubric scores
- [ ] Spike report: Life Orb frame time on your iPhone, Liquid Glass findings
- [ ] Decision record: chosen direction, what was rejected and why

## 9. Risks

| Risk | Mitigation |
| --- | --- |
| Designing only from your own taste, missing obvious problems | Score with the rubric before deciding; optionally ask 2–3 friends the 5-second question |
| 3D orb too heavy for your iPhone | 2.5D Metal-shader fallback is part of the spike, not an afterthought |
| Free-account build expires mid-phase (7 days) | Re-run from Xcode weekly; see the reinstall routine in Phase 5 |
