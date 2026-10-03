# Phase 1: Smart food logging, implementation report

| | |
|---|---|
| **Date** | 3 October 2026 |
| **Scope** | `phases/PHASE-1-smart-food-logging.md`: F02 (voice/text), F03 (presets), F04 (photo v2, labels, barcode cache) |
| **Target device** | **iPhone 15 (A16), which has no Apple Intelligence.** Phase 1 was adapted so every feature works fully without T1/T2 (§2). |
| **Status** | Built, unit-tested (123 tests + 5 eval tests), **installed and running on the iPhone**. Manual on-device UAT is pending (§6). |

## 1. What ships

| Feature | What the user gets | Where |
|---|---|---|
| **Say or type it** (F02) | In Add Meal, "Say or type it" opens a sheet. Speak or type ("two rotis, dal makhani and curd for lunch") and a confirmation card shows each item with amount, grams, kcal and a confidence dot, plus macros and a source badge. **Log** saves it; **Undo** removes it. | `AppIntegration/SmartLogSheet.swift`, `Food/SmartFoodLogger.swift` |
| Voice | `SFSpeechRecognizer`, on-device when the locale supports it (shown as "Processed on this iPhone"), en-IN first, food names as contextual hints, auto-stop after 1.5 s of silence | `AppIntegration/SpeechCaptureService.swift` |
| Corrections in words | "no curd", "3 rotis instead of 2", "paneer butter masala instead of chicken curry", "add a banana", "no sugar", "it was lunch", by voice or text | `Food/MealModifications.swift` |
| Edit by hand | Quantity steppers and delete. Tap an item to fix its name or nutrition; unknown foods can be remembered as custom foods (learning loop). | `SmartLogSheet.swift` (`FoodItemEditor`) |
| **Presets** (F03) | "Save as preset" on the card, or "save this as my usual lunch". Define by voice: "remember gym shake is 1 scoop whey, 300 ml milk and a banana". Use: "log gym shake", "my usual", "usual lunch but no curd". Preset chips appear in the sheet. A **Presets** screen supports use, rename, archive and delete. | `Food/Presets/`, `AppIntegration/PresetsView.swift` |
| Routine suggestions | After about 3 repeats in 14 days, one in-app card ("You've had poha and chai most weekdays lately. Save it as 'Poha & Chai'?"). "Not now" is remembered. Never a notification. | `Food/Presets/RoutineMiner.swift` |
| **Nutrition label scan** (F04 §4.4) | Photo of the table → on-device Vision OCR → parsed per 100 g / per serving → choose servings or grams → log. Optionally saved to My Foods. | `Food/Labels/`, `AppIntegration/LabelScanView.swift` |
| **Photo v2** (F04) | With a key, the cloud model lists every item with estimated grams; nutrition then comes from the catalog where possible, with calibrated confidence instead of a fixed 0.9. Without a key, on-device Vision now proposes up to four foods instead of one. | `Food/PhotoMealAnalysis.swift`, `MealScannerEngine`, `VisionLegacyMealProvider` |
| Barcode offline cache | A product scanned once resolves offline afterwards | `Food/BarcodeCache.swift`, `BarcodeFoodLookup` |
| Provenance | Every AI-logged entry stores `EntrySource` (`nlAI`, `preset`, `photoAI`) and a 0–1 confidence in `FoodEntry` | `FoodItem.source/aiConfidence` (platform-approved edit) |

## 2. Adaptation for phones without Apple Intelligence

The original plan assumed T1 (on-device Foundation Model) for parsing. On an iPhone 15, T1 and T2 report `deviceNotEligible`, so:

| Need | Original plan | What runs on the iPhone 15 |
|---|---|---|
| Understand "two rotis and dal" | T1 LLM | **Rule parser** (Hindi/Hinglish numbers, units, plurals, preparation, non-food guard) via the gateway's T0 tier. Groq/Gemini take over automatically if you add a key. |
| Nutrition | Resolver (already deterministic) | **Expanded:** 226-food catalog (more than half Indian) with per-100 g macros and household units (roti 40 g, katori 150 g, glass 250 ml, …), typo/alias/head-noun matching, preparation adjustments, and F02's confidence formula |
| Unknown foods | LLM estimate | Flagged "Check this" for the user to fill in (remembered next time). With a key, `nutritionEstimate` asks Groq/Gemini. |
| Preset naming and variants | T1 | Deterministic namer and modification parser |
| Semantic preset match | Embeddings | `NLEmbedding` sentence embeddings (NaturalLanguage; works on every iPhone, no Apple Intelligence) |
| Photo items | T1 vision (iOS 27) | Groq/Gemini with a key; otherwise multi-label Vision |
| Labels | T1 structuring | **Deterministic table parser.** No model needed. |

On Apple Intelligence devices, routing upgrades automatically (`foodTextParse`: T1 → T2 → T3 → rules). No code differs per device.

## 3. Quality evidence

| Check | Result |
|---|---|
| Catalog integrity | Every one of the 226 foods passes the 4P + 4C + 9F ≈ kcal check (±20%); aliases are unique |
| Demo script (Phase 1 doc), as automated tests on the no-AI config | ✅ say a meal → card → log; save as "Usual lunch"; next day "log my usual lunch but no curd" → roti + dal makhani only |
| Food-text smoke eval, deterministic tier | Item F1 100% (meal type 81.8%). ⚠️ The rules were tuned on this same set, so the held-out 500-utterance golden set is still needed (§6). |
| Label parser | Indian two-column, US %DV, kJ/kcal, split OCR rows, unreadable → "unusable" (never guessed) |
| Photo v2 | Catalog nutrition at the model's grams; model estimates only as a badged fallback; confidence = identification × match × 0.75 portion factor |
| Coverage | Gateway 94.8%, Food 92.1% |
| Device build | Debug build succeeds on iPhone 15 with no warnings in AI files |

## 4. Decisions (for AI lead review)
1. **Presets are stored in an AI-owned JSON file** (`Application Support/AI/presets.json`, file-protected) behind `PresetRepository`, until `FoodPreset` lands in LifeOSData (C1). Swapping storage is a one-line change.
2. **Favourites and custom foods are not migrated into presets** (AI-120). The resolver already uses them as the user's own foods, so nothing changes for the user.
3. **Photo schema v2 is on by default** (remote flag `photoSchemaV2`). Turning it off restores the Phase 0 v1 path exactly.
4. **Undo** removes the entries from today's log. It lives in the sheet's "Logged" state for 8 s and "Undo" stays available until the sheet closes. Removal from the day view uses the existing delete.
5. **Prompt registry bumped to `2026.10.2`** for the new prompts (photo v2, nutrition estimate).
6. **Entry point is the Add Meal sheet.** Adding a Home quick action needs `HomeView`, which another session was editing. It's a small follow-up.

## 5. How to try it on the iPhone
1. Home → Add Meal → **Say or type it** → tap the mic → "two rotis, dal makhani and curd for lunch" → **Log**, then **Undo**, then log again.
2. Tap **Save as preset**. Next time, say "log my usual lunch but no curd".
3. "remember gym shake is 1 scoop whey, 300 ml milk and a banana", then "log gym shake".
4. **Scan a nutrition label** from the same sheet, using any packet in the kitchen.
5. Scan a meal photo with no key: up to four items. With a Groq key: per-item grams.

## 6. Open items
- [ ] Manual UAT on the iPhone (the steps in §5); check speech permissions and the on-device recognition locale.
- [ ] Held-out golden sets: 500 food utterances (F02), 200 preset phrases (F03), ≥ 150 weighed photos (F04).
- [ ] Legal: licensed Indian food-composition data (IFCT) to replace or extend `lifeos-curated-v1`.
- [ ] Home quick action for Smart Log (coordinate with the `HomeView` owner).
- [ ] Custom camera with live hints (AI-140), the share-sheet import (AI-148), and the Watch preset digest (AI-128, with the Health/Watch team).
- [ ] Preset reminders and auto-log (F03 §4.6) ship with F09 in Phase 4 (policy stored, always `.off` now).
