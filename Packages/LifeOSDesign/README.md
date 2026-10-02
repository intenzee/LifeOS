# LifeOSDesign: test harness for the LifeOS design system

The design system's sources live in **`LifeOS/DesignSystem/`**. Xcode's synchronized folder compiles them straight into the app, so there are no project-file edits and no `import`. This package reaches the same files through the `Sources/LifeOSDesign` symlink, so the design system can be tested with plain `swift test`, even on a Mac with only the Command Line Tools.

```
cd Packages/LifeOSDesign
swift test                                        # tokens, motion, orb, snapshots
LX_RECORD=1 swift test --filter ComponentSnapshots   # re-record reference images after an intended change
LX_RENDER_DIR=/tmp/lx swift test --filter RenderMockups   # render Phase 1 mockups and orb states to PNG
```

## What's tested

| Suite | Checks |
|---|---|
| `TokenContrastTests` | Every direction × light/dark meets the contrast rules; Increase Contrast promotes secondary text; over-budget is copper, not red |
| `MotionTests`, `LayoutTokenTests` | Reduce Motion swaps every animation; stagger cap; 4 pt grid; radius scale |
| `OrbStateTests`, `OrbTransparency`, `OrbPerformance` | NaN and zero-budget safety, 120% cap, macro shares; the glow halo is never clipped; frame-time budget |
| `ComponentSnapshots` | 11 gallery sections × light / dark / accessibility-XXL against `__Snapshots__/`; XXL never overflows the width |
| `RenderMockups` | Opt-in: writes the Phase 1 direction boards |

## Layout of `LifeOS/DesignSystem/`

| Folder | Contents |
|---|---|
| `Tokens/` | Generated from `design/tokens`; do not edit by hand |
| `Foundations/` | `LXTheme` (`.lx(role)` colours), `lxFont`, `LXMotion`, `LXHaptic`, `lxCard`, `lxGlass` |
| `Components/` | The 30 core components ([inventory](../../docs/uiux-plan/phase2/README.md)) |
| `Orb/` | `LifeOrb` (2.5D, default), `LifeOrbRealityView` (RealityKit spike), `AdaptiveLifeOrb` |
| `Lab/` | Direction Lab, mockups, component gallery (Settings → Direction Lab) |

Settings mirror the app target (Swift 5 mode, MainActor default isolation), so anything that compiles here compiles in the app.
