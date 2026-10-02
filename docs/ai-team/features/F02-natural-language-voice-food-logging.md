# F02 — Natural-Language & Voice Food Logging

| | |
|---|---|
| **Phase** | 1 |
| **Owner** | AI Engineer A ("Food") |
| **Tiers** | T1 → T2 → T3 → deterministic fallback |
| **Depends on** | F01, Nutrition Resolver (this doc), SwiftData `FoodEntry` (C1) |

## 1. Problem
Logging food today means forms, search, barcode or a photo. The fastest possible interaction — just saying what you ate — doesn't exist.

## 2. Outcome
The user types or says *"2 rotis, dal makhani and a bowl of curd for lunch"* or *"had my usual coffee and a banana"* and gets a confirmation card with every item, quantity, calories and macros in ≤ 3 s. One tap logs it.

## 3. User stories
- As a user I can **speak** a meal from the Home quick action, the food sheet, the Assistant, Siri, or the Watch.
- I can **type** in natural English or Hinglish ("ek plate poha", "2 anda bhurji").
- I can mention **time and meal** ("yesterday's dinner", "at 4pm a protein shake") or let LifeOS infer it.
- I can say **corrections** ("no, make it 3 rotis", "without sugar") on the card.
- I can reference **presets** ("my usual breakfast") and **past meals** ("same lunch as Monday").

## 4. Pipeline — "the model understands, code computes"

```
speech ─▶ transcript ─┐
text ─────────────────┴▶ 1. Pre-parse (deterministic: numbers, units, preset aliases, time words)
                         2. LLM parse → ParsedMeal (structure only, NO calories)
                         3. Nutrition Resolver → per-item nutrition with provenance
                         4. Confidence scoring
                         5. Confirmation card (or auto-log if policy allows — F03)
                         6. Log via FoodLogRepository with undo token
                         7. Learning: corrections → memory (F06)
```

### 4.1 Speech
- iOS 26+: `SpeechAnalyzer` / `SpeechTranscriber` on-device; iOS 17–25: `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` where the locale supports it.
- Locales: `en-IN` first, `en-US`, `hi-IN` (transcript may contain Devanagari → normalise to romanised food names via a lookup table).
- Live partial transcript shown; auto-stop after 1.5 s silence.
- Contextual strings: feed the top 100 preset names, custom foods and recent foods as custom vocabulary/contextual hints to improve recognition of "paneer tikka", "sattu", etc.

### 4.2 LLM parse — output schema

```swift
@Generable struct ParsedMeal {
    @Guide(description: "Each distinct food or drink mentioned")
    var items: [ParsedItem]
    @Guide(description: "breakfast, lunch, dinner, snacks, or unknown")
    var mealType: String
    @Guide(description: "ISO-8601 time if the user stated one, else empty")
    var statedTime: String
    @Guide(description: "true if the user referred to a saved preset or 'usual' meal")
    var refersToPreset: Bool
    var presetPhrase: String          // e.g. "usual breakfast"
}
@Generable struct ParsedItem {
    var name: String                  // canonical English name, e.g. "roti", "dal makhani"
    var originalText: String          // the user's words for this item
    @Guide(.range(0...50)) var quantity: Double
    var unit: String                  // piece, bowl, cup, g, ml, slice, plate, tbsp, scoop, glass…
    var preparation: String           // fried, boiled, with ghee, no sugar… ("" if none)
    var brand: String                 // "" if none
}
```

**Instructions (prompt `food.parse.v1`, abridged):**
> You convert a person's description of what they ate into structured items. Do not estimate calories. Split combined dishes only when the user lists them separately ("dal and rice" = 2 items; "dal rice" as one dish = 1 item). Default quantity to 1 and unit to the most natural serving if not stated. Keep regional dish names (e.g. "poha", "idli") — do not translate them into generic foods. If the text is not about food or drink, return no items.

Few-shot examples live in the prompt registry and include Indian, Western and branded foods, plus non-food inputs.

### 4.3 Nutrition Resolver (deterministic, T0)
Resolution order for each `ParsedItem` — first confident hit wins:

| # | Source | Match method | Provenance tag |
|---|---|---|---|
| 1 | User **presets** & **custom foods** | alias + fuzzy + embedding | `user:preset:<id>` / `user:custom:<id>` |
| 2 | **Correction memory** (user previously fixed this item) | name + embedding | `user:learned:<id>` |
| 3 | **Bundled food database** (expanded `NutritionDatabase`) | normalised name, synonyms, embedding | `db:<source>:<id>` |
| 4 | **OpenFoodFacts** (for branded items, online) | text search by brand + name | `off:<barcode>` |
| 5 | **LLM estimate** (last resort) | separate `nutritionEstimate` task | `llm-estimate` — badged "Estimate", low confidence |

**Bundled database plan:**
- Base: USDA FoodData Central (public domain) subset of ~3,000 common foods, per-100 g + common household measures.
- Indian foods: curate ~800 common Indian dishes with per-serving values. Candidate sources: the Indian Food Composition Tables (IFCT 2017, NIN) and published recipe-based datasets — **legal must confirm licensing before bundling**; otherwise build our own reviewed table.
- Household unit map per food (roti ≈ 40 g, katori/bowl ≈ 150 g, cup ≈ 240 ml, …), editable by the user.
- Ship as a read-only SQLite/SwiftData store inside the bundle (~5–10 MB); on-device text embeddings (`NLContextualEmbedding`) precomputed at build time for semantic match.

### 4.4 Confidence
`itemConfidence = parseConfidence × matchConfidence × unitConfidence`
- parse: 1.0 if quantity/unit stated, 0.8 if defaulted.
- match: by source (preset 1.0, learned 0.95, DB exact 0.9, DB fuzzy 0.7, OFF 0.8, LLM estimate 0.4).
- unit: known household mapping 1.0, generic "serving" 0.6.
Card highlights any item < 0.6 as **"Check this"**.

### 4.5 Meal type & time inference
If not stated: use time of day + the user's own historical meal windows (from memory/profile) — e.g. a user who eats lunch at 15:00 gets "lunch" at 15:00, not "snacks".

### 4.6 Corrections on the card
Free-text correction re-runs parse with the previous `ParsedMeal` + correction text (`food.parse.refine.v1`), mirroring the existing photo refine. Item-level edits are direct (stepper for quantity, unit picker, search to swap food). Every edit is recorded for learning (F06).

## 5. Deterministic fallback (no model available)
A rule parser: split on `,`/`and`/`aur`/`with`/`+`; extract leading numbers/number words (en + hi: "ek, do, teen…"); match units from a dictionary; resolve names via fuzzy DB match. Quality is lower but the feature never disappears.

## 6. Edge cases
| Case | Behaviour |
|---|---|
| "a bite of cake" / "half a samosa" | quantity 0.5 or fraction; "bite" mapped to 10–15 g |
| Drinks ("chai with 2 sugar") | item chai + preparation "2 tsp sugar"; resolver adds sugar kcal |
| Ambiguous ("rice") | resolve to user's most-logged rice variant if any; else default + "Check this" |
| Alcohol | log normally; no judgemental tone |
| Non-food ("I went for a run") | no items; offer to route to workout logging/assistant |
| Very long dictation (> 20 items) | chunk; ask to confirm |
| Mixed past dates ("yesterday dinner and today breakfast") | split into two cards |
| Profanity / unrelated chat | treat as no items |

## 7. Privacy
Food text is `PrivacyClass.personal`. T1/T2 by default. T3 only with consent. Transcripts are not stored unless the user enables "keep voice transcripts" (off by default); parsed items are stored as log entries.

## 8. Acceptance criteria
- [ ] Golden set (≥ 500 utterances: 50% Indian foods, 20% Hinglish, 10% branded, 10% non-food/edge) — item-level F1 ≥ 0.92 on T1; ≥ 0.80 on deterministic fallback.
- [ ] Calorie MAPE ≤ 10% on golden items with known DB matches.
- [ ] p50 latency from end of speech to card ≤ 2.5 s on iPhone 15 Pro (T1); p95 ≤ 5 s.
- [ ] Works in airplane mode (T1 or deterministic).
- [ ] Every logged entry carries provenance and is undoable.

## 9. Tickets
`AI-101` Speech capture service · `AI-102` Pre-parser (numbers/units/time, en+hi) · `AI-103` ParsedMeal schema + prompt + few-shots · `AI-104` Nutrition DB build pipeline (USDA subset + Indian table + unit map) · `AI-105` Nutrition Resolver · `AI-106` Confidence scoring · `AI-107` Confirmation card integration (with Design kit C6) · `AI-108` Refine-by-text · `AI-109` Deterministic fallback parser · `AI-110` Golden set + eval.
