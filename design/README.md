# design/: LifeOS design tokens and tooling

This folder is the single source of truth for every colour, type size, spacing value, radius, motion value and orb parameter in the app. Phase 2 §2 of the UI/UX plan explains the token structure.

```
design/
├── tokens/
│   ├── core.json            space, radius, type ramp, motion, orb sizes (direction-neutral)
│   ├── color.shared.json    data colours (energy, protein, water…) and status colours, shared by all directions
│   └── directions/          obsidian.json · porcelain.json · aurora.json (surfaces, text, accent, orb, motion feel)
└── tools/
    ├── gen_tokens.py        JSON → LifeOS/DesignSystem/Tokens/LXTokens.generated.swift; --check enforces contrast + colour-blind rules
    ├── lint_raw_colors.py   ratchet: raw colours in feature code may only go down (baseline: raw_colors_baseline.json)
    └── contact_sheet.py     builds the Phase 1 comparison boards from headless renders
```

## Change a colour or size

1. Edit the JSON in `tokens/`.
2. Run `python3 design/tools/gen_tokens.py`. It refuses to write if any text pair drops below its WCAG contrast minimum, or if two data colours become hard to tell apart under protanopia, deuteranopia or tritanopia.
3. Commit the JSON together with the regenerated Swift. CI runs `--check` and fails on stale output.

## Rules the generator enforces

| Pair | Minimum contrast |
|---|---|
| Primary text on background | 7:1 |
| Secondary text | 4.5:1 |
| Tertiary text | 3:1 |
| Accent | 4.5:1 |
| Label on accent | 4.5:1 |
| Every data and status colour on background, surface and raised surface | 4.5:1 |

Data colours must also differ by at least ΔE 8 under each colour-blindness simulation. Two pairs are exempt by design and are always labelled: energy/carbs and sleep/water.

Swift usage lives in `LifeOS/DesignSystem/`. Its tests are in `Packages/LifeOSDesign/`.
