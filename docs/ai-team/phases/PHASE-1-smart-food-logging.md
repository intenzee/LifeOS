# Phase 1 — Smart Food Logging (Weeks 4–9) → Beta 1

> **Status (3 Oct 2026):** implemented for non-Apple-Intelligence devices (iPhone 15) — see [`../phase-1/PHASE-1-REPORT.md`](../phase-1/PHASE-1-REPORT.md).

**Goal:** make logging food effortless: say it, snap it, or tap a preset — free, mostly on-device, with honest confidence and instant undo.

## Scope
| In | Out |
|---|---|
| F02 natural-language + voice logging (en, Hinglish) | Assistant chat (Phase 3) |
| F03 presets: create/use/variants/suggestions/maintenance (remind & auto-log built but flagged off) | Preset notifications (enabled in Phase 4) |
| F04 photo v2: camera, Gateway tiers, schema v2, resolver, calibrated confidence, label OCR, barcode cache | LiDAR portions (Phase 5 spike) |
| Nutrition DB v1 (USDA subset + curated Indian table + unit map) | Full Hindi UI |

## Entry criteria
- Phase 0 exit met.
- C1: `FoodEntry` and `FoodPreset` SwiftData models available (or a temporary adapter over current managers, agreed with iOS Core).
- C6: Design delivers confirmation card, voice sheet, camera screen and chip specs by week 5.
- Legal answer on Indian nutrition data licensing by week 4.

## Sprint plan
| Sprint | Weeks | Food engineer (A) | Brain engineer (B) | QA |
|---|---|---|---|---|
| 1 | 4–5 | Speech service; pre-parser; ParsedMeal schema + prompt; Nutrition DB build pipeline | Preset model + migration from favorites/custom; preset resolver (exact/fuzzy/semantic/time) | Collect 500 food utterances; begin weighed-photo collection |
| 2 | 6–7 | Nutrition Resolver + confidence; confirmation card integration; refine-by-text; deterministic fallback | Define-by-voice; naming prompt; variants diff; routine miner; maintenance jobs | Food-text eval full run; preset eval |
| 3 | 8–9 | Custom camera + hints; photo schema v2 + resolver integration; confidence calibration; label OCR; barcode offline cache; per-item corrections | Watch preset digest + widget data provider (with Watch team); polish | Photo eval (≥ 150 meals by now); beta test plan |

## Deliverables
- Voice/text logging from Home quick action and food sheet.
- Presets screen data + AI suggestion card.
- New camera with photo, label and barcode modes.
- Eval report v1 (text, presets, photo).
- TestFlight **Beta 1**.

## Exit criteria
- [ ] Food-text item F1 ≥ 0.90 on T1 (1.0 bar is 0.92) and works offline.
- [ ] Photo kcal MAPE ≤ 30% on current photo set via T1/T2 (1.0 bar is 25%).
- [ ] Every AI-logged entry has provenance and undo.
- [ ] No-key users on Apple Intelligence devices get full AI logging.
- [ ] Beta crash-free sessions ≥ 99.5%.

## Demo script
1. Say "two rotis, dal makhani and curd for lunch" → card → log → undo → log.
2. "Save this as my usual lunch." Next day: "log my usual lunch but no curd."
3. Photograph a thali with no API key set → items with portions → correct one item by voice → re-scan similar plate → learned result.
4. Scan a nutrition label of a packaged snack.
