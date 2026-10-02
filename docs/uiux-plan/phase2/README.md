# Phase 2: Design System and Signature 3D, status

This tracks `../02_Phase2_Design_System_and_3D.md`. Branch `uiux/phase2-design-system` is stacked on `uiux/phase1-direction`.

**Verified:**
- Builds for iOS on the owner's iPhone 15 (Xcode 27, device build, no simulator).
- Ran on the device: Direction Lab and orb, plus a screenshot check.
- `swift test` in `Packages/LifeOSDesign`: 18 suites, including 33 component snapshots.

## Gate D2 criteria

| Criterion | Status |
|---|---|
| Token JSON is the single source; Swift generated; no hand-typed colours in feature code | ✅ Pipeline: `design/tokens` → `design/tools/gen_tokens.py` (CI `--check`). 🟡 Feature code still holds 357 raw colours; `design/tools/lint_raw_colors.py` ratchets them down (CI) as screens migrate in Phase 3 |
| 30 core components, snapshot-tested in light, dark and largest text | ✅ All 30 (table below). Snapshots: 11 gallery sections × light/dark/accessibility-XXL, rendered headless |
| Motion spec implemented as named animations | ✅ `LXMotion` (instant, snappy, smooth, gentle, celebrate), stagger, exit at 70%, `lxNumberRoll`; Reduce Motion swaps tested |
| Haptics map implemented | ✅ `LXHaptic` (§8.4) via `sensoryFeedback`; orb touch rate-limited to 300 ms |
| Life Orb final USDZ + material at frame rate | ⏳ Needs Blender + Reality Composer Pro assets (motion/3D designer). The RealityKit host is ready (`LifeOrbRealityView`) |
| 2.5D fallback orb matches the 3D orb's states | ✅ `LifeOrb` is the shipping default: fill, rim, over-tint, wobble, breathing, layers, stale, Reduce Motion/Transparency, Low Power |
| Old `ThemePalette`, `GlassSurface`, `DesignSystem.Radius` wrapped or replaced, with a migration list | 🟡 Migration list: [phase1/01-audit-board.md §7](../phase1/01-audit-board.md). Replacement happens per screen in Phase 3, each verified on device; a blind global swap would re-theme ~20 unverified screens at once |

## Component inventory (Phase 2 §7)

| # | Component | API | File |
|---|---|---|---|
| 1 | Button: primary, secondary, glass, plain, destructive; loading | `.buttonStyle(.lx(.primary, loading:))` | `Components/LXComponents.swift` |
| 2 | Icon button (44 pt, glass or plain) | `LXIconButton` | same |
| 3 | Capture button (tap = capture, long-press = assistant) | inside `LXTabBar` | `Components/LXTabBar.swift` |
| 4 | Tab bar, 5 labelled items, Liquid Glass | `LXTabBar` | same |
| 5 | Chip: filter, suggestion, status | `LXChip` | `LXComponents.swift` |
| 6 | Segmented control | `LXSegmented` | `Components/LXInputs.swift` |
| 7 | Text field: unit, voice, error | `LXTextField` | same |
| 8 | Search field with recents and suggestions | `LXSearchField` | same |
| 9 | List row; swipe delete + undo convention | `LXListRow`, `.lxDeleteSwipe` | `Components/LXStructure.swift` |
| 10 | Section header | `LXSectionHeader` | `LXComponents.swift` |
| 11 | Card: hero, standard, compact; zoom source | `LXCard`, `.lxZoomSource/Destination` | `LXStructure.swift` |
| 12 | Metric tile | `LXMetricTile` | `LXComponents.swift` |
| 13 | Metric ring, single and stacked | `LXMetricRing` | `Components/LXData.swift` |
| 14 | Macro bar | `LXMacroBar` | `LXComponents.swift` |
| 15 | Sparkline with goal line | `LXSparkline` | `LXData.swift` |
| 16 | Chart frame (Swift Charts house style) | `LXChartFrame` | same |
| 17 | Budget explainer (expandable formula) + chip | `LXBudgetExplainer`, `LXBudgetChip` | same / `LXComponents.swift` |
| 18 | Stepper / quick add, haptic per step | `LXQuickStepper` | `LXInputs.swift` |
| 19 | Date scroller (swipe days, calendar, back to today) | `LXDateScroller` | `LXData.swift` |
| 20 | Empty state | `LXEmptyState` | `Components/LXFeedback.swift` |
| 21 | Skeleton (Reduce Motion: no shimmer) | `LXSkeleton` | same |
| 22 | Inline banner: info, attention, error | `LXInlineBanner` | same |
| 23 | Toast: "Logged · Undo", 4 s, swipe away | `LXToast`, `.lxToast($model)` | same |
| 24 | AI proposal card (low confidence first) | `LXProposalCard` | same |
| 25 | Confidence indicator | `LXConfidenceDot` | `LXComponents.swift` |
| 26 | Source badge | `LXSourceBadge` | same |
| 27 | Photo card with lift + labels | `LXPhotoCard` | `LXFeedback.swift` |
| 28 | Workout card: synced or planned (outlined) | `LXWorkoutCard` | same |
| 29 | Toggle row and settings row | `LXToggleRow`, `LXSettingsRow` | `LXInputs.swift` |
| 30 | Sheet header + native sheet style | `LXSheetHeader`, `.lxSheetStyle()` | `LXStructure.swift` |

**Accessibility built in:**
- Every component carries VoiceOver labels and values.
- `LXAdaptiveStack` switches to vertical layouts at accessibility text sizes.
- Numbers never wrap: they keep one line and scale down to 0.6×.
- Chips never break mid-word.

These rules exist because the XXL snapshots exposed broken layouts ("62 / 0", "Protei / n") before the fixes.

**Gallery:** on the device, open Settings → Direction Lab → Component gallery, which has an XXL toggle. To open the Lab directly, launch with the `LX_DIRECTION_LAB` argument (DEBUG only).

## Found and fixed on the device

- **Clipped glow halo.** The orb's rim-glow halo was clipped at the canvas edge and showed as a faint square on the iPhone. Pixel sampling confirmed it. The canvas now overflows its frame by 1.4×, and `OrbTransparency` tests the canvas edges.
- **Truncated direction names.** They are now short in the Lab's segmented picker.

## Commands

```
python3 design/tools/gen_tokens.py --check
python3 design/tools/lint_raw_colors.py            # --report, --update
cd Packages/LifeOSDesign && swift test             # LX_RECORD=1 to re-record snapshots
```

Device build (no simulator):

```
xcodebuild -project LifeOS.xcodeproj -scheme LifeOS -configuration Debug \
  -destination id=<iPhone UDID> -allowProvisioningUpdates build
```

## Remaining Phase 2 work that needs people or assets

- Life Orb USDZ (Blender, ≤ 20k triangles, ≤ 2 MB) and the Reality Composer Pro shader graph with `fillLevel`, `rimIntensity`, `tint` and `wobble` inputs.
- Motion video library: screen recordings of each token on the device.
- Depth-card tilt (CoreMotion) and the meal-lift Vision cut-out prototype. These are the next engineering items and need on-device iteration.
- Colour and type values for the winning direction after gate D1.
