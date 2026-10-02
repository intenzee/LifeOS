# Phase 1 · The three directions

Each direction is a token file in `design/tokens/directions/` and switches live in the app. All three share the information architecture, components and **data and status colours**, so the comparison is about look and feel only (Phase 1 §5).

Boards (rendered from the real SwiftUI components at 2×):

| Artefact | Board |
|---|---|
| Today | [compare-today.png](boards/compare-today.png) |
| Capture sheet | [compare-capture.png](boards/compare-capture.png) |
| Meal result (AI proposal card) | [compare-mealResult.png](boards/compare-mealResult.png) |
| Workout synced | [compare-workoutSynced.png](boards/compare-workoutSynced.png) |
| App icon (120 / 60 / 29 pt) and wordmark | [compare-appIcon.png](boards/compare-appIcon.png) |
| Apple Watch dashboard and circular complication | [compare-watch.png](boards/compare-watch.png) |
| Life Orb, 8 states × 3 directions × dark and light | [orb-states.png](boards/orb-states.png) |
| Each direction in both modes | `boards/direction-<id>-{1,2,3}.png` |

## 1. Values

| | Obsidian & Champagne | Porcelain | Aurora Glass |
|---|---|---|---|
| Primary mode | Dark | Light | Dark |
| Background (dark / light) | `#0B0B0D` / `#F5F2EC` | `#12110F` / `#F6F3EE` | `#07090F` / `#F2F4F9` |
| Accent (dark / light) | champagne `#D8C3A5` / brass `#7A5F33` | `#6FC2A6` / emerald `#0F5C4A` | mint `#70EDC6` / `#0B7A5E` |
| Display and number face | New York (serif) | New York (serif) | SF Pro Rounded |
| Glass usage | Controls only | Tab bar | Every floating layer |
| Cards | Matte, 0.5 pt champagne hairline | Paper, soft shadow | Solid on aurora glow |
| Orb | Smoked glass, liquid gold | Frosted porcelain, emerald | Clear glass, mint → violet aurora |
| Motion bounce scale | 0 (weighty, precise) | 0.5 (gentle, editorial) | 1.0 (fluid, lightly springy) |
| Hero background | Warm radial glow | Soft daylight gradient | Two blurred aurora glows |

**Light-mode fix for A11:** each direction has a light-mode accent of at least 4.8:1. The old mint was 1.44:1 on white and is now used only in dark mode.

## 2. Accessibility, verified automatically

The generator (`gen_tokens.py --check`) and `TokenContrastTests` enforce these rules for every direction in both modes. CI fails if any is broken.

| Rule | Worst case across all 6 themes |
|---|---|
| Primary text on background ≥ 7:1 | 16.5:1 |
| Secondary text on surface and background ≥ 4.5:1 | 4.9:1 (Porcelain light) |
| Tertiary text ≥ 3:1 | 3.1:1 (Porcelain light) |
| Accent on background and surface ≥ 4.5:1 | 4.8:1 (Aurora light) |
| Label on filled accent ≥ 4.5:1 | 5.3:1 |
| Every data and status colour on background, surface and raised surface ≥ 4.5:1 | ✅ all pass |
| Data colours distinguishable under protanopia, deuteranopia and tritanopia (ΔE ≥ 8) | min 9.2 dark, 9.7 light, excluding 2 exempt pairs |

**Exempt pairs:** energy/carbs and sleep/water are close hues by design. They never appear side by side without labels; every chart labels its series directly.

**Shared data palette:**

| Metric | Dark | Light |
|---|---|---|
| Energy | `#F2A65A` | `#A0560B` |
| Activity | `#5FD6C2` | `#0F7468` |
| Protein | `#F08A8A` | `#B03B48` |
| Carbs | `#E3D3A8` | `#7F6227` |
| Fat | `#B67CDE` | `#541F7A` |
| Water | `#8BD6EE` | `#1750A1` |
| Sleep | `#7C86F7` | `#4A4FC4` |
| Weight | `#B4AEA7` | `#322F2A` |

The colour-blindness check changed three of the first-draft data colours. Fat and water had merged under deuteranopia (ΔE 3.7). Weight had merged with protein under protanopia.

**Status colours:**

| Status | Dark | Light |
|---|---|---|
| On track | `#8CC9A8` | `#2B7350` |
| Attention | `#E6B566` | `#8F5E0E` |
| Over (copper, never alarm red) | `#D98C5F` | `#A0491F` |
| Critical (errors only) | `#F0716A` | `#BF3328` |
| Info | `#8FB3D9` | `#2B5F91` |

## 3. Observations from the renders (team critique against the five principles)

**Obsidian & Champagne**
- **Strengths:**
  - The serif 640 has the most "private bank" presence.
  - The champagne Capture button is the one warm accent on screen, so it obeys "accent under 5%".
  - The gold liquid orb is distinctive.
- **Weaknesses:**
  - The smoked shell reads murky in light mode. It was lightened once already and needs Phase 2 look-development.
  - Champagne next to `data.energy` amber can blur together. Keep the accent off energy UI.

**Porcelain**
- **Strengths:**
  - The calmest, most legible Today in daylight.
  - The emerald orb on ivory is elegant.
  - Serif reads as editorial, not dated.
- **Weaknesses:**
  - As the plan predicted, the dark mode is a derived design and is the least characterful of the three.
  - The secondary text is at the 4.9:1 floor.

**Aurora Glass**
- **Strengths:**
  - The closest to today's app, so migration risk is lowest.
  - The luminous mint→violet orb is the most "alive".
- **Weaknesses:**
  - The least distinctive; it looks like other fitness apps.
  - Rounded numerals feel friendlier, not more premium.
  - Glass "everywhere" carries the highest Reduce Transparency fallback cost.

**All three, and already fixed in the mockups:**
- The remaining-calories number moved off the liquid. Its contrast varied with the fill level.
- The macro-layer labels pick black or white per scheme. Black on light-mode data colours failed contrast.

## 4. Motion personality

Each direction scales spring bounce, through `LXDirection.motionBounceScale` feeding `LXMotion`:
- Obsidian has no bounce.
- Porcelain is half.
- Aurora is full.

Reduce Motion swaps every token for a 0.2 s cross-fade, and number rolls change instantly (unit-tested).

The 10-second motion clips are a screen recording of the Direction Lab orb playground on the iPhone, one per direction. They are pending device access.
