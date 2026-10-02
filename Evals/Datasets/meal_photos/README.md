# `meal_photos` golden set — collection protocol (F11 §3)

**Status:** not collected yet. The photo smoke set (30 photos for Phase 0, 300 weighed meals for 1.0) cannot be synthesised. It needs real, weighed meals. The photo eval runner lands with F04 (Phase 1, sprint 3), once ≥ 30 photos exist.

## Protocol
1. Weigh each component on a kitchen scale **before eating** (grams, to 1 g).
2. Photograph the plate **top-down** and at **45°**, in normal room light, without flash. No faces, no people, no screens with personal info.
3. Record the dish names and recipe notes (oil/ghee amounts if known).
4. At least 50% of meals should be Indian. Include thalis, single dishes, snacks, drinks and branded items.
5. Every contributor signs the consent form. Photos live in the private eval bucket and are never committed to this repo.

## Manifest format (`manifest.jsonl`, one meal per line)
```json
{"id":"mp-001","images":["mp-001-top.jpg","mp-001-45.jpg"],"cuisine":"indian",
 "items":[{"name":"roti","grams":80,"kcal":240},{"name":"dal","grams":180,"kcal":190}],
 "totalKcal":430}
```

## Metrics (F11 §4)
- Item recall ≥ 85% and precision ≥ 90%, using the same name matcher as the text eval.
- kcal MAPE ≤ 25% per meal (stretch goal 20%).
- Results are reported per tier: Groq (BYOK), Gemini (BYOK), Apple on-device (iOS 27), PCC, Vision-legacy.
