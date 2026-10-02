# 08 — Premium UI Engineering: Design System, Motion, 3D

> **Squad:** UI Engineering · **Phases:** foundations P1 (parallel), hero work P4 · **Depends on:** 01 (`LifeOSDesign` package), design-team specs (Figma) · **Consumers:** every feature squad
> **Scope note:** this document covers the **engineering** of the premium look and feel: architecture, rendering tech, performance and accessibility. Visual direction, layouts and copy come from the UI/UX design team. Tickets marked 🎨 are blocked on a design deliverable.

---

## 1. Goal

LifeOS should **look and feel like a flagship, well-funded product**: depth, materials, fluid physics-based motion, tasteful 3D, rich haptics. It must hold 120 fps on ProMotion devices and stay accessible. Feature squads should get this quality by default, by composing components rather than hand-tuning each screen.

---

## 2. Current state
- `DesignSystem` spacing/typography (`AppTheme.swift`), radius scale and semantic colours (`DesignSystemKit.swift`), an environment `palette`, a custom "liquid-glass" floating tab bar, and aurora backgrounds. This is a good seed.
- Inconsistencies: views still instantiate `ThemePalette(colorScheme:)` locally, there are ad-hoc animations, no motion tokens, no haptics system, no 3D, no component gallery and no snapshot tests.

---

## 3. Architecture — `LifeOSDesign` package

```
LifeOSDesign/
├── Tokens/          # Generated from design tokens JSON (color, type, spacing, radius, elevation, materials, motion)
├── Foundations/     # Typography styles, Materials (glass/frosted), Elevation/shadows, Iconography
├── Motion/          # Spring presets, transitions, matched-geometry helpers, PhaseAnimator/KeyframeAnimator recipes
├── Haptics/         # Core Haptics patterns (+ .sensoryFeedback wrappers), sound cues (optional)
├── Components/      # Card, HeroRing, MetricTile, ProgressBar, Chip, Button styles, Sheet, TabBar, Toast, EmptyState, Skeleton
├── Charts/          # Swift Charts wrappers with house style (trend, bars, macro donut, sparkline)
├── Effects/         # Metal shaders (.colorEffect/.distortionEffect/.layerEffect), MeshGradient backgrounds, parallax
├── ThreeD/          # RealityKit views + static fallbacks, asset loader, quality tiers
└── Gallery/         # Debug-only "Design Gallery" app screen + preview catalog
```

### 3.1 Token pipeline
- The design team maintains tokens as **Figma variables**, exported as JSON (W3C design-tokens format).
- A build-time script (Swift Package plugin or a `Scripts/gen-tokens` run in CI) generates `Tokens.generated.swift`.
- Tokens are semantic (`surface.elevated`, `text.secondary`, `accent.energy`, `motion.snappy`), never raw hex values in feature code. A SwiftLint custom rule bans `Color(red:` and `.animation(.spring(` outside `LifeOSDesign`.

### 3.2 Motion system
| Token | Definition (starting point, tuned with design) | Use |
|---|---|---|
| `motion.snappy` | `.spring(duration: 0.3, bounce: 0.15)` | Taps, toggles, chips |
| `motion.smooth` | `.spring(duration: 0.5, bounce: 0.0)` | Sheet/content transitions |
| `motion.bouncy` | `.spring(duration: 0.6, bounce: 0.3)` | Celebratory moments (goal hit) |
| `motion.hero` | Keyframes, ~0.9 s | Ring fill on launch, workout-synced moment |
| `motion.reduced` | Opacity crossfade 0.2 s | Used automatically when Reduce Motion is on |

- `withDesignAnimation(.snappy) { … }` and `.designTransition(.cardPush)` helpers read the accessibility environment and swap in reduced variants automatically.
- Use `matchedGeometryEffect` / `NavigationTransition.zoom` (iOS 18) for card → detail continuity.
- **Numeric transitions:** `contentTransition(.numericText())` for all changing metrics (calories, water, steps).

### 3.3 Haptics
`Haptics.play(.success | .logConfirmed | .goalHit | .workoutSynced | .tick | .warning)` uses `.sensoryFeedback` for simple cases and custom `CHHapticPattern` files (AHAP) for signature moments. Every logging action gets a confirm haptic, and every haptic has a user toggle.

### 3.4 Materials & Liquid Glass
- **iOS 26+:** adopt the system **Liquid Glass** APIs (`glassEffect`, glass button styles, `GlassEffectContainer`) for the tab bar, toolbars, floating action and sheets. The system look stays native and coherent.
- **iOS 18–25:** keep the existing custom glass (blur + gradient stroke + specular highlight) as the fallback, behind the same `GlassSurface` component API.
- **Reduce Transparency** → solid elevated surfaces.

### 3.5 3D — technology choices
| Tech | Use for | Notes |
|---|---|---|
| **RealityKit** (`RealityView`, iOS 18+) | Hero 3D objects (energy orb, medals, body map) | Apple's current 3D direction. USDZ assets from Reality Composer Pro. PBR materials, lighting. |
| SceneKit | Avoid for new work | Apple has steered new 3D work to RealityKit |
| **SwiftUI + Metal shaders** | "2.5D" depth: shimmer, liquid fill, glow, ripple on log, parallax | Cheap, works everywhere, iOS 17+ |
| `MeshGradient` (iOS 18) | Living, animated backgrounds (aurora upgrade) | Animate control points slowly. Pause off-screen. |
| Rive (MIT runtime) or Lottie (Apache-2.0) | Character/illustrative animations (empty states, onboarding, achievements) | Designer-authored. State machines (Rive) react to data. |

### 3.6 Signature 3D/motion moments (engineering candidates — final picks by design 🎨)
| Moment | Description | Tech |
|---|---|---|
| **Energy Orb** (Home hero) | A glass/liquid sphere whose fill level and glow show calories left. Liquid sloshes with device tilt (CoreMotion, low rate). It pulses when a Watch workout adds budget. | RealityKit or Metal shader fallback |
| **Body Map** (Train) | 3D anatomical figure, muscles tinted by weekly training volume, rotatable. Tap a muscle to filter exercises. | RealityKit + USDZ (licensed or commissioned asset) |
| **Achievement medals** | 3D medallions for streak milestones. Spin with a gesture. Haptic "clink". | RealityKit |
| **Workout-synced moment** | Ring sweeps, numeric roll, particle burst (subtle), haptic | SwiftUI keyframes + shader |
| **Onboarding cinematic** | 10–15 s branded intro: depth layers, orb forms, personalised numbers appear | Rive / keyframes |
| **Meal photo reveal** | Scan result "develops" with a shader, items fly into the macro bar | Shader + matched geometry |

### 3.7 Performance budgets (enforced)
| Metric | Budget |
|---|---|
| Frame time on hero screens (ProMotion) | ≤ 8.3 ms p95 (120 fps). ≤ 16.7 ms on 60 Hz devices. |
| Hitches | Hitch-time ratio < 5 ms/s (Instruments "Hitches") |
| 3D scene first render | < 300 ms after view appears (preload on launch idle) |
| Extra memory per 3D scene | < 80 MB |
| Scrolling Home with all cards | No dropped frames during a 10 s fling test |
| Thermal | At `.serious` thermal state or in Low Power Mode, switch 3D to a static render and pause animated backgrounds |

**Quality tiers:** `RenderQuality.high/medium/low`, chosen by device class, thermal state, Low Power Mode and accessibility settings. Every effect declares its behaviour per tier.

### 3.8 Accessibility (non-negotiable)
- Dynamic Type to AX5 without truncating key numbers (layouts switch to vertical stacks).
- VoiceOver: every hero visual has a meaningful label ("Calories: 538 of 1,798 left"). 3D objects are `accessibilityHidden` with an equivalent text element.
- Reduce Motion, Reduce Transparency, Increase Contrast and Differentiate Without Colour are all honoured.
- Contrast ≥ 4.5:1 for text, verified by automated checks in snapshot tests.

---

## 4. Tickets

### P1 — Foundations (parallel with feature work)
| ID | Title | Size | Acceptance criteria |
|---|---|---|---|
| UI-01 | `LifeOSDesign` package skeleton + Gallery screen | S | Package builds for iOS/watchOS. A debug-only Gallery lists all components with light/dark/AX toggles. |
| UI-02 | Token pipeline 🎨 | M | Figma JSON → generated Swift. CI fails if tokens change without regenerated code. Lint bans raw colours/springs outside the package. |
| UI-03 | Motion tokens + reduced-motion helpers | S | §3.2. Unit test that Reduce Motion swaps animations. |
| UI-04 | Haptics library | S | §3.3. AHAP files for 3 signature moments. Settings toggle. |
| UI-05 | Core components v1 🎨 | L | Card, MetricTile, HeroRing, Chip, Buttons, Toast, Skeleton, EmptyState, Sheet. Snapshot tests (light/dark/AX3). |
| UI-06 | Migrate existing screens to tokens/components | L | Home, Food and Train use components. No local `ThemePalette(colorScheme:)` instantiation left. |

### P3–P4 — Premium experience
| ID | Title | Size | Acceptance criteria |
|---|---|---|---|
| UI-10 | Liquid Glass adoption (iOS 26) with fallback | M | §3.4. `GlassSurface` API. Tab bar, toolbars and sheets. Visual parity checks on 18 vs 26. |
| UI-11 | Living background (`MeshGradient` + shader) | S | Animated, pauses off-screen and in low tiers. ≤ 1 ms GPU per frame. |
| UI-12 | Energy Orb hero 🎨 | L | §3.6. Reacts to budget changes and tilt. Static fallback. Meets §3.7 budgets. |
| UI-13 | Workout-synced moment | M | Triggered by WCH-10. Ring sweep + numeric roll + haptic. Reduced-motion variant. |
| UI-14 | Budget breakdown sheet (waterfall) 🎨 | M | Renders `BudgetBreakdown` (CAL-07). Animated bars. VoiceOver reads each line. |
| UI-15 | Body Map 3D 🎨 | XL → split | Asset licensed/commissioned. Muscle tint from weekly volume. Gesture rotate. Tap-to-filter. Low-tier 2D fallback. |
| UI-16 | Achievement medals 3D 🎨 | M | Milestones from `StreakManager`. Gesture spin. Haptic. Share card export (image). |
| UI-17 | Meal-scan reveal effect | S | Shader "develop" + matched geometry into the macro bar |
| UI-18 | Onboarding cinematic 🎨 | M | Rive/keyframes. Skippable. Personalised numbers. < 2 MB assets. |
| UI-19 | Charts house style | M | Trend, macro donut, sparkline, week bars via Swift Charts. Interactive scrubbing with haptic ticks. |
| UI-20 | Widget & Live Activity styling | M | Matches tokens. Lock Screen legibility. Watch complications consistent. |
| UI-21 | Quality tiers + thermal manager | S | §3.7 tiers switch live on thermal/LPM notifications |
| UI-22 | Accessibility audit & fixes | M | §3.8 checklist passes on all P1–P4 screens (Accessibility Inspector + manual VoiceOver run) |

---

## 5. Inputs required from the design team (to unblock 🎨 tickets)
1. Figma variables for colour, type, spacing, radius, elevation and motion (named semantically).
2. Component specs with states (default, pressed, disabled, loading, error), including AX sizes.
3. Hero moment storyboards with timing curves (or Rive files).
4. 3D assets as USDZ (or source files plus a material spec), with a polygon budget agreed with engineering (target < 50k tris per hero object).
5. Typeface choice, and licence confirmation for app embedding.
6. Haptic/sound intent per moment.

---

## 6. Open questions
1. Custom typeface vs SF Pro/SF Rounded? (Licensing and Dynamic Type implications.)
2. Body Map asset: commission vs license? It drives timeline and cost.
3. Should Liquid Glass on iOS 26 replace the custom glass look entirely, or keep brand-specific tinting?
