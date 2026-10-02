# F04 — Meal Photo Capture v2

| | |
|---|---|
| **Phase** | 1 |
| **Owner** | AI Engineer A ("Food") |
| **Tiers** | Learned override → T1 (iOS 27 on-device vision) → T2 PCC → T3 Gemini/Groq BYOK → T4 Vision classifier |
| **Depends on** | F01, F02 Nutrition Resolver, existing `Services/MealVision/*`, Design camera states (C6) |

## 1. Today
`MealScannerEngine` runs: learned override (perceptual hash / feature print) → Groq vision with the user's key → Apple `VNClassifyImageRequest` single-label fallback. It supports natural-language refine and records corrections. Weaknesses: needs a third-party key for anything good; Groq vision models are preview-only; on-device fallback recognises one item; confidence is hard-coded; no portion reasoning; photo library picker rather than a purpose-built camera.

## 2. Outcome
A premium capture flow that, **without any key**, identifies every item on a plate (incl. Indian thalis), estimates portions, resolves nutrition from trusted sources where possible, shows honest confidence, and learns from every correction — all free.

## 3. Capture UX (with Design)
- Custom `AVCaptureSession` camera (not just the picker): full-bleed, haptic shutter, framing guide for "top-down 45°".
- Live hint chip from a lightweight on-device classifier every ~500 ms: "Food detected ✓" / "Move closer" / "Too dark".
- Optional second shot: "Add side view for better portions" (improves height/volume cues).
- Multi-photo meals (starter + main) aggregated into one meal.
- Photo library and **Share Sheet** import ("Share to LifeOS" from Photos/WhatsApp).
- Nutrition label mode and barcode mode on the same camera (segmented control).

## 4. Pipeline

```
capture ─▶ MealImageProcessor.prepare (existing)
       ─▶ ImageSignature (existing) ─▶ MealLearningEngine.instantOverride? ── yes ─▶ result (source: learned)
       ─▶ AIGateway.run(.mealPhotoAnalyze)   // tiered, see F01 §5.2
             output: PhotoMealAnalysis (items + portion estimates, NO final kcal if resolvable)
       ─▶ Nutrition Resolver (F02 §4.3) per item using estimated grams
             unresolved items keep model-estimated macros, badged "Estimate"
       ─▶ Confidence calibration
       ─▶ Result card: items with portion sliders, totals, source chip
       ─▶ Log ─▶ corrections recorded (existing record() + F06)
```

### 4.1 Output schema

```swift
@Generable struct PhotoMealAnalysis {
    var mealName: String                       // "Veg thali", "Chicken caesar salad"
    var items: [PhotoItem]
    @Guide(description: "true if the image does not show food or drink") var notFood: Bool
    var notes: String                          // e.g. "sauce may hide oil content"
}
@Generable struct PhotoItem {
    var name: String                           // canonical name (regional names kept)
    @Guide(.range(0...2000)) var estimatedGrams: Double
    var householdMeasure: String               // "1 katori", "2 pieces"
    @Guide(.range(0...1)) var identificationConfidence: Double
    var visibleCookingMethod: String           // fried, grilled, curry, raw…
    // Estimated macros for the visible portion (used only if resolver can't match)
    var kcal: Double; var protein: Double; var carbs: Double; var fat: Double
}
```

**Prompt `meal.photo.v2` (key rules):** enumerate every distinct item including drinks, sauces, chutneys and visible oil/ghee; estimate grams using plate (~26 cm), katori (~150 ml), spoon and hand references; keep regional dish names; never return 0 for a visible item; set `notFood` for non-food images; include learned hints from `MealLearningEngine.learnedHints` (existing).

### 4.2 Portion estimation improvements
| Technique | Phase | Notes |
|---|---|---|
| Reference-object prompting (plate/katori/cutlery/hand) | 1 | Prompt-level |
| User's own portion memory ("my katori is small") | 2 | From F06 memory, injected as hint |
| Two-view capture | 1 (optional) | Second image in same request |
| LiDAR / depth (Pro iPhones) | R&D spike in Phase 5 | `AVDepthData` → plate-plane volume estimate; only ship if eval shows ≥ 15% MAPE gain |

### 4.3 Confidence calibration (replace hard-coded `0.9`)
`mealConfidence = mean(itemConfidence)` where `itemConfidence = identificationConfidence × resolverMatchConfidence × portionFactor` (portionFactor: 0.9 with two views, 0.75 single top-down, 0.6 odd angle/occlusion flagged in notes). Calibrate thresholds on the golden set so "High" ≈ ≤ 15% kcal error in ≥ 80% of cases. UI shows **High / Medium / Low**, never a fake percentage.

### 4.4 Nutrition label & barcode
- Label: Vision text recognition on-device (document/table recognition where available) → T1 structures into `NutritionFacts` (per serving + per 100 g, serving size) → user picks servings eaten. No cloud required.
- Barcode: existing OpenFoodFacts lookup + new **offline cache** of scanned barcodes (audit gap) + label-mode fallback when the product isn't found.

### 4.5 Learning loop (extend existing)
- Keep `MealLearningEngine` thresholds; add per-item corrections (not just meal-level) so "this is my mom's rajma, ~180 kcal/katori" generalises across photos.
- Corrections also become memory items (F06) of kind `foodFact` with the photo signature reference.
- "Learned Corrections" screen becomes a tab inside the Memory screen.

## 5. Provider notes
- **T1 on-device (iOS 27+)**: image `Attachment` in the prompt; image size affects token usage → downscale to ~768 px long edge and test accuracy vs. tokens.
- **T2 PCC**: larger context; use for multi-photo meals and refine passes.
- **T3 Gemini/Groq (BYOK, consent)**: same schema via JSON mode. Groq model list from remote config (current vision models are *preview*).
- **T4**: existing `OnDeviceMealAnalyzer` (single label) — last resort; result card prompts the user to add missing items by voice (F02).

## 6. Edge cases
Blurry/dark → capture hint, allow anyway · Packaged food in photo → suggest barcode/label mode · Restaurant menu photo → offer "log from menu" (OCR → pick dish) · Multiple people's plates → ask "which plate is yours?" (tap region) · Half-eaten → ask "before or after?" · Non-food → friendly "No food found" with manual options.

## 7. Privacy
Photos are `.personal`. On-device/PCC by default; T3 only with consent. Photos are **not** stored by default — only the signature (hash + feature print) for learning; optional "keep meal photos" toggle stores them in the encrypted app container, never in the camera roll unless the user saves.

## 8. Acceptance criteria
- [ ] Golden photo set: ≥ 300 weighed meals (≥ 50% Indian, mix of home/restaurant/packaged) with ground-truth grams per item.
- [ ] Item recall ≥ 85%, precision ≥ 90% on T1/T2.
- [ ] Meal kcal MAPE ≤ 25% (stretch 20%) on T1/T2; report T3 and T4 separately.
- [ ] No-key experience (T1/T2) beats current Groq path on the golden set, or the team documents why not.
- [ ] Capture → result p50 ≤ 4 s on iPhone 15 Pro (T1), ≤ 6 s via PCC.
- [ ] Existing learned-override behaviour passes regression tests.

## 9. Tickets
`AI-140` Custom camera + live hint classifier · `AI-141` Gateway integration of `MealScannerEngine` · `AI-142` PhotoMealAnalysis schema + prompt v2 · `AI-143` Resolver integration with grams · `AI-144` Confidence calibration · `AI-145` Label OCR mode · `AI-146` Barcode offline cache · `AI-147` Per-item corrections in learning engine · `AI-148` Share-sheet import · `AI-149` Golden photo set collection protocol + eval · `AI-150` (Phase 5 spike) LiDAR portions.
