# Phase 1: Discovery and Direction, deliverables

These are the working files for `../01_Phase1_Discovery_and_Direction.md`. The team produced everything here except the items only the owner can provide: the diary and the final pick at gate D1.

| Phase 1 §8 checklist item | Status | Where |
|---|---|---|
| Audit board: all screens, A1–A12 plus new issues, each with severity | ✅ Code audit, 32 issues. Device screenshots are still to add | [01-audit-board.md](01-audit-board.md) |
| Usage diary synthesis | ⏳ Owner, 5 days. Template and prompts ready | [02-research-kit.md](02-research-kit.md) §1 |
| Reference teardown board | ⏳ Template and capture checklist ready; owner or team to fill | [02-research-kit.md](02-research-kit.md) §2 |
| Three directions × 6 artefacts | ✅ Rendered from real SwiftUI components | [boards/](boards), [03-directions.md](03-directions.md) |
| Motion study per direction | 🟡 Motion personality is encoded (`motionBounceScale`) and playable in the Direction Lab. 10 s clips need a device screen recording | [03-directions.md](03-directions.md) §4 |
| Life Orb concept render per direction | ✅ Eight states × 3 directions × 2 modes | [boards/orb-states.png](boards/orb-states.png) |
| Rubric scores | 🟡 Objective criteria scored; subjective ones are provisional until the owner's day with each | [05-decision-record.md](05-decision-record.md) |
| Spike report: orb frame time, Liquid Glass | 🟡 Built and measured on Mac; on-iPhone measurement pending | [04-spike-report.md](04-spike-report.md) |
| Decision record | 🟡 Recommendation written; owner sign-off at D1 | [05-decision-record.md](05-decision-record.md) |

## How to use this

1. **On the iPhone:** Settings → **Direction Lab**. Switch directions, play with the orb (tap, sliders), view each mockup, then tap **Use … everywhere**. Live with each direction for a day.
2. **Regenerate tokens** after editing `design/tokens/*.json`:
   ```
   python3 design/tools/gen_tokens.py
   python3 design/tools/gen_tokens.py --check   # CI: stale output or broken contrast/CVD rule fails
   ```
3. **Run the design-system tests** (Command Line Tools only, no Xcode needed):
   ```
   cd Packages/LifeOSDesign && swift test
   ```
4. **Re-render the boards:**
   ```
   cd Packages/LifeOSDesign && LX_RENDER_DIR=/tmp/lx swift test --filter RenderMockups
   python3 design/tools/contact_sheet.py /tmp/lx docs/uiux-plan/phase1/boards
   ```

## Code produced in this phase

These are the foundations Phase 2 builds on:

| Path | What |
|---|---|
| `design/tokens/` | Token source of truth: `core.json`, `color.shared.json`, `directions/*.json` |
| `design/tools/gen_tokens.py` | Generator plus contrast and colour-blindness rule checker (stdlib only) |
| `LifeOS/DesignSystem/Tokens/LXTokens.generated.swift` | Generated tokens |
| `LifeOS/DesignSystem/Foundations/` | `LXTheme` (environment, `.lx(_:)` ShapeStyle), typography (`lxFont`), motion (`LXMotion`, `lxAnimation`, `lxNumberRoll`), haptics (`lxHaptic`), surfaces (`lxCard`, `lxGlass`, `LXScreenBackground`) |
| `LifeOS/DesignSystem/Components/` | Button styles, icon button, chip, section header, metric tile, progress bar, macro bar, source badge, confidence dot, budget chip, 5-tab bar with Capture button |
| `LifeOS/DesignSystem/Orb/` | `LifeOrb` (2.5D Canvas), `LifeOrbRealityView` (RealityKit spike), `AdaptiveLifeOrb` + `LXRenderQuality` |
| `LifeOS/DesignSystem/Lab/` | The six mockup artefacts and the in-app Direction Lab |
| `Packages/LifeOSDesign/` | SwiftPM test harness (symlinks to the sources above) |

The app compiles `LifeOS/DesignSystem/` through its synchronized folder, so the Xcode project file was not touched. The only edits to existing app files are two lines: `LifeOSApp.swift` applies the chosen direction, and `TabViews.swift` adds the Direction Lab row in Settings.
