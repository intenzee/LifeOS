# Phase 2: Design System and Signature 3D

**Weeks:** 3–8 · **Gate:** D2 "Design system v1" at the start of week 9
**Owners:** product designer (tokens, components), motion/3D designer (motion, Life Orb, 3D), iOS UI engineer (`DesignSystem` Swift package)
**Depends on:** Phase 1 direction decision (gate D1, week 4). Weeks 3–4 build direction-neutral structure; colour and type values are filled in after D1.

By week 9 every visual decision in LifeOS comes from one token set and about 30 components, all built in a `DesignSystem` Swift package with snapshot tests. The Life Orb runs on device with live data.

---

## 1. Outcomes and gate D2 criteria

- [ ] Token JSON is the single source; Swift code is generated from it, with no hand-typed colours or sizes left in feature code
- [ ] 30 core components designed, built and snapshot-tested in light, dark and the largest text size (section 7)
- [ ] Motion spec approved and implemented as named SwiftUI animations (section 8)
- [ ] Haptics map implemented (section 8.4)
- [ ] Life Orb: final USDZ and material, driven by real budget data, at the display's frame rate on the owner's iPhone (section 9)
- [ ] 2.5D fallback orb matches the 3D orb's states
- [ ] The old `ThemePalette`, `GlassSurface` and `DesignSystem.Radius` are wrapped or replaced, with a migration list for feature screens

---

## 2. Token architecture

Three tiers, so a brand change touches only the first tier:

| Tier | Example name | Example value | Who uses it |
| --- | --- | --- | --- |
| Primitive | `champagne.300` | `#D8C3A5` | Only the semantic tier |
| Semantic | `color.accent.primary` | `{champagne.300}` in dark, `{brass.700}` in light | Components and screens |
| Component | `button.primary.background` | `{color.accent.primary}` | One component only |

**Naming:** `category.role.variant.state`, for example `color.text.secondary`, `color.data.protein`, `color.status.attention`, `space.300`, `radius.card`, `motion.spring.smooth`.

**Pipeline:** the design tool's token plugin exports JSON → Style Dictionary (free, open source) generates `DesignTokens.swift` → the `DesignSystem` package exposes it as `Color.lx.*`, `Font.lx.*`, `Spacing.lx.*`, `Animation.lx.*`. A CI check fails the build if a feature file uses `Color(red:…)`, `.orange`, `.blue` and similar outside the package.

```json
{
  "color": {
    "text": {
      "primary":   { "dark": "{ivory.50}",  "light": "{ink.900}" },
      "secondary": { "dark": "{stone.300}", "light": "{stone.600}" }
    },
    "data": {
      "energy":  { "dark": "{amber.300}", "light": "{amber.700}" },
      "protein": { "dark": "{rose.300}",  "light": "{rose.700}" }
    }
  }
}
```

---

## 3. Colour roles

Values come from the direction chosen at D1. The roles are fixed now.

### 3.1 Surfaces and text

| Role | Use | Rule |
| --- | --- | --- |
| `color.background` | Screen background | One per screen; no gradients except the hero area |
| `color.surface` | Cards | Solid, never glass |
| `color.surface.raised` | Sheets, pressed cards | One step brighter than surface |
| `color.text.primary` | Headlines, key numbers | At least 7:1 on background |
| `color.text.secondary` | Labels, metadata | At least 4.5:1 on its surface |
| `color.text.tertiary` | Placeholders, disabled | At least 3:1; never for information you need |
| `color.separator` | Hairlines | 0.5 pt |
| `color.accent.primary` | Primary action, selection, brand moments | Under 5% of any screen |

### 3.2 Status (meaning)

| Role | Meaning | Rule |
| --- | --- | --- |
| `color.status.onTrack` | Within goal | Calm, never celebratory |
| `color.status.attention` | Near a limit, needs a look | Warm amber |
| `color.status.over` | Past a limit | Deeper amber or copper. Not alarm red: LifeOS never shames |
| `color.status.critical` | Errors, destructive actions only | Red is reserved for this |
| `color.status.info` | Neutral notices, AI notes | Cool tone |

### 3.3 Data (what the number is about)

Each metric owns one hue across rings, bars, charts, icons and the Watch. Status is shown with icons, labels and status colours, never by changing a metric's own hue.

| Role | Metric | Hue family (tuned per direction) |
| --- | --- | --- |
| `color.data.energy` | Calories eaten, budget | Amber or gold |
| `color.data.activity` | Active energy, workouts | Green-cyan |
| `color.data.protein` | Protein | Rose or coral |
| `color.data.carbs` | Carbohydrates | Sand or wheat |
| `color.data.fat` | Fat | Violet |
| `color.data.water` | Water | Blue |
| `color.data.sleep` | Sleep | Indigo |
| `color.data.weight` | Body weight | Neutral stone |

**Checks:** each pair of data colours stays distinguishable under protanopia, deuteranopia and tritanopia simulation (Xcode Accessibility Inspector or the design tool's simulator). Every chart labels its series directly, so colour is never the only cue.

---

## 4. Typography

All fonts are Apple system fonts, free to use in the app. Sizes follow Apple's Dynamic Type defaults so text scales correctly; display styles scale relative to Large Title.

| Token | Font | Default size / line height | Weight | Scales with | Use |
| --- | --- | --- | --- | --- | --- |
| `font.display.hero` | New York | 64 / 68 | Semibold | `.largeTitle` (relative) | Budget number in the Life Orb |
| `font.display.l` | New York | 40 / 44 | Semibold | `.largeTitle` (relative) | Screen hero numbers |
| `font.title.large` | New York | 34 / 41 | Bold | `.largeTitle` | Screen titles |
| `font.title.1` | SF Pro Display | 28 / 34 | Semibold | `.title` | Section heroes |
| `font.title.2` | SF Pro Display | 22 / 28 | Semibold | `.title2` | Card titles |
| `font.title.3` | SF Pro Text | 20 / 25 | Semibold | `.title3` | Sheet titles |
| `font.headline` | SF Pro Text | 17 / 22 | Semibold | `.headline` | Row titles |
| `font.body` | SF Pro Text | 17 / 22 | Regular | `.body` | Body copy |
| `font.callout` | SF Pro Text | 16 / 21 | Regular | `.callout` | Secondary copy |
| `font.subhead` | SF Pro Text | 15 / 20 | Regular | `.subheadline` | Labels |
| `font.footnote` | SF Pro Text | 13 / 18 | Regular | `.footnote` | Metadata |
| `font.caption` | SF Pro Text | 12 / 16 | Medium | `.caption` | Chart labels, badges |
| `font.numeric.*` | SF Pro (rounded optional) | Matches its text style | Medium | Same | All changing numbers, with `.monospacedDigit()` so digits do not jump |

Rules: at most 2 font families on a screen; numbers that change always use monospaced digits and `contentTransition(.numericText())`; no text below 11 pt; headlines in sentence case.

---

## 5. Space, layout, shape, depth

| Token group | Values | Notes |
| --- | --- | --- |
| Spacing | 4, 8, 12, 16, 20, 24, 32, 40, 56 pt (`space.100`–`space.900`) | 4 pt base unit |
| Screen margin | 20 pt (16 pt on the 4.7" and 5.4" class) | |
| Card gap | 12 pt | |
| Radius | 12 chip, 16 tile, 22 card, 28 sheet and hero, full pill | Keeps today's `DesignSystem.Radius` values; continuous corners |
| Elevation | `flat`, `raised` (card: 1 soft shadow), `floating` (Liquid Glass controls) | No more than three levels on screen |
| Touch target | At least 44 × 44 pt | Also on Watch-sized controls in widgets |

---

## 6. Liquid Glass and materials

Apple's iOS 26 Liquid Glass is for the **navigation and controls layer** that floats above content. LifeOS follows that:

- **Glass:** tab bar, Capture button, toolbars, sheet backgrounds, floating chips (for example "Ask"), the media controls over photos.
- **Not glass:** content cards, lists, charts. They use `color.surface`.
- Group neighbouring glass controls in one `GlassEffectContainer` so they blend and morph together.
- Never put glass on glass. A glass chip on a glass sheet becomes a tinted, solid chip.
- **Reduce Transparency on:** glass falls back to `color.surface.raised` with a hairline border. Test every glass screen this way.
- The existing `GlassSurface` modifier (`AppTheme.swift`) is replaced by the system `glassEffect` on iOS 26. Keep a compatibility version only if the minimum stays below iOS 26.

---

## 7. Core components (v1)

Each component is delivered with anatomy, sizes, every state (default, pressed, focused, selected, disabled, loading, error), light and dark, the largest text size, VoiceOver label pattern, motion and haptic.

| # | Component | Variants / notes |
| --- | --- | --- |
| 1 | Button | Primary, secondary, glass, plain, destructive; small / regular / large; loading state |
| 2 | Icon button | Glass and plain; 44 pt minimum target |
| 3 | Capture button | Centre of the tab bar; tap = capture, long-press = assistant; morphing glass |
| 4 | Tab bar | 5 items, Liquid Glass, minimises on scroll |
| 5 | Chip | Filter, suggestion (AI), status, removable |
| 6 | Segmented control | 2–4 options |
| 7 | Text field | Plain, with unit (kg, g, kcal), with voice button, error |
| 8 | Search field | With recent and suggested results |
| 9 | List row | Title, subtitle, value, icon, accessory; swipe actions |
| 10 | Section header | With optional action |
| 11 | Card | Hero, standard, compact; tappable with zoom transition |
| 12 | Metric tile | Label, value, unit, trend arrow, data colour icon |
| 13 | Metric ring | Single and stacked (macros); animated fill |
| 14 | Macro bar | Protein, carbs, fat with targets |
| 15 | Sparkline | 7 and 30 days, with goal line |
| 16 | Chart frame | Swift Charts styling: axes, labels, selection callout |
| 17 | Budget explainer | "1,571 base + 222 earned = 1,793"; expandable formula |
| 18 | Stepper / quick add | Water glasses, servings; haptic per step |
| 19 | Date scroller | Swipeable day header + calendar button |
| 20 | Empty state | Illustration or 3D still, one sentence, one action |
| 21 | Skeleton loader | Shimmer that respects Reduce Motion |
| 22 | Inline banner | Info, attention, error; dismissible |
| 23 | Toast | "Logged · Undo"; 4 s, swipe to dismiss |
| 24 | AI proposal card | What AI understood, editable items, Confirm / Edit; confidence indicator |
| 25 | Confidence indicator | High / medium / low with plain-words tooltip |
| 26 | Source badge | "On device", "Apple Watch", "Photo", "Voice", "Preset" |
| 27 | Photo card | Meal photo with lift effect and items overlay |
| 28 | Workout card | Activity icon, duration, kcal, source, "+X earned" |
| 29 | Toggle row and settings row | With explanation text |
| 30 | Sheet header | Title, close, primary action; grabber; detents |

**Code:** each component lives in the `DesignSystem` package with SwiftUI previews and snapshot tests (for example the open-source swift-snapshot-testing library) covering light, dark and accessibility XXL. Then the large view files are split: `FoodFlowViews.swift` and `TabViews.swift` are rebuilt from these components screen by screen in Phase 3.

---

## 8. Motion system

### 8.1 Motion tokens

| Token | SwiftUI | Use |
| --- | --- | --- |
| `motion.instant` | `.easeOut(duration: 0.12)` | Toggles, selection |
| `motion.spring.snappy` | `.snappy(duration: 0.3)` | Buttons, chips, small state changes |
| `motion.spring.smooth` | `.smooth(duration: 0.45)` | Card expand, sheet content, list insert |
| `motion.spring.gentle` | `.spring(duration: 0.6, bounce: 0.1)` | Hero changes, Life Orb level |
| `motion.spring.celebrate` | `.spring(duration: 0.7, bounce: 0.25)` | Streak kept, goal reached (rare) |
| `motion.number` | `.contentTransition(.numericText(value:))` | Every changing number |
| `motion.symbol` | `.symbolEffect(.bounce)`, `.drawOn` | Icon confirmations |

### 8.2 Choreography rules

1. One hero motion at a time. If the orb is animating, cards wait.
2. Things enter from where they come from: a logged meal flies from the Capture sheet into the orb; a Watch workout slides in from the top edge.
3. Stagger lists by 35 ms per item, at most 6 items, then the rest appear together.
4. Exits run at about 70% of the enter duration.
5. Nothing loops forever except the orb's slow breathing and the assistant's thinking state, and both stop when off screen.

### 8.3 Reduce Motion

| Normal | With Reduce Motion |
| --- | --- |
| Fly-in, zoom, parallax | Cross-fade |
| Orb breathing and liquid slosh | Static orb; level changes with a 0.2 s fade |
| Card tilt with device | Off |
| Number roll | Instant change |

### 8.4 Haptics map

| Event | `sensoryFeedback` | Notes |
| --- | --- | --- |
| Item logged (food, water, weight) | `.success` | Once per save, not per item |
| Picker or chip selection | `.selection` | |
| Stepper up / down | `.increase` / `.decrease` | |
| Touching the orb | `.impact(weight: .light)` | Rate-limited to once per 300 ms |
| Watch workout arrives and budget rises | `.impact(weight: .medium)` then `.success` | Only if the app is open |
| First time over budget today | `.warning` | Once per day |
| Destructive confirm | `.impact(weight: .heavy)` | |

---

## 9. Signature 3D specification

### 9.1 The Life Orb

The orb replaces today's calorie ring as the heart of the Today screen.

| Visual property | Driven by | Behaviour |
| --- | --- | --- |
| Liquid level | Calories eaten ÷ today's budget | 0–100% fill; above 100% the liquid tints `status.over` and the surface ripples once |
| Rim glow | Activity calories earned today | Brightness grows with earned kcal; one soft pulse when a new Apple Watch workout arrives |
| Inner layers (on tap) | Protein, carbs, fat share | Orb separates into three stacked translucent bands for 3 s, labelled with grams |
| Idle | Time | Breathes: scale 1.000 ↔ 1.015 over 4 s |
| Touch | Finger | Liquid wobbles (spring), light haptic |

**States to design:** first run (empty glass, hint "Log your first meal"), loading (soft shimmer), normal, near budget (90%+), over budget, stale data ("Updated 2 h ago", slight desaturation), offline, Reduce Motion, Low Power Mode.

**Sizes:** 240 pt hero on Today; 120 pt in the Nutrition header; 44 pt glyph version for widgets and the Watch (2D render).

**Asset spec (motion/3D designer → engineering)**

| Item | Budget |
| --- | --- |
| Model | Blender; glass shell and liquid as separate meshes; total ≤ 20,000 triangles |
| Textures | ≤ 1024 × 1024 each; environment lighting HDR ≤ 512 px |
| File | USDZ ≤ 2 MB |
| Material | Reality Composer Pro shader graph with exposed inputs: `fillLevel` (0–1.2), `rimIntensity` (0–1), `tint` (colour), `wobble` (0–1) |
| Fallbacks | 2.5D SwiftUI version using a Metal `layerEffect` shader with the same four inputs; plus pre-rendered PNGs for 0%, 25%, 50%, 75%, 100%, over |

**Engineering notes:** render in a `RealityView` (iOS 18+). SwiftUI state updates the material parameters, so no re-render is needed per frame. Pause the scene when the view disappears, in Low Power Mode and with Reduce Motion. Do not use SceneKit (deprecated).

### 9.2 Depth cards

- Cards tilt up to 4° on x and y with device motion (CoreMotion attitude, low-pass filtered), using `rotation3DEffect` with a 0.6 perspective.
- The top-edge sheen moves opposite to the tilt.
- Only hero and photo cards tilt, never lists. Off with Reduce Motion.

### 9.3 Meal lift (used in Phase 3)

- After a photo is taken, the foreground (plate) is cut out with Vision's foreground instance mask request (iOS 17+). It scales to 1.04, gains a soft shadow, and the background blurs and dims.
- While AI analyses, item labels appear one by one at the matching spots on the plate.
- If the cut-out fails, the full photo is shown with a vignette instead.

### 9.4 Shared visual language for later 3D

Define now, build later: streak medals (Phase 5) and the assistant orb (Phase 4) use the same glass material family, lighting and colour rules as the Life Orb, so the app has one 3D world, not several.

---

## 10. Iconography

| Concept | SF Symbol (starting point) |
| --- | --- |
| Today | `circle.circle` (or custom orb symbol) |
| Nutrition | `fork.knife` |
| Capture | `plus` morphing to `waveform` while listening |
| Training | `figure.strengthtraining.traditional` |
| You | `person.crop.circle` |
| Water | `drop.fill` |
| Activity earned | `flame.fill` |
| Apple Watch source | `applewatch` |
| AI on device | `sparkles` + "On device" badge |
| Preset | `star.square.on.square` |

Custom symbols (orb, brand mark) are made from SF Symbols app templates so they scale and animate like system symbols.

---

## 11. Weekly plan

| Week | Product designer | Motion/3D designer | iOS UI engineer |
| --- | --- | --- | --- |
| 3 | Token structure, naming, spacing, type ramp (direction-neutral) | Orb modelling base mesh | `DesignSystem` package skeleton, Style Dictionary pipeline |
| 4 | Fill colour and type values after D1; components 1–10 | Orb material look-dev | Tokens generated in code; CI lint for raw colours |
| 5 | Components 11–20 | Motion tokens, choreography clips | Components 1–10 built + snapshots |
| 6 | Components 21–30 | Orb states and fallbacks; depth cards | Components 11–20; orb in `RealityView` |
| 7 | Component documentation, usage do's and don'ts | Haptics map, meal-lift prototype | Components 21–30; 2.5D fallback orb |
| 8 | Design QA on device; fixes | Orb performance tuning with engineer | Performance pass; migration list for old theme code |

## 12. Deliverables checklist

- [ ] Token JSON (primitive, semantic, component) and generated Swift
- [ ] Colour role sheet with contrast ratios for every text pair, light and dark
- [ ] Type ramp sheet with Dynamic Type examples at default and XXL
- [ ] 30 components with full state sheets and VoiceOver labels
- [ ] Motion spec and a video library of every motion token
- [ ] Haptics map
- [ ] Life Orb USDZ, shader-graph material, fallback shader, PNG set
- [ ] Depth-card and meal-lift prototypes
- [ ] Icon map and custom symbols
- [ ] Design system documentation page (usage rules, do's and don'ts)
