# Phase 1 · Spike report: Life Orb and Liquid Glass

**Environment:** this Mac currently has only the Command Line Tools (Swift 6.4, macOS SDKs). Xcode is not installed, so:
- The iOS target has not been compiled in this phase.
- Nothing has been installed on the iPhone.
- The two on-device measurements below are still to do.

Everything that could be checked without Xcode was checked.

## 1. Life Orb, 2.5D (default path)

**Implementation:** `LifeOS/DesignSystem/Orb/LifeOrb.swift`.
- A SwiftUI `Canvas` inside `TimelineView(.animation)`.
- Draws, in order: rim glow, contact shadow, glass back face, two-layer liquid with meniscus, inner depth, refraction edge, specular highlight.
- Inputs match the Phase 2 §9.1 material spec:
  - `fillLevel` 0–1.2 (clamped and NaN-safe)
  - `rimIntensity` 0–1
  - `tint` (over-budget turns to `status.over`)
  - `wobble` 0–1
  - Also: `isStale` (desaturates) and `macroLayers` (tap-to-split bands)
- Idle breathing: scale 1.000 ↔ 1.015 over 4 s.
- **Pauses** off screen, with Reduce Motion, in Low Power Mode, and for frozen snapshot renders.
- Reduce Transparency makes the shell solid.

**Why Canvas rather than a Metal `layerEffect`:** Metal shaders need the `metal` compiler, which ships with Xcode, not the Command Line Tools. Canvas runs on iOS 17.6 (the current minimum), needs no asset, and measured fast enough (below). A Metal liquid shader stays a Phase 2 option if device profiling asks for it.

**Measured on this Mac** (`OrbPerformance` test): one 240 pt hero frame at 3× rasterised offscreen on the CPU.

| Metric | Time | Budget |
|---|---|---|
| p50 | 0.59 ms | — |
| p95 | 2.31 ms | 8.3 ms (120 Hz) |

This is a proxy: on device, Canvas is composited on the GPU and the cost profile differs. The test guards against regressions (fails above 25 ms p50).

**On-device check still to do** (Phase 1 exit criterion, owner's iPhone):
1. Settings → Direction Lab → orb playground.
2. Run Instruments → Animation Hitches for 30 s while dragging the sliders and tapping the orb.
3. **Pass** if frame time p95 ≤ 8.3 ms on ProMotion (≤ 16.7 ms at 60 Hz) and the hitch ratio is < 5 ms/s.
4. Record the result in §4.

## 2. Life Orb, RealityKit (`LifeOrbRealityView`, iOS 18+)

- **Proves:**
  - A `RealityView` hosts the hero.
  - SwiftUI state drives entity parameters through the `update:` closure without rebuilding the scene.
  - It compiles against the macOS 15+ SDK.
- **Placeholder:** the liquid is a vertically scaled sphere.
- **Needs before it can be compared fairly:**
  - A real liquid surface, which needs the Reality Composer Pro shader graph with the four exposed inputs. Reality Composer Pro needs Xcode.
  - A Blender USDZ (≤ 20k triangles, ≤ 2 MB).
- `AdaptiveLifeOrb` + `LXRenderQuality` choose RealityKit only when opted in and not in a low tier.
  - Low tier means Reduce Motion, Low Power Mode, or `.serious` thermal state; each drops to the static 2.5D orb.
  - Opt-in stays off until the RealityKit orb beats the 2.5D one on device.

**Recommendation:** ship the 2.5D orb as the default hero. Treat RealityKit as a Phase 2 upgrade, gated on the frame-time test and on the USDZ and material existing. That matches the plan's "2.5D fallback is part of the spike, not an afterthought".

## 3. Liquid Glass

- `lxGlass(in:)` uses the system `glassEffect` (interactive for controls) on iOS 26.
- On iOS 17.6–25 it falls back to `ultraThinMaterial` + hairline.
- With Reduce Transparency it uses a solid `surfaceRaised` + hairline.
- Snapshot renders use a translucent raised surface, because offscreen rendering cannot sample a backdrop.
- **Compiles** against the macOS 26 SDK (`glassEffect` has the same API on iOS 26).
- **Tab bar:** 5 labelled tabs plus a raised Capture button on one glass capsule. Tap captures; long-press opens the assistant, also exposed as a VoiceOver custom action.
- **Still to verify on device (iOS 26):**
  - Morphing between neighbouring glass controls once a `GlassEffectContainer` is added in Phase 2.
  - Legibility of glass over the aurora glow.
  - The "minimise on scroll" behaviour.

**Open decision for the owner** (master plan §10): if the iPhone runs iOS 26, raise the minimum to iOS 26 and delete the material fallback. That gives one look to design and test.

## 4. On-device results (fill in)

| Check | Result | Date |
|---|---|---|
| 2.5D orb p95 frame time, hitch ratio | | |
| RealityKit orb p95 frame time (after RCP material) | | |
| First frame ≤ 300 ms after Today appears | | |
| Glass tab bar legibility over each direction's hero | | |
| Reduce Transparency / Reduce Motion / largest text pass | | |
