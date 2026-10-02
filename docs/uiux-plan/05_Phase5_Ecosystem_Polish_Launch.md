# Phase 5: Ecosystem, Polish and Daily Use

**Weeks:** 15–26 · **Gate:** D3 "Ready for daily use" at the start of week 27
**Owners:** product designer, motion/3D designer, iOS UI engineer (+ watchOS engineer for Watch screens)
**Depends on:** Phases 2–4 screens; engineering work on WidgetKit, App Intents, Live Activities and the Watch app.
**Cost:** zero. Everything here works with a free Apple account and Xcode. There is no App Store release; the app is installed from Xcode on the owner's own iPhone and Apple Watch.

LifeOS should feel premium wherever it shows up: on the wrist, on the Lock Screen, in Siri and in StandBy. This phase designs those surfaces, adds the 3D medals, runs the full accessibility and polish pass, and designs the backup and 7-day reinstall experience that a free-account app needs.

---

## 1. Outcomes and gate D3 criteria

- [ ] Apple Watch app redesigned to the new system; complications and Smart Stack widget working
- [ ] iPhone widgets (Home Screen, Lock Screen, StandBy) and two Control Center controls working
- [ ] Live Activity for in-app gym sessions and the rest timer
- [ ] Siri / Shortcuts snippet views for the top 6 intents
- [ ] 3D streak medals with AR Quick Look
- [ ] Every screen passes the accessibility checklist (section 7)
- [ ] Polish bug bash closed: no open P1 visual bugs
- [ ] Backup, restore and the "refresh from Xcode" reminder designed, built and tested (section 9)

---

## 2. Apple Watch

The current Watch app (`LifeOS Watch App/Views/`) has Dashboard, Workout (auto set tracking), Rest Timer, Water, Weight and Todos. Keep the features; redesign the look to the new system using watchOS 26 conventions.

**Free-account rule:** the Watch app cannot use HealthKit on a free Apple account (today's build already avoids it). So the Watch app shows data the iPhone sends it over WatchConnectivity, and it does not read heart rate or run background workout sessions itself.

### Screens

| Screen | Design |
| --- | --- |
| **Today** | 2D Life Orb glyph with remaining kcal in large numerals; earned activity line; protein and water mini bars (all sent from the iPhone) |
| **Quick log** | Top 4 presets for this time of day as large buttons; dictation button ("Say what you ate"); confirm screen with kcal |
| **Water** | One big +1 button, Digital Crown adjusts; glass fill animation; haptic per glass |
| **Workout (LifeOS gym session)** | Large rep counter, set dots, current exercise, elapsed time; auto set tracking state ("Counting…" / "Resting"); keep-screen-on reminder |
| **Rest timer** | Full-screen ring countdown; haptic at 10 s and 0 s |
| **Weight** | Crown-driven picker with 0.1 kg steps; trend arrow |
| **Todos** | Today's list, tap to complete |

### Two workout sources to design for

1. **Apple's own Workout app (main source).** Start any workout there as usual. Apple Health stores it, the iPhone LifeOS app reads it for free, and the Watch Today screen then shows "+190 earned from Strength". Design a small hint on the LifeOS Watch Today screen: "Use the Workout app for cardio; LifeOS counts your gym reps."
2. **LifeOS gym session (rep counting).** Works while the LifeOS screen is on, as it does today. Design for that honestly: a clear "Keep this screen open while you lift" note, a big tap target for "Log set" as a fallback, and a summary that is sent to the iPhone when the session ends.

### Complications and Smart Stack

| Family | Content |
| --- | --- |
| Circular | Orb fill gauge with remaining kcal |
| Rectangular | "640 left · 96 g protein" with a small bar |
| Corner | Remaining kcal as a curved gauge |
| Inline | "640 kcal left" |
| Smart Stack widget | Today summary; shows the next likely preset around meal times |

Support the tinted watch-face rendering mode: designs must work in a single tint colour.

---

## 3. iPhone widgets, StandBy and controls

| Widget | Size | Content | Interaction |
| --- | --- | --- | --- |
| Today | Small | 2D orb, remaining kcal | Tap opens Today |
| Today + log | Medium | Orb, macros, 2 preset buttons | Preset buttons log directly (interactive widget) with a confirmation tick |
| Day timeline | Large | Today's meals and workouts, remaining kcal | Tap opens item |
| Lock Screen circular | Accessory | Orb gauge | — |
| Lock Screen rectangular | Accessory | "640 left · 96 g protein" | — |
| Lock Screen inline | Accessory | "640 kcal left" | — |
| StandBy | Large, night mode aware | Big remaining number and orb; red-tint safe at night | — |

**Control Center / Lock Screen controls:** "Capture" (opens the Capture sheet listening) and "Add water" (+1 glass, no app launch).

**Rules:** widgets use the same data colours as the app; every widget is designed in full colour, tinted, and clear (iOS 26 Home Screen appearances); numbers use monospaced digits; no 3D rendering in widgets (use pre-rendered orb images from Phase 2).

**Free-account rule:** a free account can only create 10 new App IDs every 7 days, and every extension needs one. All widgets, controls and Live Activities therefore live in **one** widget extension, sharing data with the app through one App Group.

---

## 4. Live Activities and Dynamic Island

| Live Activity | Compact (Dynamic Island) | Expanded | Lock Screen |
| --- | --- | --- | --- |
| Gym session (in LifeOS) | Exercise icon + set count | Exercise, set 3 of 4, reps, elapsed | Same as expanded, plus a "Log set" button |
| Rest timer | Countdown ring | Countdown + next exercise | Countdown + "Skip" button |

Design the minimal (single icon) state too, for when another app's activity takes the island. These are updated by the app on the phone, so no push server (and no cost) is needed.

---

## 5. Siri and Shortcuts

Design snippet views for the top intents engineering exposes through App Intents (free):

| Intent | Siri phrase example | Snippet view |
| --- | --- | --- |
| Remaining calories | "How many calories do I have left in LifeOS?" | Orb gauge + "640 left, 222 earned today" |
| Log preset | "Log my usual breakfast in LifeOS" | Preset name, items, kcal, Log / Cancel |
| Log water | "Add a glass of water in LifeOS" | Glass fill + new total |
| Log weight | "Log my weight in LifeOS" | Weight + trend |
| Ask LifeOS | "Ask LifeOS how my protein is this week" | Short answer + mini chart |
| Start gym session | "Start my workout in LifeOS" | Exercise picker summary |

Also provide the App Shortcuts icons (SF Symbols with LifeOS tint) and short titles for the Shortcuts app. Personal automations in the Shortcuts app (for example "When I arrive at the gym, start my LifeOS session") are free and use these same intents.

---

## 6. 3D streak medals and achievements

- A small, meaningful set. No points or levels.

| Medal | Earned for |
| --- | --- |
| First week | 7 perfect days in a row |
| Month | 30-day perfect streak |
| Century | 100-day perfect streak |
| Ritual | First preset used 20 times |
| Synced | 50 Apple Watch workouts in LifeOS |
| Balance | 4 weeks within 5% of budget on average |

- **Look:** the Life Orb's glass family. Medals are glass discs with a metal rim in the chosen accent, engraved with a custom symbol and the date earned.
- **Viewing:** a `RealityView` you can spin with a finger, with light catching the rim; a "View in your space" button opens AR Quick Look (free, built into iOS).
- **Asset budget:** each medal ≤ 8,000 triangles, ≤ 1 MB USDZ, textures ≤ 1024 px; a shared material so medals load fast. Modelled in Blender (free).
- **Earning moment:** full-screen, 2.5 s, medal drops in and settles (`motion.spring.celebrate`), one `.success` haptic. Reduce Motion: fade in.

---

## 7. Accessibility audit checklist

Run on every screen, widget and Watch view. Fix or log each failure before gate D3.

**Vision**
- [ ] Text contrast: body at least 4.5:1, large text and icons at least 3:1, in light and dark
- [ ] Works at the largest accessibility text size without truncating key numbers (layouts switch to vertical stacks)
- [ ] Bold Text, Increase Contrast and Reduce Transparency all render correctly
- [ ] Colour is never the only signal (status has an icon or word; charts label series)
- [ ] Colour-blind simulation passes for all data colours (Xcode Accessibility Inspector, free)

**VoiceOver**
- [ ] Every control has a label, value and hint where useful
- [ ] Reading order matches visual order; the orb reads as one element ("Remaining calories, 640…")
- [ ] Charts have audio graphs or a summary label
- [ ] Streaming AI answers are announced once complete
- [ ] Custom actions on rows (Edit, Delete, Log) instead of swipe-only

**Motion and interaction**
- [ ] Reduce Motion: no parallax, zoom or orb motion; cross-fades only
- [ ] Every haptic has a visible counterpart
- [ ] All touch targets at least 44 × 44 pt
- [ ] Voice features have a typed alternative

---

## 8. Polish pass

Two-week bug bash (weeks 21–22) on the devices you own: your iPhone and your Apple Watch. Use Xcode's free simulators for other iPhone sizes, in case you change phones later.

| Category | Examples of what to catch |
| --- | --- |
| Alignment and spacing | Off-grid padding, baseline mismatches in metric tiles |
| Type | Wrong token, widows in headlines, numbers that jump instead of roll |
| Motion | Janky transitions, double animations, missing Reduce Motion paths |
| States | Missing empty, error or offline states |
| Copy | Tone breaks, inconsistent units ("kcal" vs "cal"), exclamation marks |
| Performance | Frame drops on the orb, slow sheet open, slow app start |
| Dark/light | Glass legibility over photos, shadows invisible in dark |

Severity: P1 = visible on a primary flow, blocks daily use; P2 = noticeable, fix soon; P3 = nice to have.

---

## 9. Backup, restore and the 7-day reinstall

With a free Apple account, an app installed from Xcode **stops opening 7 days after it was installed**. Running it again from Xcode fixes it and keeps all data. Deleting the app would lose all data. The design makes both facts painless.

### 9.1 "Refresh soon" reminder

- The app reads its own expiry date from the installed provisioning profile.
- **2 days before:** a quiet banner at the top of You → Settings, and a one-time notification: "LifeOS needs a refresh from Xcode by Thursday. Your data is safe."
- **On the last day:** the banner moves to the top of Today, still calm, with a "How to refresh" link.
- Never a blocking alert.

### 9.2 Backup and restore (You → Settings → Data and backup)

| Element | Design |
| --- | --- |
| Last backup | "Last backup: today, 8:02 am · 1.4 MB" |
| Back up now | Creates one file containing meals, presets, workouts, metrics, memories and automations; saves via the system share sheet to Files (On My iPhone or any folder you choose) |
| Automatic backup | Toggle: a fresh backup file each time you open the app after midnight, keeping the last 7 |
| Restore | Pick a backup file; preview "This backup is from 3 Oct with 1,204 meals"; confirm |
| Export for spreadsheets | CSV of meals, workouts and weight, for your own analysis |

API keys are never included in backups. They stay in the Keychain and must be re-entered after a restore on a new phone.

### 9.3 Refresh routine (one-page in-app help + this doc)

1. Connect the iPhone (and paired Watch) to the Mac, or use the same Wi-Fi with wireless debugging on.
2. Open the LifeOS project in Xcode, choose your iPhone, press Run.
3. Done: the app gets a fresh 7 days, data untouched. The Watch app has the same 7-day limit; if it has stopped opening, also run the "LifeOS Watch App" scheme to your Watch.

Target: under 2 minutes. If it takes longer, simplify the steps before gate D3.

---

## 10. Weekly plan

| Week | Product designer | Motion/3D designer | Engineers |
| --- | --- | --- | --- |
| 15–16 | Watch screens, complications | Watch motion, orb glyph renders | Watch UI build |
| 17–18 | Widgets, controls, StandBy | Widget orb image set | WidgetKit (single extension), controls |
| 19 | Live Activities, Siri snippets | Medal modelling | Live Activities, App Intents snippets |
| 20 | Achievements flow | Medal materials, AR Quick Look | Medal viewer |
| 21–22 | Accessibility audit, bug bash | Motion bug bash | Fixes |
| 23–24 | Backup, restore, refresh reminder | Polish of remaining motion | Backup file format, expiry reminder |
| 25–26 | Two weeks of daily use; final fixes | Final polish | Fixes; refresh routine timed |

## 11. Deliverables checklist

- [ ] Watch screens, complications (all families, tinted mode), Smart Stack widget
- [ ] iPhone widgets (all sizes, full colour / tinted / clear), StandBy, controls
- [ ] Live Activity layouts (compact, minimal, expanded, Lock Screen)
- [ ] Siri snippet views and App Shortcuts icons
- [ ] Six 3D medals (USDZ) and the earning moment
- [ ] Accessibility audit report, all P1 issues closed
- [ ] Polish bug bash report
- [ ] Data and backup screen, restore flow, refresh reminder, refresh help page
